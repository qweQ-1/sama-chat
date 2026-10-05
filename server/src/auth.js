// Auth: register / login / me. Passwords hashed with scrypt, sessions are JWTs.
import { scrypt, randomBytes, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';
import jwt from 'jsonwebtoken';
import {
  db,
  newId,
  now,
  publicUser,
  selfUser,
  findUserById,
  findUserByUsername,
  findUsersByPhone,
  save,
} from './store.js';

export const JWT_SECRET =
  process.env.JWT_SECRET || 'sama-chat-dev-secret-change-me-in-production';

export function signToken(userId) {
  return jwt.sign({ sub: userId }, JWT_SECRET, { expiresIn: '90d' });
}

export function verifyToken(token) {
  try {
    const payload = jwt.verify(token, JWT_SECRET);
    return payload.sub;
  } catch {
    return null;
  }
}

const USERNAME_RE = /^[a-zA-Z0-9_]{3,20}$/;
const PHONE_RE = /^1[3-9]\d{9}$/;
const MAX_ACCOUNTS_PER_PHONE = 10;

/** 归一化手机号：去掉空格/横线等，允许 +86 前缀。 */
export function normalizePhone(raw) {
  let s = String(raw ?? '').replace(/[^\d]/g, '');
  if (s.length === 13 && s.startsWith('86')) s = s.slice(2);
  return s;
}

// --- password hashing (scrypt) -------------------------------------------
// Format: scrypt$N$r$p$saltHex$hashHex — parameters stored inline so they can
// be raised later without invalidating existing passwords.
const SCRYPT = { N: 16384, r: 8, p: 1, keylen: 64 };
const scryptAsync = promisify(scrypt);

export async function hashPassword(password) {
  const salt = randomBytes(16);
  const buf = await scryptAsync(password, salt, SCRYPT.keylen, {
    N: SCRYPT.N,
    r: SCRYPT.r,
    p: SCRYPT.p,
  });
  return [
    'scrypt',
    SCRYPT.N,
    SCRYPT.r,
    SCRYPT.p,
    salt.toString('hex'),
    buf.toString('hex'),
  ].join('$');
}

export async function verifyPassword(password, stored) {
  try {
    const [scheme, N, r, p, saltHex, hashHex] = String(stored).split('$');
    if (scheme !== 'scrypt') return false;
    const salt = Buffer.from(saltHex, 'hex');
    const expected = Buffer.from(hashHex, 'hex');
    const buf = await scryptAsync(password, salt, expected.length, {
      N: Number(N),
      r: Number(r),
      p: Number(p),
    });
    return buf.length === expected.length && timingSafeEqual(buf, expected);
  } catch {
    return false;
  }
}

export function registerAuthRoutes(app) {
  app.post('/auth/register', async (req, reply) => {
    const { password, displayName } = req.body ?? {};
    const phone = normalizePhone(req.body?.phone);
    const rawUsername = String(req.body?.username ?? '').trim();
    const byPhone = rawUsername.length === 0; // 不带用户名 → 手机号注册模式

    if (!PHONE_RE.test(phone)) {
      return reply.code(400).send({
        error: 'invalid_phone',
        message: '请填写正确的 11 位手机号',
      });
    }
    if (String(password ?? '').length < 6) {
      return reply.code(400).send({
        error: 'invalid_password',
        message: '密码至少 6 位',
      });
    }
    if (findUsersByPhone(phone).length >= MAX_ACCOUNTS_PER_PHONE) {
      return reply.code(400).send({
        error: 'phone_limit',
        message: `该手机号绑定的账号已达上限（${MAX_ACCOUNTS_PER_PHONE} 个）`,
      });
    }

    let username;
    if (byPhone) {
      // 手机号注册：自动生成用户名（phone、phone_2、phone_3……）
      username = phone;
      let n = 1;
      while (findUserByUsername(username)) {
        n += 1;
        username = `${phone}_${n}`;
      }
    } else {
      if (!USERNAME_RE.test(rawUsername)) {
        return reply.code(400).send({
          error: 'invalid_username',
          message: '用户名需为 3-20 位字母、数字或下划线',
        });
      }
      if (findUserByUsername(rawUsername)) {
        return reply.code(409).send({
          error: 'username_taken',
          message: '该用户名已被占用',
        });
      }
      username = rawUsername;
    }

    const dn = String(displayName ?? '').trim().slice(0, 32);
    const user = {
      id: newId('u'),
      username,
      displayName: dn || (byPhone ? `用户${phone.slice(-4)}` : username),
      phone,
      passwordHash: await hashPassword(String(password)),
      avatar: null,
      createdAt: now(),
    };
    db.data.users.push(user);
    await save();

    return { token: signToken(user.id), user: selfUser(user) };
  });

  // 手机号登录第一步：列出该手机号名下的所有账号（不含敏感信息）。
  app.post('/auth/accounts', async (req, reply) => {
    const phone = normalizePhone(req.body?.phone);
    if (!PHONE_RE.test(phone)) {
      return reply.code(400).send({ error: 'invalid_phone', message: '请填写正确的 11 位手机号' });
    }
    const accounts = findUsersByPhone(phone)
      .sort((a, b) => (a.createdAt ?? 0) - (b.createdAt ?? 0))
      .slice(0, MAX_ACCOUNTS_PER_PHONE)
      .map((u) => publicUser(u));
    return { phone, accounts };
  });

  app.post('/auth/login', async (req, reply) => {
    const { username, password } = req.body ?? {};
    const user = findUserByUsername(username ?? '');
    if (!user || !(await verifyPassword(String(password ?? ''), user.passwordHash))) {
      return reply.code(401).send({
        error: 'bad_credentials',
        message: '用户名或密码错误',
      });
    }
    return { token: signToken(user.id), user: selfUser(user) };
  });

  app.get('/auth/me', { preHandler: app.auth }, async (req) => ({
    user: selfUser(findUserById(req.userId)),
  }));

  app.patch('/auth/me', { preHandler: app.auth }, async (req, reply) => {
    const user = findUserById(req.userId);
    const { displayName, avatar } = req.body ?? {};
    if (typeof displayName === 'string' && displayName.trim()) {
      user.displayName = displayName.trim().slice(0, 32);
    }
    if (typeof avatar === 'string') {
      user.avatar = avatar;
    }
    if (typeof req.body?.phone === 'string' && req.body.phone.trim()) {
      const phone = normalizePhone(req.body.phone);
      if (!PHONE_RE.test(phone)) {
        return reply.code(400).send({ error: 'invalid_phone', message: '请填写正确的 11 位手机号' });
      }
      const others = findUsersByPhone(phone).filter((u) => u.id !== user.id);
      if (others.length >= MAX_ACCOUNTS_PER_PHONE) {
        return reply.code(400).send({
          error: 'phone_limit',
          message: `该手机号绑定的账号已达上限（${MAX_ACCOUNTS_PER_PHONE} 个）`,
        });
      }
      user.phone = phone;
    }
    await save();
    return { user: selfUser(user) };
  });
}
