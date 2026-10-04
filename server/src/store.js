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
  friends: [],      // {id, userId, friendId, createdAt}  (mutual, stored both ways)
  friendRequests: [], // {id, fromId, toId, status: pending|accepted|rejected, createdAt}
  conversations: [], // {id, type: 'private'|'group', name?, memberIds[], ownerId?, createdAt}
  messages: [],     // {id, conversationId, senderId, type, content, createdAt, readBy[]}
  moments: [],      // {id, authorId, text, images[], createdAt, likes[], comments[]}
};

export const db = await JSONFilePreset(path.join(DATA_DIR, 'db.json'), defaultData);

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
