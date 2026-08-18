const baseUrl = (process.env.HEALTHCHECK_URL || '').replace(/\/$/, '')

if (!baseUrl) {
  console.error('HEALTHCHECK_URL is required')
  process.exit(1)
}

const response = await fetch(`${baseUrl}/health`, {
  headers: { 'user-agent': 'meshsetu-render-healthcheck/1.0' },
})

if (!response.ok) {
  console.error(`Health check failed with status ${response.status}`)
  process.exit(1)
}

const payload = await response.json().catch(() => null)
console.log(JSON.stringify({ ok: true, checked_at: new Date().toISOString(), payload }))
