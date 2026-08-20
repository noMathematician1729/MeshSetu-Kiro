# GAT / SOS work done

Branch: `fix/gatt-sos`  
Scope: reliable BLE GATT SOS delivery, voice evidence over mesh, incident notifications, gateway forwarding to the admin dashboard, and related UX fixes.

This document summarizes the work completed against the **Reliable SOS delivery and incident handling** plan.

---

## Problem summary (before)

1. **“Queued for BLE” was misleading** — local outbox persistence looked like delivery; no peer / frame / ACK visibility.
2. **Compact SOS advertising blocked discoverability** — `broadcastSos()` replaced normal discovery advertising for **12 seconds**, which could prevent a rich SOS from getting a GATT session.
3. **Split mesh identity** — `MeshBridgeClient` generated its own random ephemeral ID instead of using the foreground `MeshEventController` token, so a device could treat its own compact advert as a peer alert.
4. **Voice was not real mesh evidence** — SOS screen used PCM → STT then discarded audio; `VoiceRepository.attachToSos()` had no production caller, so no `voiceObject` reached peers or the dashboard.
5. **Notification taps went nowhere** — no payload, no incident detail screen, no cold-start routing.
6. **Origin gateway path was legacy** — originated SOS went to plaintext `/api/events`; received objects used verified `/v1/gateway/objects`. Voice could not ride the origin path.
7. **UX footguns** — permissions screen not scrollable; Gateway URL/key fields lost focus because providers rebuilt on every keystroke.

---

## What was implemented

### 1. Transport status, identity, and discovery

| Change | Detail |
|--------|--------|
| Shared BLE identity | Foreground task sends `localEphemeralId` on `started`; Event Mode starts `MeshBridgeClient` with that token (no second random ID). |
| Self-advert suppression | Compact SOS alerts with matching `originId` are ignored; duplicate dedupe keys still suppressed. |
| Shorter SOS advert window | Compact SOS advert duration **12s → 2s** in `ble_discovery.dart` so discovery advertising is restored sooner and GATT linking is less interrupted. |
| Delivery labels on SOS screen | After send, UI watches the outbox row and shows human labels for `ready` / `relaying` / `acked` / `expired` / `failed`. |

**Key files:**  
`mobile/lib/app/event_mode_screen.dart`, `mobile/lib/app/mesh_event_controller.dart`, `mobile/lib/core/ble/ble_discovery.dart`, `mobile/lib/feature/sos/sos_screen.dart`

**Note:** Full outbox taxonomy from the plan (`waiting_for_peer`, `frames_sent`, etc.) was approximated with clearer labels on existing states (`ready` / `relaying` / `acked`), not a full new state machine.

---

### 2. Voice evidence as a correlated mesh object

| Change | Detail |
|--------|--------|
| Opus capture on SOS | SOS screen records Opus via `recordOpusClip()` (≤10s) instead of PCM-only STT discard. |
| Attach to SOS | Calls `VoiceRepository.attachToSos(...)` → outbox row `PayloadType.voiceObject` (P2), linked by `sosEventId` / `clipId`. |
| Finalize unlocks voice | On SOS finalize, linked voice outbox row is set to `ready` so it drains after the structured SOS. |
| Structured SOS still P0 | Metadata / GPS / triage remain the critical object; voice is secondary evidence and must not block SOS. |

**Voice → BLE path (high level):**

1. Opus bytes → `VoiceObjectPayload` JSON (base64 audio + sha256 + IDs).  
2. Outbox `voiceObject` → `OutboxSender` → mesh envelope.  
3. AES-GCM encrypt → MTU fragmentation → GATT write/notify.  
4. Peer reassembly + decrypt → inbox / relay / gateway.  

Voice is **not** inside the compact BLE SOS advert. Reassembly happens **on phones**, not on the admin dashboard.

**Key files:**  
`mobile/lib/feature/sos/sos_screen.dart`, `mobile/lib/feature/sos/sos_repository.dart`, `mobile/lib/feature/voice/voice_recorder.dart`, `mobile/lib/feature/voice/voice_repository.dart`

---

### 3. Incident detail + notification routing

| Change | Detail |
|--------|--------|
| `IncidentDetailScreen` | Durable inbox-backed detail: type, priority, transcript, GPS, hops, voice presence, etc. |
| SOS card → detail | Event Mode received-SOS card taps into incident detail when IDs are known. |
| `NotificationRouter` | App-level init, tap handler, cold-start launch details, pending-payload flush. |
| Payload | Rich SOS notifications carry JSON `{ siteId, eventId, objectId }`. |
| Navigation | Root `navigatorKey` + `/incident` route in `main.dart`. |

**Key files:**  
`mobile/lib/feature/sos/incident_detail_screen.dart` (new),  
`mobile/lib/app/notification_router.dart` (new),  
`mobile/lib/main.dart`,  
`mobile/lib/app/event_mode_screen.dart`

---

### 4. Gateway forwarding (origin + voice)

| Change | Detail |
|--------|--------|
| Encrypt for gateway on origin | Foreground path calls `encryptForGateway(envelope)` and sends `encryptedBytes` with `mesh_origin_submitted`. |
| Verified HTTP path | Origin SOS **and** voice use `GatewayBridge.postEncryptedObject` → `POST /v1/gateway/objects` (same as relayed objects). |
| Admin handling | Server decrypts one complete packet, upserts SOS or attaches Opus (`audio_state: complete`) for `voiceObject`. |

**Important:** BLE fragments are assembled on-device. The gateway POSTs **one** encrypted object blob. The dashboard decrypts/stores; it does not reassemble GATT frames.

**Key files:**  
`mobile/lib/app/event_mode_screen.dart`,  
`mobile/lib/app/mesh_bridge_client.dart`,  
`admin/server/src/server.ts` (existing `/v1/gateway/objects` + voice persistence)

---

### 5. UX / onboarding fixes (related)

| Change | Detail |
|--------|--------|
| Scrollable permissions | `permission_gate.dart` wrapped in `SingleChildScrollView` / `LayoutBuilder`. |
| Gateway fields keep focus | `onboardingRepositoryProvider` no longer `watch`es gateway URL/key; lazy bridge callback via `ref.read` so typing does not rebuild and steal focus. |

**Key files:**  
`mobile/lib/core/ble/permission_gate.dart`,  
`mobile/lib/app/providers.dart`,  
`mobile/lib/feature/onboarding/onboarding_repository.dart`

---

### 6. Tests added / extended

- Voice linkage / outbox correlation — `mobile/test/feature/onboarding_sos_test.dart`
- Notification routing — `mobile/test/app/notification_router_test.dart` (new)
- Gateway provider focus / lazy bridge — `mobile/test/feature/gateway_provider_test.dart` (new)

---

## Files touched (this workstream)

**Modified**

- `mobile/lib/app/event_mode_screen.dart`
- `mobile/lib/app/mesh_bridge_client.dart`
- `mobile/lib/app/mesh_event_controller.dart`
- `mobile/lib/app/providers.dart`
- `mobile/lib/core/ble/ble_discovery.dart`
- `mobile/lib/core/ble/mesh_transport.dart` (minor)
- `mobile/lib/core/ble/permission_gate.dart`
- `mobile/lib/feature/onboarding/onboarding_repository.dart`
- `mobile/lib/feature/sos/sos_repository.dart`
- `mobile/lib/feature/sos/sos_screen.dart`
- `mobile/lib/feature/voice/voice_recorder.dart`
- `mobile/lib/feature/voice/voice_repository.dart`
- `mobile/lib/main.dart`
- `mobile/test/feature/onboarding_sos_test.dart`
- lockfiles as needed

**Added**

- `mobile/lib/app/notification_router.dart`
- `mobile/lib/feature/sos/incident_detail_screen.dart`
- `mobile/test/app/notification_router_test.dart`
- `mobile/test/feature/gateway_provider_test.dart`

---

## Explicitly not kept / incomplete vs plan

- **HTTP 401 / dotenv fix for `MESHSETU_GATEWAY_SECRET`** — investigated (server often not loading `admin/.env` when run from `admin/server`); a temporary auth/dotenv fix was **reverted** per request. Ops still need the gateway key to match the server secret (default often `change-me`).
- Full outbox states like `waiting_for_peer` / `frames_sent` are **not** fully modeled beyond UI labels on existing states.
- Dual concurrent discovery + SOS advertising was **approximated** by shortening the SOS advert window, not true dual adverts.
- Persistent durable gateway forward-ACK table / rich HTTP retry beyond in-memory behavior may still be thin.
- STT/PCM path on SOS was de-emphasized in favor of Opus mesh clips; triage may see empty transcript when STT is skipped.

---

## How to validate on devices

1. Rebuild/reinstall the mobile app on two Android devices (origin + peer/gateway).  
2. Configure gateway URL + key on the gateway phone; enable gateway.  
3. Origin: Event Mode → Send SOS (real voice + GPS) → confirm delivery labels move past “queued locally”.  
4. Peer: notification + incident detail; optional voice playback when `voiceObject` arrives.  
5. Dashboard: SOS incident appears via `/v1/gateway/objects`; when voice arrives, audio via `/v1/sos/:eventId/voice`.

---

## Architecture snapshot (post-change)

```
[Origin phone]
  SOS UI → structuredSos (P0) + voiceObject (P2) outbox
       → foreground mesh: encrypt, fragment, GATT
       → if gateway: POST /v1/gateway/objects (encrypted blob)

[Peer phone]
  GATT frames → reassemble → decrypt → inbox
       → notification (+ payload) → IncidentDetailScreen
       → if gateway: same /v1/gateway/objects path

[Admin server]
  decryptPacket → upsert SOS and/or attach Opus bytes
       → dashboard SSE / REST playback
```

---

## Plan reference

Plan file (external to repo): `reliable-sos-flow_ec6d2899.plan.md`  
Todos marked completed in that plan: transport-status, voice-evidence, incident-notifications, gateway-forwarding, coverage.
