// One-off lookup: show every sos_sms_deliveries row for a given recipient
// phone number, joined with basic incident context, ordered oldest first.
//
// Usage:
//   DATABASE_URL=postgres://... node scripts/find_sms_deliveries.mjs "+919131744308"
import { Pool } from 'pg'

const target = process.argv[2]
if (!target) {
  console.error('Usage: DATABASE_URL=... node scripts/find_sms_deliveries.mjs "+91XXXXXXXXXX"')
  process.exit(1)
}
if (!process.env.DATABASE_URL) {
  console.error('DATABASE_URL is not set in the environment.')
  process.exit(1)
}

const pool = new Pool({ connectionString: process.env.DATABASE_URL })
try {
  const result = await pool.query(
    `SELECT d.sms_delivery_id, d.event_id, d.recipient_phone, d.recipient_name,
            d.state, d.provider_message_sid, d.failure_reason,
            d.created_at_ms, d.completed_at_ms,
            i.reporter_uid, i.reporter_name, i.status AS incident_status,
            i.decrypt_status, i.incident_type, i.received_at_ms
     FROM sos_sms_deliveries d
     LEFT JOIN sos_incidents i ON i.event_id = d.event_id
     WHERE d.recipient_phone = $1
     ORDER BY d.created_at_ms ASC`,
    [target],
  )
  console.log(`Deliveries found for ${target}: ${result.rows.length}`)
  for (const row of result.rows) {
    console.log('---')
    console.log('event_id:', row.event_id)
    console.log('reporter:', row.reporter_name, `(${row.reporter_uid})`)
    console.log('incident_type:', row.incident_type, '| decrypt_status:', row.decrypt_status, '| incident_status:', row.incident_status)
    console.log('sms state:', row.state)
    console.log('provider_message_sid:', row.provider_message_sid)
    console.log('failure_reason:', row.failure_reason)
    console.log('created_at:', new Date(Number(row.created_at_ms)).toISOString())
    console.log('completed_at:', row.completed_at_ms ? new Date(Number(row.completed_at_ms)).toISOString() : null)
  }
} finally {
  await pool.end()
}
