import { describe, expect, it } from 'vitest'
import { triageSos } from './triage.js'

describe('SOS triage engine', () => {
  it('keeps a high-risk SOS in the immediate-dispatch band and recommends the matching route', () => {
    const result = triageSos({ event_id: 'medical-1', hazards: ['medical'], received_at_ms: Date.UTC(2026, 0, 1, 12), latitude: 19.076, longitude: 72.877, reporter_blood_group: 'O+' }, [], Date.UTC(2026, 0, 1, 12))
    expect(result).toMatchObject({ emergency_type: 'medical', score: 100, band: 'immediate_dispatch', route: { primary: 'Medical / EMS' } })
  })

  it('adds repeat and nearby-report signals without downgrading a general SOS', () => {
    const now = Date.UTC(2026, 0, 1, 12)
    const event = { event_id: 'general-1', hazards: ['general'], reporter_uid: 'reporter-1', received_at_ms: now, latitude: 19.076, longitude: 72.877 }
    const result = triageSos(event, [{ event_id: 'general-2', hazards: ['general'], reporter_uid: 'reporter-1', received_at_ms: now - 10_000, latitude: 19.077, longitude: 72.877 }], now)
    expect(result.score).toBe(100)
    expect(result.band).toBe('immediate_dispatch')
    expect(result.reasons).toEqual(expect.arrayContaining([expect.stringContaining('Repeated SOS'), expect.stringContaining('nearby reports')]))
  })
})
