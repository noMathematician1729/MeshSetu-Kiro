export type TwilioSmsResult =
  | { state: 'disabled' | 'invalid-recipient'; reason: string }
  | { state: 'sent'; providerMessageSid: string }
  | { state: 'failed'; reason: string }

type FetchLike = typeof fetch

export function normalizeE164(value: unknown): string | undefined {
  const input = String(value ?? '').trim()
  // Do not infer a country code: sending to the wrong country is worse than
  // skipping an incorrectly configured contact.
  return /^\+[1-9]\d{7,14}$/.test(input) ? input : undefined
}

export function twilioSmsConfigured(env: NodeJS.ProcessEnv = process.env): boolean {
  return env.TWILIO_SMS_ENABLED === 'true'
    && Boolean(env.TWILIO_ACCOUNT_SID?.trim())
    && Boolean(env.TWILIO_AUTH_TOKEN?.trim())
    && Boolean(normalizeE164(env.TWILIO_FROM_NUMBER))
}

export function buildEmergencySms(record: Record<string, any>, contactName?: string, incidentUrl?: string): string {
  const location = record.latitude != null && record.longitude != null
    ? `${record.latitude}, ${record.longitude}${record.accuracy_m != null ? ` (±${record.accuracy_m}m)` : ''}`
    : undefined
  const fields: Array<[string, unknown]> = [
    ['Alert', 'VERIFIED EMERGENCY ALERT'],
    ['For', contactName], ['Reporter', record.reporter_name ?? record.reporter_uid],
    ['Phone', record.reporter_phone], ['Status', record.status],
    ['Priority', record.priority], ['Type', record.incident_type], ['Zone', record.zone],
    ['Location', location], ['Transcript', record.transcript],
    ['Hazards', Array.isArray(record.hazards) ? record.hazards.join(', ') : record.hazards],
    ['Blood group', record.reporter_blood_group], ['Hop count', record.hops],
    ['Details', incidentUrl],
  ]
  return fields
    .filter(([, value]) => value != null && String(value).trim() !== '')
    .map(([label, value]) => `${label}: ${String(value).replace(/\s+/g, ' ').trim()}`)
    .join('\n')
}

/** Uses Twilio's HTTPS API; credentials come exclusively from deployment env. */
export async function sendEmergencySms(
  to: string,
  body: string,
  options: { env?: NodeJS.ProcessEnv; fetcher?: FetchLike } = {},
): Promise<TwilioSmsResult> {
  const env = options.env ?? process.env
  const recipient = normalizeE164(to)
  if (!recipient) return { state: 'invalid-recipient', reason: 'contact phone must be E.164 (for example +15551234567)' }
  if (!twilioSmsConfigured(env)) return { state: 'disabled', reason: 'Twilio SMS is not enabled or configured' }

  const accountSid = env.TWILIO_ACCOUNT_SID!.trim()
  const form = new URLSearchParams({ To: recipient, From: normalizeE164(env.TWILIO_FROM_NUMBER)!, Body: body })
  try {
    const response = await (options.fetcher ?? fetch)(
      `https://api.twilio.com/2010-04-01/Accounts/${encodeURIComponent(accountSid)}/Messages.json`,
      {
        method: 'POST',
        headers: {
          authorization: `Basic ${Buffer.from(`${accountSid}:${env.TWILIO_AUTH_TOKEN!.trim()}`).toString('base64')}`,
          'content-type': 'application/x-www-form-urlencoded',
        },
        body: form.toString(),
      },
    )
    const payload = await response.json().catch(() => ({})) as { sid?: unknown; message?: unknown; code?: unknown }
    if (!response.ok || typeof payload.sid !== 'string') {
      return { state: 'failed', reason: `Twilio rejected the SMS (${payload.code ?? response.status}): ${String(payload.message ?? 'unknown error').slice(0, 200)}` }
    }
    return { state: 'sent', providerMessageSid: payload.sid }
  } catch (error: any) {
    return { state: 'failed', reason: `Twilio request failed: ${String(error?.message ?? error).slice(0, 200)}` }
  }
}
