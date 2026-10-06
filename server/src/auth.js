// Auth: register / login / me + 验证码（短信 / 邮箱）+ 注册模式切换。
// 注册模式：server/config.json 里 authMode = "email"（默认）| "phone"，改完即时生效。
// 账号密码登录始终可用。
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
  findUsersByEmail,
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
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const MAX_ACCOUNTS_PER_IDENT = 10;
const APP_NAME = '萨摩聊天';

/** 归一化手机号：去掉空格/横线等，允许 +86 前缀。 */
export function normalizePhone(raw) {
  let s = String(raw ?? '').replace(/[^\d]/g, '');
  if (s.length === 13 && s.startsWith('86')) s = s.slice(2);
  return s;
}

/** 归一化邮箱：去空格 + 转小写。 */
export function normalizeEmail(raw) {
  return String(raw ?? '').trim().toLowerCase();
}

// ---------- 配置文件（server/config.json，兼容旧 sms.config.json） ----------
let _cfgCache = { t: 0, v: null };

function readJsonFile(name) {
  try {
    const raw = fs.readFileSync(path.resolve(process.cwd(), name), 'utf8');
    return JSON.parse(raw.replace(/^\uFEFF/, '')); // 容忍 Windows 写入的 BOM
  } catch {
    return null;
  }
}

function serverConfig() {
  const t = Date.now();
  if (_cfgCache.v && t - _cfgCache.t < 5000) return _cfgCache.v;
  const main = readJsonFile('config.json') ?? {};
  const legacy = readJsonFile('sms.config.json') ?? {}; // 旧版平铺短信配置
  const v = {
    authMode: main.authMode ?? legacy.authMode ?? '',
    smsFile: { ...legacy, ...(main.sms ?? {}) },
    emailFile: main.email ?? {},
    consoleFile: main.consoleMode ?? legacy.consoleMode === true,
    announceAdmins: main.announceAdmins ?? legacy.announceAdmins ?? '',
  };
  _cfgCache = { t, v };
  return v;
}

/** 当前注册/登录模式：'email'（默认）| 'phone'。 */
export function authMode() {
  const m = String(process.env.AUTH_MODE || serverConfig().authMode || 'email')
    .trim()
    .toLowerCase();
  return m === 'phone' ? 'phone' : 'email';
}

// ---------- 公告发布权限（只有 huzhi 等管理员账号可发公告） ----------
// 配置：server/config.json 的 announceAdmins（数组或逗号分隔字符串），默认 huzhi。
// 匹配规则：用户名或昵称（大小写不敏感）。
export function canAnnounce(user) {
  if (!user) return false;
  const raw =
    process.env.ANNOUNCE_ADMINS || serverConfig().announceAdmins || 'huzhi';
  const admins = (Array.isArray(raw) ? raw : String(raw).split(','))
    .map((s) => String(s).trim().toLowerCase())
    .filter(Boolean);
  if (admins.length === 0) admins.push('huzhi');
  const names = [user.username, user.displayName]
    .filter(Boolean)
    .map((s) => String(s).toLowerCase());
  return names.some((n) => admins.includes(n));
}

/** 自己的账号信息 + 公告权限标志（客户端据此显示「发布公告」入口）。 */
function selfMe(u) {
  const su = selfUser(u);
  if (su) su.canAnnounce = canAnnounce(u);
  return su;
}

function smsConfig() {
  const f = serverConfig().smsFile;
  const provider = process.env.SMS_PROVIDER || f.provider || '';
  return {
    provider,
    devMode:
      process.env.SMS_DEV_MODE === '1'
        ? true
        : process.env.SMS_DEV_MODE === '0'
          ? false
          : !provider,
    // 管理员模式：验证码只打印在服务器窗口（由管理员转告注册的人）
    consoleMode:
      process.env.SMS_CONSOLE === '1'
        ? true
        : process.env.SMS_CONSOLE === '0'
          ? false
          : serverConfig().consoleFile,
    smsbaoUser: process.env.SMS_SMSBAO_USER || f.smsbaoUser || '',
    smsbaoPass: process.env.SMS_SMSBAO_PASS || f.smsbaoPass || '',
    sign: process.env.SMS_SMSBAO_SIGN || f.sign || APP_NAME,
    customUrl: process.env.SMS_CUSTOM_URL || f.customUrl || '',
    smsgateUser: process.env.SMS_SMSGATE_USER || f.smsgateUser || '',
    smsgatePass: process.env.SMS_SMSGATE_PASS || f.smsgatePass || '',
  };
}

function emailConfig() {
  const f = serverConfig().emailFile;
  const host = process.env.EMAIL_SMTP_HOST || f.host || '';
  return {
    host,
    port: Number(process.env.EMAIL_SMTP_PORT || f.port || 465),
    secure:
      String(process.env.EMAIL_SMTP_SECURE ?? String(f.secure ?? true)) !== 'false',
    user: process.env.EMAIL_SMTP_USER || f.user || '',
    pass: process.env.EMAIL_SMTP_PASS || f.pass || '',
    from: process.env.EMAIL_SMTP_FROM || f.from || process.env.EMAIL_SMTP_USER || f.user || '',
    devMode: !host,
  };
}

// ---------- 验证码（短信 / 邮箱共用一套机制） ----------
const CODE_COOLDOWN_MS = Number(process.env.SMS_COOLDOWN_MS ?? 60 * 1000);
const CODE_TTL_MS = Number(process.env.SMS_CODE_TTL_MS ?? 5 * 60 * 1000);
const CODE_MAX_PER_HOUR = Number(process.env.SMS_MAX_PER_HOUR ?? 8);
const CODE_MAX_FAILS = 5;
const codes = new Map(); // 'p:<phone>' | 'e:<email>' -> {code, expiresAt, sentAt, fails, hourStart, hourCount}

function issueCode(key) {
  const t = Date.now();
  const rec = codes.get(key);
  if (rec && t - rec.sentAt < CODE_COOLDOWN_MS) {
    const wait = Math.ceil((CODE_COOLDOWN_MS - (t - rec.sentAt)) / 1000);
    return { status: 429, error: 'too_frequent', message: `发送太频繁，请 ${wait} 秒后再试` };
  }
  const hourRec = rec && t - (rec.hourStart ?? 0) < 3600 * 1000 ? rec : null;
  if (hourRec && (hourRec.hourCount ?? 0) >= CODE_MAX_PER_HOUR) {
    return { status: 429, error: 'limit', message: '发送次数过多，请稍后再试' };
  }
  const code = String(randomInt(100000, 1000000));
  codes.set(key, {
    code,
    expiresAt: t + CODE_TTL_MS,
    sentAt: t,
    fails: 0,
    hourStart: hourRec ? hourRec.hourStart : t,
    hourCount: (hourRec?.hourCount ?? 0) + 1,
  });
  return { code, expiresIn: Math.round(CODE_TTL_MS / 1000) };
}

/** 校验验证码，返回错误文案；null 表示通过。 */
function checkCode(key, code) {
  const rec = codes.get(key);
  if (!rec) return '验证码不存在或已过期，请先获取验证码';
  if (Date.now() > rec.expiresAt) {
    codes.delete(key);
    return '验证码已过期，请重新获取';
  }
  if (rec.fails >= CODE_MAX_FAILS) {
    codes.delete(key);
    return '错误次数过多，请重新获取验证码';
  }
  if (String(code ?? '').trim() !== rec.code) {
    rec.fails += 1;
    return '验证码不正确';
  }
  return null;
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
  if (cfg.provider === 'smsgate') {
    // 免费方案：安卓手机装 SMS Gateway 应用（sms-gate.app），用手机卡发短信
    if (!cfg.smsgateUser || !cfg.smsgatePass) throw new Error('SMSGate 账号/密码未配置');
    const auth = Buffer.from(`${cfg.smsgateUser}:${cfg.smsgatePass}`).toString('base64');
    const res = await fetch('https://api.sms-gate.app/3rdparty/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Basic ${auth}`,
      },
      body: JSON.stringify({ textMessage: { text }, phoneNumbers: [`+86${phone}`] }),
      signal: AbortSignal.timeout(20000),
    });
    if (!res.ok) {
      const body = await res.text().catch(() => '');
      throw new Error(`SMSGate HTTP ${res.status} ${String(body).slice(0, 120)}`);
    }
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

async function sendEmail(cfg, to, code) {
  let nodemailer;
  try {
    nodemailer = (await import('nodemailer')).default;
  } catch {
    throw new Error('邮件组件未安装：请在服务器上进行一次更新（会自动运行 npm install）');
  }
  const transport = nodemailer.createTransport({
    host: cfg.host,
    port: cfg.port,
    secure: cfg.secure,
    auth: cfg.user ? { user: cfg.user, pass: cfg.pass } : undefined,
  });
  await transport.sendMail({
    from: cfg.from || cfg.user,
    to,
    subject: `【${APP_NAME}】注册验证码`,
    text: `你的验证码是 ${code}，5 分钟内有效。请勿泄露给他人。`,
  });
}

/** 从邮箱自动生成用户名（邮箱前缀，占用则加 _2、_3…）。 */
function usernameFromEmail(email) {
  let base = String(email.split('@')[0] || 'user')
    .toLowerCase()
    .replace(/[^a-z0-9_]/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 16);
  if (base.length < 3) base = `${base}user`.slice(0, 16);
  let username = base;
  let n = 1;
  while (findUserByUsername(username)) {
    n += 1;
    username = `${base}_${n}`;
  }
  return username;
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
  // ---------- 发送验证码 ----------
  // 短信（手机号模式注册 / 绑定手机号用）
  app.post('/auth/sms/send', async (req, reply) => {
    const phone = normalizePhone(req.body?.phone);
    if (!PHONE_RE.test(phone)) {
      return reply.code(400).send({ error: 'invalid_phone', message: '请填写正确的 11 位手机号' });
    }
    const issued = issueCode(`p:${phone}`);
    if (issued.error) return reply.code(issued.status).send({ error: issued.error, message: issued.message });
    const { code, expiresIn } = issued;
    const cfg = smsConfig();
    if (!cfg.devMode) {
      try {
        await sendSms(cfg, phone, code);
      } catch (e) {
        console.error(`[SMS] 发送失败 (${phone}): ${e.message}`);
        return reply.code(502).send({ error: 'sms_failed', message: '短信发送失败，请稍后再试' });
      }
      return { ok: true, expiresIn };
    }
    if (cfg.consoleMode) {
      console.log('═══════════════ 短信验证码 ═══════════════');
      console.log(`  手机号 ${phone} 的验证码：${code}`);
      console.log('  （5 分钟内有效，请发给要注册的朋友）');
      console.log('══════════════════════════════════════════');
      return { ok: true, consoleMode: true, expiresIn };
    }
    console.log(`[SMS][开发模式] ${phone} 的验证码: ${code}（未配置短信服务，验证码直接返回给 App）`);
    return { ok: true, devMode: true, devCode: code, expiresIn };
  });

  // 邮箱（邮箱模式注册 / 绑定邮箱用）
  app.post('/auth/email/send', async (req, reply) => {
    const email = normalizeEmail(req.body?.email);
    if (!EMAIL_RE.test(email)) {
      return reply.code(400).send({ error: 'invalid_email', message: '请填写正确的邮箱地址' });
    }
    const issued = issueCode(`e:${email}`);
    if (issued.error) return reply.code(issued.status).send({ error: issued.error, message: issued.message });
    const { code, expiresIn } = issued;
    const cfg = emailConfig();
    const consoleMode = smsConfig().consoleMode;
    if (!cfg.devMode) {
      try {
        await sendEmail(cfg, email, code);
      } catch (e) {
        console.error(`[Email] 发送失败 (${email}): ${e.message}`);
        return reply.code(502).send({ error: 'email_failed', message: `邮件发送失败：${e.message}` });
      }
      return { ok: true, expiresIn };
    }
    if (consoleMode) {
      console.log('═══════════════ 邮箱验证码 ═══════════════');
      console.log(`  邮箱 ${email} 的验证码：${code}`);
      console.log('  （5 分钟内有效，请发给要注册的朋友）');
      console.log('══════════════════════════════════════════');
      return { ok: true, consoleMode: true, expiresIn };
    }
    console.log(`[Email][开发模式] ${email} 的验证码: ${code}（未配置邮箱服务，验证码直接返回给 App）`);
    return { ok: true, devMode: true, devCode: code, expiresIn };
  });

  // ---------- 注册（按当前模式：email | phone） ----------
  app.post('/auth/register', async (req, reply) => {
    const { password, displayName } = req.body ?? {};
    const rawUsername = String(req.body?.username ?? '').trim();
    const autoUsername = rawUsername.length === 0; // 不带用户名 → 该模式的快捷注册
    const mode = authMode();

    if (String(password ?? '').length < 6) {
      return reply.code(400).send({ error: 'invalid_password', message: '密码至少 6 位' });
    }

    let identField; // 写入 user 的字段：phone 或 email
    let identValue;
    let genUsername;
    if (mode === 'email') {
      const email = normalizeEmail(req.body?.email);
      if (!EMAIL_RE.test(email)) {
        return reply.code(400).send({ error: 'invalid_email', message: '请填写正确的邮箱地址' });
      }
      const codeErr = checkCode(`e:${email}`, req.body?.code);
      if (codeErr) return reply.code(400).send({ error: 'bad_code', message: codeErr });
      if (findUsersByEmail(email).length >= MAX_ACCOUNTS_PER_IDENT) {
        return reply.code(400).send({
          error: 'ident_limit',
          message: `该邮箱绑定的账号已达上限（${MAX_ACCOUNTS_PER_IDENT} 个）`,
        });
      }
      identField = 'email';
      identValue = email;
      genUsername = () => usernameFromEmail(email);
    } else {
      const phone = normalizePhone(req.body?.phone);
      if (!PHONE_RE.test(phone)) {
        return reply.code(400).send({ error: 'invalid_phone', message: '请填写正确的 11 位手机号' });
      }
      const codeErr = checkCode(`p:${phone}`, req.body?.code);
      if (codeErr) return reply.code(400).send({ error: 'bad_code', message: codeErr });
      if (findUsersByPhone(phone).length >= MAX_ACCOUNTS_PER_IDENT) {
        return reply.code(400).send({
          error: 'ident_limit',
          message: `该手机号绑定的账号已达上限（${MAX_ACCOUNTS_PER_IDENT} 个）`,
        });
      }
      identField = 'phone';
      identValue = phone;
      genUsername = () => {
        let username = phone;
        let n = 1;
        while (findUserByUsername(username)) {
          n += 1;
          username = `${phone}_${n}`;
        }
        return username;
      };
    }

    let username;
    if (autoUsername) {
      username = genUsername();
    } else {
      if (!USERNAME_RE.test(rawUsername)) {
        return reply.code(400).send({
          error: 'invalid_username',
          message: '用户名需为 3-20 位字母、数字或下划线',
        });
      }
      if (findUserByUsername(rawUsername)) {
        return reply.code(409).send({ error: 'username_taken', message: '该用户名已被占用' });
      }
      username = rawUsername;
    }

    const dn = String(displayName ?? '').trim().slice(0, 32);
    const defaultDn =
      mode === 'email' ? String(identValue.split('@')[0]).slice(0, 32) : `用户${identValue.slice(-4)}`;
    const user = {
      id: newId('u'),
      username,
      displayName: dn || defaultDn || username,
      phone: mode === 'phone' ? identValue : '',
      email: mode === 'email' ? identValue : '',
      passwordHash: await hashPassword(String(password)),
      avatar: null,
      createdAt: now(),
    };
    db.data.users.push(user);
    await save();

    return { token: signToken(user.id), user: selfMe(user) };
  });

  // ---------- 某手机号 / 邮箱名下的所有账号（登录第一步） ----------
  app.post('/auth/accounts', async (req, reply) => {
    const email = normalizeEmail(req.body?.email);
    if (email) {
      if (!EMAIL_RE.test(email)) {
        return reply.code(400).send({ error: 'invalid_email', message: '请填写正确的邮箱地址' });
      }
      const accounts = findUsersByEmail(email)
        .sort((a, b) => (a.createdAt ?? 0) - (b.createdAt ?? 0))
        .slice(0, MAX_ACCOUNTS_PER_IDENT)
        .map((u) => publicUser(u));
      return { email, accounts };
    }
    const phone = normalizePhone(req.body?.phone);
    if (!PHONE_RE.test(phone)) {
      return reply.code(400).send({ error: 'invalid_phone', message: '请填写正确的 11 位手机号' });
    }
    const accounts = findUsersByPhone(phone)
      .sort((a, b) => (a.createdAt ?? 0) - (b.createdAt ?? 0))
      .slice(0, MAX_ACCOUNTS_PER_IDENT)
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
    return { token: signToken(user.id), user: selfMe(user) };
  });

  app.get('/auth/me', { preHandler: app.auth }, async (req) => ({
    user: selfMe(findUserById(req.userId)),
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
      const codeErr = checkCode(`p:${phone}`, req.body?.code);
      if (codeErr) {
        return reply.code(400).send({ error: 'bad_code', message: codeErr });
      }
      const others = findUsersByPhone(phone).filter((u) => u.id !== user.id);
      if (others.length >= MAX_ACCOUNTS_PER_IDENT) {
        return reply.code(400).send({
          error: 'ident_limit',
          message: `该手机号绑定的账号已达上限（${MAX_ACCOUNTS_PER_IDENT} 个）`,
        });
      }
      user.phone = phone;
    }
    if (typeof req.body?.email === 'string' && req.body.email.trim()) {
      const email = normalizeEmail(req.body.email);
      if (!EMAIL_RE.test(email)) {
        return reply.code(400).send({ error: 'invalid_email', message: '请填写正确的邮箱地址' });
      }
      const codeErr = checkCode(`e:${email}`, req.body?.code);
      if (codeErr) {
        return reply.code(400).send({ error: 'bad_code', message: codeErr });
      }
      const others = findUsersByEmail(email).filter((u) => u.id !== user.id);
      if (others.length >= MAX_ACCOUNTS_PER_IDENT) {
        return reply.code(400).send({
          error: 'ident_limit',
          message: `该邮箱绑定的账号已达上限（${MAX_ACCOUNTS_PER_IDENT} 个）`,
        });
      }
      user.email = email;
    }
    await save();
    return { user: selfMe(user) };
  });
}
