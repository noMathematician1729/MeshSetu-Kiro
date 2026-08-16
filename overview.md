# MeshSetu — codebase overview

Offline BLE mesh for disaster response: SOS + Room chat relay phone-to-phone
with no internet, an optional gateway phone bridges to a laptop dashboard.
Full spec: `MeshSetu_Technical_Development_Bible_Flutter.pdf`.

## Two trees in this repo

- **`core-model/`, `core-protocol/`, `core-ble/`, `app/`** — original Kotlin/JVM
  implementation. Frozen as reference; not being extended further.
- **`mobile/`** — the active Flutter/Dart port, kept in sync with the Kotlin
  transport/protocol logic. This is where all new work happens.

## `mobile/lib` layout (current)

```
lib/
  app/                    # app shell — mesh_event_controller.dart, event_mode_screen.dart, main.dart
  core/model/             # domain model.dart (MeshEnvelope, EncryptedObject, TrafficClass, PriorityBand...)
  core/protocol/          # frame.dart (fragment/reassemble + HELLO), outbound_scheduler.dart,
                           # secure_envelope.dart (AEAD), relay_engine.dart (RelayStore/FileRelayStore/
                           # MeshRelayEngine — ACK/NACK retry, dedupe, custody), protocol_metrics.dart,
                           # envelope_codec.dart, generated/ (protobuf)
  core/ble/                # universal_ble adapter: ble_discovery.dart (scan/advertise),
                           # ble_permissions.dart, mesh_gatt.dart (service/char UUIDs, fingerprinting),
                           # gatt_server.dart, gatt_peer_session.dart, mesh_transport.dart
                           # (MeshTransportCoordinator — peer sessions, replication fan-out, tick loop),
                           # device_key_store.dart (secure storage + site-key provisioning), async_lock.dart
```

This is **Developer A's scope** (Bible §20.1): BLE transport, frame codec,
fragmentation/reassembly, relay, scheduler, ACK/retry, crypto envelope. It is
covered by the protocol and transport tests in `mobile/test/`; the full local
Flutter suite currently passes 59 tests — protocol wire format matches the
Kotlin implementation byte-for-byte.

`app/mesh_event_controller.dart` is a thin demo harness Dev A wired up to
prove the stack end-to-end (advertise/scan/connect/tick loop, a "send test
SOS" button). It is **not** the product UI — that's Developer B's job below.

## Developer B's scope — built

Per the Bible's module layout (§4.1) and team split (§20.1), `mobile/lib`
now also has:

```
core/data/          # Drift DB — durable outbox/inbox, event state machine
                     #   (CREATED -> READY -> RELAYING -> ACKED/EXPIRED),
                     #   OutboxSender drains it into the mesh
feature/join/        # Mesh Code / QR join -> signed site manifest + Rooms
feature/rooms/       # scoped Rooms UI + ACL policy (RoomPolicy, §10.2)
feature/sos/         # SOS composition + state machine, SosRepository (frozen, §20.2)
feature/voice/       # record-package capture (Opus), chunk lifecycle, inbox playback
feature/stt/         # OfflineSttEngine frozen interface + NullSttEngine stub
feature/triage/      # deterministic SafetyRules + TriageEngine fallback
feature/gateway/     # gateway phone -> laptop dashboard HTTP bridge
```

plus a top-level `dashboard/` (FastAPI + WebSocket + minimal browser UI,
Bible §15) and `app/mesh_bridge.dart` / `app/mesh_bridge_client.dart`, which
carry envelopes and received objects across the isolate boundary between
the UI isolate (where Drift/Riverpod live) and the `flutter_foreground_task`
background isolate (where `MeshTransportCoordinator` lives).

Key architectural rule (Bible §4.2): UI/features depend on Riverpod
repositories, which depend on `core/data` + `core/protocol`, which depend on
`core/ble`. Features never touch BLE or STT directly — `SosRepository` and
`OfflineSttEngine` are the frozen contracts Dev A/B/C compile against
independently (§20.2).

Not built (see `checklist.md` for the full rationale): a real STT engine or
triage classifier (Dev C's primary ownership), `feature/map`/zone precursor
scoring, and a hand-rolled native Opus FFI wrapper (unneeded — `record`'s
built-in Opus file encoder covers the current voice-only path).

The current verification is local: Dart analysis, 59 Flutter tests, an Android
debug APK build, and dashboard endpoint tests pass. Physical BLE relay,
microphone capture, offline STT, and the full two-hop demo remain hardware /
integration acceptance work rather than proven claims.

**Not yet decided:** whether the Kotlin `core-model`/`core-protocol`/`core-ble`/`app`
modules get deleted now that the Flutter port covers their scope — flagged for
the user, not deleted unilaterally.
