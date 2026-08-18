import crypto from 'node:crypto';
import path from 'node:path';
import protobuf from 'protobufjs';
import { describe, expect, it } from 'vitest';
import { decryptPacket } from './mesh.js';
async function fixture() {
    const root = await protobuf.load(path.join(import.meta.dirname, 'meshsetu.proto'));
    const type = root.lookupType('meshsetu.v1.MeshEnvelope');
    const objectId = 987654321n;
    const site = Buffer.from('demo-site');
    const payload = Buffer.from(JSON.stringify({ incidentType: 'medical', transcript: 'I cannot breathe near Gate B', sttConfidence: 0, triagePriority: 'p0Critical', triageConfidence: 1, hazards: [], rationale: ['critical safety rule matched'], inputMode: 'voice', locationHint: '', logicalZone: 'Gate-B', voiceClipId: '', lat: null, lon: null, accuracyM: null, locationCapturedAtMs: null }));
    const encoded = type.encode(type.create({ objectId: objectId.toString(), eventId: 'fixture-sos-1', siteId: 'demo-site', roomId: 'public', createdAtMs: 1000, expiresAtMs: 900000, hopCount: 2, hopLimit: 4, priority: 1, payloadType: 1, payload, originEphemeralId: '12345', traceId: Buffer.alloc(16) })).finish();
    const iv = Buffer.alloc(12, 7);
    const aad = Buffer.alloc(1 + 8 + 2 + site.length);
    aad.writeUInt8(1, 0);
    aad.writeBigUInt64BE(objectId, 1);
    aad.writeUInt16BE(site.length, 9);
    site.copy(aad, 11);
    const cipher = crypto.createCipheriv('aes-256-gcm', crypto.createHash('sha256').update('MeshSetu-demo-site-key-v1:demo-site').digest(), iv);
    cipher.setAAD(aad);
    const encrypted = Buffer.concat([cipher.update(encoded), cipher.final(), cipher.getAuthTag()]);
    return { packet: Buffer.concat([Buffer.from([1, 0, site.length]), site, iv, encrypted]), objectId: objectId.toString() };
}
describe('MeshSetu encrypted object decoder', () => {
    it('decodes the mobile AES-GCM/protobuf/SOS wire contract', async () => {
        const value = await decryptPacket((await fixture()).packet, '987654321', 'demo-site');
        expect(value.envelope.eventId).toBe('fixture-sos-1');
        expect(value.envelope.hopCount).toBe(2);
        expect(value.payload.triagePriority).toBe('p0Critical');
        expect(value.payload.logicalZone).toBe('Gate-B');
    });
    it('rejects tampered packets', async () => {
        const value = await fixture();
        value.packet[value.packet.length - 1] ^= 1;
        await expect(decryptPacket(value.packet, value.objectId, 'demo-site')).rejects.toThrow();
    });
});
