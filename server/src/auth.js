// Auth: register / login / me. Passwords hashed with scrypt, sessions are JWTs.
import { scrypt, randomBytes, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';
import jwt from 'jsonwebtoken';
import {
  db,
  newId,
  now,
  publicUser,
  findUserById,
  findUserByUsername,
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
    const { username, password, displayName } = req.body ?? {};

    if (!USERNAME_RE.test(String(username ?? ''))) {
      return reply.code(400).send({
        error: 'invalid_username',
        message: '用户名需为 3-20 位字母、数字或下划线',
      });
    }
    if (String(password ?? '').length < 6) {
      return reply.code(400).send({
        error: 'invalid_password',
        message: '密码至少 6 位',
      });
    }
    if (findUserByUsername(username)) {
      return reply.code(409).send({
        error: 'username_taken',
        message: '该用户名已被占用',
      });
    }

    const user = {
      id: newId('u'),
      username: String(username),
      displayName: String(displayName ?? username).slice(0, 32),
      passwordHash: await hashPassword(String(password)),
      avatar: null,
      createdAt: now(),
    };
    db.data.users.push(user);
    await save();

    return { token: signToken(user.id), user: publicUser(user) };
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
    return { token: signToken(user.id), user: publicUser(user) };
  });

  app.get('/auth/me', { preHandler: app.auth }, async (req) => ({
    user: publicUser(findUserById(req.userId)),
  }));

  app.patch('/auth/me', { preHandler: app.auth }, async (req) => {
    const user = findUserById(req.userId);
    const { displayName, avatar } = req.body ?? {};
    if (typeof displayName === 'string' && displayName.trim()) {
      user.displayName = displayName.trim().slice(0, 32);
    }
    if (typeof avatar === 'string') {
      user.avatar = avatar;
    }
    await save();
    return { user: publicUser(user) };
  });
}
