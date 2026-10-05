// Simple JSON-file backed store. Low ceremony, easy to inspect, good enough
// for an MVP chat backend. Swap for Postgres later without touching routes.
import { JSONFilePreset } from 'lowdb/node';
import { nanoid } from 'nanoid';
import fs from 'node:fs';
import path from 'node:path';

const DATA_DIR = process.env.DATA_DIR || path.resolve(process.cwd(), 'data');
fs.mkdirSync(DATA_DIR, { recursive: true });

const defaultData = {
  users: [],        // {id, username, displayName, passwordHash, avatar, createdAt}
  friends: [],      // {id, userId, friendId, remark, createdAt}  (mutual, stored both ways)
  friendRequests: [], // {id, fromId, toId, status: pending|accepted|rejected, createdAt}
  conversations: [], // {id, type, name?, memberIds[], ownerId?, adminIds[], mutes{}, lastTransferAt?, createdAt}
  messages: [],     // {id, conversationId, senderId, type, content, createdAt, readBy[]}
  moments: [],      // {id, authorId, text, images[], createdAt, likes[], comments[]}
  blocks: [],       // {id, userId, blockedId, createdAt}  用户 userId 拉黑了 blockedId
};

export const db = await JSONFilePreset(path.join(DATA_DIR, 'db.json'), defaultData);

// 兼容旧数据库：补齐新增字段（老数据升级用）
for (const f of db.data.friends) f.remark ??= '';
for (const c of db.data.conversations) {
  c.adminIds ??= [];
  c.mutes ??= {};
  c.lastTransferAt ??= 0;
}
db.data.blocks ??= [];

export const newId = (prefix = '') => (prefix ? `${prefix}_` : '') + nanoid(12);
export const now = () => Date.now();

/** Public shape of a user — never leaks passwordHash. */
export function publicUser(u) {
  if (!u) return null;
  return {
    id: u.id,
    username: u.username,
    displayName: u.displayName,
    avatar: u.avatar ?? null,
    createdAt: u.createdAt,
  };
}

export function findUserById(id) {
  return db.data.users.find((u) => u.id === id) ?? null;
}

export function findUserByUsername(username) {
  const key = String(username).toLowerCase();
  return db.data.users.find((u) => u.username.toLowerCase() === key) ?? null;
}

/** Are these two users friends? Friendship is stored symmetrically. */
export function areFriends(a, b) {
  return db.data.friends.some((f) => f.userId === a && f.friendId === b);
}

/** 查询好友记录（含备注）。 */
export function friendRecord(userId, friendId) {
  return (
    db.data.friends.find((f) => f.userId === userId && f.friendId === friendId) ?? null
  );
}

/** 解除双方好友关系。 */
export function removeFriendship(a, b) {
  db.data.friends = db.data.friends.filter(
    (f) =>
      !(
        (f.userId === a && f.friendId === b) ||
        (f.userId === b && f.friendId === a)
      ),
  );
}

/** userId 是否拉黑了 targetId。 */
export function isBlocked(userId, targetId) {
  return db.data.blocks.some((b) => b.userId === userId && b.blockedId === targetId);
}

export function blockIdsOf(userId) {
  return db.data.blocks.filter((b) => b.userId === userId).map((b) => b.blockedId);
}

/** 发送消息前的校验：返回错误文案，或 null 表示可发。 */
export function conversationSendBlock(conv, userId) {
  if (conv.type === 'group') {
    const muted = (conv.mutes ?? {})[userId];
    if (muted !== undefined && (muted < 0 || Date.now() < muted)) {
      return '你已被禁言';
    }
  } else {
    const peer = conv.memberIds.find((m) => m !== userId);
    if (peer && isBlocked(peer, userId)) return '对方拒收了你的消息';
  }
  return null;
}

export function friendIdsOf(userId) {
  return db.data.friends.filter((f) => f.userId === userId).map((f) => f.friendId);
}

export function addFriendPair(a, b) {
  const pairs = [
    { id: newId('fr'), userId: a, friendId: b, createdAt: now() },
    { id: newId('fr'), userId: b, friendId: a, createdAt: now() },
  ];
  for (const p of pairs) {
    if (!db.data.friends.some((f) => f.userId === p.userId && f.friendId === p.friendId)) {
      db.data.friends.push(p);
    }
  }
}

/** Find or create the 1:1 conversation between two users. */
export function ensurePrivateConversation(a, b) {
  const found = db.data.conversations.find(
    (c) =>
      c.type === 'private' &&
      c.memberIds.length === 2 &&
      c.memberIds.includes(a) &&
      c.memberIds.includes(b),
  );
  if (found) return found;
  const conv = {
    id: newId('cv'),
    type: 'private',
    memberIds: [a, b],
    createdAt: now(),
  };
  db.data.conversations.push(conv);
  return conv;
}

export function conversationsOf(userId) {
  return db.data.conversations.filter((c) => c.memberIds.includes(userId));
}

export function lastMessageOf(conversationId) {
  const msgs = db.data.messages.filter((m) => m.conversationId === conversationId);
  return msgs.length ? msgs[msgs.length - 1] : null;
}

export async function save() {
  await db.write();
}
