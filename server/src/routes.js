// REST surface: friends (incl. QR-code face-to-face add), conversations,
// message history, and moments (朋友圈 / 炫圈).
import {
  db,
  newId,
  now,
  publicUser,
  findUserById,
  areFriends,
  friendIdsOf,
  addFriendPair,
  friendRecord,
  removeFriendship,
  isBlocked,
  blockIdsOf,
  conversationSendBlock,
  ensurePrivateConversation,
  conversationsOf,
  lastMessageOf,
  formerMembersOf,
  save,
} from './store.js';
import fs from 'node:fs';
import path from 'node:path';
import { canAnnounce } from './auth.js';

// Where uploaded images live. Served back at /uploads/<file>.
export const UPLOAD_DIR =
  process.env.UPLOAD_DIR || path.resolve(process.cwd(), 'uploads');
fs.mkdirSync(UPLOAD_DIR, { recursive: true });

const ALLOWED_EXT = new Set(['jpg', 'jpeg', 'png', 'gif', 'webp']);
const ALLOWED_VIDEO_EXT = new Set([
  'mp4', 'mov', 'm4v', 'webm', // 视频
  'm4a', 'aac', 'mp3', 'wav', 'ogg', 'opus', // 音频（语音消息）
]);
const MIME = {
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  png: 'image/png',
  gif: 'image/gif',
  webp: 'image/webp',
  mp4: 'video/mp4',
  mov: 'video/quicktime',
  m4v: 'video/x-m4v',
  webm: 'video/webm',
  m4a: 'audio/mp4',
  aac: 'audio/aac',
  mp3: 'audio/mpeg',
  wav: 'audio/wav',
};
const MAX_UPLOAD_BYTES = 6 * 1024 * 1024;
const MAX_VIDEO_BYTES = 48 * 1024 * 1024;
const MAX_FILE_BYTES = 25 * 1024 * 1024;
const MEDIA_NAME_RE =
  /^(?:(img|vid)_[A-Za-z0-9_-]{6,48}\.(jpg|jpeg|png|gif|webp|mp4|mov|m4v|webm|m4a|aac|mp3|wav|ogg|opus)|f_[A-Za-z0-9_-]{6,48}(\.[A-Za-z0-9]{1,10})?)$/;

export function registerApiRoutes(app, io) {
  // ---------- uploads ----------
  app.post('/upload', { preHandler: app.auth }, async (req, reply) => {
    const { data, ext } = req.body ?? {};
    const cleanExt = String(ext ?? 'jpg').toLowerCase().replace(/^\./, '');
    if (!ALLOWED_EXT.has(cleanExt)) {
      return reply.code(400).send({ error: 'bad_ext', message: '不支持的图片格式' });
    }
    if (typeof data !== 'string' || !data) {
      return reply.code(400).send({ error: 'empty', message: '图片数据为空' });
    }
    let buf;
    try {
      buf = Buffer.from(data, 'base64');
    } catch {
      return reply.code(400).send({ error: 'bad_base64', message: '图片数据异常' });
    }
    if (buf.length === 0 || buf.length > MAX_UPLOAD_BYTES) {
      return reply.code(413).send({ error: 'too_large', message: '图片过大（限 6MB）' });
    }
    const name = `${newId('img')}.${cleanExt}`;
    fs.writeFileSync(path.join(UPLOAD_DIR, name), buf);
    return { url: `/uploads/${name}`, size: buf.length };
  });

  // 通用文件上传（任意类型：文档/压缩包/音频等；原始二进制）。
  app.post(
    '/upload/file',
    { preHandler: app.auth, bodyLimit: 27 * 1024 * 1024 },
    async (req, reply) => {
      const ext = String(req.query?.ext ?? '')
        .toLowerCase()
        .replace(/^\./, '')
        .replace(/[^a-z0-9]/g, '')
        .slice(0, 10);
      const buf = req.body;
      if (!Buffer.isBuffer(buf) || buf.length === 0) {
        return reply.code(400).send({ error: 'empty', message: '文件数据为空' });
      }
      if (buf.length > MAX_FILE_BYTES) {
        return reply.code(413).send({ error: 'too_large', message: '文件过大（限 25MB）' });
      }
      const suffix = ext ? `.${ext}` : '';
      const name = `${newId('f')}${suffix}`;
      fs.writeFileSync(path.join(UPLOAD_DIR, name), buf);
      return {
        url: `/uploads/${name}`,
        name: String(req.query?.name ?? '').slice(0, 120),
        size: buf.length,
      };
    },
  );

  // Raw binary video upload (application/octet-stream) — avoids base64 overhead.
  app.post(
    '/upload/video',
    { preHandler: app.auth, bodyLimit: 52 * 1024 * 1024 },
    async (req, reply) => {
      const ext = String(req.query?.ext ?? 'mp4')
        .toLowerCase()
        .replace(/^\./, '');
      if (!ALLOWED_VIDEO_EXT.has(ext)) {
        return reply.code(400).send({ error: 'bad_ext', message: '不支持的音视频格式' });
      }
      const buf = req.body;
      if (!Buffer.isBuffer(buf) || buf.length === 0) {
        return reply.code(400).send({ error: 'empty', message: '视频数据为空' });
      }
      if (buf.length > MAX_VIDEO_BYTES) {
        return reply.code(413).send({ error: 'too_large', message: '视频过大（限 48MB）' });
      }
      const name = `${newId('vid')}.${ext}`;
      fs.writeFileSync(path.join(UPLOAD_DIR, name), buf);
      return { url: `/uploads/${name}`, size: buf.length };
    },
  );

  // Serve media with HTTP Range support (video streaming / seeking needs it).
  app.get('/uploads/:name', async (req, reply) => {
    const name = String(req.params.name ?? '');
    if (!MEDIA_NAME_RE.test(name)) {
      return reply.code(404).send({ error: 'not_found' });
    }
    const file = path.join(UPLOAD_DIR, name);
    if (!fs.existsSync(file)) return reply.code(404).send({ error: 'not_found' });
    const ext = name.split('.').pop();
    const mime = MIME[ext] ?? 'application/octet-stream';
    const size = fs.statSync(file).size;
    const range = req.headers.range;
    if (range) {
      const m = /^bytes=(\d*)-(\d*)$/.exec(String(range).trim());
      if (m && (m[1] !== '' || m[2] !== '')) {
        let start = m[1] === '' ? null : Number(m[1]);
        let end = m[2] === '' ? null : Number(m[2]);
        if (start === null) {
          start = Math.max(0, size - (end ?? 0));
          end = size - 1;
        } else if (end === null || end > size - 1) {
          end = size - 1;
        }
        if (start > end || start >= size) {
          return reply.code(416).header('Content-Range', `bytes */${size}`).send();
        }
        return reply
          .code(206)
          .headers({
            'Content-Range': `bytes ${start}-${end}/${size}`,
            'Accept-Ranges': 'bytes',
            'Cache-Control': 'public, max-age=86400',
            'Content-Length': String(end - start + 1),
          })
          .type(mime)
          .send(fs.createReadStream(file, { start, end }));
      }
    }
    return reply
      .headers({
        'Accept-Ranges': 'bytes',
        'Cache-Control': 'public, max-age=86400',
        'Content-Length': String(size),
      })
      .type(mime)
      .send(fs.createReadStream(file));
  });

  // ---------- users ----------
  app.get('/users/search', { preHandler: app.auth }, async (req) => {
    const q = String(req.query?.q ?? '').trim().toLowerCase();
    if (!q) return { users: [] };
    const me = req.userId;
    const results = db.data.users
      .filter(
        (u) =>
          u.id !== me &&
          (u.username.toLowerCase().includes(q) ||
            u.displayName.toLowerCase().includes(q)),
      )
      .slice(0, 20)
      .map((u) => ({ ...publicUser(u), isFriend: areFriends(me, u.id) }));
    return { users: results };
  });

  // Face-to-face add: my code encodes my user id; scanning it resolves the user.
  app.get('/users/qr', { preHandler: app.auth }, async (req) => ({
    payload: `samachat://add?uid=${req.userId}`,
    userId: req.userId,
  }));

  app.get('/users/resolve/:uid', { preHandler: app.auth }, async (req, reply) => {
    const target = findUserById(req.params.uid);
    if (!target) {
      return reply.code(404).send({ error: 'not_found', message: '用户不存在' });
    }
    return {
      user: { ...publicUser(target), isFriend: areFriends(req.userId, target.id) },
    };
  });

  // ---------- friends ----------
  app.get('/friends', { preHandler: app.auth }, async (req) => ({
    friends: friendIdsOf(req.userId).map((id) => ({
      ...publicUser(findUserById(id)),
      remark: friendRecord(req.userId, id)?.remark ?? '',
    })),
  }));

  // 删除好友（双向）
  app.delete('/friends/:userId', { preHandler: app.auth }, async (req, reply) => {
    const targetId = req.params.userId;
    if (!areFriends(req.userId, targetId)) {
      return reply.code(404).send({ error: 'not_found', message: '你们不是好友' });
    }
    removeFriendship(req.userId, targetId);
    await save();
    io?.toUser(targetId, 'friend:removed', { userId: req.userId });
    io?.toUser(req.userId, 'friend:removed', { userId: targetId });
    return { ok: true };
  });

  // 设置好友备注
  app.patch('/friends/:userId', { preHandler: app.auth }, async (req, reply) => {
    const rec = friendRecord(req.userId, req.params.userId);
    if (!rec) return reply.code(404).send({ error: 'not_found', message: '你们不是好友' });
    rec.remark = String(req.body?.remark ?? '').trim().slice(0, 32);
    await save();
    return { remark: rec.remark };
  });

  app.get('/friends/requests', { preHandler: app.auth }, async (req) => ({
    incoming: db.data.friendRequests
      .filter((r) => r.toId === req.userId && r.status === 'pending')
      .map((r) => ({ ...r, from: publicUser(findUserById(r.fromId)) })),
    outgoing: db.data.friendRequests
      .filter((r) => r.fromId === req.userId && r.status === 'pending')
      .map((r) => ({ ...r, to: publicUser(findUserById(r.toId)) })),
  }));

  app.post('/friends/request', { preHandler: app.auth }, async (req, reply) => {
    const { userId: targetId, message } = req.body ?? {};
    const target = findUserById(targetId);
    if (!target) return reply.code(404).send({ error: 'not_found', message: '用户不存在' });
    if (targetId === req.userId) {
      return reply.code(400).send({ error: 'self', message: '不能加自己为好友' });
    }
    if (isBlocked(targetId, req.userId)) {
      return reply.code(403).send({ error: 'blocked', message: '对方已将你加入黑名单' });
    }
    if (isBlocked(req.userId, targetId)) {
      return reply.code(403).send({ error: 'blocked', message: '你已将对方加入黑名单，请先解除' });
    }
    if (areFriends(req.userId, targetId)) {
      return reply.code(409).send({ error: 'already_friends', message: '你们已经是好友' });
    }
    const existing = db.data.friendRequests.find(
      (r) =>
        r.fromId === req.userId && r.toId === targetId && r.status === 'pending',
    );
    if (existing) return { request: existing };

    const request = {
      id: newId('fq'),
      fromId: req.userId,
      toId: targetId,
      message: String(message ?? '').slice(0, 120),
      status: 'pending',
      createdAt: now(),
    };
    db.data.friendRequests.push(request);
    await save();

    io?.toUser(targetId, 'friend:request', {
      request,
      from: publicUser(findUserById(req.userId)),
    });
    return { request };
  });

  app.post('/friends/respond', { preHandler: app.auth }, async (req, reply) => {
    const { requestId, accept } = req.body ?? {};
    const request = db.data.friendRequests.find((r) => r.id === requestId);
    if (!request || request.toId !== req.userId) {
      return reply.code(404).send({ error: 'not_found', message: '请求不存在' });
    }
    request.status = accept ? 'accepted' : 'rejected';
    if (accept) addFriendPair(request.fromId, request.toId);
    await save();

    if (accept) {
      io?.toUser(request.fromId, 'friend:accepted', {
        user: publicUser(findUserById(request.toId)),
      });
    }
    return { request };
  });

  // ---------- 黑名单 ----------
  app.get('/blocks', { preHandler: app.auth }, async (req) => ({
    blocks: blockIdsOf(req.userId).map((id) => publicUser(findUserById(id))),
  }));

  app.post('/blocks', { preHandler: app.auth }, async (req, reply) => {
    const targetId = req.body?.userId;
    if (!findUserById(targetId)) {
      return reply.code(404).send({ error: 'not_found', message: '用户不存在' });
    }
    if (targetId === req.userId) {
      return reply.code(400).send({ error: 'self', message: '不能拉黑自己' });
    }
    if (!isBlocked(req.userId, targetId)) {
      db.data.blocks.push({
        id: newId('bk'),
        userId: req.userId,
        blockedId: targetId,
        createdAt: now(),
      });
    }
    // 注意：拉黑不影响好友关系（解除后立即恢复正常），只拦截消息/好友申请/炫圈可见性
    await save();
    return { ok: true };
  });

  app.delete('/blocks/:userId', { preHandler: app.auth }, async (req) => {
    db.data.blocks = db.data.blocks.filter(
      (b) => !(b.userId === req.userId && b.blockedId === req.params.userId),
    );
    await save();
    return { ok: true };
  });

  // ---------- conversations & messages ----------
  app.get('/conversations', { preHandler: app.auth }, async (req) => {
    // 兜底清理：用户退过的群若已不存在（被解散），把记录清掉
    const me = findUserById(req.userId);
    const left = me?.leftConvs ?? [];
    const gone = left.filter(
      (id) => !db.data.conversations.some((c) => c.id === id),
    );
    if (gone.length > 0 && me) {
      me.leftConvs = left.filter((id) => !gone.includes(id));
      await save();
    }
    const list = conversationsOf(req.userId).map((c) => {
      const last = lastMessageOf(c.id);
      let title;
      if (c.type === 'group') {
        title = c.name;
      } else {
        const peerId = c.memberIds.find((m) => m !== req.userId);
        const peer = findUserById(peerId);
        const remark = friendRecord(req.userId, peerId ?? '')?.remark;
        title = remark && remark.length > 0 ? remark : peer?.displayName ?? '未知用户';
      }
      const pref = (me?.convPrefs ?? {})[c.id] ?? {};
      return {
        id: c.id,
        type: c.type,
        name: title,
        memberIds: c.memberIds,
        memberCount: c.memberIds.length,
        lastMessage: last,
        unread: last
          ? db.data.messages.filter(
              (m) =>
                m.conversationId === c.id &&
                m.senderId !== req.userId &&
                !(m.readBy ?? []).includes(req.userId),
            ).length
          : 0,
        pinned: pref.pinned === true,
        muted: pref.muted === true,
      };
    });
    list.sort(
      (a, b) => (b.lastMessage?.createdAt ?? 0) - (a.lastMessage?.createdAt ?? 0),
    );
    return { conversations: list };
  });

  // 会话偏好：置顶 / 免打扰。
  app.post('/conversations/:id/prefs', { preHandler: app.auth }, async (req, reply) => {
    const conv = db.data.conversations.find((c) => c.id === req.params.id);
    if (!conv || !conv.memberIds.includes(req.userId)) {
      return reply.code(404).send({ error: 'not_found', message: '会话不存在' });
    }
    const me = findUserById(req.userId);
    me.convPrefs ??= {};
    const pref = me.convPrefs[conv.id] ?? {};
    if (req.body?.pinned !== undefined) pref.pinned = req.body.pinned === true;
    if (req.body?.muted !== undefined) pref.muted = req.body.muted === true;
    me.convPrefs[conv.id] = pref;
    await save();
    return { pinned: pref.pinned === true, muted: pref.muted === true };
  });

  // 搜索消息 / 会话（限我参与的会话）。
  app.get('/search', { preHandler: app.auth }, async (req, reply) => {
    const q = String(req.query?.q ?? '').trim();
    if (!q) return reply.code(400).send({ error: 'empty', message: '请输入搜索内容' });
    const lower = q.toLowerCase();
    const myConvs = conversationsOf(req.userId);
    const convById = new Map(myConvs.map((c) => [c.id, c]));
    const hits = [];
    for (let i = db.data.messages.length - 1; i >= 0 && hits.length < 60; i--) {
      const m = db.data.messages[i];
      if (m.recalled || m.type !== 'text') continue;
      const conv = convById.get(m.conversationId);
      if (!conv) continue;
      if (!String(m.content ?? '').toLowerCase().includes(lower)) continue;
      let title;
      if (conv.type === 'group') title = conv.name;
      else {
        const peerId = conv.memberIds.find((x) => x !== req.userId);
        const peer = findUserById(peerId);
        const remark = friendRecord(req.userId, peerId ?? '')?.remark;
        title = remark && remark.length > 0 ? remark : peer?.displayName ?? '聊天';
      }
      hits.push({
        id: m.id,
        conversationId: m.conversationId,
        conversationName: title,
        isGroup: conv.type === 'group',
        senderId: m.senderId,
        senderName: m.sender?.displayName ?? findUserById(m.senderId)?.displayName ?? '',
        content: String(m.content).slice(0, 300),
        createdAt: m.createdAt,
      });
    }
    return { results: hits };
  });

  app.post('/conversations/private', { preHandler: app.auth }, async (req, reply) => {
    const { userId: peerId } = req.body ?? {};
    if (!findUserById(peerId)) {
      return reply.code(404).send({ error: 'not_found', message: '用户不存在' });
    }
    // 若这是某个群的前成员，重新私聊要把「已退出/已解散」标记清掉
    const conv = ensurePrivateConversation(req.userId, peerId);
    await save();
    return { conversation: conv };
  });

  // 解散群聊（仅群主；所有人失去该群）
  app.post('/conversations/:id/disband', { preHandler: app.auth }, async (req, reply) => {
    const idx = db.data.conversations.findIndex((c) => c.id === req.params.id);
    if (idx < 0) {
      return reply.code(404).send({ error: 'not_found', message: '群聊不存在' });
    }
    const conv = db.data.conversations[idx];
    if (conv.type !== 'group') {
      return reply.code(400).send({ error: 'not_group', message: '不是群聊' });
    }
    if (conv.ownerId !== req.userId) {
      return reply.code(403).send({ error: 'forbidden', message: '只有群主可以解散群聊' });
    }
    const members = [...conv.memberIds];
    db.data.messages = db.data.messages.filter((m) => m.conversationId !== conv.id);
    db.data.conversations.splice(idx, 1);
    // 所有收到过这个群的人（含已退出的）都要清掉本地残留
    const targets = new Set(members);
    for (const u of formerMembersOf(conv.id)) targets.add(u.id);
    for (const u of db.data.users) {
      if (Array.isArray(u.leftConvs)) {
        u.leftConvs = u.leftConvs.filter((id) => id !== conv.id);
      }
    }
    await save();
    for (const m of targets) {
      io?.toUser(m, 'conversation:removed', {
        conversationId: conv.id,
        reason: 'disbanded',
        name: conv.name,
      });
    }
    return { ok: true };
  });

  // 退出群聊（群主不可直接退；需先转让或解散）
  app.post('/conversations/:id/leave', { preHandler: app.auth }, async (req, reply) => {
    const conv = db.data.conversations.find((c) => c.id === req.params.id);
    if (!conv || conv.type !== 'group') {
      return reply.code(404).send({ error: 'not_found', message: '群聊不存在' });
    }
    if (!conv.memberIds.includes(req.userId)) {
      return reply.code(400).send({ error: 'not_member', message: '你不在这个群里' });
    }
    if (conv.ownerId === req.userId) {
      return reply
        .code(403)
        .send({ error: 'owner_cannot_leave', message: '群主不能直接退群，请先转让群主或解散群聊' });
    }
    conv.memberIds = conv.memberIds.filter((m) => m !== req.userId);
    conv.adminIds = (conv.adminIds ?? []).filter((m) => m !== req.userId);
    delete (conv.mutes ?? {})[req.userId];
    // 记录「退过的群」，供服务器清理本地残留
    const me = findUserById(req.userId);
    if (me) me.leftConvs = [...new Set([...(me.leftConvs ?? []), conv.id])].slice(-50);
    await save();
    for (const m of conv.memberIds) {
      io?.toUser(m, 'conversation:update', { conversation: conv });
      io?.toUser(m, 'conversation:memberLeft', {
        conversationId: conv.id,
        userId: req.userId,
        name: me?.displayName ?? '',
      });
    }
    io?.toUser(req.userId, 'conversation:removed', {
      conversationId: conv.id,
      reason: 'left',
      name: conv.name,
    });
    return { ok: true };
  });

  app.post('/conversations/group', { preHandler: app.auth }, async (req, reply) => {
    const { name, memberIds } = req.body ?? {};
    const members = [...new Set([req.userId, ...(memberIds ?? [])])].filter((m) =>
      findUserById(m),
    );
    if (members.length < 2) {
      return reply.code(400).send({ error: 'too_few', message: '群聊至少需要 2 人' });
    }
    const conv = {
      id: newId('cv'),
      type: 'group',
      name: String(name ?? '新群聊').slice(0, 32),
      memberIds: members,
      ownerId: req.userId,
      adminIds: [],
      mutes: {},
      lastTransferAt: 0,
      createdAt: now(),
    };
    db.data.conversations.push(conv);
    await save();
    for (const m of members) io?.toUser(m, 'conversation:new', { conversation: conv });
    return { conversation: conv };
  });

  app.post('/conversations/:id/members', { preHandler: app.auth }, async (req, reply) => {
    const conv = db.data.conversations.find((c) => c.id === req.params.id);
    if (!conv || !conv.memberIds.includes(req.userId)) {
      return reply.code(404).send({ error: 'not_found', message: '会话不存在' });
    }
    if (conv.type !== 'group') {
      return reply.code(400).send({ error: 'not_group', message: '不是群聊' });
    }
    const add = (req.body?.memberIds ?? []).filter(
      (m) => findUserById(m) && !conv.memberIds.includes(m),
    );
    conv.memberIds.push(...add);
    await save();
    for (const m of conv.memberIds) io?.toUser(m, 'conversation:update', { conversation: conv });
    return { conversation: conv };
  });

  // ---------- 群管理 ----------
  function groupRole(conv, userId) {
    if (conv.ownerId === userId) return 'owner';
    if ((conv.adminIds ?? []).includes(userId)) return 'admin';
    return 'member';
  }

  // 群成员详情（群资料页用）
  app.get('/conversations/:id/members', { preHandler: app.auth }, async (req, reply) => {
    const conv = db.data.conversations.find((c) => c.id === req.params.id);
    if (!conv || !conv.memberIds.includes(req.userId) || conv.type !== 'group') {
      return reply.code(404).send({ error: 'not_found', message: '群聊不存在' });
    }
    return {
      conversation: conv,
      members: conv.memberIds.map((id) => ({
        ...publicUser(findUserById(id)),
        role: groupRole(conv, id),
        mutedUntil: (conv.mutes ?? {})[id] ?? 0,
      })),
    };
  });

  // 修改群名称（群主 / 管理员）
  app.patch('/conversations/:id', { preHandler: app.auth }, async (req, reply) => {
    const conv = db.data.conversations.find((c) => c.id === req.params.id);
    if (!conv || conv.type !== 'group') {
      return reply.code(404).send({ error: 'not_found', message: '群聊不存在' });
    }
    if (!['owner', 'admin'].includes(groupRole(conv, req.userId))) {
      return reply.code(403).send({ error: 'forbidden', message: '只有群主和管理员可以修改群名称' });
    }
    const name = String(req.body?.name ?? '').trim().slice(0, 32);
    if (!name) return reply.code(400).send({ error: 'empty', message: '群名称不能为空' });
    conv.name = name;
    await save();
    for (const m of conv.memberIds) io?.toUser(m, 'conversation:update', { conversation: conv });
    return { conversation: conv };
  });

  // 设置 / 取消管理员（仅群主）
  app.post('/conversations/:id/admins', { preHandler: app.auth }, async (req, reply) => {
    const conv = db.data.conversations.find((c) => c.id === req.params.id);
    if (!conv || conv.type !== 'group') {
      return reply.code(404).send({ error: 'not_found', message: '群聊不存在' });
    }
    if (conv.ownerId !== req.userId) {
      return reply.code(403).send({ error: 'forbidden', message: '只有群主可以设置管理员' });
    }
    const { userId: targetId, remove } = req.body ?? {};
    if (!conv.memberIds.includes(targetId) || targetId === conv.ownerId) {
      return reply.code(400).send({ error: 'invalid', message: '只能设置群里的成员为管理员' });
    }
    conv.adminIds ??= [];
    if (remove) {
      conv.adminIds = conv.adminIds.filter((a) => a !== targetId);
    } else if (!conv.adminIds.includes(targetId)) {
      conv.adminIds.push(targetId);
    }
    await save();
    for (const m of conv.memberIds) io?.toUser(m, 'conversation:update', { conversation: conv });
    return { conversation: conv };
  });

  // 禁言 / 解除禁言（群主、管理员；minutes: >0 定时、0 解除、-1 永久）
  app.post('/conversations/:id/mute', { preHandler: app.auth }, async (req, reply) => {
    const conv = db.data.conversations.find((c) => c.id === req.params.id);
    if (!conv || conv.type !== 'group') {
      return reply.code(404).send({ error: 'not_found', message: '群聊不存在' });
    }
    const role = groupRole(conv, req.userId);
    if (role !== 'owner' && role !== 'admin') {
      return reply.code(403).send({ error: 'forbidden', message: '只有群主和管理员可以禁言' });
    }
    const { userId: targetId, minutes } = req.body ?? {};
    if (!conv.memberIds.includes(targetId) || targetId === req.userId) {
      return reply.code(400).send({ error: 'invalid', message: '不能对自己操作' });
    }
    if (targetId === conv.ownerId) {
      return reply.code(403).send({ error: 'forbidden', message: '不能禁言群主' });
    }
    if (role === 'admin' && (conv.adminIds ?? []).includes(targetId)) {
      return reply.code(403).send({ error: 'forbidden', message: '管理员之间不能互相禁言' });
    }
    conv.mutes ??= {};
    const mins = Number(minutes ?? 0);
    if (mins === 0) {
      delete conv.mutes[targetId];
    } else if (mins < 0) {
      conv.mutes[targetId] = -1;
    } else {
      conv.mutes[targetId] = now() + mins * 60 * 1000;
    }
    await save();
    for (const m of conv.memberIds) io?.toUser(m, 'conversation:update', { conversation: conv });
    return { conversation: conv };
  });

  // 踢出群聊（群主、管理员）
  app.post('/conversations/:id/kick', { preHandler: app.auth }, async (req, reply) => {
    const conv = db.data.conversations.find((c) => c.id === req.params.id);
    if (!conv || conv.type !== 'group') {
      return reply.code(404).send({ error: 'not_found', message: '群聊不存在' });
    }
    const role = groupRole(conv, req.userId);
    if (role !== 'owner' && role !== 'admin') {
      return reply.code(403).send({ error: 'forbidden', message: '只有群主和管理员可以踢人' });
    }
    const targetId = req.body?.userId;
    if (!conv.memberIds.includes(targetId) || targetId === req.userId) {
      return reply.code(400).send({ error: 'invalid', message: '成员不存在' });
    }
    if (targetId === conv.ownerId) {
      return reply.code(403).send({ error: 'forbidden', message: '不能踢出群主' });
    }
    if (role === 'admin' && (conv.adminIds ?? []).includes(targetId)) {
      return reply.code(403).send({ error: 'forbidden', message: '管理员不能踢出其他管理员' });
    }
    conv.memberIds = conv.memberIds.filter((m) => m !== targetId);
    conv.adminIds = (conv.adminIds ?? []).filter((m) => m !== targetId);
    delete (conv.mutes ?? {})[targetId];
    await save();
    for (const m of conv.memberIds) io?.toUser(m, 'conversation:update', { conversation: conv });
    io?.toUser(targetId, 'conversation:update', { conversation: conv });
    return { conversation: conv };
  });

  // 转让群主（仅群主；每 30 天一次）
  app.post('/conversations/:id/transfer', { preHandler: app.auth }, async (req, reply) => {
    const conv = db.data.conversations.find((c) => c.id === req.params.id);
    if (!conv || conv.type !== 'group') {
      return reply.code(404).send({ error: 'not_found', message: '群聊不存在' });
    }
    if (conv.ownerId !== req.userId) {
      return reply.code(403).send({ error: 'forbidden', message: '只有群主可以转让' });
    }
    const targetId = req.body?.userId;
    if (!conv.memberIds.includes(targetId) || targetId === req.userId) {
      return reply.code(400).send({ error: 'invalid', message: '只能转让给群内其他成员' });
    }
    const MONTH = 30 * 24 * 60 * 60 * 1000;
    const last = conv.lastTransferAt ?? 0;
    if (last && now() - last < MONTH) {
      const days = Math.ceil((MONTH - (now() - last)) / (24 * 60 * 60 * 1000));
      return reply.code(400).send({
        error: 'cooldown',
        message: `群主转让每 30 天只能进行一次，还需等待 ${days} 天`,
      });
    }
    const oldOwner = conv.ownerId;
    conv.ownerId = targetId;
    conv.adminIds = (conv.adminIds ?? []).filter((a) => a !== targetId);
    if (!conv.adminIds.includes(oldOwner)) conv.adminIds.push(oldOwner);
    conv.lastTransferAt = now();
    await save();
    for (const m of conv.memberIds) io?.toUser(m, 'conversation:update', { conversation: conv });
    return { conversation: conv };
  });

  app.get('/conversations/:id/messages', { preHandler: app.auth }, async (req, reply) => {
    const conv = db.data.conversations.find((c) => c.id === req.params.id);
    if (!conv || !conv.memberIds.includes(req.userId)) {
      return reply.code(404).send({ error: 'not_found', message: '会话不存在' });
    }
    const limit = Math.min(Number(req.query?.limit ?? 50), 200);
    const before = Number(req.query?.before ?? Date.now() + 1);
    const msgs = db.data.messages
      .filter((m) => m.conversationId === conv.id && m.createdAt < before)
      .slice(-limit);
    return { messages: msgs };
  });

  app.post('/conversations/:id/messages', { preHandler: app.auth }, async (req, reply) => {
    const conv = db.data.conversations.find((c) => c.id === req.params.id);
    if (!conv || !conv.memberIds.includes(req.userId)) {
      return reply.code(404).send({ error: 'not_found', message: '会话不存在' });
    }
    const content = String(req.body?.content ?? '').slice(0, 4000);
    if (!content) return reply.code(400).send({ error: 'empty', message: '消息不能为空' });

    const sendBlock = conversationSendBlock(conv, req.userId);
    if (sendBlock) return reply.code(403).send({ error: 'blocked', message: sendBlock });

    const message = {
      id: newId('m'),
      conversationId: conv.id,
      senderId: req.userId,
      sender: publicUser(findUserById(req.userId)),
      type: ['image', 'video', 'sticker', 'voice', 'file'].includes(req.body?.type)
        ? req.body.type
        : 'text',
      content,
      createdAt: now(),
      readBy: [req.userId],
    };
    if (message.type === 'file') {
      message.fileName = String(req.body?.fileName ?? '').slice(0, 120);
      message.fileSize = Number(req.body?.fileSize ?? 0) || 0;
    }
    if (message.type === 'voice') {
      message.duration = Math.min(Math.max(Number(req.body?.duration ?? 0) || 0, 0), 300);
    }
    const replyToId = String(req.body?.replyToId ?? '');
    if (replyToId) {
      const orig = db.data.messages.find(
        (m) => m.id === replyToId && m.conversationId === conv.id,
      );
      if (orig) {
        message.replyToId = orig.id;
        const senderName = orig.sender?.displayName ?? '';
        const body =
          orig.type === 'text'
            ? String(orig.content ?? '')
            : orig.type === 'image'
              ? '[图片]'
              : orig.type === 'video'
                ? '[视频]'
                : orig.type === 'sticker'
                  ? '[表情]'
                  : orig.type === 'voice'
                    ? '[语音]'
                    : orig.type === 'file'
                      ? '[文件]'
                      : '';
        message.replyPreview = `${senderName ? senderName + ': ' : ''}${body}`.slice(0, 120);
      }
    }
    db.data.messages.push(message);
    await save();
    io?.toConversation(conv, 'message:new', { message });
    // @提及 → 给被提及的人额外推一个高亮事件
    if (conv.type === 'group') {
      for (const m of new Set(String(content).match(/@\S+/g) ?? [])) {
        const name = m.slice(1);
        const hit = conv.memberIds.find((id) => {
          const u = findUserById(id);
          return u && (u.displayName === name || u.username === name);
        });
        if (hit) {
          io?.toUser(hit, 'group:mention', {
            conversationId: conv.id,
            conversationName: conv.name,
            from: publicUser(findUserById(req.userId)),
            content: String(content).slice(0, 150),
          });
        }
      }
    }
    return { message };
  });

  app.post('/conversations/:id/messages/:mid/recall', { preHandler: app.auth }, async (req, reply) => {
    const conv = db.data.conversations.find((c) => c.id === req.params.id);
    if (!conv || !conv.memberIds.includes(req.userId)) {
      return reply.code(404).send({ error: 'not_found', message: '会话不存在' });
    }
    const msg = db.data.messages.find(
      (m) => m.id === req.params.mid && m.conversationId === conv.id,
    );
    if (!msg) return reply.code(404).send({ error: 'not_found', message: '消息不存在' });
    if (msg.senderId !== req.userId) {
      return reply.code(403).send({ error: 'not_owner', message: '只能撤回自己的消息' });
    }
    if (msg.recalled) return { message: msg }; // 已撤回，幂等返回
    if (now() - msg.createdAt > 24 * 60 * 60 * 1000) {
      return reply.code(400).send({ error: 'too_old', message: '超过 24 小时的消息不能撤回' });
    }
    msg.recalled = true;
    msg.content = '';
    await save();
    io?.toConversation(conv, 'message:recalled', {
      conversationId: conv.id,
      messageId: msg.id,
      senderId: msg.senderId,
    });
    return { message: msg };
  });

  app.post('/conversations/:id/read', { preHandler: app.auth }, async (req, reply) => {
    const conv = db.data.conversations.find((c) => c.id === req.params.id);
    if (!conv || !conv.memberIds.includes(req.userId)) {
      return reply.code(404).send({ error: 'not_found', message: '会话不存在' });
    }
    for (const m of db.data.messages) {
      if (m.conversationId === conv.id && !(m.readBy ?? []).includes(req.userId)) {
        (m.readBy ??= []).push(req.userId);
      }
    }
    await save();
    io?.toConversation(conv, 'message:read', {
      conversationId: conv.id,
      userId: req.userId,
    });
    return { ok: true };
  });

  // ---------- moments (炫圈) ----------
  app.get('/moments', { preHandler: app.auth }, async (req) => {
    const visible = new Set([req.userId, ...friendIdsOf(req.userId)]);
    const myBlocks = new Set(blockIdsOf(req.userId));
    const blockedMe = new Set(
      db.data.blocks.filter((b) => b.blockedId === req.userId).map((b) => b.userId),
    );
    const moments = db.data.moments
      .filter(
        (m) =>
          visible.has(m.authorId) &&
          !myBlocks.has(m.authorId) &&
          !blockedMe.has(m.authorId),
      )
      .sort((a, b) => b.createdAt - a.createdAt)
      .slice(0, 100)
      .map((m) => ({
        ...m,
        author: publicUser(findUserById(m.authorId)),
        likedByMe: m.likes.includes(req.userId),
        likeCount: m.likes.length,
      }));
    return { moments };
  });

  app.post('/moments', { preHandler: app.auth }, async (req) => {
    const { text, images } = req.body ?? {};
    const moment = {
      id: newId('mo'),
      authorId: req.userId,
      text: String(text ?? '').slice(0, 1000),
      images: Array.isArray(images) ? images.slice(0, 9) : [],
      createdAt: now(),
      likes: [],
      comments: [],
    };
    db.data.moments.push(moment);
    await save();
    for (const f of friendIdsOf(req.userId)) {
      io?.toUser(f, 'moment:new', {
        moment: { ...moment, author: publicUser(findUserById(req.userId)) },
      });
    }
    return { moment };
  });

  app.post('/moments/:id/like', { preHandler: app.auth }, async (req, reply) => {
    const moment = db.data.moments.find((m) => m.id === req.params.id);
    if (!moment) return reply.code(404).send({ error: 'not_found', message: '动态不存在' });
    const i = moment.likes.indexOf(req.userId);
    if (i >= 0) moment.likes.splice(i, 1);
    else moment.likes.push(req.userId);
    await save();
    // 通知动态作者（自己赞自己不通知）
    if (i < 0 && moment.authorId !== req.userId) {
      io?.toUser(moment.authorId, 'moment:interaction', {
        momentId: moment.id,
        kind: 'like',
        from: publicUser(findUserById(req.userId)),
      });
    }
    return { liked: i < 0, likeCount: moment.likes.length };
  });

  app.post('/moments/:id/comment', { preHandler: app.auth }, async (req, reply) => {
    const moment = db.data.moments.find((m) => m.id === req.params.id);
    if (!moment) return reply.code(404).send({ error: 'not_found', message: '动态不存在' });
    const text = String(req.body?.text ?? '').trim().slice(0, 500);
    if (!text) return reply.code(400).send({ error: 'empty', message: '评论不能为空' });
    const comment = {
      id: newId('cm'),
      authorId: req.userId,
      author: publicUser(findUserById(req.userId)),
      text,
      createdAt: now(),
    };
    moment.comments.push(comment);
    await save();
    // 通知动态作者 / 被回复的评论者
    if (moment.authorId !== req.userId) {
      io?.toUser(moment.authorId, 'moment:interaction', {
        momentId: moment.id,
        kind: 'comment',
        text,
        from: publicUser(findUserById(req.userId)),
      });
    }
    const parentId = String(req.body?.parentId ?? '');
    if (parentId) {
      const parent = moment.comments.find((c) => c.id === parentId);
      if (parent && parent.authorId && parent.authorId !== req.userId && parent.authorId !== moment.authorId) {
        io?.toUser(parent.authorId, 'moment:interaction', {
          momentId: moment.id,
          kind: 'reply',
          text,
          from: publicUser(findUserById(req.userId)),
        });
      }
    }
    return { comment };
  });

  // 删除自己的炫圈（发布 2 分钟内）
  app.delete('/moments/:id', { preHandler: app.auth }, async (req, reply) => {
    const idx = db.data.moments.findIndex((m) => m.id === req.params.id);
    if (idx < 0) {
      return reply.code(404).send({ error: 'not_found', message: '动态不存在或已被删除' });
    }
    const moment = db.data.moments[idx];
    if (moment.authorId !== req.userId) {
      return reply.code(403).send({ error: 'not_owner', message: '只能删除自己的动态' });
    }
    const windowMs = Number(process.env.MOMENT_DELETE_WINDOW_MS ?? 2 * 60 * 1000);
    if (now() - moment.createdAt > windowMs) {
      return reply.code(403).send({ error: 'too_old', message: '发布超过 2 分钟的动态不能删除' });
    }
    db.data.moments.splice(idx, 1);
    await save();
    for (const f of friendIdsOf(req.userId)) {
      io?.toUser(f, 'moment:deleted', { momentId: moment.id });
    }
    io?.toUser(req.userId, 'moment:deleted', { momentId: moment.id });
    return { ok: true };
  });

  // ---------- 公告 ----------
  // 只有管理员账号（默认 huzhi，用户名或昵称均可）能发布；
  // 每个人在打开 App + 登录后收到一次，弹窗看过即标记已读，之后不再重复弹出。
  const annDto = (a) => ({
    id: a.id,
    content: a.content,
    authorName: a.authorName,
    createdAt: a.createdAt,
  });

  // 拉取我的未读公告。
  app.get('/announce', { preHandler: app.auth }, async (req) => {
    const u = findUserById(req.userId);
    const seen = new Set(u?.seenAnns ?? []);
    const announcements = db.data.announcements
      .filter((a) => !seen.has(a.id))
      .slice(-50)
      .map(annDto);
    return { announcements };
  });

  // 发布公告（仅管理员；发布后对所有在线用户实时推送）。
  app.post('/announce', { preHandler: app.auth }, async (req, reply) => {
    const u = findUserById(req.userId);
    if (!canAnnounce(u)) {
      return reply
        .code(403)
        .send({ error: 'no_permission', message: '没有发布公告的权限（仅 huzhi 账号可以发布）' });
    }
    const content = String(req.body?.content ?? '').trim().slice(0, 2000);
    if (!content) {
      return reply.code(400).send({ error: 'empty', message: '公告内容不能为空' });
    }
    const ann = {
      id: newId('ann'),
      content,
      authorId: u.id,
      authorName: u.displayName || u.username,
      createdAt: now(),
    };
    db.data.announcements.push(ann);
    if (db.data.announcements.length > 200) {
      db.data.announcements.splice(0, db.data.announcements.length - 200);
    }
    await save();
    io?.toAll?.('announce:new', { announcement: annDto(ann) });
    return { ok: true, announcement: annDto(ann) };
  });

  // 标记公告已读（客户端弹过一次后调用；保证「只弹一次」）。
  app.post('/announce/ack', { preHandler: app.auth }, async (req, reply) => {
    const u = findUserById(req.userId);
    if (!u) return reply.code(401).send({ error: 'unauthorized' });
    const ids = Array.isArray(req.body?.ids)
      ? req.body.ids.slice(0, 100).map(String)
      : [];
    if (ids.length === 0) return { ok: true };
    const valid = new Set(db.data.announcements.map((a) => a.id));
    const seen = new Set(u.seenAnns ?? []);
    for (const id of ids) if (valid.has(id)) seen.add(id);
    u.seenAnns = [...seen].slice(-300);
    await save();
    return { ok: true };
  });

  // ---------- 群投票 ----------
  const pollDto = (p, uid) => ({
    id: p.id,
    conversationId: p.conversationId,
    creatorId: p.creatorId,
    creatorName: p.creatorName ?? '',
    question: p.question,
    options: p.options.map((o) => ({
      id: o.id,
      text: o.text,
      count: o.votes.length,
      votedByMe: o.votes.includes(uid),
    })),
    totalVotes: new Set(p.options.flatMap((o) => o.votes)).size,
    multiple: p.multiple === true,
    closed: p.closed === true,
    createdAt: p.createdAt,
  });

  // 发起投票（群成员均可）。
  app.post('/conversations/:id/polls', { preHandler: app.auth }, async (req, reply) => {
    const conv = db.data.conversations.find((c) => c.id === req.params.id);
    if (!conv || !conv.memberIds.includes(req.userId)) {
      return reply.code(404).send({ error: 'not_found', message: '会话不存在' });
    }
    if (conv.type !== 'group') {
      return reply.code(400).send({ error: 'not_group', message: '只能在群里发起投票' });
    }
    const question = String(req.body?.question ?? '').trim().slice(0, 200);
    const rawOptions = (Array.isArray(req.body?.options) ? req.body.options : [])
      .map((s) => String(s).trim().slice(0, 60))
      .filter((s) => s.length > 0)
      .slice(0, 10);
    if (!question) return reply.code(400).send({ error: 'empty', message: '投票主题不能为空' });
    if (rawOptions.length < 2) {
      return reply.code(400).send({ error: 'few_options', message: '至少要有 2 个选项' });
    }
    const u = findUserById(req.userId);
    const poll = {
      id: newId('poll'),
      conversationId: conv.id,
      creatorId: u.id,
      creatorName: u.displayName || u.username,
      question,
      options: rawOptions.map((t) => ({ id: newId('op'), text: t, votes: [] })),
      multiple: req.body?.multiple === true,
      closed: false,
      createdAt: now(),
    };
    db.data.polls.push(poll);
    await save();
    for (const m of conv.memberIds) {
      io?.toUser(m, 'poll:new', { poll: pollDto(poll, m), conversationId: conv.id });
    }
    return { poll: pollDto(poll, req.userId) };
  });

  // 会话的投票列表。
  app.get('/conversations/:id/polls', { preHandler: app.auth }, async (req, reply) => {
    const conv = db.data.conversations.find((c) => c.id === req.params.id);
    if (!conv || !conv.memberIds.includes(req.userId)) {
      return reply.code(404).send({ error: 'not_found', message: '会话不存在' });
    }
    const polls = db.data.polls
      .filter((p) => p.conversationId === conv.id)
      .slice(-30)
      .map((p) => pollDto(p, req.userId));
    return { polls };
  });

  // 投票 / 取消投票。
  app.post('/polls/:id/vote', { preHandler: app.auth }, async (req, reply) => {
    const poll = db.data.polls.find((p) => p.id === req.params.id);
    if (!poll) return reply.code(404).send({ error: 'not_found', message: '投票不存在' });
    const conv = db.data.conversations.find((c) => c.id === poll.conversationId);
    if (!conv || !conv.memberIds.includes(req.userId)) {
      return reply.code(403).send({ error: 'forbidden', message: '你不在这个群里' });
    }
    if (poll.closed) return reply.code(400).send({ error: 'closed', message: '投票已结束' });
    const optionIds = (Array.isArray(req.body?.optionIds) ? req.body.optionIds : [])
      .map((s) => String(s));
    if (optionIds.length === 0) {
      return reply.code(400).send({ error: 'empty', message: '请选择选项' });
    }
    for (const o of poll.options) {
      if (!optionIds.includes(o.id)) continue;
      const i = o.votes.indexOf(req.userId);
      if (i >= 0) o.votes.splice(i, 1); // 再点取消
      else {
        if (!poll.multiple) {
          // 单选：先清除其它选项
          for (const o2 of poll.options) {
            const j = o2.votes.indexOf(req.userId);
            if (j >= 0) o2.votes.splice(j, 1);
          }
        }
        o.votes.push(req.userId);
      }
    }
    await save();
    for (const m of conv.memberIds) {
      io?.toUser(m, 'poll:update', { poll: pollDto(poll, m), conversationId: conv.id });
    }
    return { poll: pollDto(poll, req.userId) };
  });

  // 结束投票（发起人；结束后不可再投）。
  app.post('/polls/:id/close', { preHandler: app.auth }, async (req, reply) => {
    const poll = db.data.polls.find((p) => p.id === req.params.id);
    if (!poll) return reply.code(404).send({ error: 'not_found', message: '投票不存在' });
    if (poll.creatorId !== req.userId) {
      return reply.code(403).send({ error: 'not_owner', message: '只有发起人可以结束投票' });
    }
    poll.closed = true;
    await save();
    const conv = db.data.conversations.find((c) => c.id === poll.conversationId);
    if (conv) {
      for (const m of conv.memberIds) {
        io?.toUser(m, 'poll:update', { poll: pollDto(poll, m), conversationId: conv.id });
      }
    }
    return { poll: pollDto(poll, req.userId) };
  });

  // ---------- 表情商店（所有人可发布图片/GIF 表情整合包） ----------
  const packDto = (p, uid) => ({
    id: p.id,
    name: p.name,
    authorId: p.authorId,
    authorName: p.authorName ?? '',
    stickers: p.stickers ?? [],
    downloads: (p.downloads ?? []).length,
    downloaded: (p.downloads ?? []).includes(uid),
    createdAt: p.createdAt,
  });

  // 商店列表（最新在前）。
  app.get('/stickers/store', { preHandler: app.auth }, async (req) => {
    const packs = [...db.data.stickerPacks]
      .sort((a, b) => (b.createdAt ?? 0) - (a.createdAt ?? 0))
      .slice(0, 200)
      .map((p) => packDto(p, req.userId));
    return { packs };
  });

  // 发布表情包（名称 + 已上传的表情图片 URL 列表；支持 gif 动图）。
  app.post('/stickers/packs', { preHandler: app.auth }, async (req, reply) => {
    const name = String(req.body?.name ?? '').trim().slice(0, 30);
    if (!name) {
      return reply.code(400).send({ error: 'empty_name', message: '给表情包起个名字吧' });
    }
    const stickers = (Array.isArray(req.body?.stickers) ? req.body.stickers : [])
      .slice(0, 50)
      .map((s) => String(s))
      .filter((s) => s.startsWith('/uploads/') && s.length < 300);
    if (stickers.length === 0) {
      return reply.code(400).send({ error: 'empty_pack', message: '表情包至少要有 1 个表情' });
    }
    const u = findUserById(req.userId);
    const pack = {
      id: newId('pk'),
      authorId: u.id,
      authorName: u.displayName || u.username,
      name,
      stickers,
      downloads: [],
      createdAt: now(),
    };
    db.data.stickerPacks.push(pack);
    await save();
    return { pack: packDto(pack, req.userId) };
  });

  // 下载（收藏）表情包 → 之后在聊天表情面板里作为独立分区直接使用。
  app.post('/stickers/packs/:id/download', { preHandler: app.auth }, async (req, reply) => {
    const p = db.data.stickerPacks.find((x) => x.id === req.params.id);
    if (!p) {
      return reply.code(404).send({ error: 'not_found', message: '表情包不存在或已被删除' });
    }
    p.downloads ??= [];
    if (!p.downloads.includes(req.userId)) p.downloads.push(req.userId);
    await save();
    return { pack: packDto(p, req.userId) };
  });

  // 我下载过的表情包（完整数据）。
  app.get('/stickers/downloaded', { preHandler: app.auth }, async (req) => {
    const packs = db.data.stickerPacks
      .filter((p) => (p.downloads ?? []).includes(req.userId))
      .map((p) => packDto(p, req.userId));
    return { packs };
  });

  // 删除表情包（作者本人，或公告管理员）。
  app.delete('/stickers/packs/:id', { preHandler: app.auth }, async (req, reply) => {
    const i = db.data.stickerPacks.findIndex((x) => x.id === req.params.id);
    if (i < 0) {
      return reply.code(404).send({ error: 'not_found', message: '表情包不存在' });
    }
    const p = db.data.stickerPacks[i];
    const u = findUserById(req.userId);
    if (p.authorId !== req.userId && !canAnnounce(u)) {
      return reply.code(403).send({ error: 'not_owner', message: '只能删除自己的表情包' });
    }
    db.data.stickerPacks.splice(i, 1);
    await save();
    return { ok: true };
  });
}
