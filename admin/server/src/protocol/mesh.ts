import crypto from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import protobuf from 'protobufjs'
import { z } from 'zod'

const VERSION = 1
const IV_BYTES = 12
const TAG_BYTES = 16
const priorityNames = ['p3Bulk', 'p0Critical', 'p1High', 'p2Normal', 'p3Bulk']
const payloadNames = ['unknown', 'structuredSos', 'roomMessage', 'voiceManifest', 'voiceObject', 'ack', 'responderUpdate', 'beaconObservation']

const sosSchema = z.object({
  incidentType: z.string(), transcript: z.string(), sttConfidence: z.number(),
  triagePriority: z.enum(['p0Critical', 'p1High', 'p2Normal', 'p3Bulk']),
  triageConfidence: z.number(), hazards: z.array(z.string()), rationale: z.array(z.string()),
  inputMode: z.enum(['tap', 'text', 'voice']), locationHint: z.string().default(''),
  logicalZone: z.string().default(''), voiceClipId: z.string().default(''),
  lat: z.number().nullable().optional(), lon: z.number().nullable().optional(),
  accuracyM: z.number().nullable().optional(), locationCapturedAtMs: z.number().int().nullable().optional()
})

const voiceSchema = z.object({ version: z.literal(1), sosEventId: z.string().min(1), clipId: z.string().min(1), codec: z.literal('opus'), sampleRateHz: z.number(), channels: z.number(), bytes: z.string(), sha256: z.string().length(64) })

let rootPromise: Promise<protobuf.Root> | undefined
function root() {
  const proto = fs.existsSync(path.join(import.meta.dirname, 'protocol', 'meshsetu.proto'))
    ? path.join(import.meta.dirname, 'protocol', 'meshsetu.proto')
    : path.join(import.meta.dirname, '../../src/protocol/meshsetu.proto')
  rootPromise ??= protobuf.load(proto)
  return rootPromise
}

export function demoSiteKey(siteId: string) {
  const configured = process.env.MESHSETU_SITE_KEY_B64
  return configured ? Buffer.from(configured, 'base64') : crypto.createHash('sha256').update(`MeshSetu-demo-site-key-v1:${siteId}`).digest()
}

function u64(value: any) { return BigInt(value?.toString?.() ?? value ?? 0).toString() }

export async function decryptPacket(packet: Buffer, expectedObjectId: string, expectedSiteId: string) {
  if (packet.length <= 1 + 2 + IV_BYTES + TAG_BYTES) throw new Error('encrypted object is too short')
  let offset = 0
  if (packet.readUInt8(offset++) !== VERSION) throw new Error('unsupported crypto format')
  const siteLength = packet.readUInt16BE(offset); offset += 2
  if (siteLength > packet.length - offset - IV_BYTES - TAG_BYTES) throw new Error('invalid site metadata')
  const site = packet.subarray(offset, offset + siteLength); offset += siteLength
  const iv = packet.subarray(offset, offset + IV_BYTES); offset += IV_BYTES
  const encrypted = packet.subarray(offset)
  const ciphertext = encrypted.subarray(0, encrypted.length - TAG_BYTES)
  const tag = encrypted.subarray(encrypted.length - TAG_BYTES)
  const siteId = site.toString('utf8')
  if (siteId !== expectedSiteId) throw new Error('site id mismatch')
  const objectId = BigInt(expectedObjectId)
  const aad = Buffer.alloc(1 + 8 + 2 + site.length)
  aad.writeUInt8(VERSION, 0); aad.writeBigUInt64BE(objectId, 1); aad.writeUInt16BE(site.length, 9); site.copy(aad, 11)
  const decipher = crypto.createDecipheriv('aes-256-gcm', demoSiteKey(siteId), iv)
  decipher.setAAD(aad); decipher.setAuthTag(tag)
  const plaintext = Buffer.concat([decipher.update(ciphertext), decipher.final()])
  const type = (await root()).lookupType('meshsetu.v1.MeshEnvelope')
  const decoded: any = type.toObject(type.decode(plaintext), { longs: String, enums: Number, bytes: Buffer, defaults: true })
  if (u64(decoded.objectId) !== expectedObjectId) throw new Error('object id mismatch')
  if (decoded.siteId !== siteId) throw new Error('envelope site id mismatch')
  const payloadType = Number(decoded.payloadType ?? 0)
  const envelope = {
    objectId: expectedObjectId, eventId: decoded.eventId, siteId: decoded.siteId, roomId: decoded.roomId,
    createdAtMs: Number(decoded.createdAtMs), expiresAtMs: Number(decoded.expiresAtMs), hopCount: Number(decoded.hopCount),
    hopLimit: Number(decoded.hopLimit), priority: priorityNames[Number(decoded.priority)] ?? 'p3Bulk',
    payloadType: payloadNames[payloadType] ?? 'unknown', payload: Buffer.from(decoded.payload ?? []),
    originEphemeralId: u64(decoded.originEphemeralId), traceId: Buffer.from(decoded.traceId ?? [])
  }
  let payload: any = null
  if (envelope.payloadType === 'structuredSos') payload = sosSchema.parse(JSON.parse(envelope.payload.toString('utf8')))
  if (envelope.payloadType === 'voiceObject') {
    const voice = voiceSchema.parse(JSON.parse(envelope.payload.toString('utf8')))
    const bytes = Buffer.from(voice.bytes, 'base64')
    if (crypto.createHash('sha256').update(bytes).digest('hex') !== voice.sha256) throw new Error('voice integrity check failed')
    payload = { ...voice, bytes }
  }
  return { envelope, payload, packetSha256: crypto.createHash('sha256').update(packet).digest('hex') }
}
