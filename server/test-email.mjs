// Email-mode e2e test for sama-chat.
// Run: node test-email.mjs  (server in default email mode, on :8080)
const BASE = 'http://127.0.0.1:8080';
let pass = 0, fail = 0;

const ok = (name, cond, extra = '') => {
  if (cond) { pass++; console.log(`  ✅ ${name}`); }
  else { fail++; console.log(`  ❌ ${name} ${extra}`); }
};

async function api(method, path, { token, body } = {}) {
  const res = await fetch(BASE + path, {
    method,
    headers: {
      ...(body ? { 'Content-Type': 'application/json' } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  let json = null;
  try { json = await res.json(); } catch {}
  return { status: res.status, json };
}

const sendEmailCode = async (email) => {
  const r = await api('POST', '/auth/email/send', { body: { email } });
  return { status: r.status, code: r.json?.devCode, devMode: r.json?.devMode };
};

console.log('\n== 邮箱模式（默认）==');
const health = await api('GET', '/health');
ok('authMode=email（默认值）', health.json?.authMode === 'email', String(health.json?.authMode));

const b1 = await api('POST', '/auth/email/send', { body: { email: '不是邮箱' } });
ok('非法邮箱被拒', b1.status === 400);

const c1 = await sendEmailCode('zhangsan@qq.com');
ok('邮箱验证码（开发模式返回）', c1.status === 200 && c1.devMode === true && /^\d{6}$/.test(c1.code ?? ''));

const rE = await api('POST', '/auth/register', { body: { email: 'zhangsan@qq.com', password: 'secret123', code: c1.code } });
ok('邮箱注册成功（用户名=邮箱前缀）', rE.status === 200 && rE.json?.user?.username === 'zhangsan', JSON.stringify(rE.json));
ok('返回带 email 字段', rE.json?.user?.email === 'zhangsan@qq.com');
ok('默认昵称=邮箱前缀', rE.json?.user?.displayName === 'zhangsan');
const tokA = rE.json?.token;

const rE2 = await api('POST', '/auth/register', { body: { email: 'ZHANGSAN@qq.com', password: 'secret456', code: c1.code } });
ok('同邮箱再注册（大小写不敏感 → 多账号）', rE2.status === 200 && rE2.json?.user?.username === 'zhangsan_2', JSON.stringify(rE2.json));

const cBob = await sendEmailCode('bob@163.com');
const rE3 = await api('POST', '/auth/register', { body: { username: 'bob', email: 'bob@163.com', password: 'secret789', displayName: '鲍勃', code: cBob.code } });
ok('账号注册模式 + 邮箱验证', rE3.status === 200 && rE3.json?.user?.email === 'bob@163.com');

const rBad = await api('POST', '/auth/register', { body: { email: 'new@qq.com', password: 'secret123', code: '000000' } });
ok('未发送/错误验证码注册被拒', rBad.status === 400);

const rPhone = await api('POST', '/auth/register', { body: { phone: '13800000099', password: 'secret123', code: '123456' } });
ok('邮箱模式下手机号注册被拒', rPhone.status === 400, JSON.stringify(rPhone.json));

const ac = await api('POST', '/auth/accounts', { body: { email: 'zhangsan@qq.com' } });
ok('邮箱可查到名下 2 个账号', ac.json?.accounts?.length === 2, JSON.stringify(ac.json));
ok('账号列表不含敏感信息', !JSON.stringify(ac.json?.accounts ?? []).includes('passwordHash'));

const lg = await api('POST', '/auth/login', { body: { username: 'zhangsan', password: 'secret123' } });
ok('账号密码登录保留可用', lg.status === 200 && lg.json?.user?.username === 'zhangsan');

const cBind = await sendEmailCode('lisi@163.com');
const bd = await api('PATCH', '/auth/me', { token: tokA, body: { email: 'lisi@163.com', code: cBind.code } });
ok('可绑定 / 换绑邮箱', bd.status === 200 && bd.json?.user?.email === 'lisi@163.com');
const ac2 = await api('POST', '/auth/accounts', { body: { email: 'lisi@163.com' } });
ok('换绑后新邮箱可查到该账号', ac2.json?.accounts?.some((a) => a.username === 'zhangsan'));
const bd2 = await api('PATCH', '/auth/me', { token: tokA, body: { email: 'x@qq.com', code: '999999' } });
ok('坏验证码换绑被拒', bd2.status === 400);

const cPhone = await api('POST', '/auth/sms/send', { body: { phone: '13800000111' } });
ok('短信接口仍可用（供绑定手机号）', cPhone.status === 200 && !!cPhone.json?.devCode);
const bd3 = await api('PATCH', '/auth/me', { token: tokA, body: { phone: '13800000111', code: cPhone.json?.devCode } });
ok('邮箱模式下也可绑定手机号', bd3.status === 200 && bd3.json?.user?.phone === '13800000111');

console.log(`\n===== RESULT: ${pass} passed, ${fail} failed =====`);
process.exit(fail ? 1 : 0);
