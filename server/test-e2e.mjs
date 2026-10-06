// End-to-end API smoke test for the sama-chat backend.
// Run: AUTH_MODE=phone node test-e2e.mjs  (server must run with the same env, on :8080)
import WebSocket from 'ws';
import http from 'node:http';

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

// 发送短信验证码（测试环境为开发模式，devCode 直接返回）
const sendCode = async (phone) => {
  const r = await api('POST', '/auth/sms/send', { body: { phone } });
  return { status: r.status, code: r.json?.devCode, devMode: r.json?.devMode };
};

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
ok('authMode=phone（配合 AUTH_MODE=phone 运行）', health.json?.authMode === 'phone', String(health.json?.authMode));

const cA = await sendCode('13800000001');
ok('发送验证码（开发模式返回 devCode）', cA.status === 200 && cA.devMode === true && /^\d{6}$/.test(cA.code ?? ''));
const r1 = await api('POST', '/auth/register', {
  body: { username: 'alice', password: 'secret123', displayName: '爱丽丝', phone: '13800000001', code: cA.code },
});
ok('register alice', r1.status === 200 && !!r1.json?.token, JSON.stringify(r1.json));

const cB = await sendCode('13800000002');
const r2 = await api('POST', '/auth/register', {
  body: { username: 'bob', password: 'secret123', displayName: '鲍勃', phone: '13800000002', code: cB.code },
});
const cC = await sendCode('13800000003');
const r3 = await api('POST', '/auth/register', {
  body: { username: 'carol', password: 'secret123', displayName: '卡罗', phone: '13800000003', code: cC.code },
});
ok('register bob & carol', r2.status === 200 && r3.status === 200);

const cD = await sendCode('13800000004');
const dup = await api('POST', '/auth/register', {
  body: { username: 'alice', password: 'secret123', phone: '13800000004', code: cD.code },
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

console.log('\n== 10. 好友备注 ==');
const rm1 = await api('PATCH', `/friends/${idB}`, { token: A, body: { remark: '好哥们' } });
ok('设置备注成功', rm1.status === 200 && rm1.json?.remark === '好哥们');
const fl1 = await api('GET', '/friends', { token: A });
ok('好友列表带备注', fl1.json?.friends?.find((f) => f.id === idB)?.remark === '好哥们');
const cvl = await api('GET', '/conversations', { token: A });
const pcv = cvl.json?.conversations?.find(
  (c) => c.type === 'private' && c.memberIds.includes(idB),
);
ok('私聊名称使用备注显示', pcv?.name === '好哥们');

console.log('\n== 11. 群管理 ==');
const rn1 = await api('PATCH', `/conversations/${grpId}`, { token: B, body: { name: '越权改名' } });
ok('普通成员不能改群名', rn1.status === 403);
const rn2 = await api('PATCH', `/conversations/${grpId}`, { token: A, body: { name: '测试群·改' } });
ok('群主改群名成功', rn2.status === 200 && rn2.json?.conversation?.name === '测试群·改');
const ad1 = await api('POST', `/conversations/${grpId}/admins`, { token: A, body: { userId: idB } });
ok('群主设置管理员', ad1.status === 200 && ad1.json?.conversation?.adminIds?.includes(idB));
const ad2 = await api('POST', `/conversations/${grpId}/admins`, { token: B, body: { userId: idC } });
ok('管理员不能任命管理员', ad2.status === 403);
const mu1 = await api('POST', `/conversations/${grpId}/mute`, { token: B, body: { userId: idC, minutes: 10 } });
ok('管理员禁言成员', mu1.status === 200);
const cSend1 = await api('POST', `/conversations/${grpId}/messages`, { token: C, body: { content: '我被禁言了？' } });
ok('被禁言成员发消息被拒', cSend1.status === 403);
const mu2 = await api('POST', `/conversations/${grpId}/mute`, { token: B, body: { userId: idC, minutes: 0 } });
ok('解除禁言', mu2.status === 200);
const cSend2 = await api('POST', `/conversations/${grpId}/messages`, { token: C, body: { content: '能发了' } });
ok('解除后可发言', cSend2.status === 200);
const mu3 = await api('POST', `/conversations/${grpId}/mute`, { token: B, body: { userId: idA, minutes: 10 } });
ok('管理员不能禁言群主', mu3.status === 403);
const kk1 = await api('POST', `/conversations/${grpId}/kick`, { token: B, body: { userId: idC } });
ok('管理员踢出成员', kk1.status === 200 && !kk1.json?.conversation?.memberIds?.includes(idC));
const cSend3 = await api('POST', `/conversations/${grpId}/messages`, { token: C, body: { content: '还在吗' } });
ok('被踢出后不能发言', cSend3.status === 404);
const tr1 = await api('POST', `/conversations/${grpId}/transfer`, { token: A, body: { userId: idB } });
ok('转交群主成功', tr1.status === 200 && tr1.json?.conversation?.ownerId === idB);
const tr2 = await api('POST', `/conversations/${grpId}/transfer`, { token: B, body: { userId: idA } });
ok('30 天内不能再次转交', tr2.status === 400);
const mem1 = await api('GET', `/conversations/${grpId}/members`, { token: A });
ok('成员角色正确（bob=群主, alice=管理员）',
  mem1.json?.members?.some((m) => m.id === idB && m.role === 'owner') &&
  mem1.json?.members?.some((m) => m.id === idA && m.role === 'admin'));

console.log('\n== 12. 删除好友 / 黑名单 ==');
const del1 = await api('DELETE', `/friends/${idB}`, { token: A });
ok('删除好友', del1.status === 200);
const flA2 = await api('GET', '/friends', { token: A });
const flB2 = await api('GET', '/friends', { token: B });
ok('双方好友列表都已移除',
  !flA2.json?.friends?.some((f) => f.id === idB) &&
  !flB2.json?.friends?.some((f) => f.id === idA));
await api('POST', '/friends/request', { token: C, body: { userId: idA } });
const rqA = await api('GET', '/friends/requests', { token: A });
const fromCarol = rqA.json?.incoming?.find((r) => r.fromId === idC);
await api('POST', '/friends/respond', { token: A, body: { requestId: fromCarol.id, accept: true } });
const blk1 = await api('POST', '/blocks', { token: A, body: { userId: idC } });
ok('拉黑成功', blk1.status === 200);
const flA3 = await api('GET', '/friends', { token: A });
ok('拉黑后好友关系保留', flA3.json?.friends?.some((f) => f.id === idC));
const cvCA = await api('POST', '/conversations/private', { token: C, body: { userId: idA } });
const cvCAId = cvCA.json?.conversation?.id;
const cB1 = await api('POST', `/conversations/${cvCAId}/messages`, { token: C, body: { content: '在吗' } });
ok('被拉黑者发消息被拒收', cB1.status === 403);
const cB2 = await api('POST', '/friends/request', { token: C, body: { userId: idA } });
ok('被拉黑者加好友被拒', cB2.status === 403);
const bl1 = await api('GET', '/blocks', { token: A });
ok('黑名单列表可见', bl1.json?.blocks?.some((u) => u.id === idC));
const mCarol = await api('POST', '/moments', { token: C, body: { text: 'carol 的测试动态' } });
const feedA1 = await api('GET', '/moments', { token: A });
ok('拉黑后看不到对方炫圈', !feedA1.json?.moments?.some((m) => m.id === mCarol.json?.moment?.id));
const feedC1 = await api('GET', '/moments', { token: C });
ok('（反向）也看不到对方的炫圈', !feedC1.json?.moments?.some((m) => m.authorId === idA));
await api('DELETE', `/blocks/${idC}`, { token: A });
const cB4 = await api('POST', `/conversations/${cvCAId}/messages`, { token: C, body: { content: '解除后发送' } });
ok('解除后可以正常发消息', cB4.status === 200);
const flA4 = await api('GET', '/friends', { token: A });
ok('解除后好友仍在列表', flA4.json?.friends?.some((f) => f.id === idC));

console.log('\n== 13. 炫圈删除（2 分钟窗口）==');
const md1 = await api('POST', '/moments', { token: A, body: { text: '待删除的动态' } });
const md1Id = md1.json?.moment?.id;
const delM1 = await api('DELETE', `/moments/${md1Id}`, { token: A });
ok('窗口内可删除自己的动态', delM1.status === 200, JSON.stringify(delM1.json));
const feedBAfter = await api('GET', '/moments', { token: B });
ok('删除后别人看不到了', !feedBAfter.json?.moments?.some((m) => m.id === md1Id));
await new Promise((r) => setTimeout(r, 400));
ok('好友收到 moment:deleted 事件', carol.events.some((e) => e.event === 'moment:deleted' && e.data?.momentId === md1Id));
const md2 = await api('POST', '/moments', { token: A, body: { text: '不给你删' } });
const delM2 = await api('DELETE', `/moments/${md2.json?.moment?.id}`, { token: B });
ok('不能删除别人的动态', delM2.status === 403);
const delM4 = await api('DELETE', `/moments/${md1Id}`, { token: A });
ok('重复删除返回 404', delM4.status === 404);
const WIN = Number(process.env.MOMENT_DELETE_WINDOW_MS ?? 120000);
if (WIN < 10000) {
  const md3 = await api('POST', '/moments', { token: A, body: { text: '过期不能删' } });
  await new Promise((r) => setTimeout(r, WIN + 800));
  const delM3 = await api('DELETE', `/moments/${md3.json?.moment?.id}`, { token: A });
  ok('超过窗口后不能删除', delM3.status === 403, JSON.stringify(delM3.json));
} else {
  console.log('  ⏭️  跳过过期场景（设置 MOMENT_DELETE_WINDOW_MS 后重跑）');
}

console.log('\n== 14. 视频上传与视频消息 ==');
const fakeVideo = Buffer.concat([
  Buffer.from('00000020667479706d703432', 'hex'),
  Buffer.alloc(2048, 7),
]);
// iSH 的 fetch polyfill 会把 Buffer body JSON 化，这里用原生 http 发送二进制。
const rawPost = (p, headers, buf) =>
  new Promise((resolve, reject) => {
    const req = http.request(`${BASE}${p}`, {
      method: 'POST',
      headers: { ...headers, 'Content-Length': buf.length },
    }, (res) => {
      let data = '';
      res.on('data', (c) => (data += c));
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    });
    req.on('error', reject);
    req.end(buf);
  });
const upv = await rawPost('/upload/video?ext=mp4', { Authorization: `Bearer ${A}`, 'Content-Type': 'application/octet-stream' }, fakeVideo);
let upvJson = null;
try { upvJson = JSON.parse(upv.body); } catch {}
ok('视频上传成功', upv.status === 200 && upvJson?.size === fakeVideo.length && typeof upvJson?.url === 'string', upv.body);
const badExtV = await rawPost('/upload/video?ext=exe', { Authorization: `Bearer ${A}`, 'Content-Type': 'application/octet-stream' }, fakeVideo);
ok('非法扩展名被拒', badExtV.status === 400);
const vmsg = await api('POST', `/conversations/${cvCAId}/messages`, {
  token: A,
  body: { content: upvJson.url, type: 'video' },
});
ok('视频消息发送成功', vmsg.status === 200 && vmsg.json?.message?.type === 'video');
const histV = await api('GET', `/conversations/${cvCAId}/messages`, { token: A });
ok('历史消息类型为 video', histV.json?.messages?.some((m) => m.id === vmsg.json?.message?.id && m.type === 'video'));
const mgFull = await fetch(`${BASE}${upvJson.url}`);
ok('媒体可访问 (200)', mgFull.status === 200 && Number(mgFull.headers.get('content-length')) === fakeVideo.length);
await mgFull.arrayBuffer();
const mgRange = await fetch(`${BASE}${upvJson.url}`, { headers: { Range: 'bytes=0-3' } });
ok('Range 请求返回 206', mgRange.status === 206);
const mgBody = Buffer.from(await mgRange.arrayBuffer());
ok('Range 内容长度正确', mgBody.length === 4);

console.log('\n== 15. 手机号注册 / 多账号登录（验证码）==');
const c15 = await sendCode('13900000001');
const pr1 = await api('POST', '/auth/register', { body: { phone: '13900000001', password: 'secret123', code: c15.code } });
ok('手机号注册成功（用户名=手机号）', pr1.status === 200 && pr1.json?.user?.username === '13900000001', JSON.stringify(pr1.json));
ok('默认昵称为 用户+尾号', pr1.json?.user?.displayName === '用户0001');
const pr2 = await api('POST', '/auth/register', { body: { phone: '13900000001', password: 'secret456', displayName: '二号机', code: c15.code } });
ok('同手机号再注册（多账号，同一验证码）', pr2.status === 200 && pr2.json?.user?.username === '13900000001_2', JSON.stringify(pr2.json));
const pr3 = await api('POST', '/auth/register', { body: { username: 'zoe', password: 'secret789', displayName: '佐伊', phone: '13900000001', code: c15.code } });
ok('账号注册可绑定同一手机号', pr3.status === 200 && pr3.json?.user?.phone === '13900000001');
const np1 = await api('POST', '/auth/register', { body: { username: 'nophone', password: 'secret123' } });
ok('账号注册必须绑定手机号', np1.status === 400);
const nc1 = await api('POST', '/auth/register', { body: { phone: '13944444444', password: 'secret123' } });
ok('不带验证码注册被拒', nc1.status === 400);
await sendCode('13944444444');
const wc1 = await api('POST', '/auth/register', { body: { phone: '13944444444', password: 'secret123', code: '000000' } });
ok('验证码错误被拒', wc1.status === 400 && wc1.json?.error === 'bad_code', JSON.stringify(wc1.json));
const ip1 = await api('POST', '/auth/register', { body: { phone: '123', password: 'secret123', code: '123456' } });
ok('非法手机号注册被拒', ip1.status === 400);
const ac1 = await api('POST', '/auth/accounts', { body: { phone: '13900000001' } });
ok('手机号可查到名下 3 个账号', ac1.json?.accounts?.length === 3, JSON.stringify(ac1.json));
const unames = (ac1.json?.accounts ?? []).map((a) => a.username);
ok('列表含三种用户名（手机号/_2/自定义）', unames.includes('13900000001') && unames.includes('13900000001_2') && unames.includes('zoe'));
const acNone = await api('POST', '/auth/accounts', { body: { phone: '13911111111' } });
ok('查无此号返回空列表', acNone.status === 200 && acNone.json?.accounts?.length === 0);
const acBad = await api('POST', '/auth/accounts', { body: { phone: '12345' } });
ok('非法手机号查询被拒', acBad.status === 400);
const login2 = await api('POST', '/auth/login', { body: { username: '13900000001_2', password: 'secret456' } });
ok('多账号之一可正常登录', login2.status === 200 && login2.json?.user?.username === '13900000001_2');
const cBind = await sendCode('13955555555');
const bind1 = await api('PATCH', '/auth/me', { token: A, body: { phone: '13955555555', code: cBind.code } });
ok('老账号可绑定手机号（验证码校验）', bind1.status === 200 && bind1.json?.user?.phone === '13955555555');
const ac2 = await api('POST', '/auth/accounts', { body: { phone: '13955555555' } });
ok('绑定后该号码可查到 alice', ac2.json?.accounts?.length === 1 && ac2.json?.accounts?.[0]?.username === 'alice');
const badBind = await api('PATCH', '/auth/me', { token: A, body: { phone: '999', code: '123456' } });
ok('非法手机号绑定被拒', badBind.status === 400);

console.log('\n== 16. 验证码机制（频率 / 过期 / 错误次数）==');
const f1 = await sendCode('13966666666');
const f2 = await sendCode('13966666666');
ok('重复发送被频率限制', f1.status === 200 && f2.status === 429, `${f1.status}/${f2.status}`);
const ex1 = await api('POST', '/auth/register', { body: { phone: '13977777777', password: 'secret123', code: '123456' } });
ok('未发送验证码直接注册被拒', ex1.status === 400);
const tx = await sendCode('13977777777');
await new Promise((r) => setTimeout(r, Number(process.env.SMS_CODE_TTL_MS ?? 300000) + 1200));
const ex2 = await api('POST', '/auth/register', { body: { phone: '13977777777', password: 'secret123', code: tx.code } });
ok('验证码过期后注册被拒', ex2.status === 400, JSON.stringify(ex2.json));
const ay = await sendCode('13988888888');
for (let i = 0; i < 5; i++) {
  await api('POST', '/auth/register', { body: { phone: '13988888888', password: 'secret123', code: '111111' } });
}
const ex3 = await api('POST', '/auth/register', { body: { phone: '13988888888', password: 'secret123', code: ay.code } });
ok('错误 5 次后验证码作废', ex3.status === 400, JSON.stringify(ex3.json));

console.log('\n== 17. 公告系统 ==');
const annNoPerm = await api('POST', '/announce', { token: A, body: { content: '测试' } });
ok('普通用户发公告被拒(403)', annNoPerm.status === 403);
ok('普通用户 canAnnounce=false', me.json?.user?.canAnnounce === false);
const cH = await sendCode('13800000005');
const rH = await api('POST', '/auth/register', {
  body: { username: 'huzhi', password: 'secret123', displayName: 'huzhi', phone: '13800000005', code: cH.code },
});
ok('huzhi 管理员账号注册成功', rH.status === 200 && !!rH.json?.token);
ok('huzhi canAnnounce=true', rH.json?.user?.canAnnounce === true);
const H = rH.json.token;
const rHMe = await api('GET', '/auth/me', { token: H });
ok('GET /auth/me 含 canAnnounce', rHMe.json?.user?.canAnnounce === true);
const annWatcher = await connectWs(B);
const pub = await api('POST', '/announce', { token: H, body: { content: '你好，这是一条测试公告' } });
ok('管理员发布公告成功', pub.status === 200 && pub.json?.ok === true && pub.json?.announcement?.content === '你好，这是一条测试公告');
const annPush = await waitFor(annWatcher.events, 'announce:new', (d) => d?.announcement?.content === '你好，这是一条测试公告');
ok('在线用户实时收到公告推送', !!annPush);
const annList = await api('GET', '/announce', { token: B });
ok('登录后可拉取未读公告', Array.isArray(annList.json?.announcements) && annList.json.announcements.some((x) => x.content === '你好，这是一条测试公告'));
const annIds = (annList.json?.announcements ?? []).map((x) => x.id);
const annAck = await api('POST', '/announce/ack', { token: B, body: { ids: annIds } });
ok('标记公告已读', annAck.status === 200 && annAck.json?.ok === true);
const annList2 = await api('GET', '/announce', { token: B });
ok('已读后不再下发（只弹一次）', !(annList2.json?.announcements ?? []).some((x) => annIds.includes(x.id)));
const annNoAuth = await api('GET', '/announce');
ok('未登录拉公告被拒(401)', annNoAuth.status === 401);
const annEmpty = await api('POST', '/announce', { token: H, body: { content: '   ' } });
ok('空公告被拒(400)', annEmpty.status === 400);
annWatcher.ws.close();

console.log('\n== 18. 表情消息（sticker 类型）==');
const stUp = await api('POST', '/upload', { token: A, body: { data: pngB64, ext: 'png' } });
ok('表情图片上传成功', stUp.status === 200 && !!stUp.json?.url);
const stMsg = await api('POST', `/conversations/${convId}/messages`, {
  token: A, body: { content: stUp.json.url, type: 'sticker' },
});
ok('发送表情消息(type=sticker)', stMsg.status === 200 && stMsg.json?.message?.type === 'sticker');
const stHist = await api('GET', `/conversations/${convId}/messages`, { token: B });
ok('历史里表情类型保留', stHist.json?.messages?.some((m) => m.type === 'sticker' && m.content === stUp.json.url));
const weirdMsg = await api('POST', `/conversations/${convId}/messages`, {
  token: A, body: { content: 'x', type: 'weird' },
});
ok('非法类型回退为文本', weirdMsg.status === 200 && weirdMsg.json?.message?.type === 'text');

alice.ws.close(); bob.ws.close(); carol.ws.close();

console.log(`\n===== RESULT: ${pass} passed, ${fail} failed =====`);
process.exit(fail === 0 ? 0 : 1);
