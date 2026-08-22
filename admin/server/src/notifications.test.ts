import crypto from 'node:crypto'
import path from 'node:path'
import protobuf from 'protobufjs'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'

process.env.NODE_ENV = 'test'
process.env.DATABASE_URL = ''
process.env.TWILIO_SMS_ENABLED = 'true'
process.env.TWILIO_ACCOUNT_SID = 'test-account'
process.env.TWILIO_AUTH_TOKEN = 'test-token'
process.env.TWILIO_FROM_NUMBER = '+15550009999'
const nativeFetch = globalThis.fetch
const twilioRequests: Array<{ url: string; body: string }> = []
globalThis.fetch = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
  const url = String(input)
  if (url.startsWith('https://api.twilio.com/')) {
    twilioRequests.push({ url, body: String(init?.body ?? '') })
    return new Response(JSON.stringify({ sid: `SM-test-${twilioRequests.length}` }), { status: 201, headers: { 'content-type': 'application/json' } })
  }
  return nativeFetch(input, init)
}
const [{ server }, { store }] = await Promise.all([import('./server.js'), import('./store.js')])
let base = ''
let eventId = ''
const gatewayHeaders = { 'content-type': 'application/json', 'x-meshsetu-gateway-key': 'change-me' }

async function encryptedStructuredPacket({ objectId, eventId, reporterUid }: { objectId: bigint; eventId: string; reporterUid: string }) {
  const root = await protobuf.load(path.join(import.meta.dirname, 'protocol', 'meshsetu.proto'))
  const type = root.lookupType('meshsetu.v1.MeshEnvelope')
  const site = Buffer.from('demo-site')
  const payload = Buffer.from(JSON.stringify({ incidentType: 'medical', transcript: 'help at Gate B', sttConfidence: 0, triagePriority: 'p0Critical', triageConfidence: 1, hazards: [], rationale: [], inputMode: 'tap', locationHint: '', logicalZone: 'Gate-B', voiceClipId: '', lat: 19.076, lon: 72.8777, accuracyM: 8, locationCapturedAtMs: Date.now(), reporter: { uid: reporterUid, name: 'Priya Sharma', phone: '+919876543210', language: 'English', bloodGroup: 'O+', primaryContactName: 'Ravi', primaryContactPhone: '+15550003333' } }))
  const now = Date.now()
  const encoded = type.encode(type.create({ objectId: objectId.toString(), eventId, siteId: 'demo-site', roomId: 'public', createdAtMs: now, expiresAtMs: now + 900000, hopCount: 1, hopLimit: 4, priority: 1, payloadType: 1, payload, originEphemeralId: '12345', traceId: Buffer.alloc(16) })).finish()
  const iv = Buffer.alloc(12, 9)
  const aad = Buffer.alloc(1 + 8 + 2 + site.length); aad.writeUInt8(1, 0); aad.writeBigUInt64BE(objectId, 1); aad.writeUInt16BE(site.length, 9); site.copy(aad, 11)
  const cipher = crypto.createCipheriv('aes-256-gcm', crypto.createHash('sha256').update('MeshSetu-demo-site-key-v1:demo-site').digest(), iv); cipher.setAAD(aad)
  const encrypted = Buffer.concat([cipher.update(encoded), cipher.final(), cipher.getAuthTag()])
  return { packet: Buffer.concat([Buffer.from([1, 0, site.length]), site, iv, encrypted]), objectId: objectId.toString() }
}

beforeAll(async () => {
  await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve))
  const address = server.address() as { port: number }
  base = `http://127.0.0.1:${address.port}`
  await fetch(`${base}/v1/profiles`, { method: 'POST', headers: gatewayHeaders, body: JSON.stringify({ reporter_uid: 'contact-uid', name: 'Emergency Contact', phone: '+15550002' }) })
  await fetch(`${base}/v1/profiles`, { method: 'POST', headers: gatewayHeaders, body: JSON.stringify({ reporter_uid: 'sender-uid', name: 'SOS Sender', phone: '+15550001', emergency_contacts: [{ name: 'Emergency Contact', phone: '+15550002' }] }) })
  // Registered with a differently formatted phone than the sender saved.
  await fetch(`${base}/v1/profiles`, { method: 'POST', headers: gatewayHeaders, body: JSON.stringify({ reporter_uid: 'a1b2c3d4e5f6', name: 'Priya Sharma', phone: '+91 98765 43210', blood_group: 'O+', emergency_contacts: [{ name: 'Ravi', phone: '(555) 000-3333' }] }) })
  await fetch(`${base}/v1/profiles`, { method: 'POST', headers: gatewayHeaders, body: JSON.stringify({ reporter_uid: 'ravi-uid', name: 'Ravi Sharma', phone: '+15550003333' }) })
})
afterAll(async () => {
  globalThis.fetch = nativeFetch
  await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()))
})

describe('SOS recipient notifications', () => {
  it('fans out a compact SOS to registered emergency contacts and exposes its full incident page', async () => {
    const response = await fetch(`${base}/v1/gateway/ceal-sos`, { method: 'POST', headers: gatewayHeaders, body: JSON.stringify({ reporter_uid: 'sender-uid', sequence: 8, site_id: 'demo-site' }) })
    const raw = await response.text()
    expect(response.status, raw).toBe(200)
    const payload: any = JSON.parse(raw)
    eventId = payload.event.event_id
    const notifications: any[] = await (await fetch(`${base}/v1/notifications/contact-uid`)).json()
    expect(notifications).toHaveLength(1)
    expect(notifications[0]).toMatchObject({ event_id: eventId, recipient_type: 'emergency_contact', update_type: 'new' })
    expect(notifications[0].public_url).toContain(`/sos/${encodeURIComponent(eventId)}`)
    const detail: any = await (await fetch(`${base}/v1/public/sos/${encodeURIComponent(eventId)}`)).json()
    expect(detail.reporter_name).toBe('SOS Sender')
    expect(detail.incident_type).toBe('general')
    expect(detail.hazards).toEqual(['general'])
    const smsDeliveries = await store.smsDeliveriesForEvent(eventId)
    expect(smsDeliveries).toMatchObject([{ recipient_phone: '+15550002', state: 'sent', provider_message_sid: 'twilio:SM-test-1' }])
    expect(twilioRequests).toHaveLength(1)
    expect(new URLSearchParams(twilioRequests[0].body).get('Body')).toContain('Reporter: SOS Sender')
    // Several connected relays may forward this exact alert. It stays one SMS.
    const duplicate = await fetch(`${base}/v1/gateway/ceal-sos`, { method: 'POST', headers: gatewayHeaders, body: JSON.stringify({ reporter_uid: 'sender-uid', sequence: 8, site_id: 'demo-site' }) })
    const duplicatePayload: any = await duplicate.json()
    expect(duplicatePayload.event.event_id).toBe(eventId)
    expect(twilioRequests).toHaveLength(1)
  })

  it('adds a new notification when the SOS is escalated', async () => {
    const login = await fetch(`${base}/v1/auth/token`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email: 'operator@meshsetu.local', password: 'meshsetu-demo' }) })
    const token = (await login.json() as any).access_token
    const update = await fetch(`${base}/v1/sos/${encodeURIComponent(eventId)}/status`, { method: 'PATCH', headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: JSON.stringify({ status: 'dispatched' }) })
    expect(update.status).toBe(200)
    const notifications: any[] = await (await fetch(`${base}/v1/notifications/contact-uid`)).json()
    expect(notifications.map(item => item.update_type)).toContain('status:dispatched')
  })
})

describe('compact SOS resolved from an advertised reporter UID', () => {
  it('returns the full incident detail to the forwarding peer', async () => {
    const response = await fetch(`${base}/v1/gateway/ceal-sos`, { method: 'POST', headers: gatewayHeaders, body: JSON.stringify({ reporter_uid: 'a1b2c3d4e5f6', sequence: 11, site_id: 'demo-site', latitude: 19.076, longitude: 72.8777 }) })
    const payload: any = await response.json()

    expect(response.status).toBe(200)
    expect(payload.resolved).toBe(true)
    // This is what the internet-connected peer shows instead of a bare alert.
    expect(payload.event.reporter_name).toBe('Priya Sharma')
    expect(payload.event.reporter_phone).toBe('+91 98765 43210')
    expect(payload.event.reporter_blood_group).toBe('O+')
    expect(payload.event.latitude).toBe(19.076)
    expect(payload.event.event_id).toBeTruthy()
  })

  it('notifies the contact whose registered phone is formatted differently', async () => {
    const notifications: any[] = await (await fetch(`${base}/v1/notifications/ravi-uid`)).json()

    expect(notifications).toHaveLength(1)
    expect(notifications[0].recipient_type).toBe('emergency_contact')
    expect(notifications[0].body).toContain('Priya Sharma')
    expect(notifications[0].public_url).toContain('/sos/')
  })

  it('converges repeated relays of one alert into a single incident and alert', async () => {
    const second = await fetch(`${base}/v1/gateway/ceal-sos`, { method: 'POST', headers: gatewayHeaders, body: JSON.stringify({ reporter_uid: 'a1b2c3d4e5f6', sequence: 11, site_id: 'demo-site' }) })
    const third = await fetch(`${base}/v1/gateway/ceal-sos`, { method: 'POST', headers: gatewayHeaders, body: JSON.stringify({ reporter_uid: 'a1b2c3d4e5f6', sequence: 11, site_id: 'demo-site' }) })
    const secondBody: any = await second.json()
    const thirdBody: any = await third.json()

    expect(secondBody.event.event_id).toBe(thirdBody.event.event_id)
    const notifications: any[] = await (await fetch(`${base}/v1/notifications/ravi-uid`)).json()
    expect(notifications).toHaveLength(1)
  })

  it('upgrades a compact alert when the matching encrypted GATT SOS arrives', async () => {
    const compact = await fetch(`${base}/v1/gateway/ceal-sos`, { method: 'POST', headers: gatewayHeaders, body: JSON.stringify({ reporter_uid: 'a1b2c3d4e5f6', sequence: 23, site_id: 'demo-site' }) })
    const compactBody: any = await compact.json()
    const packet = await encryptedStructuredPacket({ objectId: 65559n, eventId: 'rich-event-23', reporterUid: 'a1b2c3d4e5f6' })
    const rich = await fetch(`${base}/v1/gateway/objects`, { method: 'POST', headers: gatewayHeaders, body: JSON.stringify({ site_id: 'demo-site', object_id: packet.objectId, packet_b64: packet.packet.toString('base64') }) })
    const richBody: any = await rich.json()

    expect(rich.status).toBe(200)
    expect(richBody.event.event_id).toBe(compactBody.event.event_id)
    expect(richBody.event.incident_type).toBe('medical')
    expect(richBody.event.decrypt_status).toBe('verified')
  })

  it('still records an unresolved alert when the UID is unknown', async () => {
    const response = await fetch(`${base}/v1/gateway/ceal-sos`, { method: 'POST', headers: gatewayHeaders, body: JSON.stringify({ reporter_uid: 'ffffffffffff', sequence: 3, site_id: 'demo-site' }) })
    const payload: any = await response.json()

    expect(response.status).toBe(200)
    expect(payload.resolved).toBe(false)
    expect(payload.event.transcript).toContain('unregistered')
  })

  it('maps compact flags to the CEAL emergency category in hazards', async () => {
    const response = await fetch(`${base}/v1/gateway/ceal-sos`, { method: 'POST', headers: gatewayHeaders, body: JSON.stringify({ reporter_uid: 'sender-uid', sequence: 31, site_id: 'demo-site', flags: 0x05 }) })
    const payload: any = await response.json()

    expect(response.status).toBe(200)
    expect(payload.event.incident_type).toBe('fire')
    expect(payload.event.hazards).toEqual(['fire'])
  })
})
