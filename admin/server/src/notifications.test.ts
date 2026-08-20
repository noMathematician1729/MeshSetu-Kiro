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
