import { afterAll, beforeAll, describe, expect, it } from 'vitest'

process.env.NODE_ENV = 'test'
process.env.DATABASE_URL = ''
const { server } = await import('./server.js')
let base = ''
let eventId = ''
const gatewayHeaders = { 'content-type': 'application/json', 'x-meshsetu-gateway-key': 'change-me' }

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
afterAll(async () => { await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve())) })

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
    expect(detail.incident_type).toBe('ceal_compact_sos')
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

  it('still records an unresolved alert when the UID is unknown', async () => {
    const response = await fetch(`${base}/v1/gateway/ceal-sos`, { method: 'POST', headers: gatewayHeaders, body: JSON.stringify({ reporter_uid: 'ffffffffffff', sequence: 3, site_id: 'demo-site' }) })
    const payload: any = await response.json()

    expect(response.status).toBe(200)
    expect(payload.resolved).toBe(false)
    expect(payload.event.transcript).toContain('unregistered')
  })
})
