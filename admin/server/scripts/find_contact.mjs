// One-off lookup: find any user_profiles row whose emergency_contacts (or
// primary_contact_phone) contains a given phone number's last 10 digits.
//
// Usage:
//   DATABASE_URL=postgres://... node scripts/find_contact.mjs "+919131744308"
//
// Does not print or persist the connection string. Read-only query.
import { Pool } from 'pg'

const target = process.argv[2]
if (!target) {
  console.error('Usage: DATABASE_URL=... node scripts/find_contact.mjs "+91XXXXXXXXXX"')
  process.exit(1)
}
if (!process.env.DATABASE_URL) {
  console.error('DATABASE_URL is not set in the environment.')
  process.exit(1)
}

const digits = target.replace(/\D/g, '')
const suffix = digits.slice(-10)
if (suffix.length < 6) {
  console.error('Number too short after stripping non-digits.')
  process.exit(1)
}

const pool = new Pool({ connectionString: process.env.DATABASE_URL })
try {
  const result = await pool.query(
    `SELECT reporter_uid, name, phone, primary_contact_phone, emergency_contacts
     FROM user_profiles
     WHERE right(regexp_replace(phone, '\\D', '', 'g'), 10) = $1
        OR right(regexp_replace(primary_contact_phone, '\\D', '', 'g'), 10) = $1
        OR emergency_contacts::text LIKE '%' || $1 || '%'`,
    [suffix],
  )
  console.log(`Searched for suffix: ${suffix}`)
  console.log(`Matches found: ${result.rows.length}`)
  for (const row of result.rows) {
    console.log('---')
    console.log('reporter_uid:', row.reporter_uid)
    console.log('name:', row.name)
    console.log('own phone:', row.phone)
    console.log('primary_contact_phone:', row.primary_contact_phone)
    console.log('emergency_contacts:', JSON.stringify(row.emergency_contacts))
  }
} finally {
  await pool.end()
}
