import { Pool } from 'pg'

export type EventRecord = Record<string, any>
export type ProfileRecord = { reporter_uid: string; name: string; phone: string; language: string; blood_group: string; allergies: string; conditions: string; primary_contact_name: string; primary_contact_phone: string; emergency_contacts: any[]; registered_at_ms: number; updated_at?: string }
export class EventStore {
  pool?: Pool
  memory = new Map<string, EventRecord>()
  profiles = new Map<string, ProfileRecord>()
  constructor() { if (process.env.DATABASE_URL) this.pool = new Pool({ connectionString: process.env.DATABASE_URL }) }
  async init() {
    if (!this.pool) return
    await this.pool.query(`CREATE TABLE IF NOT EXISTS sos_incidents (event_id text PRIMARY KEY, object_id text UNIQUE NOT NULL, site_id text NOT NULL, room_id text, priority text NOT NULL, incident_type text NOT NULL, transcript text, stt_confidence real, triage_confidence real, hazards jsonb NOT NULL DEFAULT '[]', rationale jsonb NOT NULL DEFAULT '[]', input_mode text, zone text, latitude double precision, longitude double precision, accuracy_m real, location_captured_at_ms bigint, hops integer NOT NULL DEFAULT 0, relay_latency_ms integer, created_at_ms bigint, expires_at_ms bigint, received_at_ms bigint NOT NULL, packet_sha256 text NOT NULL, decrypt_status text NOT NULL, voice_clip_id text, audio_state text, status text NOT NULL DEFAULT 'new', audio_bytes bytea, audio_sha256 text, audio_content_type text, reporter_uid text, reporter_name text, reporter_phone text, reporter_language text, reporter_blood_group text, reporter_primary_contact text, updated_at timestamptz NOT NULL DEFAULT now())`)
    await this.pool.query(`CREATE TABLE IF NOT EXISTS user_profiles (reporter_uid text PRIMARY KEY, name text NOT NULL, phone text NOT NULL, language text NOT NULL DEFAULT 'English', blood_group text, allergies text, conditions text, primary_contact_name text, primary_contact_phone text, emergency_contacts jsonb NOT NULL DEFAULT '[]', registered_at_ms bigint NOT NULL, updated_at timestamptz NOT NULL DEFAULT now())`)
  }
  async upsert(record: EventRecord) {
    const existing = this.memory.get(record.event_id)
    const merged = { ...existing, ...record, updated_at: new Date().toISOString() }
    this.memory.set(record.event_id, merged)
    if (this.pool) await this.pool.query(`INSERT INTO sos_incidents (event_id, object_id, site_id, room_id, priority, incident_type, transcript, stt_confidence, triage_confidence, hazards, rationale, input_mode, zone, latitude, longitude, accuracy_m, location_captured_at_ms, hops, relay_latency_ms, created_at_ms, expires_at_ms, received_at_ms, packet_sha256, decrypt_status, voice_clip_id, audio_state, status, audio_bytes, audio_sha256, audio_content_type) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25,$26,$27,$28,$29,$30) ON CONFLICT (event_id) DO UPDATE SET object_id=COALESCE(EXCLUDED.object_id,sos_incidents.object_id), priority=COALESCE(EXCLUDED.priority,sos_incidents.priority), incident_type=COALESCE(EXCLUDED.incident_type,sos_incidents.incident_type), transcript=COALESCE(EXCLUDED.transcript,sos_incidents.transcript), zone=COALESCE(EXCLUDED.zone,sos_incidents.zone), latitude=COALESCE(EXCLUDED.latitude,sos_incidents.latitude), longitude=COALESCE(EXCLUDED.longitude,sos_incidents.longitude), hops=GREATEST(sos_incidents.hops,EXCLUDED.hops), relay_latency_ms=COALESCE(EXCLUDED.relay_latency_ms,sos_incidents.relay_latency_ms), voice_clip_id=COALESCE(EXCLUDED.voice_clip_id,sos_incidents.voice_clip_id), audio_state=COALESCE(EXCLUDED.audio_state,sos_incidents.audio_state), status=sos_incidents.status, audio_bytes=COALESCE(EXCLUDED.audio_bytes,sos_incidents.audio_bytes), audio_sha256=COALESCE(EXCLUDED.audio_sha256,sos_incidents.audio_sha256), updated_at=now()`, [record.event_id, record.object_id, record.site_id, record.room_id, record.priority, record.incident_type, record.transcript, record.stt_confidence, record.triage_confidence, JSON.stringify(record.hazards ?? []), JSON.stringify(record.rationale ?? []), record.input_mode, record.zone, record.latitude, record.longitude, record.accuracy_m, record.location_captured_at_ms, record.hops ?? 0, record.relay_latency_ms, record.created_at_ms, record.expires_at_ms, record.received_at_ms ?? Date.now(), record.packet_sha256, record.decrypt_status ?? 'verified', record.voice_clip_id, record.audio_state, record.status ?? 'new', record.audio_bytes ?? null, record.audio_sha256 ?? null, record.audio_content_type ?? null])
    return merged
  }
  async all() { if (!this.pool) return [...this.memory.values()]; const result = await this.pool.query('SELECT * FROM sos_incidents ORDER BY CASE priority WHEN $1 THEN 0 WHEN $2 THEN 1 WHEN $3 THEN 2 ELSE 3 END, received_at_ms DESC', ['p0Critical','p1High','p2Normal']); return result.rows }
  async get(id: string) { if (!this.pool) return this.memory.get(id); const result = await this.pool.query('SELECT * FROM sos_incidents WHERE event_id=$1', [id]); return result.rows[0] }
  async status(id: string, value: string) { const current = await this.get(id); if (!current) return undefined; const next = { ...current, status: value }; return this.upsert(next) }
  async upsertProfile(profile: ProfileRecord) {
    const merged = { ...profile, updated_at: new Date().toISOString() }
    this.profiles.set(profile.reporter_uid, merged)
    if (this.pool) await this.pool.query(`INSERT INTO user_profiles (reporter_uid, name, phone, language, blood_group, allergies, conditions, primary_contact_name, primary_contact_phone, emergency_contacts, registered_at_ms) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) ON CONFLICT (reporter_uid) DO UPDATE SET name=EXCLUDED.name, phone=EXCLUDED.phone, language=EXCLUDED.language, blood_group=EXCLUDED.blood_group, allergies=EXCLUDED.allergies, conditions=EXCLUDED.conditions, primary_contact_name=EXCLUDED.primary_contact_name, primary_contact_phone=EXCLUDED.primary_contact_phone, emergency_contacts=EXCLUDED.emergency_contacts, updated_at=now()`, [profile.reporter_uid, profile.name, profile.phone, profile.language, profile.blood_group ?? '', profile.allergies ?? '', profile.conditions ?? '', profile.primary_contact_name ?? '', profile.primary_contact_phone ?? '', JSON.stringify(profile.emergency_contacts ?? []), profile.registered_at_ms])
    return merged
  }
  async getProfile(uid: string): Promise<ProfileRecord | undefined> {
    if (!this.pool) return this.profiles.get(uid)
    const result = await this.pool.query('SELECT * FROM user_profiles WHERE reporter_uid=$1', [uid])
    return result.rows[0]
  }
  async allProfiles(): Promise<ProfileRecord[]> {
    if (!this.pool) return [...this.profiles.values()]
    const result = await this.pool.query('SELECT * FROM user_profiles ORDER BY registered_at_ms DESC')
    return result.rows
  }
}

export const store = new EventStore()
