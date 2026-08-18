# MeshSetu — Complete Codebase Overview

Offline BLE mesh for disaster response: SOS + Room chat relay phone-to-phone
with no internet, an optional gateway phone bridges to a laptop dashboard.
Full spec: `MeshSetu_Technical_Development_Bible_Flutter.pdf`.

---

## Repository Structure

### Frozen Reference (Kotlin/JVM)

- **`core-model/`, `core-protocol/`, `core-ble/`, `app/`** — Original Kotlin implementation, kept in sync for protocol wire format verification. Not actively developed; used only as test oracle for Dart port correctness.

### Active Development (Flutter/Dart + Node/React)

- **`mobile/`** — Flutter Android app (Dart) with complete BLE mesh, durable outbox, UI, and integrations.
- **`backend/`** — Express/TypeScript backend for the control room API, gateway ingest, WebSocket stream, and persistence.
- **`admin-dashboard/`** — React/Vite operator dashboard.
- **`landing-page/`** — Public React/Vite site.
- **`docs/`, `.github/`** — Documentation and CI/CD workflows.

---

## Service Architecture

### Layer 1: BLE Transport (Dev A — `mobile/lib/core/ble/`)

**Responsibilities:** Bluetooth discovery, connection management, frame codec, GATT server/client.

| Module | Purpose |
|--------|---------|
| `ble_discovery.dart` | BLE scan (find peers) + advertise (listen for peers) via universal_ble |
| `ble_permissions.dart` | Android permission requests (BT, location, notifications) |
| `mesh_gatt.dart` | MeshSetu-specific GATT service/characteristic UUIDs, site fingerprinting |
| `gatt_server.dart` | GATT server exposing MeshSetu characteristics for peer writes |
| `gatt_peer_session.dart` | Per-peer GATT session: characteristic subscriptions, write listeners |
| `mesh_transport.dart` | **Core coordinator:** manages peer sessions, frame I/O, send/receive dispatch, 2-peer replication fan-out, tick loop (2s) |
| `device_key_store.dart` | Secure storage + site-key derivation (AES-GCM wrapped by device keystore) |
| `async_lock.dart` | Mutex for concurrent read/write safety |

**Key Classes:**
- `MeshTransportCoordinator` — main event loop, peer state machine, send/receive channel
- `PeerLink` / `GattPeerSessionLink` — per-peer transport connection
- `DeviceKeyStore.getOrCreateSiteKey()` — deterministic site-key provisioning

---

### Layer 2: Protocol & Relay (Dev A — `mobile/lib/core/protocol/`)

**Responsibilities:** Frame codec, fragmentation/reassembly, relay persistence, retry/ACK logic, encryption envelope.

| Module | Purpose |
|--------|---------|
| `model.dart` | Domain objects: `MeshEnvelope`, `EncryptedObject`, `ReceivedObject`, priority/traffic-class enums |
| `frame.dart` | Wire format: `Frame` (fragment/HELLO/ACK/NACK), codec for variable-length protobuf frames |
| `envelope_codec.dart` | Protobuf serialization for MeshEnvelope (protobuf defined in `generated/meshsetu.proto`) |
| `secure_envelope.dart` | AEAD encryption (AES-256-GCM): site-ID authenticated, version-checked, tamper-detection |
| `outbound_scheduler.dart` | Priority queue (sort by priority, then creation time) for frames ready to send |
| `relay_engine.dart` | **Durable relay:** `MeshRelayEngine` (in-flight tracking, ACK/NACK retry, dedupe, metrics), `FileRelayStore` (SQLite via Drift for outbox persistence across restarts) |
| `protocol_metrics.dart` | Metrics sink: latency, hops, error counters → JSON-line file or stream |

**Key Classes:**
- `MeshEnvelope` — wire object carrying payload, priority, site/room context
- `Frame` — variable-length protobuf message (fragment/HELLO/ACK/NACK)
- `MeshRelayEngine` — custody tracking, retry on NACK, expiry sweep
- `FileRelayStore` — atomic file write-then-rename persistence

**Wire Format:**
- Outer: `[Frame(protobuf)]` via `universal_ble` write
- Inner: `[version][siteLen:2][site-utf8-bytes][iv][aes256-gcm(envelope)][auth-tag]`
- Replay protection: AEAD tag covers `[version][objectId:8][siteLen:2][site]`

---

### Layer 3: App Shell & Isolate Bridge (Dev A+B — `mobile/lib/app/`)

**Responsibilities:** BLE lifecycle, cross-isolate messaging, foreground service, app entry point.

| Module | Purpose |
|--------|---------|
| `main.dart` | Entry point: `ProviderScope` (Riverpod DI), Material app with teal theme |
| `event_mode_screen.dart` | UI for starting/stopping BLE mesh, displays peer state + metrics, "Send test SOS" button, navigates to Join/Rooms/SOS flows |
| `mesh_event_controller.dart` | Foreground task handler: owns `MeshTransportCoordinator`, starts/stops mesh, wires incoming envelopes to UI-isolate listener |
| `mesh_bridge.dart` | JSON codec: serializes `MeshEnvelope`, `ReceivedObject`, `RelayMetric` to/from Maps for cross-isolate channel |
| `mesh_bridge_client.dart` | UI-isolate listener: deserializes `mesh_received` messages, inserts to Drift inbox, sends outbox via `sendDataToTask` |
| `providers.dart` | Riverpod dependency injection: database, repositories, state providers (gateway URL, enabled toggle) |

**Key Flow:**
1. UI-isolate: `event_mode_screen.dart` starts foreground task
2. Background-isolate: `meshEventTaskCallback()` → `_MeshEventTaskHandler` → `MeshEventController` → `MeshTransportCoordinator.start()`
3. BLE events arrive in background → sent to UI via `FlutterForegroundTask.sendDataToMain()` (JSON)
4. UI deserializes via `mesh_bridge.dart`, applies to Drift database
5. Outbound (UI→Mesh): `mesh_bridge_client.dart._sendToMesh()` → `sendDataToTask()` → background receives + `coordinator.send()`

---

### Layer 4: Durable Storage (Dev B — `mobile/lib/core/data/`)

**Responsibilities:** SQLite persistence for outbox/inbox, state machine enforcement, event lifecycle.

| Module | Purpose |
|--------|---------|
| `database.dart` | Drift schema: `OutboxEvents`, `InboxEvents`, `SiteManifests` tables; streaming watches + helpers (markState, expireOverdue, insertInbox) |
| `outbox_sender.dart` | Listener on Drift `watchReady()` stream; drains READY→RELAYING→ACKED|EXPIRED, calls mesh send callback |

**State Machine:**
```
Draft (CREATED) → Ready (READY) → Relaying (RELAYING) → Acked (ACKED) or Expired (EXPIRED)
```

**Database:**
- `OutboxEvents` — messages this device sends (SOS, rooms, voice manifests); includes transcript, voice path, triage JSON
- `InboxEvents` — messages received from mesh; includes sender peer ID, received timestamp
- `SiteManifests` — currently-active site config (rooms, ACL, manifest signature) for multi-site support

---

### Layer 5a: Feature — SOS Composition (Dev B — `mobile/lib/feature/sos/`)

**Responsibilities:** SOS payload assembly, state management, voice/transcript/triage attachment.

| Module | Purpose |
|--------|---------|
| `sos_repository.dart` | Frozen interface `SosRepository` + Drift-backed `DriftSosRepository`: createDraft → attachTranscript/Voice/Triage → finalizeAndEnqueue |
| `sos_payload.dart` | `StructuredSosPayload` class: JSON codec for incident type, transcript, confidence, hazards, priority |
| `sos_screen.dart` | UI: compose SOS (manual text or voice), attach voice clip, review triage result, enqueue to mesh |

**API Call Pattern:**
```dart
final sos = await sosRepo.createDraft(SosInput(...));
await sosRepo.attachTranscript(sos, sttResult);
await sosRepo.attachVoice(sos, pcm16Bytes);
await sosRepo.attachTriage(sos, triageOutput);
await sosRepo.finalizeAndEnqueue(sos);  // → Drift OUTBOX_EVENTS, state=READY
```

---

### Layer 5b: Feature — Voice Capture & STT (Dev B+C — `mobile/lib/feature/voice/`, `mobile/lib/feature/stt/`)

**Responsibilities:** Microphone capture, speech-to-text inference, voice playback.

| Module | Purpose |
|--------|---------|
| `voice_recorder.dart` | Captures 16kHz mono PCM16 via `record` package; Opus-encodes; 10s cap via Timer |
| `voice_repository.dart` | Attach voice bytes to SOS, retrieve/playback from inbox |
| `voice_inbox_screen.dart` | Browse received voice objects; tap to play via `audioplayers` |
| **`stt_engine.dart`** | Frozen interface `OfflineSttEngine` (§12.1) + `NullSttEngine` stub (returns error if no model) |
| **`sherpa_onnx_stt_engine.dart`** | **Model inference:** ONNX Zipformer small model (encoder/decoder/joiner), PCM16→text, ~200–500ms latency on CPU (2 threads), confidence always 0.0 (model doesn't expose it) |
| `fake_stt_engine.dart` | Test stub returning fixed transcript + confidence |

**Model Details (Sherpa-ONNX):**
- Model: `sherpa-onnx-zipformer-small-en-2023-06-26` (eng only, 200MB+)
- Framework: ONNX Runtime via native FFI binding
- Input: 16kHz mono PCM (float32 normalized, [-1.0, 1.0])
- Output: `SttResult { text, confidence=0.0, inferenceMs, modelId }`
- Assets: Must be pre-bundled in `mobile/assets/models/` (download via `mobile/assets/models/README.md`)
- Fallback: `NullSttEngine` (no model) → gracefully fails; manual/voice SOS continues without transcript

**Dependency:** `sherpa_onnx: ^0.2.x` (Dart FFI binding to C++ ONNX Runtime)

---

### Layer 5c: Feature — Triage (Dev B — `mobile/lib/feature/triage/`)

**Responsibilities:** Priority classification (deterministic rules + optional ML classifier).

| Module | Purpose |
|--------|---------|
| `triage_engine.dart` | `SafetyRules` (regex: breathing, fire, crush, etc. → P0 Critical), `TriageEngine` (rules first, fallback conservative P1) |

**Priority Mapping:**
- **P0 Critical:** breathing/consciousness keywords → hard safety rule
- **P1 High:** fallback (no classifier, no rule match, or classifier input)
- **P2 Normal:** triage neutral assessment
- **P3 Bulk:** background/telemetry

---

### Layer 5d: Feature — Join & Manifests (Dev B — `mobile/lib/feature/join/`)

**Responsibilities:** Site enrollment, QR code parsing, manifest validation.

| Module | Purpose |
|--------|---------|
| `manifest.dart` | `EventManifest`, `RoomManifest` classes (site, rooms, ACL); `EventManifestCodec` (HMAC-SHA256 sign/verify, QR payload) |
| `join_repository.dart` | Parse typed code (`DEMO01` → bundled manifest) or QR → validate signature + expiry → activate in Drift |
| `join_screen.dart` | UI: scan QR or type Mesh Code → join site → save manifest + rooms → navigate to rooms screen |

**Bundled Demo:**
- Site: `DEMO01`, mesh code: ASCII alphanumeric
- Manifest key: `meshsetu-demo-manifest-key-v1` (demo-only, hardcoded)
- Rooms: Public Alerts, Medical, Responders (ACL per role)

---

### Layer 5e: Feature — Rooms (Dev B — `mobile/lib/feature/rooms/`)

**Responsibilities:** Per-room chat, ACL enforcement, user role management.

| Module | Purpose |
|--------|---------|
| `room_policy.dart` | `RoomPolicy` class: traffic class, TTL, send/read role sets; `canSend(policy, userRoles)` enforcement |
| `room_repository.dart` | Send message → validate ACL → insert to Drift OUTBOX (state=READY); watch inbox/outbox for conversation stream |
| `rooms_screen.dart` | List rooms; display ACL and user role; navigate to chat |
| `room_chat_screen.dart` | Message UI: send text, receive + display, sorted by timestamp |

**ACL Model (§10.2):**
- Public Alerts → send: [public], read: [*]
- Medical → send: [medical, responder], read: [medical, responder, authority]
- Responders → send: [responder, authority], read: [responder, authority]
- Authority implicit: all rooms

---

### Layer 5f: Feature — Gateway Bridge (Dev B — `mobile/lib/feature/gateway/`)

**Responsibilities:** Bridge SOS/voice from mesh to laptop dashboard over HTTP.

| Module | Purpose |
|--------|---------|
| `gateway_bridge.dart` | HTTP `POST /api/events` to laptop; body: `Event` (priority, incident type, transcript, zone, hops, audio state); header: `x-meshsetu-demo-key` |
| `gateway_screen.dart` | UI toggle: enable gateway, set laptop IP:port, watch connection status |

**Integration:**
- `mesh_bridge_client.dart` deserializes incoming `StructuredSos` objects
- Calls `GatewayBridge.postToDashboard(envelope, sos)` if gateway enabled
- HTTP POST with demo-key auth; dashboard broadcasts to all WebSocket clients

---

### Backend: Control Room Services (`backend/` + `admin-dashboard/`)

**Languages:** Node.js/TypeScript (API) + React/Vite (operator UI)

**Responsibilities:** Receive incidents, validate/decrypt gateway objects, persist incidents, stream updates over WebSocket, and provide the operator dashboard UI.

| File | Purpose |
|------|---------|
| `backend/src/server.ts` | Express app: `/health`, `/v1/*`, compatibility `/api/events`, and `/ws` or `/v1/stream` WebSocket endpoints |
| `backend/src/store.ts` | Postgres-backed incident store with in-memory fallback |
| `admin-dashboard/src/App.jsx` | Operator dashboard UI (login, live incident queue, playback, status updates) |
| `admin-dashboard/src/api.js` | Dashboard API and WebSocket client |

**API:**
```
GET /health
  Response: { ok, service, database, time }

POST /v1/gateway/objects
  Header: x-meshsetu-gateway-key: "<MESHSETU_GATEWAY_SECRET>"
  Body: { site_id, object_id, packet_b64, peer_id?, received_at_ms? }
  Response: { ok: true, verified: true, event? } or 401/422

GET /v1/sos
  Header: Authorization: Bearer <token>
  Response: [ { event_id, priority, ... }, ... ]

WS /v1/stream?token=<jwt>
  Real-time incident stream; client receives:
  - { type: "snapshot", data: [...current events...] } on connect
  - { type: "incident" | "voice" | "event", data: {...updated event...} }
```

**Gateway/Auth Config:** `MESHSETU_GATEWAY_SECRET`, `MESHSETU_ADMIN_EMAIL`, `MESHSETU_ADMIN_PASSWORD`, and `JWT_SECRET`

**Deployment:**
```bash
cd backend
npm ci
npm run build
npm start

cd ../admin-dashboard
npm ci
VITE_API_BASE_URL=http://127.0.0.1:8000 npm run dev
```

---

## Data Flow Diagram

```
┌─── Mobile App (UI Isolate) ───────────────────────────────────────────┐
│                                                                        │
│  EventModeScreen ─────┐                                               │
│  Join/Rooms/SOS ──────┤─→ Riverpod Providers                          │
│  Voice/Triage ────────┤   ├─ SosRepository                            │
│                       │   ├─ JoinRepository                           │
│                       └─→ ├─ RoomRepository                           │
│                           ├─ VoiceRepository                          │
│                           └─ OfflineSttEngine                         │
│                                    ↓                                  │
│                           Drift Database (SQLite)                     │
│                           ├─ OutboxEvents                             │
│                           ├─ InboxEvents                              │
│                           └─ SiteManifests                            │
│                                    ↓                                  │
│                        MeshBridgeClient (listener)                    │
│                        ├─ Deserializes mesh_received                  │
│                        ├─ Inserts to Drift inbox                      │
│                        └─ Calls GatewayBridge.post() if enabled       │
└─────────────────────────────────────────────────────────────────────┘
         │
         │ cross-isolate JSON bridge (FlutterForegroundTask)
         ↓
┌─── Mobile App (Background Isolate) ───────────────────────────────────┐
│                                                                        │
│  MeshEventTaskHandler                                                 │
│         ↓                                                              │
│  MeshEventController                                                  │
│         ↓                                                              │
│  MeshTransportCoordinator                                             │
│  ├─ Manages peer sessions                                             │
│  ├─ Receives MeshEnvelopes from peers                                 │
│  ├─ Relays to up to 2 replication peers                               │
│  ├─ Runs tick loop (2s): scan, connect, frame pump                    │
│  └─ Forwards received to UI-isolate listener                          │
│         ↓                                                              │
│  [BLE Transport]                                                       │
│  ├─ universal_ble scan/advertise                                      │
│  ├─ GATT server/client                                                │
│  └─ Peer frame I/O                                                    │
└─────────────────────────────────────────────────────────────────────┘
         │
         │ BLE radio
         ↓
    [Other Peer Devices]

┌─── Gateway HTTP Bridge ───────────────────────────────────────────┐
│                                                                   │
│  GatewayBridge.postToDashboard()                                 │
│         │ HTTP POST /api/events or /v1/gateway/objects           │
│         ↓ + gateway secret header                                │
└───────────────────────────────────────────────────────────────────┘
         │
         ↓
┌─── Control-Room Backend (Node/Express) ─────────────────────────┐
│                                                                  │
│  POST /api/events or /v1/gateway/objects                        │
│  ├─ Validate gateway key / decrypt verified objects             │
│  ├─ Store in Postgres or memory fallback                        │
│  └─ Broadcast to all WS clients                                 │
│                                                                  │
│  GET /v1/sos → return operator view                             │
│                                                                  │
│  WS /v1/stream or /ws ↔ Browser UI                              │
│  ├─ Send snapshot on connect                                    │
│  └─ Broadcast incident updates in real-time                     │
└──────────────────────────────────────────────────────────────────┘
         │
         ↓
    [Browser: admin-dashboard]
    Displays incident list, status workflow, and verified playback
```

---

## Dependency Injection (Riverpod, §4.2)

**DI Boundary:** `mobile/lib/app/providers.dart`

```dart
final databaseProvider = Provider<MeshDatabase>((ref) { ... });
final sosRepositoryProvider = Provider<SosRepository>((ref) => 
  DriftSosRepository(ref.watch(databaseProvider)));
final joinRepositoryProvider = Provider<JoinRepository>((ref) => 
  JoinRepository(ref.watch(databaseProvider)));
final roomRepositoryProvider = Provider.family<RoomRepository, String>((ref, siteId) => 
  RoomRepository(ref.watch(databaseProvider), siteId: siteId));
final voiceRepositoryProvider = Provider<VoiceRepository>((ref) => 
  VoiceRepository(ref.watch(databaseProvider), ref.watch(sosRepositoryProvider)));

// State providers for gateway UI toggles
final gatewayUrlProvider = StateProvider<String>((ref) => '');
final gatewayEnabledProvider = StateProvider<bool>((ref) => false);
```

**Rule:** UI/features never touch `core/ble` directly; all access flows through repository interfaces.

---

## Key External Dependencies

| Package | Version | Used For |
|---------|---------|----------|
| `universal_ble` | 2.1.1 | BLE central/peripheral via custom fork in `third_party/` |
| `drift` | 2.34.3 | SQLite ORM, reactive watches, code generation |
| `flutter_riverpod` | 2.6.1 | Dependency injection, state management |
| `flutter_foreground_task` | 10.0.0 | Background service isolate, cross-isolate messaging |
| `record` | 7.1.1 | Microphone capture (Opus encoding) |
| `audioplayers` | 6.5.1 | Voice clip playback |
| `mobile_scanner` | 7.1.2 | QR code scanning |
| `qr_flutter` | 4.1.0 | QR code generation |
| `sherpa_onnx` | 0.2.x | Offline STT (ONNX Zipformer) |
| `http` | 1.5.0 | Gateway HTTP bridge |
| `uuid` | 4.5.1 | Event ID generation |
| `cryptography` | 2.7.0 | AEAD cipher (AES-256-GCM) |
| `protobuf` | 6.0.0 | Protobuf message serialization |

---

## Test Coverage

- **Unit tests** (53+): protocol codec, relay state machine, triage rules, manifest validation, SOS payload round-trip
- **Widget tests** (6+): UI screens (join, rooms, SOS, gateway)
- **Integration tests** (control room): HTTP/WebSocket endpoints and dashboard builds
- **No device tests:** physical BLE relay, microphone capture, model inference (requires Android device/emulator)

---

## Known Limitations & Future Work

1. **STT Model Size:** Sherpa-ONNX Zipformer (200MB+) bloats APK; could optimize with quantization or serve remotely.
2. **Dashboard Operator Workflow:** Basic status workflow exists, but operational escalation remains minimal.
3. **Zone Precursor Scoring:** Not implemented (§20.5); zone is stored but not computed.
4. **Kotlin Modules:** Not deleted; live alongside Flutter port as reference. Decision pending.
5. **Hardware Integration:** Full BLE relay, STT inference, and microphone capture require Android device testing.

---

## Build & Run

```bash
cd mobile
flutter pub get
flutter analyze        # Should pass cleanly
flutter test          # 53+ tests
dart format lib test  # Code formatting
flutter build apk --debug
```

**Control room:**
```bash
cd backend
npm ci
npm run build
npm start

cd ../admin-dashboard
npm ci
VITE_API_BASE_URL=http://127.0.0.1:8000 npm run dev
```

Access dashboard: `http://localhost:5173` locally, or its deployed static URL in production.
