// Realtime layer: WebSocket transport for instant message delivery, typing
// indicators and presence. Clients authenticate with the same JWT.
import { verifyToken } from './auth.js';
import {
  db,
  newId,
  now,
  publicUser,
  findUserById,
  conversationsOf,
  conversationSendBlock,
  save,
} from './store.js';

/**
 * Realtime hub. Maps userId -> Set<socket>. A user may be connected from
 * several devices at once; every socket receives the event.
 */
export function createIo(app) {
  const sockets = new Map(); // userId -> Set<ws>

  function add(userId, ws) {
    if (!sockets.has(userId)) sockets.set(userId, new Set());
    sockets.get(userId).add(ws);
  }

  function remove(userId, ws) {
    const set = sockets.get(userId);
    if (!set) return;
    set.delete(ws);
    if (set.size === 0) sockets.delete(userId);
  }

  function send(ws, event, data) {
    if (ws.readyState !== 1) return;
    ws.send(JSON.stringify({ event, data }));
  }

  function toUser(userId, event, data) {
    const set = sockets.get(userId);
    if (!set) return;
    for (const ws of set) send(ws, event, data);
  }

  function toConversation(conv, event, data, exceptUserId = null) {
    for (const m of conv.memberIds) {
      if (m !== exceptUserId) toUser(m, event, data);
    }
  }

  /** 给所有在线用户推送（公告用）。 */
  function toAll(event, data) {
    for (const userId of sockets.keys()) toUser(userId, event, data);
  }

  function isOnline(userId) {
    return sockets.has(userId);
  }

  app.get('/ws', { websocket: true }, (socket, req) => {
    const token =
      req.query?.token ??
      (req.headers.authorization ?? '').replace(/^Bearer\s+/i, '');
    const userId = verifyToken(token);

    if (!userId || !findUserById(userId)) {
      socket.close(4001, 'unauthorized');
      return;
    }

    add(userId, socket);
    socket.send(JSON.stringify({ event: 'connected', data: { userId } }));

    // Tell my friends I came online.
    for (const c of conversationsOf(userId)) {
      toConversation(c, 'presence:update', { userId, online: true }, userId);
    }

    socket.on('message', async (raw) => {
      let msg;
      try {
        msg = JSON.parse(raw.toString());
      } catch {
        return;
      }
      await handleMessage(userId, msg);
    });

    socket.on('close', () => {
      remove(userId, socket);
      if (!isOnline(userId)) {
        for (const c of conversationsOf(userId)) {
          toConversation(c, 'presence:update', { userId, online: false }, userId);
        }
      }
    });
  });

  /**
   * Handle one inbound realtime frame.
   * Supported:  message:send | typing | message:read
   */
  async function handleMessage(userId, msg) {
    const { event, data } = msg ?? {};

    if (event === 'message:send') {
      const conv = db.data.conversations.find((c) => c.id === data?.conversationId);
      if (!conv || !conv.memberIds.includes(userId)) return;

      // 禁言 / 黑名单校验
      if (conversationSendBlock(conv, userId)) return;

      const message = {
        id: newId('m'),
        conversationId: conv.id,
        senderId: userId,
        sender: publicUser(findUserById(userId)),
        type: ['image', 'video', 'sticker'].includes(data?.type) ? data.type : 'text',
        content: String(data?.content ?? '').slice(0, 4000),
        createdAt: now(),
        readBy: [userId],
      };
      if (!message.content) return;

      db.data.messages.push(message);
      await save();

      toConversation(conv, 'message:new', { message });
      return;
    }

    if (event === 'typing') {
      const conv = db.data.conversations.find((c) => c.id === data?.conversationId);
      if (!conv || !conv.memberIds.includes(userId)) return;
      toConversation(
        conv,
        'typing',
        { conversationId: conv.id, userId, typing: !!data?.typing },
        userId,
      );
      return;
    }

    if (event === 'message:read') {
      const conv = db.data.conversations.find((c) => c.id === data?.conversationId);
      if (!conv || !conv.memberIds.includes(userId)) return;
      for (const m of db.data.messages) {
        if (m.conversationId === conv.id && !(m.readBy ?? []).includes(userId)) {
          (m.readBy ??= []).push(userId);
        }
      }
      await save();
      toConversation(
        conv,
        'message:read',
        { conversationId: conv.id, userId },
        userId,
      );
    }
  }

  return { toUser, toConversation, toAll, isOnline, count: () => sockets.size };
}
