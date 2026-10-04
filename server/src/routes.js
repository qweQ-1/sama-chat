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
  ensurePrivateConversation,
  conversationsOf,
  lastMessageOf,
  save,
} from './store.js';
import fs from 'node:fs';
import path from 'node:path';

// Where uploaded images live. Served back at /uploads/<file>.
export const UPLOAD_DIR =
  process.env.UPLOAD_DIR || path.resolve(process.cwd(), 'uploads');
fs.mkdirSync(UPLOAD_DIR, { recursive: true });

const ALLOWED_EXT = new Set(['jpg', 'jpeg', 'png', 'gif', 'webp']);
const MIME = {
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  png: 'image/png',
  gif: 'image/gif',
  webp: 'image/webp',
};
const MAX_UPLOAD_BYTES = 6 * 1024 * 1024;

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

  app.get('/uploads/:name', async (req, reply) => {
    const name = String(req.params.name ?? '');
    if (!/^img_[A-Za-z0-9_-]{6,32}\.(jpg|jpeg|png|gif|webp)$/.test(name)) {
      return reply.code(404).send({ error: 'not_found' });
    }
    const file = path.join(UPLOAD_DIR, name);
    if (!fs.existsSync(file)) return reply.code(404).send({ error: 'not_found' });
    const ext = name.split('.').pop();
    return reply.type(MIME[ext] ?? 'application/octet-stream').send(fs.readFileSync(file));
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
    friends: friendIdsOf(req.userId).map((id) => publicUser(findUserById(id))),
  }));

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

  // ---------- conversations & messages ----------
  app.get('/conversations', { preHandler: app.auth }, async (req) => {
    const list = conversationsOf(req.userId).map((c) => {
      const last = lastMessageOf(c.id);
      const title =
        c.type === 'group'
          ? c.name
          : publicUser(findUserById(c.memberIds.find((m) => m !== req.userId)))
              ?.displayName ?? '未知用户';
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
      };
    });
    list.sort(
      (a, b) => (b.lastMessage?.createdAt ?? 0) - (a.lastMessage?.createdAt ?? 0),
    );
    return { conversations: list };
  });

  app.post('/conversations/private', { preHandler: app.auth }, async (req, reply) => {
    const { userId: peerId } = req.body ?? {};
    if (!findUserById(peerId)) {
      return reply.code(404).send({ error: 'not_found', message: '用户不存在' });
    }
    const conv = ensurePrivateConversation(req.userId, peerId);
    await save();
    return { conversation: conv };
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

    const message = {
      id: newId('m'),
      conversationId: conv.id,
      senderId: req.userId,
      sender: publicUser(findUserById(req.userId)),
      type: req.body?.type === 'image' ? 'image' : 'text',
      content,
      createdAt: now(),
      readBy: [req.userId],
    };
    db.data.messages.push(message);
    await save();
    io?.toConversation(conv, 'message:new', { message });
    return { message };
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
    const moments = db.data.moments
      .filter((m) => visible.has(m.authorId))
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
    return { comment };
  });
}
