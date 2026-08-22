import 'dotenv/config'
import http from 'node:http'
import express from 'express'
import jwt from 'jsonwebtoken'
import { WebSocketServer } from 'ws'
import { z } from 'zod'
import { decryptPacket } from './protocol/mesh.js'
import { createHash } from 'node:crypto'
import { store } from './store.js'
import { triageSos } from './triage.js'
import { buildEmergencySms, normalizeE164, sendEmergencySms, twilioSmsConfigured } from './twilio_sms.js'
import { anySmsProviderConfigured, dispatchSms } from './sms_delivery.js'

const app = express()
const normalizeOrigin = (value?: string) => value?.trim().replace(/\/$/, '')
const localOrigins = ['http://localhost:5173', 'http://127.0.0.1:5173']
const configuredOrigins = [
  process.env.MESHSETU_ADMIN_ORIGIN,
  process.env.MESHSETU_PUBLIC_APP_ORIGIN,
  ...(process.env.CORS_ALLOWED_ORIGINS || '').split(','),
].map(normalizeOrigin).filter(Boolean) as string[]
const allowedOrigins = new Set([...localOrigins, ...configuredOrigins])

app.use((req, res, next) => {
  const origin = normalizeOrigin(req.headers.origin)
  if (origin && allowedOrigins.has(origin)) {
    res.header('Access-Control-Allow-Origin', origin)
    res.header('Vary', 'Origin')
    res.header('Access-Control-Allow-Credentials', 'true')
    res.header('Access-Control-Allow-Headers', 'Authorization, Content-Type')
    res.header('Access-Control-Allow-Methods', 'GET,POST,PATCH,OPTIONS')
  }
  if (req.method === 'OPTIONS') return res.sendStatus(204)
  next()
})
app.use(express.json({ limit: '12mb' }))
const clients = new Set<any>()
type RoomMember = { memberId: string, displayName: string, joinedAtMs: number }
type RoomConnection = { roomKey: string, memberId: string }
const roomConnections = new Map<any, RoomConnection>()
const roomMembers = new Map<string, Map<string, RoomMember>>()
const jwtSecret = () => process.env.JWT_SECRET || 'meshsetu-local-jwt-change-me'
const gatewaySecret = () => process.env.MESHSETU_GATEWAY_SECRET || process.env.MESHSETU_DEMO_KEY || 'change-me'
const adminEmail = () => process.env.MESHSETU_ADMIN_EMAIL || 'operator@meshsetu.local'
const adminPassword = () => process.env.MESHSETU_ADMIN_PASSWORD || 'meshsetu-demo'
const emit = (type: string, data: any) => { const message = JSON.stringify({ type, data }); for (const client of clients) if (client.readyState === 1) client.send(message) }
const roomKey = (siteId: string, roomId: string) => `${siteId}\u0000${roomId}`
const emitRoomMembers = (key: string) => {
  const members = [...(roomMembers.get(key)?.values() ?? [])].sort((a, b) => a.joinedAtMs - b.joinedAtMs)
  const message = JSON.stringify({ type: 'room-members', data: members })
  for (const [socket, connection] of roomConnections) {
    if (connection.roomKey === key && socket.readyState === 1) socket.send(message)
  }
}
const roomJoinSchema = z.object({ type: z.literal('join-room'), siteId: z.string().min(1).max(100), roomId: z.string().min(1).max(100), memberId: z.string().min(1).max(200), displayName: z.string().min(1).max(100), gatewayKey: z.string().min(1) })
const roomMessageSchema = z.object({ type: z.literal('room-message'), messageId: z.string().min(1).max(200), text: z.string().trim().min(1).max(2000), sentAtMs: z.number().int().positive() })
function bearer(req: express.Request, res: express.Response, next: express.NextFunction) { const token = req.headers.authorization?.replace(/^Bearer\s+/i, ''); if (!token) return res.status(401).json({ error: 'authentication required' }); try { (req as any).operator = jwt.verify(token, jwtSecret()); next() } catch { res.status(401).json({ error: 'invalid token' }) } }
function gateway(req: express.Request, res: express.Response, next: express.NextFunction) { if (req.header('x-meshsetu-gateway-key') !== gatewaySecret() && req.header('x-meshsetu-demo-key') !== gatewaySecret()) return res.status(401).json({ error: 'bad gateway key' }); next() }

const publicAppOrigin = () => normalizeOrigin(process.env.MESHSETU_PUBLIC_APP_ORIGIN || process.env.MESHSETU_ADMIN_ORIGIN || 'http://localhost:5173')!
const publicIncidentUrl = (eventId: string) => `${publicAppOrigin()}/sos/${encodeURIComponent(eventId)}`

/**
 * Sends exactly one SMS to each configured contact for an initial SOS. A
 * durable reservation is created before calling Twilio, so re-forwarded BLE
 * packets and gateway retries cannot produce duplicate texts.
 */
async function dispatchEmergencySms(record: any, updateType: string) {
  const log = (level: 'info' | 'warn' | 'error', message: string, details: Record<string, unknown> = {}) => console[level]('[sos-sms]', message, { eventId: record.event_id, ...details })
  const redactedPhone = (phone: string) => `***${phone.slice(-4)}`
  if (updateType !== 'new') {
    log('info', 'not sending SMS for a non-initial incident update', { updateType })
    return
  }
  if (!anySmsProviderConfigured()) {
    log('warn', 'SMS skipped: no SMS provider is enabled or configured')
    return
  }

  const profileResolved = record.decrypt_status === 'verified'
    || record.decrypt_status === 'relay-decrypted'
    || (record.decrypt_status === 'ceal-uid-only' && Boolean(record.reporter_name))
  if (!profileResolved || !record.reporter_uid) {
    log('warn', 'SMS skipped: SOS is not verified or profile-resolved', { decryptStatus: record.decrypt_status ?? 'missing', hasReporterUid: Boolean(record.reporter_uid) })
    return
  }

  const profile = await store.getProfile(record.reporter_uid) ?? await store.getProfileByPrefix(record.reporter_uid)
  if (!profile) {
    log('warn', 'SMS skipped: no registered reporter profile was found')
    return
  }
  const contacts = new Map<string, string | undefined>()
  for (const contact of profile.emergency_contacts ?? []) {
    const phone = normalizeE164(contact?.phone)
    if (phone) contacts.set(phone, contact?.name)
    else if (contact?.phone) log('warn', 'SMS skipped for invalid emergency-contact phone', { contactIndex: contacts.size })
  }
  if (contacts.size === 0) {
    log('warn', 'SMS skipped: reporter has no E.164 emergency contacts')
    return
  }

  log('info', 'preparing emergency-contact SMS deliveries', { contactCount: contacts.size, source: record.decrypt_status })
  for (const [phone, name] of contacts) {
    const deliveryId = createHash('sha256').update(`${record.event_id}\u0000${phone}`).digest('hex')
    const reserved = await store.reserveSmsDelivery({
      sms_delivery_id: deliveryId, event_id: record.event_id, recipient_phone: phone,
      recipient_name: name ?? null, state: 'reserved', provider_message_sid: null,
      failure_reason: null, created_at_ms: Date.now(), completed_at_ms: null,
    })
    if (!reserved) {
      log('info', 'SMS not re-sent: a delivery record already exists', { deliveryId: deliveryId.slice(0, 12), recipient: redactedPhone(phone) })
      continue
    }
    log('info', 'submitting SMS to provider chain', { deliveryId: deliveryId.slice(0, 12), recipient: redactedPhone(phone) })
    const result = await dispatchSms(phone, buildEmergencySms(record, name, publicIncidentUrl(record.event_id)))
    if (result.state === 'sent') {
      await store.completeSmsDelivery(deliveryId, { state: 'sent', providerMessageSid: `${result.provider}:${result.providerMessageSid}` })
      log('info', 'SMS accepted by provider', { deliveryId: deliveryId.slice(0, 12), recipient: redactedPhone(phone), provider: result.provider, messageSid: result.providerMessageSid })
    } else {
      await store.completeSmsDelivery(deliveryId, { state: 'failed', failureReason: result.reason })
      log('error', 'SMS delivery failed on every configured provider', { deliveryId: deliveryId.slice(0, 12), recipient: redactedPhone(phone), reason: result.reason })
    }
  }
}

async function fanOutIncident(record: any, updateType: string, relayDeviceId?: string) {
  const existingRecipients = await store.recipientKeysForEvent(record.event_id)
  const recipients = new Map<string, { recipient_type: 'admin' | 'emergency_contact' | 'relay'; recipient_key: string }>()
  recipients.set('admin:all', { recipient_type: 'admin', recipient_key: 'admin:all' })
  if (record.reporter_uid) {
    const profile = await store.getProfile(record.reporter_uid) ?? await store.getProfileByPrefix(record.reporter_uid)
    for (const contact of profile?.emergency_contacts ?? []) {
      if (!contact?.phone) continue
      for (const account of await store.profilesForPhone(String(contact.phone))) recipients.set(`contact:${account.reporter_uid}`, { recipient_type: 'emergency_contact', recipient_key: `contact:${account.reporter_uid}` })
    }
  }
  for (const recipient of existingRecipients) recipients.set(`${recipient.recipient_type}:${recipient.recipient_key}`, recipient)
  if (relayDeviceId) recipients.set(`relay:${relayDeviceId}`, { recipient_type: 'relay', recipient_key: `relay:${relayDeviceId}` })
  const reporter = record.reporter_name || (record.reporter_uid ? `UID ${record.reporter_uid}` : 'Unknown sender')
  const updateLabel = updateType === 'new' ? 'SOS received' : updateType === 'status:dispatched' ? 'SOS escalated' : `SOS update: ${updateType.replace(/^status:/, '')}`
  const body = `${reporter} · ${record.incident_type || 'emergency'}${record.zone ? ` · ${record.zone}` : ''}`
  const notifications = await store.createNotifications([...recipients.values()].map(recipient => ({
    notification_id: `${record.event_id}:${recipient.recipient_key}:${updateType}`,
    event_id: record.event_id,
    recipient_type: recipient.recipient_type,
    recipient_key: recipient.recipient_key,
    update_type: updateType,
    title: updateLabel,
    body,
    public_url: publicIncidentUrl(record.event_id),
    created_at_ms: Date.now(),
  })))
  notifications.forEach(notification => emit('notification', notification))
  await dispatchEmergencySms(record, updateType)
  return notifications
}

async function triageP0(record: any) {
  if (record.priority !== 'p0Critical') return record
  const receivedAtMs = Number(record.received_at_ms ?? Date.now())
  const recent = await store.recentForTriage(record, receivedAtMs - 60_000)
  return await store.applyTriage(record.event_id, triageSos(record, recent)) ?? record
}

async function healthPayload() {
  let database = 'memory'
  if (store.pool) {
    await store.pool.query('SELECT 1')
    database = 'postgres'
  }
  return { ok: true, service: 'meshsetu-control-room', database, time: Date.now() }
}

app.get('/health', async (_req, res) => {
  try {
    res.json(await healthPayload())
  } catch (error: any) {
    res.status(503).json({ ok: false, service: 'meshsetu-control-room', error: error?.message || 'health check failed', time: Date.now() })
  }
})
app.get('/v1/health', async (_req, res) => {
  try {
    res.json(await healthPayload())
  } catch (error: any) {
    res.status(503).json({ ok: false, service: 'meshsetu-control-room', error: error?.message || 'health check failed', time: Date.now() })
  }
})
app.post('/v1/auth/token', (req, res) => { const body = z.object({ email: z.string().email(), password: z.string().min(1) }).safeParse(req.body); if (!body.success || body.data.email !== adminEmail() || body.data.password !== adminPassword()) return res.status(401).json({ error: 'invalid credentials' }); const token = jwt.sign({ sub: body.data.email, role: 'operator' }, jwtSecret(), { expiresIn: '12h' }); res.json({ access_token: token, token_type: 'Bearer', expires_in: 43200, operator: { email: body.data.email, role: 'operator' } }) })

// Notification recipients open a dedicated, indefinitely-addressable incident page.
app.get('/v1/public/sos/:eventId', async (req, res) => { const event = await store.get(String(req.params.eventId)); if (!event) return res.status(404).json({ error: 'not found' }); res.json(event) })
app.get('/v1/notifications/:recipientUid', async (req, res) => res.json(await store.notificationsFor(`contact:${String(req.params.recipientUid)}`)))

const relaySosSchema = z.object({
  relay_device_id: z.string().min(1).max(128),
  event: z.object({
    event_id: z.string().min(1), object_id: z.string().min(1), site_id: z.string().min(1), room_id: z.string().default('public'),
    priority: z.string().default('p0Critical'), incident_type: z.string().default('compact_sos'), transcript: z.string().nullable().optional(),
    zone: z.string().nullable().optional(), latitude: z.number().nullable().optional(), longitude: z.number().nullable().optional(), accuracy_m: z.number().nullable().optional(), location_captured_at_ms: z.number().nullable().optional(),
    hops: z.number().int().nonnegative().default(0), relay_latency_ms: z.number().int().nonnegative().default(0), created_at_ms: z.number(), expires_at_ms: z.number(), reporter_uid: z.string().nullable().optional(),
  }),
})
app.post('/v1/gateway/relay-sos', gateway, async (req, res) => {
  const parsed = relaySosSchema.safeParse(req.body); if (!parsed.success) return res.status(400).json({ error: 'invalid relay SOS', details: parsed.error.issues })
  const source = parsed.data.event
  const profile = source.reporter_uid ? await store.getProfile(source.reporter_uid) ?? await store.getProfileByPrefix(source.reporter_uid) : undefined
  const record = await triageP0(await store.upsert({ ...source, received_at_ms: Date.now(), packet_sha256: `relay:${source.object_id}`, decrypt_status: 'relay-decrypted', status: 'new', reporter_uid: source.reporter_uid ?? null, reporter_name: profile?.name ?? null, reporter_phone: profile?.phone ?? null, reporter_language: profile?.language ?? null, reporter_blood_group: profile?.blood_group ?? null, reporter_primary_contact: profile ? `${profile.primary_contact_name} (${profile.primary_contact_phone})` : null }))
  await fanOutIncident(record, 'new', parsed.data.relay_device_id)
  emit('incident', record)
  res.json({ ok: true, event: record, public_url: publicIncidentUrl(source.event_id) })
})

const packetSchema = z.object({ site_id: z.string().min(1), object_id: z.union([z.string(), z.number()]).transform(String), packet_b64: z.string().min(1), peer_id: z.string().optional(), received_at_ms: z.number().optional() })
app.post('/v1/gateway/objects', gateway, async (req, res) => {
  const parsed = packetSchema.safeParse(req.body); if (!parsed.success) return res.status(400).json({ error: 'invalid packet request', details: parsed.error.issues })
  try {
    const packet = Buffer.from(parsed.data.packet_b64, 'base64')
    const decoded = await decryptPacket(packet, parsed.data.object_id, parsed.data.site_id)
    const now = parsed.data.received_at_ms ?? Date.now()
    if (decoded.envelope.expiresAtMs <= now) return res.status(422).json({ error: 'expired packet' })
    if (decoded.envelope.payloadType === 'structuredSos') {
      const s = decoded.payload
      const compactSequence = Number(BigInt(decoded.envelope.objectId) & 0xffffn)
      const compact = s.reporter?.uid
        ? await store.findRecentCompactEvent(
            s.reporter.uid,
            compactSequence,
            now - 600000,
            decoded.envelope.siteId,
          )
        : undefined
      const record = await triageP0(await store.upsert({ event_id: compact?.event_id ?? decoded.envelope.eventId, object_id: decoded.envelope.objectId, site_id: decoded.envelope.siteId, room_id: decoded.envelope.roomId, priority: s.triagePriority, incident_type: s.incidentType, transcript: s.transcript || null, stt_confidence: s.sttConfidence, triage_confidence: s.triageConfidence, hazards: s.hazards, rationale: s.rationale, input_mode: s.inputMode, zone: s.logicalZone || null, latitude: s.lat ?? null, longitude: s.lon ?? null, accuracy_m: s.accuracyM ?? null, location_captured_at_ms: s.locationCapturedAtMs ?? null, hops: decoded.envelope.hopCount, relay_latency_ms: Math.max(0, now - decoded.envelope.createdAtMs), created_at_ms: decoded.envelope.createdAtMs, expires_at_ms: decoded.envelope.expiresAtMs, received_at_ms: now, packet_sha256: decoded.packetSha256, decrypt_status: 'verified', voice_clip_id: s.voiceClipId || null, audio_state: s.voiceClipId ? 'queued' : 'n/a', status: 'new', reporter_uid: s.reporter?.uid ?? null, reporter_name: s.reporter?.name ?? null, reporter_phone: s.reporter?.phone ?? null, reporter_language: s.reporter?.language ?? null, reporter_blood_group: s.reporter?.bloodGroup ?? null, reporter_primary_contact: s.reporter ? `${s.reporter.primaryContactName} (${s.reporter.primaryContactPhone})` : null, compact_sequence: compact?.compact_sequence ?? compactSequence }))
      await fanOutIncident(record, 'new')
      emit('incident', record); return res.json({ ok: true, verified: true, event: record })
    }
    if (decoded.envelope.payloadType === 'voiceObject') {
      const voice = decoded.payload
      const current = await store.get(voice.sosEventId)
      const record = await store.upsert({ ...(current ?? { event_id: voice.sosEventId, object_id: decoded.envelope.objectId, site_id: decoded.envelope.siteId, room_id: decoded.envelope.roomId, priority: decoded.envelope.priority, incident_type: 'unknown', status: 'new' }), voice_clip_id: voice.clipId, audio_state: 'complete', audio_bytes: voice.bytes, audio_sha256: voice.sha256, audio_content_type: 'audio/ogg; codecs=opus', packet_sha256: decoded.packetSha256, decrypt_status: 'verified', received_at_ms: now, hops: decoded.envelope.hopCount, relay_latency_ms: Math.max(0, now - decoded.envelope.createdAtMs) })
      await fanOutIncident(record, 'voice:complete')
      emit('voice', record); return res.json({ ok: true, verified: true, event: record })
    }
    return res.json({ ok: true, verified: true, ignored: decoded.envelope.payloadType })
  } catch (error: any) { return res.status(422).json({ error: error?.message || 'packet rejected', verified: false }) }
})

app.get('/v1/sos', bearer, async (_req, res) => res.json(await store.all()))
app.get('/v1/sos/:eventId', bearer, async (req, res) => { const event = await store.get(String(req.params.eventId)); if (!event) return res.status(404).json({ error: 'not found' }); res.json(event) })
app.patch('/v1/sos/:eventId/status', bearer, async (req, res) => { const body = z.object({ status: z.enum(['new', 'acknowledged', 'dispatched', 'resolved']) }).safeParse(req.body); if (!body.success) return res.status(400).json({ error: 'invalid status' }); const event = await store.status(String(req.params.eventId), body.data.status); if (!event) return res.status(404).json({ error: 'not found' }); await fanOutIncident(event, `status:${body.data.status}`); emit('incident', event); res.json(event) })
app.get('/v1/sos/:eventId/voice', bearer, async (req, res) => { const event = await store.get(String(req.params.eventId)); if (!event?.audio_bytes) return res.status(404).end(); res.type(event.audio_content_type || 'audio/ogg'); res.send(event.audio_bytes) })

// Compatibility surface for the existing Flutter gateway and dashboard.
app.post('/api/events', gateway, async (req, res) => { const event = req.body; if (!event?.event_id) return res.status(400).json({ error: 'event_id required' }); const saved = await triageP0(await store.upsert({ ...event, decrypt_status: event.decrypt_status || 'legacy-unverified', received_at_ms: Date.now(), packet_sha256: event.packet_sha256 || 'legacy' })); emit('event', saved); res.json({ ok: true, event: saved }) })
app.get('/api/events', async (_req, res) => res.json(await store.all()))
app.patch('/api/events/:eventId/status', gateway, async (req, res) => { const event = await store.status(String(req.params.eventId), req.body.status); if (!event) return res.status(404).json({ error: 'not found' }); emit('event', event); res.json(event) })

// CEAL-style profile registration and UID→profile resolution.
const profileSchema = z.object({ reporter_uid: z.string().min(1).max(12), name: z.string().min(1).max(100), phone: z.string().min(5).max(30), language: z.string().min(1).max(30).default('English'), blood_group: z.string().max(10).default(''), allergies: z.string().max(500).default(''), conditions: z.string().max(500).default(''), primary_contact_name: z.string().max(100).default(''), primary_contact_phone: z.string().max(30).default(''), emergency_contacts: z.array(z.object({ name: z.string(), phone: z.string(), priority: z.number().optional() })).max(10).default([]) })
app.post('/v1/profiles', gateway, async (req, res) => { const parsed = profileSchema.safeParse(req.body); if (!parsed.success) return res.status(400).json({ error: 'invalid profile', details: parsed.error.issues }); const saved = await store.upsertProfile({ ...parsed.data, registered_at_ms: Date.now() }); emit('profile', saved); res.json({ ok: true, profile: saved }) })
app.get('/v1/profiles/:uid', bearer, async (req, res) => { const profile = await store.getProfile(String(req.params.uid)); if (!profile) return res.status(404).json({ error: 'profile not found' }); res.json(profile) })
app.get('/v1/profiles', bearer, async (_req, res) => res.json(await store.allProfiles()))

// CEAL-style compact SOS alert with UID→profile resolution.
const cealSosSchema = z.object({ reporter_uid: z.string().min(1), site_id: z.string().min(1).default('demo-site'), flags: z.number().int().min(0).max(255).default(1), received_at_ms: z.number().nullable().optional(), origin_id: z.number().nullable().optional(), sequence: z.number().nullable().optional(), latitude: z.number().nullable().optional(), longitude: z.number().nullable().optional(), accuracy_m: z.number().nullable().optional(), location_captured_at_ms: z.number().nullable().optional() })
const compactEmergencyTypes = [
  { incidentType: 'general', hazard: 'general' },
  { incidentType: 'fire', hazard: 'fire' },
  { incidentType: 'crime', hazard: 'crime' },
  { incidentType: 'kidnap', hazard: 'kidnap' },
  { incidentType: 'medical', hazard: 'medical' },
  { incidentType: 'natural_disaster', hazard: 'natural_disaster' },
]
const compactEmergencyType = (flags: number) => compactEmergencyTypes[(flags >> 2) & 0x0f] ?? compactEmergencyTypes[0]
app.post('/v1/gateway/ceal-sos', gateway, async (req, res) => {
  const parsed = cealSosSchema.safeParse(req.body); if (!parsed.success) return res.status(400).json({ error: 'invalid CEAL SOS', details: parsed.error.issues })
  const profile = await store.getProfile(parsed.data.reporter_uid) ?? await store.getProfileByPrefix(parsed.data.reporter_uid)
  const now = parsed.data.received_at_ms ?? Date.now()
  const emergencyType = compactEmergencyType(parsed.data.flags)
  // Every nearby peer with internet forwards the same alert. Converge them on
  // one incident so the dashboard and the contacts see a single emergency.
  const existing = await store.findRecentCompactEvent(parsed.data.reporter_uid, parsed.data.sequence ?? null, now - 600000, parsed.data.site_id)
  if (existing?.decrypt_status === 'verified') {
    emit('incident', existing)
    return res.json({ ok: true, resolved: true, event: existing, profile: profile ?? null })
  }
  const eventId = existing?.event_id ?? `ceal-${parsed.data.reporter_uid}-${Date.now()}`
  const record = await triageP0(await store.upsert({
    event_id: eventId,
    object_id: existing?.object_id ?? `ceal-${parsed.data.origin_id ?? 0}-${parsed.data.sequence ?? 0}-${now}`,
    compact_sequence: parsed.data.sequence ?? null,
    site_id: parsed.data.site_id,
    room_id: 'public',
    priority: 'p0Critical',
    incident_type: emergencyType.incidentType,
    hazards: [emergencyType.hazard],
    transcript: profile ? `${emergencyType.incidentType} SOS from ${profile.name} (${profile.phone})` : `${emergencyType.incidentType} SOS from UID ${parsed.data.reporter_uid} (unregistered)`,
    latitude: parsed.data.latitude ?? null,
    longitude: parsed.data.longitude ?? null,
    accuracy_m: parsed.data.accuracy_m ?? null,
    location_captured_at_ms: parsed.data.location_captured_at_ms ?? null,
    hops: 0,
    relay_latency_ms: 0,
    created_at_ms: now,
    expires_at_ms: now + 900000,
    received_at_ms: now,
    packet_sha256: 'ceal-compact',
    decrypt_status: 'ceal-uid-only',
    status: 'new',
    reporter_uid: parsed.data.reporter_uid,
    reporter_name: profile?.name ?? null,
    reporter_phone: profile?.phone ?? null,
    reporter_language: profile?.language ?? null,
    reporter_blood_group: profile?.blood_group ?? null,
    reporter_primary_contact: profile ? `${profile.primary_contact_name} (${profile.primary_contact_phone})` : null,
  }))
  await fanOutIncident(record, 'new')
  emit('incident', record)
  res.json({ ok: true, resolved: !!profile, event: record, profile: profile ?? null })
})

export const server = http.createServer(app)
const wss = new WebSocketServer({ noServer: true })
wss.on('connection', (socket, request) => {
  const url = new URL(request.url || '/', 'http://localhost')
  if (url.pathname === '/v1/stream') {
    try { jwt.verify(url.searchParams.get('token') || '', jwtSecret()) } catch { socket.close(1008, 'authentication required'); return }
  }
  if (url.pathname === '/v1/rooms/stream') {
    let joined = false
    socket.on('message', (raw: Buffer) => {
      let payload: unknown
      try { payload = JSON.parse(raw.toString()) } catch { socket.close(1008, 'invalid room join request'); return }
      if (!joined) {
        const parsed = roomJoinSchema.safeParse(payload)
        if (!parsed.success || parsed.data.gatewayKey !== gatewaySecret()) { socket.close(1008, 'authentication required'); return }
        joined = true
        const key = roomKey(parsed.data.siteId, parsed.data.roomId)
        roomConnections.set(socket, { roomKey: key, memberId: parsed.data.memberId })
        const members = roomMembers.get(key) ?? new Map<string, RoomMember>()
        roomMembers.set(key, members)
        members.set(parsed.data.memberId, { memberId: parsed.data.memberId, displayName: parsed.data.displayName.trim(), joinedAtMs: Date.now() })
        socket.send(JSON.stringify({ type: 'room-joined', data: { siteId: parsed.data.siteId, roomId: parsed.data.roomId } }))
        console.log(`[room-chat] ${parsed.data.siteId}/${parsed.data.roomId}: ${parsed.data.displayName.trim()} joined`)
        emitRoomMembers(key)
        return
      }
      const message = roomMessageSchema.safeParse(payload)
      const connection = roomConnections.get(socket)
      const member = connection == null ? undefined : roomMembers.get(connection.roomKey)?.get(connection.memberId)
      if (!message.success || connection == null || member == null) return
      const outbound = JSON.stringify({ type: 'room-message', data: { messageId: message.data.messageId, text: message.data.text, memberId: member.memberId, displayName: member.displayName, sentAtMs: message.data.sentAtMs } })
      let recipients = 0
      for (const [client, clientConnection] of roomConnections) {
        if (client === socket) continue
        if (clientConnection.roomKey === connection.roomKey && client.readyState === 1) { client.send(outbound); recipients++ }
      }
      if (socket.readyState === 1) {
        socket.send(JSON.stringify({ type: 'room-message-accepted', data: { messageId: message.data.messageId, recipientCount: recipients } }))
      }
      console.log(`[room-chat] ${member.displayName}: broadcast to ${recipients} connection(s)`)
    })
    socket.on('close', () => {
      const connection = roomConnections.get(socket)
      if (!connection) return
      roomConnections.delete(socket)
      const memberStillConnected = [...roomConnections.values()].some((item) => item.roomKey === connection.roomKey && item.memberId === connection.memberId)
      if (!memberStillConnected) roomMembers.get(connection.roomKey)?.delete(connection.memberId)
      if (roomMembers.get(connection.roomKey)?.size === 0) roomMembers.delete(connection.roomKey)
      emitRoomMembers(connection.roomKey)
    })
    return
  }
  clients.add(socket); store.all().then(events => socket.send(JSON.stringify({ type: 'snapshot', data: events }))); socket.on('close', () => clients.delete(socket))
})
server.on('upgrade', (request, socket, head) => { if (request.url?.startsWith('/ws') || request.url?.startsWith('/v1/stream') || request.url?.startsWith('/v1/rooms/stream')) wss.handleUpgrade(request, socket, head, ws => wss.emit('connection', ws, request)); else socket.destroy() })

if (process.env.NODE_ENV !== 'test') { await store.init(); server.listen(Number(process.env.PORT || 8000), '0.0.0.0', () => console.log(`MeshSetu control room listening on ${process.env.PORT || 8000}`)) }
