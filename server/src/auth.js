// Auth: register / login / me. Passwords hashed with scrypt, sessions are JWTs.
import { scrypt, randomBytes, timingSafeEqual, randomInt, createHash } from 'node:crypto';
import { promisify } from 'node:util';
import jwt from 'jsonwebtoken';
import fs from 'node:fs';
import path from 'node:path';
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

// ---------- 短信验证码 ----------
// 短信服务配置（二选一）：
//   1) 环境变量：SMS_PROVIDER=smsbao + SMS_SMSBAO_USER/SMS_SMSBAO_PASS/SMS_SMSBAO_SIGN
//      或 SMS_PROVIDER=custom + SMS_CUSTOM_URL（URL 模板，占位符 {phone} {code} {content}）
//   2) 配置文件：server/sms.config.json（改完即时生效，无需重启）
// 未配置任何短信服务时自动进入"开发模式"：验证码直接返回给 App（仅用于调试）。
const SMS_COOLDOWN_MS = Number(process.env.SMS_COOLDOWN_MS ?? 60 * 1000);
const SMS_CODE_TTL_MS = Number(process.env.SMS_CODE_TTL_MS ?? 5 * 60 * 1000);
const SMS_MAX_PER_HOUR = Number(process.env.SMS_MAX_PER_HOUR ?? 8);
const SMS_MAX_FAILS = 5;
const smsCodes = new Map(); // phone -> {code, expiresAt, sentAt, fails, hourStart, hourCount}

function smsConfig() {
  let file = {};
  try {
    file = JSON.parse(
      fs.readFileSync(path.resolve(process.cwd(), 'sms.config.json'), 'utf8'),
    );
  } catch {
    /* 没配置文件就用环境变量 */
  }
  const provider = process.env.SMS_PROVIDER || file.provider || '';
  return {
    provider,
    devMode:
      process.env.SMS_DEV_MODE === '1'
        ? true
        : process.env.SMS_DEV_MODE === '0'
          ? false
          : !provider,
    smsbaoUser: process.env.SMS_SMSBAO_USER || file.smsbaoUser || '',
    smsbaoPass: process.env.SMS_SMSBAO_PASS || file.smsbaoPass || '',
    sign: process.env.SMS_SMSBAO_SIGN || file.sign || '萨摩聊天',
    customUrl: process.env.SMS_CUSTOM_URL || file.customUrl || '',
  };
}

async function sendSms(cfg, phone, code) {
  const text = `【${cfg.sign}】您的验证码是 ${code}，5 分钟内有效。请勿泄露给他人。`;
  if (cfg.provider === 'smsbao') {
    if (!cfg.smsbaoUser || !cfg.smsbaoPass) throw new Error('短信宝账号/密码未配置');
    const md5 = createHash('md5').update(cfg.smsbaoPass).digest('hex');
    const url =
      `http://api.smsbao.com/sms?u=${encodeURIComponent(cfg.smsbaoUser)}` +
      `&p=${md5}&m=${phone}&c=${encodeURIComponent(text)}`;
    const res = await fetch(url, { signal: AbortSignal.timeout(10000) });
    const body = (await res.text()).trim();
    if (body !== '0') throw new Error(`短信宝返回码 ${body}`);
    return;
  }
  if (cfg.provider === 'custom' && cfg.customUrl) {
    const url = cfg.customUrl
      .replaceAll('{phone}', phone)
      .replaceAll('{code}', code)
      .replaceAll('{content}', encodeURIComponent(text));
    const res = await fetch(url, { signal: AbortSignal.timeout(10000) });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return;
  }
  throw new Error(`未知短信服务: ${cfg.provider}`);
}

/** 校验验证码，返回错误文案；null 表示通过。 */
function checkSmsCode(phone, code) {
  const rec = smsCodes.get(phone);
  if (!rec) return '验证码不存在或已过期，请先获取验证码';
  if (Date.now() > rec.expiresAt) {
    smsCodes.delete(phone);
    return '验证码已过期，请重新获取';
  }
  if (rec.fails >= SMS_MAX_FAILS) {
    smsCodes.delete(phone);
    return '错误次数过多，请重新获取验证码';
  }
  if (String(code ?? '').trim() !== rec.code) {
    rec.fails += 1;
    return '验证码不正确';
  }
  return null;
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
  // 发送短信验证码（注册 / 绑定手机号用）
  app.post('/auth/sms/send', async (req, reply) => {
    const phone = normalizePhone(req.body?.phone);
    if (!PHONE_RE.test(phone)) {
      return reply.code(400).send({ error: 'invalid_phone', message: '请填写正确的 11 位手机号' });
    }
    const cfg = smsConfig();
    const t = Date.now();
    const rec = smsCodes.get(phone);
    if (rec && t - rec.sentAt < SMS_COOLDOWN_MS) {
      const wait = Math.ceil((SMS_COOLDOWN_MS - (t - rec.sentAt)) / 1000);
      return reply.code(429).send({
        error: 'too_frequent',
        message: `发送太频繁，请 ${wait} 秒后再试`,
      });
    }
    const hourRec = rec && t - (rec.hourStart ?? 0) < 3600 * 1000 ? rec : null;
    if (hourRec && (hourRec.hourCount ?? 0) >= SMS_MAX_PER_HOUR) {
      return reply.code(429).send({ error: 'limit', message: '发送次数过多，请稍后再试' });
    }
    const code = String(randomInt(100000, 1000000));
    smsCodes.set(phone, {
      code,
      expiresAt: t + SMS_CODE_TTL_MS,
      sentAt: t,
      fails: 0,
      hourStart: hourRec ? hourRec.hourStart : t,
      hourCount: (hourRec?.hourCount ?? 0) + 1,
    });
    if (!cfg.devMode) {
      try {
        await sendSms(cfg, phone, code);
      } catch (e) {
        console.error(`[SMS] 发送失败 (${phone}): ${e.message}`);
        return reply.code(502).send({ error: 'sms_failed', message: '短信发送失败，请稍后再试' });
      }
      return { ok: true, expiresIn: Math.round(SMS_CODE_TTL_MS / 1000) };
    }
    console.log(`[SMS][开发模式] ${phone} 的验证码: ${code}（未配置短信服务，验证码直接返回给 App）`);
    return { ok: true, devMode: true, devCode: code, expiresIn: Math.round(SMS_CODE_TTL_MS / 1000) };
  });

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
    const codeErr = checkSmsCode(phone, req.body?.code);
    if (codeErr) {
      return reply.code(400).send({ error: 'bad_code', message: codeErr });
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
      const codeErr = checkSmsCode(phone, req.body?.code);
      if (codeErr) {
        return reply.code(400).send({ error: 'bad_code', message: codeErr });
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
