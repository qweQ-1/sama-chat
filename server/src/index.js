// sama-chat backend entry point.
import Fastify from 'fastify';
import websocket from '@fastify/websocket';
import { registerAuthRoutes, verifyToken, authMode } from './auth.js';
import { registerApiRoutes } from './routes.js';
import { createIo } from './realtime.js';

const PORT = Number(process.env.PORT || 8080);
const HOST = process.env.HOST || '0.0.0.0';

const app = Fastify({
  logger: { level: process.env.LOG_LEVEL || 'info' },
  bodyLimit: 8 * 1024 * 1024, // room for base64 image uploads
});

// 心跳：25 秒一次 ping；15 秒无回应判定掉线并清理（穿透/网络抖动下更稳）
await app.register(websocket, {
  options: { pingInterval: 25000, pingTimeout: 15000 },
});

// Treat an empty body on application/json requests as {} — several endpoints
// (like, read, respond) take no payload but clients may still send the header.
app.addContentTypeParser(
  'application/json',
  { parseAs: 'string' },
  (req, body, done) => {
    const raw = String(body ?? '').trim();
    if (!raw) return done(null, {});
    try {
      done(null, JSON.parse(raw));
    } catch (err) {
      err.statusCode = 400;
      done(err);
    }
  },
);

// Raw binary bodies (video uploads) — up to 52 MB.
app.addContentTypeParser(
  'application/octet-stream',
  { parseAs: 'buffer', bodyLimit: 52 * 1024 * 1024 },
  (req, body, done) => done(null, body),
);

// CORS — the Flutter app talks to us from a different origin.
app.addHook('onRequest', async (req, reply) => {
  reply.header('Access-Control-Allow-Origin', '*');
  reply.header('Access-Control-Allow-Methods', 'GET,POST,PATCH,DELETE,OPTIONS');
  reply.header('Access-Control-Allow-Headers', 'Content-Type,Authorization');
  if (req.method === 'OPTIONS') reply.code(204).send();
});

// Bearer-token guard, reused as a preHandler on protected routes.
app.decorate('auth', async (req, reply) => {
  const token = (req.headers.authorization ?? '').replace(/^Bearer\s+/i, '');
  const userId = verifyToken(token);
  if (!userId) {
    reply.code(401).send({ error: 'unauthorized', message: '请先登录' });
    return;
  }
  req.userId = userId;
});

const io = createIo(app);
app.decorate('io', io);

app.get('/health', async () => ({
  status: 'ok',
  service: 'sama-chat',
  online: io.count(),
  authMode: authMode(),
  time: Date.now(),
}));

registerAuthRoutes(app);
registerApiRoutes(app, io);

app.listen({ port: PORT, host: HOST }, (err, address) => {
  if (err) {
    app.log.error(err);
    process.exit(1);
  }
  console.log(`sama-chat server listening on ${address}`);
});
