import type { EventRecord } from './store.js'

export type EmergencyType = 'general' | 'fire' | 'crime' | 'kidnap' | 'medical' | 'natural_disaster'

export type TriageResult = {
  version: 1
  emergency_type: EmergencyType
  score: number
  confidence: number
  band: 'immediate_dispatch' | 'operator_dispatch' | 'operator_review'
  route: { primary: string; secondary: string[]; instruction: string }
  reasons: string[]
  ran_at_ms: number
}

const emergencyTypes: EmergencyType[] = ['general', 'fire', 'crime', 'kidnap', 'medical', 'natural_disaster']
const baseScores: Record<EmergencyType, number> = { kidnap: 100, medical: 95, fire: 90, natural_disaster: 85, crime: 80, general: 75 }
const routes: Record<EmergencyType, TriageResult['route']> = {
  kidnap: { primary: 'Police / security', secondary: ['Control room'], instruction: 'Preserve the last known location and coordinate an immediate safety response.' },
  medical: { primary: 'Medical / EMS', secondary: ['Control room'], instruction: 'Dispatch medical aid and share available medical profile details with responders.' },
  fire: { primary: 'Fire response', secondary: ['Site evacuation lead', 'Control room'], instruction: 'Start evacuation coordination and send fire response to the reported location.' },
  crime: { primary: 'Security / police', secondary: ['Control room'], instruction: 'Send security response and preserve the reported location for responders.' },
  natural_disaster: { primary: 'Disaster response', secondary: ['Site authority', 'Control room'], instruction: 'Coordinate site safety actions and notify the relevant disaster-response authority.' },
  general: { primary: 'Control room', secondary: [], instruction: 'Contact the reporter if possible and obtain emergency classification.' },
}

const number = (value: unknown) => Number.isFinite(Number(value)) ? Number(value) : undefined
const emergencyType = (event: EventRecord): EmergencyType => {
  const candidate = Array.isArray(event.hazards) ? event.hazards[0] : event.incident_type
  return emergencyTypes.includes(candidate as EmergencyType) ? candidate as EmergencyType : 'general'
}
const hasLocation = (event: EventRecord) => {
  const latitude = number(event.latitude)
  const longitude = number(event.longitude)
  return latitude != null && longitude != null && Math.abs(latitude) <= 90 && Math.abs(longitude) <= 180
}
const closeEnough = (a: EventRecord, b: EventRecord) => {
  if (!hasLocation(a) || !hasLocation(b)) return a.zone && a.zone === b.zone
  const latitudeDistance = number(a.latitude)! - number(b.latitude)!
  const longitudeDistance = (number(a.longitude)! - number(b.longitude)!) * Math.cos((number(a.latitude)! * Math.PI) / 180)
  return Math.hypot(latitudeDistance, longitudeDistance) * 111_000 <= 500
}

export function triageSos(event: EventRecord, recentIncidents: EventRecord[], ranAtMs = Date.now()): TriageResult {
  const type = emergencyType(event)
  let score = baseScores[type]
  let confidence = 0.55
  const reasons = [`${type.replace('_', ' ')} SOS base score: ${baseScores[type]}`]
  const eventTime = number(event.received_at_ms) ?? number(event.created_at_ms) ?? ranAtMs
  const sameReporterRecent = recentIncidents.some(candidate => candidate.reporter_uid && candidate.reporter_uid === event.reporter_uid && Math.abs((number(candidate.received_at_ms) ?? 0) - eventTime) <= 60_000)
  const nearbyReports = recentIncidents.filter(candidate => emergencyType(candidate) === type && closeEnough(event, candidate)).length

  if (sameReporterRecent) { score += 15; confidence += 0.1; reasons.push('Repeated SOS from the same reporter in the last 60 seconds: +15') }
  if (hasLocation(event)) { score += 10; confidence += 0.15; reasons.push('Verified GPS location is available: +10') }
  if (event.reporter_blood_group || event.reporter_primary_contact) { score += 10; confidence += 0.1; reasons.push('Emergency profile details are available: +10') }
  if (nearbyReports > 0) { score += 10; confidence += 0.1; reasons.push(`${nearbyReports + 1} nearby reports of the same emergency type: +10`) }
  const hour = new Date(eventTime).getHours()
  if (hour >= 20 || hour < 6) { score += 5; reasons.push('Reported during local night hours: +5') }

  score = Math.min(100, score)
  confidence = Math.min(0.95, confidence)
  const band = score >= 95 ? 'immediate_dispatch' : score >= 80 ? 'operator_dispatch' : 'operator_review'
  reasons.push(band === 'immediate_dispatch' ? 'Recommendation: immediate dispatch.' : band === 'operator_dispatch' ? 'Recommendation: immediate operator alert and dispatch review.' : 'Recommendation: keep in the P0 queue and request classification.')
  return { version: 1, emergency_type: type, score, confidence, band, route: routes[type], reasons, ran_at_ms: ranAtMs }
}
