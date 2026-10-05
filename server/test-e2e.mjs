// End-to-end API smoke test for the sama-chat backend.
// Run: node test-e2e.mjs  (server must be on :8080)
import WebSocket from 'ws';

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

function connectWs(token) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://127.0.0.1:8080/ws?token=${token}`);
    const events = [];
    ws.on('message', (raw) => {
      const m = JSON.parse(raw.toString());
      events.push(m);
      if (m.event === 'connected') resolve({ ws, events });
    });
    ws.on('error', reject);
    setTimeout(() => reject(new Error('ws connect timeout')), 5000);
  });
}

const waitFor = (events, event, pred = null, ms = 4000) =>
  new Promise((resolve) => {
    const t0 = Date.now();
    const poll = () => {
      const found = events.find((e) => e.event === event && (!pred || pred(e.data)));
      if (found) return resolve(found.data);
      if (Date.now() - t0 > ms) return resolve(null);
      setTimeout(poll, 50);
    };
    poll();
  });

console.log('\n== 1. health & auth ==');
const health = await api('GET', '/health');
ok('health endpoint', health.json?.status === 'ok');

const r1 = await api('POST', '/auth/register', {
  body: { username: 'alice', password: 'secret123', displayName: '爱丽丝' },
});
ok('register alice', r1.status === 200 && !!r1.json?.token, JSON.stringify(r1.json));

const r2 = await api('POST', '/auth/register', {
  body: { username: 'bob', password: 'secret123', displayName: '鲍勃' },
});
const r3 = await api('POST', '/auth/register', {
  body: { username: 'carol', password: 'secret123', displayName: '卡罗' },
});
ok('register bob & carol', r2.status === 200 && r3.status === 200);

const dup = await api('POST', '/auth/register', {
  body: { username: 'alice', password: 'secret123' },
});
ok('duplicate username rejected', dup.status === 409);

const badLogin = await api('POST', '/auth/login', {
  body: { username: 'alice', password: 'wrong' },
});
ok('wrong password rejected', badLogin.status === 401);

const login = await api('POST', '/auth/login', {
  body: { username: 'alice', password: 'secret123' },
});
ok('login works', login.status === 200 && !!login.json?.token);

const A = login.json.token;
const B = r2.json.token;
const C = r3.json.token;
const idA = login.json.user.id, idB = r2.json.user.id, idC = r3.json.user.id;

const me = await api('GET', '/auth/me', { token: A });
ok('GET /auth/me', me.json?.user?.username === 'alice');
ok('passwordHash never leaked', !JSON.stringify(me.json).includes('scrypt$'));

console.log('\n== 2. users & QR ==');
const search = await api('GET', '/users/search?q=bob', { token: A });
ok('search finds bob', search.json?.users?.some((u) => u.username === 'bob'));

const qr = await api('GET', '/users/qr', { token: B });
ok('QR payload format', qr.json?.payload === `samachat://add?uid=${idB}`);

const resolved = await api('GET', `/users/resolve/${idB}`, { token: A });
ok('QR resolve finds bob', resolved.json?.user?.username === 'bob');
ok('resolve reports isFriend=false', resolved.json?.user?.isFriend === false);

console.log('\n== 3. friends ==');
const fq = await api('POST', '/friends/request', { token: A, body: { userId: idB } });
ok('friend request sent', fq.status === 200 && fq.json?.request?.status === 'pending');

const reqs = await api('GET', '/friends/requests', { token: B });
ok('bob sees incoming request', reqs.json?.incoming?.length === 1);

const accepted = await api('POST', '/friends/respond', {
  token: B, body: { requestId: fq.json.request.id, accept: true },
});
ok('bob accepts', accepted.json?.request?.status === 'accepted');

const friendsA = await api('GET', '/friends', { token: A });
ok('alice now has bob as friend', friendsA.json?.friends?.some((f) => f.id === idB));

const resolve2 = await api('GET', `/users/resolve/${idB}`, { token: A });
ok('isFriend=true after accept', resolve2.json?.user?.isFriend === true);

console.log('\n== 4. private chat via WebSocket ==');
const alice = await connectWs(A);
const bob = await connectWs(B);
ok('both sockets connected', true);

const conv = await api('POST', '/conversations/private', { token: A, body: { userId: idB } });
ok('private conversation created', !!conv.json?.conversation?.id);
const convId = conv.json.conversation.id;

alice.ws.send(JSON.stringify({
  event: 'message:send',
  data: { conversationId: convId, content: '你好 Bob！' },
}));
const delivered = await waitFor(bob.events, 'message:new');
ok('bob receives message in realtime', delivered?.message?.content === '你好 Bob！');

alice.ws.send(JSON.stringify({
  event: 'typing', data: { conversationId: convId, typing: true },
}));
const typingEvt = await waitFor(bob.events, 'typing');
ok('typing indicator relayed', typingEvt?.typing === true);

bob.ws.send(JSON.stringify({
  event: 'message:read', data: { conversationId: convId },
}));
const readEvt = await waitFor(alice.events, 'message:read');
ok('read receipt relayed', readEvt?.userId === idB);

const history = await api('GET', `/conversations/${convId}/messages`, { token: B });
ok('message history persisted', history.json?.messages?.length === 1);

const convList = await api('GET', '/conversations', { token: B });
const bConv = convList.json?.conversations?.find((c) => c.id === convId);
ok('conversation list shows last message', bConv?.lastMessage?.content === '你好 Bob！');
ok('unread count zero after read', bConv?.unread === 0);

console.log('\n== 5. group chat ==');
const grp = await api('POST', '/conversations/group', {
  token: A, body: { name: '测试群', memberIds: [idB, idC] },
});
ok('group created', grp.json?.conversation?.memberIds?.length === 3);
const grpId = grp.json.conversation.id;

const carol = await connectWs(C);
alice.ws.send(JSON.stringify({
  event: 'message:send',
  data: { conversationId: grpId, content: '群消息测试' },
}));
const gDelivered = await waitFor(carol.events, 'message:new', (d) => d?.message?.content === '群消息测试');
ok('carol receives group message', gDelivered?.message?.content === '群消息测试');
const gDeliveredB = await waitFor(bob.events, 'message:new', (d) => d?.message?.content === '群消息测试');
ok('bob also receives group message', gDeliveredB?.message?.content === '群消息测试');

console.log('\n== 6. moments (炫圈) ==');
const noAuth = await api('GET', '/moments');
ok('moments require auth', noAuth.status === 401);

const post = await api('POST', '/moments', {
  token: A, body: { text: '今天天气真好 ☀️', images: [] },
});
ok('moment posted', !!post.json?.moment?.id);
const momentId = post.json.moment.id;

const feedB = await api('GET', '/moments', { token: B });
ok('friend sees moment in feed', feedB.json?.moments?.some((m) => m.id === momentId));
ok('moment includes author info', feedB.json?.moments?.[0]?.author?.username === 'alice');

const like = await api('POST', `/moments/${momentId}/like`, { token: B });
ok('like works', like.json?.liked === true && like.json?.likeCount === 1);
const unlike = await api('POST', `/moments/${momentId}/like`, { token: B });
ok('unlike works', unlike.json?.liked === false && unlike.json?.likeCount === 0);

const comment = await api('POST', `/moments/${momentId}/comment`, {
  token: B, body: { text: '确实不错！' },
});
ok('comment works', comment.json?.comment?.text === '确实不错！');

const feedC = await api('GET', '/moments', { token: C });
ok('non-friend cannot see moment', !feedC.json?.moments?.some((m) => m.id === momentId));

console.log('\n== 7. image upload ==');
const pngB64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const up = await api('POST', '/upload', { token: A, body: { data: pngB64, ext: 'png' } });
ok('upload succeeds', up.status === 200 && !!up.json?.url);
const imgRes = await fetch(BASE + up.json.url);
ok('uploaded image served', imgRes.status === 200 && imgRes.headers.get('content-type') === 'image/png');
const badExt = await api('POST', '/upload', { token: A, body: { data: pngB64, ext: 'exe' } });
ok('bad extension rejected', badExt.status === 400);
const traversal = await fetch(`${BASE}/uploads/..%2F..%2Fpackage.json`);
ok('path traversal blocked', traversal.status === 404);
const noAuthUp = await api('POST', '/upload', { body: { data: pngB64, ext: 'png' } });
ok('upload requires auth', noAuthUp.status === 401);

console.log('\n== 8. REST message send ==');
const restMsg = await api('POST', `/conversations/${convId}/messages`, {
  token: A, body: { content: 'REST 发送' },
});
ok('REST send persists', restMsg.status === 200 && restMsg.json?.message?.content === 'REST 发送');
const hist2 = await api('GET', `/conversations/${convId}/messages`, { token: B });
ok('REST message in history', hist2.json?.messages?.some((m) => m.content === 'REST 发送'));
const restEmpty = await api('POST', `/conversations/${convId}/messages`, { token: A, body: { content: '' } });
ok('empty REST message rejected', restEmpty.status === 400);

console.log('\n== 9. 消息撤回 ==');
const fresh = await api('POST', `/conversations/${convId}/messages`, {
  token: A, body: { content: '这条稍后会撤回' },
});
const freshId = fresh.json.message.id;
await new Promise((r) => setTimeout(r, 400));
const rec1 = await api('POST', `/conversations/${convId}/messages/${freshId}/recall`, { token: A });
ok('撤回自己的消息', rec1.status === 200 && rec1.json?.message?.recalled === true);
const recalledEvt = await waitFor(bob.events, 'message:recalled', (d) => d?.messageId === freshId);
ok('bob 实时收到撤回事件', !!recalledEvt);
const hist3 = await api('GET', `/conversations/${convId}/messages`, { token: B });
const recalledMsg = hist3.json?.messages?.find((m) => m.id === freshId);
ok('历史记录中内容已清空', recalledMsg?.recalled === true && recalledMsg?.content === '');
const rec2 = await api('POST', `/conversations/${convId}/messages/${freshId}/recall`, { token: B });
ok('不能撤回别人的消息', rec2.status === 403);
const rec3 = await api('POST', `/conversations/${convId}/messages/${freshId}/recall`, { token: A });
ok('重复撤回幂等', rec3.status === 200);

alice.ws.close(); bob.ws.close(); carol.ws.close();

console.log(`\n===== RESULT: ${pass} passed, ${fail} failed =====`);
process.exit(fail === 0 ? 0 : 1);
