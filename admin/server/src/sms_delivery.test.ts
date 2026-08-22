import { describe, expect, it } from 'vitest'
import { dispatchSms } from './sms_delivery.js'
import { indianSubscriberNumber } from './fast2sms.js'

const twilioEnv = {
  TWILIO_SMS_ENABLED: 'true',
  TWILIO_ACCOUNT_SID: 'AC-test',
  TWILIO_AUTH_TOKEN: 'token',
  TWILIO_FROM_NUMBER: '+15092849424',
} as NodeJS.ProcessEnv

describe('Fast2SMS recipient normalization', () => {
  it('accepts Indian numbers in E.164 or local form and rejects others', () => {
    expect(indianSubscriberNumber('+919573804520')).toBe('9573804520')
    expect(indianSubscriberNumber('9573804520')).toBe('9573804520')
    expect(indianSubscriberNumber('+15095551234')).toBeUndefined()
    expect(indianSubscriberNumber('123')).toBeUndefined()
  })
})

describe('multi-provider SMS delivery', () => {
  it('falls back to Fast2SMS when Twilio rejects an unverified Indian number', async () => {
    const calls: string[] = []
    const originalFetch = globalThis.fetch
    globalThis.fetch = (async (input: RequestInfo | URL) => {
      const url = String(input)
      calls.push(url)
      if (url.startsWith('https://api.twilio.com/')) {
        // Real trial-account behaviour observed against Twilio: error 21608.
        return new Response(JSON.stringify({ code: 21608, message: 'unverified number' }), { status: 400, headers: { 'content-type': 'application/json' } })
      }
      return new Response(JSON.stringify({ return: true, request_id: 'f2s-1' }), { status: 200, headers: { 'content-type': 'application/json' } })
    }) as typeof fetch

    try {
      const result = await dispatchSms('+919573804520', 'emergency', {
        env: { ...twilioEnv, FAST2SMS_API_KEY: 'f2s-key' } as NodeJS.ProcessEnv,
      })
      expect(result).toMatchObject({ state: 'sent', provider: 'fast2sms', providerMessageSid: 'f2s-1' })
      expect(calls[0]).toContain('api.twilio.com')
      expect(calls[1]).toContain('fast2sms.com')
    } finally {
      globalThis.fetch = originalFetch
    }
  })

  it('reports every provider failure when none accepts the message', async () => {
    const originalFetch = globalThis.fetch
    globalThis.fetch = (async () =>
      new Response(JSON.stringify({ code: 21608, message: 'unverified number' }), { status: 400, headers: { 'content-type': 'application/json' } })) as typeof fetch
    try {
      const result = await dispatchSms('+919573804520', 'emergency', { env: twilioEnv })
      expect(result.state).toBe('failed')
      expect(result.state === 'failed' && result.reason).toContain('twilio')
    } finally {
      globalThis.fetch = originalFetch
    }
  })

  it('reports no-provider when nothing is configured', async () => {
    const result = await dispatchSms('+919573804520', 'emergency', { env: {} as NodeJS.ProcessEnv })
    expect(result.state).toBe('no-provider')
  })
})
