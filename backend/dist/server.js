import 'dotenv/config';
import http from 'node:http';
import path from 'node:path';
import express from 'express';
import jwt from 'jsonwebtoken';
import { WebSocketServer } from 'ws';
import { z } from 'zod';
import { decryptPacket } from './protocol/mesh.js';
import { store } from './store.js';
const app = express();
app.use(express.json({ limit: '12mb' }));
app.use(express.static(path.resolve(import.meta.dirname, '../../admin-dashboard/dist')));
const clients = new Set();
const jwtSecret = () => process.env.JWT_SECRET || 'meshsetu-local-jwt-change-me';
const gatewaySecret = () => process.env.MESHSETU_GATEWAY_SECRET || process.env.MESHSETU_DEMO_KEY || 'change-me';
const adminEmail = () => process.env.MESHSETU_ADMIN_EMAIL || 'operator@meshsetu.local';
const adminPassword = () => process.env.MESHSETU_ADMIN_PASSWORD || 'meshsetu-demo';
const emit = (type, data) => { const message = JSON.stringify({ type, data }); for (const client of clients)
    if (client.readyState === 1)
        client.send(message); };
function bearer(req, res, next) { const token = req.headers.authorization?.replace(/^Bearer\s+/i, ''); if (!token)
    return res.status(401).json({ error: 'authentication required' }); try {
    req.operator = jwt.verify(token, jwtSecret());
    next();
}
catch {
    res.status(401).json({ error: 'invalid token' });
} }
function gateway(req, res, next) { if (req.header('x-meshsetu-gateway-key') !== gatewaySecret() && req.header('x-meshsetu-demo-key') !== gatewaySecret())
    return res.status(401).json({ error: 'bad gateway key' }); next(); }
app.get('/v1/health', async (_req, res) => res.json({ ok: true, service: 'meshsetu-control-room', database: Boolean(store.pool), time: Date.now() }));
app.post('/v1/auth/token', (req, res) => { const body = z.object({ email: z.string().email(), password: z.string().min(1) }).safeParse(req.body); if (!body.success || body.data.email !== adminEmail() || body.data.password !== adminPassword())
    return res.status(401).json({ error: 'invalid credentials' }); const token = jwt.sign({ sub: body.data.email, role: 'operator' }, jwtSecret(), { expiresIn: '12h' }); res.json({ access_token: token, token_type: 'Bearer', expires_in: 43200, operator: { email: body.data.email, role: 'operator' } }); });
const packetSchema = z.object({ site_id: z.string().min(1), object_id: z.union([z.string(), z.number()]).transform(String), packet_b64: z.string().min(1), peer_id: z.string().optional(), received_at_ms: z.number().optional() });
app.post('/v1/gateway/objects', gateway, async (req, res) => {
    const parsed = packetSchema.safeParse(req.body);
    if (!parsed.success)
        return res.status(400).json({ error: 'invalid packet request', details: parsed.error.issues });
    try {
        const packet = Buffer.from(parsed.data.packet_b64, 'base64');
        const decoded = await decryptPacket(packet, parsed.data.object_id, parsed.data.site_id);
        const now = parsed.data.received_at_ms ?? Date.now();
        if (decoded.envelope.expiresAtMs <= now)
            return res.status(422).json({ error: 'expired packet' });
        if (decoded.envelope.payloadType === 'structuredSos') {
            const s = decoded.payload;
            const record = await store.upsert({ event_id: decoded.envelope.eventId, object_id: decoded.envelope.objectId, site_id: decoded.envelope.siteId, room_id: decoded.envelope.roomId, priority: s.triagePriority, incident_type: s.incidentType, transcript: s.transcript || null, stt_confidence: s.sttConfidence, triage_confidence: s.triageConfidence, hazards: s.hazards, rationale: s.rationale, input_mode: s.inputMode, zone: s.logicalZone || null, latitude: s.lat ?? null, longitude: s.lon ?? null, accuracy_m: s.accuracyM ?? null, location_captured_at_ms: s.locationCapturedAtMs ?? null, hops: decoded.envelope.hopCount, relay_latency_ms: Math.max(0, now - decoded.envelope.createdAtMs), created_at_ms: decoded.envelope.createdAtMs, expires_at_ms: decoded.envelope.expiresAtMs, received_at_ms: now, packet_sha256: decoded.packetSha256, decrypt_status: 'verified', voice_clip_id: s.voiceClipId || null, audio_state: s.voiceClipId ? 'queued' : 'n/a', status: 'new' });
            emit('incident', record);
            return res.json({ ok: true, verified: true, event: record });
        }
        if (decoded.envelope.payloadType === 'voiceObject') {
            const voice = decoded.payload;
            const current = await store.get(voice.sosEventId);
            const record = await store.upsert({ ...(current ?? { event_id: voice.sosEventId, object_id: decoded.envelope.objectId, site_id: decoded.envelope.siteId, room_id: decoded.envelope.roomId, priority: decoded.envelope.priority, incident_type: 'unknown', status: 'new' }), voice_clip_id: voice.clipId, audio_state: 'complete', audio_bytes: voice.bytes, audio_sha256: voice.sha256, audio_content_type: 'audio/ogg; codecs=opus', packet_sha256: decoded.packetSha256, decrypt_status: 'verified', received_at_ms: now, hops: decoded.envelope.hopCount, relay_latency_ms: Math.max(0, now - decoded.envelope.createdAtMs) });
            emit('voice', record);
            return res.json({ ok: true, verified: true, event: record });
        }
        return res.json({ ok: true, verified: true, ignored: decoded.envelope.payloadType });
    }
    catch (error) {
        return res.status(422).json({ error: error?.message || 'packet rejected', verified: false });
    }
});
app.get('/v1/sos', bearer, async (_req, res) => res.json(await store.all()));
app.get('/v1/sos/:eventId', bearer, async (req, res) => { const event = await store.get(String(req.params.eventId)); if (!event)
    return res.status(404).json({ error: 'not found' }); res.json(event); });
app.patch('/v1/sos/:eventId/status', bearer, async (req, res) => { const body = z.object({ status: z.enum(['new', 'acknowledged', 'dispatched', 'resolved']) }).safeParse(req.body); if (!body.success)
    return res.status(400).json({ error: 'invalid status' }); const event = await store.status(String(req.params.eventId), body.data.status); if (!event)
    return res.status(404).json({ error: 'not found' }); emit('incident', event); res.json(event); });
app.get('/v1/sos/:eventId/voice', bearer, async (req, res) => { const event = await store.get(String(req.params.eventId)); if (!event?.audio_bytes)
    return res.status(404).end(); res.type(event.audio_content_type || 'audio/ogg'); res.send(event.audio_bytes); });
// Compatibility surface for the existing Flutter gateway and dashboard.
app.post('/api/events', gateway, async (req, res) => { const event = req.body; if (!event?.event_id)
    return res.status(400).json({ error: 'event_id required' }); const saved = await store.upsert({ ...event, decrypt_status: event.decrypt_status || 'legacy-unverified', received_at_ms: Date.now(), packet_sha256: event.packet_sha256 || 'legacy' }); emit('event', saved); res.json({ ok: true, event: saved }); });
app.get('/api/events', async (_req, res) => res.json(await store.all()));
app.patch('/api/events/:eventId/status', gateway, async (req, res) => { const event = await store.status(String(req.params.eventId), req.body.status); if (!event)
    return res.status(404).json({ error: 'not found' }); emit('event', event); res.json(event); });
export const server = http.createServer(app);
const wss = new WebSocketServer({ noServer: true });
wss.on('connection', (socket, request) => {
    const url = new URL(request.url || '/', 'http://localhost');
    if (url.pathname === '/v1/stream') {
        try {
            jwt.verify(url.searchParams.get('token') || '', jwtSecret());
        }
        catch {
            socket.close(1008, 'authentication required');
            return;
        }
    }
    clients.add(socket);
    store.all().then(events => socket.send(JSON.stringify({ type: 'snapshot', data: events })));
    socket.on('close', () => clients.delete(socket));
});
server.on('upgrade', (request, socket, head) => { if (request.url?.startsWith('/ws') || request.url?.startsWith('/v1/stream'))
    wss.handleUpgrade(request, socket, head, ws => wss.emit('connection', ws, request));
else
    socket.destroy(); });
if (process.env.NODE_ENV !== 'test') {
    await store.init();
    server.listen(Number(process.env.PORT || 8000), '0.0.0.0', () => console.log(`MeshSetu control room listening on ${process.env.PORT || 8000}`));
}
