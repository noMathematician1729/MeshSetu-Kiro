import { fast2SmsConfigured, sendFast2Sms } from './fast2sms.js'
import { sendEmergencySms, twilioSmsConfigured } from './twilio_sms.js'

export type SmsDispatchResult =
  | { state: 'sent'; provider: string; providerMessageSid: string }
  | { state: 'failed'; reason: string }
  | { state: 'no-provider'; reason: string }

/**
 * Tries each configured transport in order until one accepts the message.
 * Emergency delivery must not depend on a single provider: Twilio trial
 * accounts cannot reach unverified Indian numbers, while Fast2SMS covers
 * India but no other country.
 */
export async function dispatchSms(
  to: string,
  body: string,
  options: { env?: NodeJS.ProcessEnv } = {},
): Promise<SmsDispatchResult> {
  const env = options.env ?? process.env
  const order = (env.SMS_PROVIDER_ORDER || 'twilio,fast2sms')
    .split(',')
    .map((name) => name.trim().toLowerCase())
    .filter(Boolean)

  const failures: string[] = []
  let attempted = false
  for (const provider of order) {
    if (provider === 'twilio') {
      if (!twilioSmsConfigured(env)) continue
      attempted = true
      const result = await sendEmergencySms(to, body, { env })
      if (result.state === 'sent') return { state: 'sent', provider, providerMessageSid: result.providerMessageSid }
      failures.push(`twilio: ${result.reason}`)
    } else if (provider === 'fast2sms') {
      if (!fast2SmsConfigured(env)) continue
      attempted = true
      const result = await sendFast2Sms(to, body, { env })
      if (result.state === 'sent') return { state: 'sent', provider, providerMessageSid: result.providerMessageSid }
      failures.push(`fast2sms: ${result.reason}`)
    }
  }
  if (!attempted) {
    return { state: 'no-provider', reason: 'no SMS provider is enabled or configured' }
  }
  return { state: 'failed', reason: failures.join(' | ').slice(0, 400) }
}

export function anySmsProviderConfigured(env: NodeJS.ProcessEnv = process.env): boolean {
  return twilioSmsConfigured(env) || fast2SmsConfigured(env)
}
