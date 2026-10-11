// Realtime layer: WebSocket transport for instant message delivery, typing
// indicators and presence. Clients authenticate with the same JWT.
import { verifyToken } from './auth.js';
import {
  db,
  newId,
  now,
  publicUser,
  findUserById,
  areFriends,
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

  // ---- 语音/视频通话信令（纯内存态，不落库）----
  const activeCalls = new Map(); // callId -> {id, callerId, calleeId, type, state, createdAt, updatedAt}
  const userCalls = new Map(); // userId -> callId（忙线判断）
  const CALL_RING_TIMEOUT = 45 * 1000; // 45 秒无应答自动结束
  const CALL_MAX_DURATION = 6 * 60 * 60 * 1000; // 通话最长 6 小时（兜底）

  function endCall(callId, reason) {
    const call = activeCalls.get(callId);
    if (!call) return;
    activeCalls.delete(callId);
    if (userCalls.get(call.callerId) === callId) userCalls.delete(call.callerId);
    if (userCalls.get(call.calleeId) === callId) userCalls.delete(call.calleeId);
    const payload = { callId, reason };
    // 广播给双方的所有设备（多端场景：另一台还在响铃的设备靠这个收线）
    toUser(call.callerId, 'call:ended', payload);
    toUser(call.calleeId, 'call:ended', payload);
  }

  // 兜底清理：响铃没人接 / 客户端崩溃没发挂断
  const callSweeper = setInterval(() => {
    for (const call of [...activeCalls.values()]) {
      if (call.state === 'pending' && Date.now() - call.createdAt > CALL_RING_TIMEOUT) {
        endCall(call.id, 'no_answer');
      } else if (call.state === 'connected' && Date.now() - call.updatedAt > CALL_MAX_DURATION) {
        endCall(call.id, 'timeout');
      }
    }
  }, 15 * 1000);
  callSweeper.unref?.();

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
        // 掉线时若正在通话 → 结束它，让对方收到通知
        const callId = userCalls.get(userId);
        if (callId) endCall(callId, 'peer_offline');
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
        type: ['image', 'video', 'sticker', 'voice', 'file'].includes(data?.type)
          ? data.type
          : 'text',
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

    // ---- 通话信令：invite / accept / reject / end / ice ----
    if (event === 'call:invite') {
      const calleeId = String(data?.to ?? '');
      const callee = findUserById(calleeId);
      const fail = (reason) => toUser(userId, 'call:failed', { reason });

      if (!callee || calleeId === userId || !areFriends(userId, calleeId)) return fail('not_friend');
      if (!isOnline(calleeId)) return fail('offline');
      if (userCalls.has(userId) || userCalls.has(calleeId)) return fail('busy');

      const call = {
        id: newId('call'),
        callerId: userId,
        calleeId,
        type: data?.callType === 'video' ? 'video' : 'audio',
        state: 'pending',
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      activeCalls.set(call.id, call);
      userCalls.set(userId, call.id);
      userCalls.set(calleeId, call.id);

      toUser(calleeId, 'call:invite', {
        callId: call.id,
        from: publicUser(findUserById(userId)),
        callType: call.type,
        offer: data?.offer ?? null,
      });
      toUser(userId, 'call:ringing', { callId: call.id, to: publicUser(callee) });
      return;
    }

    if (event === 'call:accept') {
      const call = activeCalls.get(String(data?.callId ?? ''));
      if (!call || call.calleeId !== userId || call.state !== 'pending') return;
      call.state = 'connected';
      call.updatedAt = Date.now();
      toUser(call.callerId, 'call:accepted', {
        callId: call.id,
        answer: data?.answer ?? null,
      });
      // 也给自己（多设备）：接听者的其他设备靠这个自动收线（无 answer，幂等忽略）
      toUser(call.calleeId, 'call:accepted', { callId: call.id });
      return;
    }

    if (event === 'call:reject') {
      const call = activeCalls.get(String(data?.callId ?? ''));
      if (!call || call.calleeId !== userId) return;
      toUser(call.callerId, 'call:rejected', { callId: call.id });
      endCall(call.id, 'rejected');
      return;
    }

    if (event === 'call:end') {
      const call = activeCalls.get(String(data?.callId ?? ''));
      if (!call || (call.callerId !== userId && call.calleeId !== userId)) return;
      endCall(call.id, String(data?.reason ?? 'hangup'));
      return;
    }

    if (event === 'call:ice') {
      const call = activeCalls.get(String(data?.callId ?? ''));
      if (!call || (call.callerId !== userId && call.calleeId !== userId)) return;
      const peer = call.callerId === userId ? call.calleeId : call.callerId;
      toUser(peer, 'call:ice', { callId: call.id, candidate: data?.candidate ?? null });
      return;
    }
  }

  return { toUser, toConversation, toAll, isOnline, count: () => sockets.size };
}
