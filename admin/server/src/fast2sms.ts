/**
 * Fast2SMS transport for Indian destinations.
 *
 * Twilio's US long codes require the recipient to be verified while the
 * account is on trial, which blocks real emergency delivery in India.
 * Fast2SMS's "Quick SMS" route (`route=q`) sends to Indian numbers without
 * DLT template registration, so it is used as an India-capable fallback.
 */
export type Fast2SmsResult =
  | { state: 'disabled' | 'unsupported-recipient'; reason: string }
  | { state: 'sent'; providerMessageSid: string }
  | { state: 'failed'; reason: string }

type FetchLike = typeof fetch

/** Fast2SMS accepts bare 10-digit Indian subscriber numbers. */
export function indianSubscriberNumber(value: unknown): string | undefined {
  const digits = String(value ?? '').replace(/\D/g, '')
  const local = digits.length === 12 && digits.startsWith('91') ? digits.slice(2) : digits
  return /^[6-9]\d{9}$/.test(local) ? local : undefined
}

export function fast2SmsConfigured(env: NodeJS.ProcessEnv = process.env): boolean {
  return Boolean(env.FAST2SMS_API_KEY?.trim())
}

export async function sendFast2Sms(
  to: string,
  body: string,
  options: { env?: NodeJS.ProcessEnv; fetcher?: FetchLike } = {},
): Promise<Fast2SmsResult> {
  const env = options.env ?? process.env
  const number = indianSubscriberNumber(to)
  if (!number) return { state: 'unsupported-recipient', reason: 'Fast2SMS only delivers to Indian (+91) mobile numbers' }
  if (!fast2SmsConfigured(env)) return { state: 'disabled', reason: 'FAST2SMS_API_KEY is not configured' }

  try {
    const response = await (options.fetcher ?? fetch)('https://www.fast2sms.com/dev/bulkV2', {
      method: 'POST',
      headers: {
        authorization: env.FAST2SMS_API_KEY!.trim(),
        'content-type': 'application/x-www-form-urlencoded',
      },
      // `route=q` is the DLT-free quick route; flash=0 delivers a normal SMS.
      body: new URLSearchParams({ route: 'q', message: body, numbers: number, flash: '0' }).toString(),
    })
    const payload = await response.json().catch(() => ({})) as { return?: unknown; request_id?: unknown; message?: unknown }
    if (!response.ok || payload.return !== true) {
      const detail = Array.isArray(payload.message) ? payload.message.join('; ') : String(payload.message ?? response.status)
      return { state: 'failed', reason: `Fast2SMS rejected the SMS: ${detail.slice(0, 200)}` }
    }
    return { state: 'sent', providerMessageSid: String(payload.request_id ?? 'fast2sms-accepted') }
  } catch (error: any) {
    return { state: 'failed', reason: `Fast2SMS request failed: ${String(error?.message ?? error).slice(0, 200)}` }
  }
}
