# Developer B build checklist

Tracks progress on Bible §4.1/§20.1 Developer B scope (Flutter UI, Rooms,
SOS, Drift, voice, STT/triage integration, gateway, dashboard). Updated as
each item lands.

- [x] `core/data`: Drift outbox/inbox DB (`mobile/lib/core/data/database.dart`, `outbox_sender.dart`)
- [x] `feature/join`: Mesh Code / QR (`mobile/lib/feature/join/`)
- [x] `feature/rooms`: Rooms UI + ACL (`mobile/lib/feature/rooms/`)
- [x] `feature/sos`: SOS state machine + `SosRepository`
- [x] `feature/voice`: capture + chunk lifecycle
- [x] `feature/stt`: `OfflineSttEngine` contract + null stub
- [x] `feature/triage`: deterministic safety rules
- [x] `feature/gateway`: HTTP bridge to dashboard
- [x] `admin/server/` + `admin/client/`: control-room API and browser UI
- [x] Riverpod wiring + app shell integration (join -> rooms -> sos navigable flow, cross-isolate mesh bridge)
- [x] Verify: `dart analyze` clean, `flutter test` 59/59 passing (12 Dev B tests), `dart format` applied, `flutter build apk --debug` succeeds, dashboard unit/integration test passes

Developer B's prototype slice is implemented and locally verifiable. Known limitations:
- Voice uses `record`'s built-in Opus file encoder, not a hand-rolled `native/opus` FFI wrapper (Bible's module layout assumed one was needed; it wasn't).
- `StructuredSos`/`RoomMessage` payloads are JSON, not a second generated protobuf message (only `MeshEnvelope` is protobuf, matching the Kotlin wire format; the inner payload is opaque `bytes` either way).
- No STT engine or triage classifier is wired in (`NullSttEngine` stub, deterministic `SafetyRules` only) — both are Developer C's primary ownership per Bible §20.1.
- `feature/map` (beacon/zone visualization) and zone precursor scoring are not built — not required by the Bible §20.5 Developer B checklist for a working join→rooms→SOS→gateway→dashboard demo.
- The recorder uses direct Opus capture; it does not expose the same PCM stream to STT until Developer C supplies that adapter.
- The dashboard keeps current events in process memory and has no operator ACK/dispatch workflow.
- Real BLE/device behavior, physical microphone capture, and the 10-trial two-hop acceptance run still require physical Android devices; the local tests use synthetic transport links.
- The default dashboard key and bundled manifest signing key are demo credentials, not production enrollment.
