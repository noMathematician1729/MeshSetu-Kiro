# MeshSetu session handoff

**Date:** 2026-08-21  
**Repository:** `SIH26_-1xDevs`  
**Branch:** `fix/gatt-sos`  
**Purpose:** Preserve the BLE/GATT audit, implementation history, ACK investigation, validation evidence, and the remaining device-test work so another agent can continue without reconstructing this session.

## 1. User-reported problems that drove this work

Two Android screenshots exposed confusing behavior:

1. The SOS sender displayed **“Delivery: accepted by mesh, waiting for a GATT peer”** even though a relayer phone appeared to receive the SOS.
2. Event Mode displayed **`gatt_server_disconnected`**, leading to the question of whether the sender/server had failed.
3. The user also reported that other SOS signals were not being sent reliably, although that observation was made before the merge-conflict resolution and ACK changes.

The important interpretation established during the session is:

- A phone runs both BLE roles. Its GATT **server/peripheral** accepts writes from a nearby central; its GATT **client/central** connects to another phone's server and writes frames.
- `relaying` means the SOS is persisted in the local outbox and the foreground mesh service has accepted/queued it. It does **not** mean a peer has saved it.
- `acked` means the sender received a protocol custody ACK from the first relay that persisted the complete object. It is not an admin-server ACK or proof that the object reached its final destination.
- `gatt_server_disconnected` is a local historical link event: a peer disconnected from this phone while this phone was acting as the GATT server. It is not a statement that the phone's own sender stopped.

The status text was changed to make those meanings explicit.

## 2. Documentation and reference material

These links were supplied as implementation references and should remain the primary external context:

- [BLE GATT Server Library for Flutter](https://pub.dev/packages/ble_gatt_server) — server/peripheral patterns and APIs.
- [Guide to BLE GATT Client in Flutter](https://exabyting.com/blog/getting-started-with-ble-and-gatt-in-flutter-part-1/) — central/peripheral roles and service/characteristic concepts.
- [Navideck `ble_peripheral_nd`](https://github.com/Navideck/ble_peripheral_nd) — client-side/reference BLE implementation.
- [Chipweinberger `flutter_blue_plus`](https://github.com/chipweinberger/flutter_blue_plus) — server-side/reference implementation.

The repository's comprehensive historical audit is [report.md](report.md). The earlier implementation summary is [GAT_work_done.md](GAT_work_done.md). Mobile build and test commands are documented in [mobile/README.md](mobile/README.md).

## 3. Relevant architecture and ACK flow

The main code path is:

```text
SOS screen
  -> local Drift outbox row (ready)
  -> OutboxSender / MeshBridgeClient
  -> MeshTransportCoordinator
  -> GATT client writes fragmented data frames to a peer server
  -> peer reassembles, decrypts, deduplicates, and persists the object
  -> peer emits a custody-ACK control frame back over the same link
  -> source relay engine accepts the ACK
  -> source outbox row becomes acked
```

The relay engine tracks in-flight custody by `(peerId, objectId)`. A custody ACK is accepted only when:

1. Its payload contains the same object ID as the frame header.
2. That exact peer/object pair is currently in flight.

An ACK from a wrong peer, a malformed ACK, or an ACK that arrives after the in-flight entry is gone is not accepted as delivery. It produces a diagnostic metric instead.

The receiver acknowledges both a first valid delivery and a duplicate delivery. The duplicate is not persisted twice, but the ACK is still returned so a source that missed the first ACK can recover.

## 4. Historical GATT implementation and merge work

The prior GATT work was integrated on `fix/gatt-sos` through these commits:

- `0d8e05b` — `fix: gatt p2p connection fixed, voice packet decoding dashboard side fixed but not tested yet`
- `54f0452` — `fix: gatt pipeline audited and implemented`
- `24bc1d9` — `fix: complete gatt rebase integration`

The user performed `git pull origin main --rebase`. Conflicts occurred in:

- `mobile/lib/app/event_mode_screen.dart`
- `mobile/lib/app/mesh_bridge_client.dart`
- `mobile/lib/app/mesh_event_controller.dart`
- `mobile/lib/app/providers.dart`
- `mobile/lib/main.dart`

The conflicts were resolved with the user's instruction to preserve the current/local GATT changes over incoming changes. The rebase was completed; do not redo it unless the branch history changes.

The earlier GATT audit in `report.md` identified 24 findings (2 critical, 6 high, 10 medium, 6 low). Its remediation addendum records fixes for frame-size validation, capacity admission, notification/disconnect races, configurable notification timeout, reassembly bounds and object consistency, retry/ACK timeout behavior, and lock-order documentation. Production sign-off in that report remains dependent on a real Bluetooth SIG company ID and multi-phone radio testing.

## 5. ACK audit findings and changes made in this session

The ACK audit concluded that the core custody-ACK protocol already existed, but several gaps made it hard to trust or diagnose in the field:

### Finding A — GATT readiness callback ordering could lose peer admission

The transport coordinator previously listened only for the TX subscription event. Android may report the connection callback before or after the CCCD/TX subscription callback. If subscription arrived first, the old flow could fail to observe the later connection state and never attach the server peer.

**Fix:** [gatt_server.dart](mobile/lib/core/ble/gatt_server.dart) now exposes `readyPeerIds`. A peer is emitted when both live connection state and TX subscription are present, regardless of callback order. [mesh_transport.dart](mobile/lib/core/ble/mesh_transport.dart) listens to this combined readiness stream before calling `_ensureServerPeer`.

### Finding B — ACK send/receive results were not object-correlated in diagnostics

Control-send failures were previously reported only as generic `control_send_failed` events. That made it difficult to prove whether a custody ACK was sent for a specific SOS.

**Fix:** [mesh_transport.dart](mobile/lib/core/ble/mesh_transport.dart) now decodes control frames in `_reportControlResult` and emits:

- `custody_ack_sent` with `objectId` and `peerId` on successful ACK transmission.
- `custody_ack_send_failed` with `objectId` and `peerId` when ACK transmission fails.
- `control_send_failed` is retained for generic compatibility and now carries the ACK object ID when available.

[relay_engine.dart](mobile/lib/core/protocol/relay_engine.dart) retains the legacy `ack` metric used by the outbox and also emits `custody_ack_received` with the object and peer IDs when the source accepts a valid ACK.

### Finding C — Outbox ACK updates were broader than the active delivery

`OutboxSender` previously updated every row matching an object ID. That could incorrectly mark a non-relaying row or a row for another site as acknowledged.

**Fix:** [outbox_sender.dart](mobile/lib/core/data/outbox_sender.dart) now updates only rows where `siteId` matches the sender and `state == 'relaying'`, in addition to matching `objectId`.

### Finding D — Timeout and peer-validation behavior needed explicit regression coverage

The relay already had retry behavior, but it needed tests proving that a timeout requeues an object, a wrong peer cannot acknowledge it, and duplicate delivery does not duplicate persistence.

**Fix:** Added tests for all three cases. No second retry framework was introduced.

### Finding E — UI wording obscured local-vs-peer state

The SOS and Event Mode screens now distinguish local persistence, mesh queuing, peer acknowledgement, retry/expiry, and link events.

Changes are in [sos_screen.dart](mobile/lib/feature/sos/sos_screen.dart) and [event_mode_screen.dart](mobile/lib/app/event_mode_screen.dart). The Event Mode field is now labeled **“Latest link event”**, and `gatt_server_disconnected` is rendered as **“Peer disconnected from this phone as a GATT server”**.

### Finding F — Compact and rich SOS paths created different dashboard incidents

Every structured GATT SOS also emits a small unauthenticated manufacturer-data alert for fast nearby detection. A gateway phone could therefore forward `/v1/gateway/ceal-sos` first, creating a `ceal_compact_sos` incident, while the later encrypted GATT object was stored under the envelope's unrelated `event_id`. The dashboard then showed the compact incident even when the full SOS had arrived.

**Fix:** The backend derives the compact sequence from the encrypted object's low 16-bit object ID and matches it to a recent compact event by reporter UID (including v1 UID-prefix compatibility) and site. The verified GATT object upgrades that existing event instead of creating a second incident. A verified event is never overwritten by a later compact fallback. The dashboard also refreshes an already-open alert when the same event receives verified fields.

### Finding G — ACK state could be lost at the UI-isolate boundary

The foreground BLE isolate correctly accepted and persisted the custody ACK, but the sender UI depended on a best-effort `mesh_metric` callback. If Android paused or delayed the UI isolate, the Drift outbox row could remain `relaying` even though the relay engine had already removed its durable outbound copy.

**Fix:** [relay_engine.dart](mobile/lib/core/protocol/relay_engine.dart) now writes an atomic `$objectId.ack` marker whenever `FileRelayStore.markAck` runs. [mesh_bridge_client.dart](mobile/lib/app/mesh_bridge_client.dart) consumes those markers during the existing durable-inbox sync loop and applies the same `ack` metric to the UI outbox. The live callback remains a fast path; the marker is the recovery path.

### TI BLE notification/indication research

The supplied [TI E2E thread](https://e2e.ti.com/support/wireless-connectivity/bluetooth-group/bluetooth/f/bluetooth-forum/429019/acknowledging-ble-notifications-and-indications) and related TI answers clarify that the BLE Link Layer acknowledges/retransmits radio packets, but a GATT **notification** has no application-visible ATT confirmation. A GATT **indication** adds a mandatory client confirmation and serializes indication flow. This implementation intentionally keeps the high-throughput TX characteristic as notifications and uses a protocol-level custody ACK only after full reassembly, authentication, and persistence. Switching to indications alone would confirm delivery to the remote GATT stack, not durable SOS custody, and would add one-at-a-time flow control to fragmented traffic. The code therefore uses the TI-recommended application-level ACK/retry model and now makes its state durable across isolates.

## 6. Current uncommitted implementation

At handoff time, the following files are modified but not committed:

- `mobile/lib/app/event_mode_screen.dart` — friendly GATT/ACK diagnostics and “Latest link event” label.
- `mobile/lib/feature/sos/sos_screen.dart` — clearer `ready`, `relaying`, `acked`, `expired`, and `failed` delivery labels.
- `mobile/lib/core/ble/gatt_server.dart` — combined connection + subscription readiness stream.
- `mobile/lib/core/ble/mesh_transport.dart` — readiness subscription and object-correlated control-send metrics.
- `mobile/lib/core/protocol/relay_engine.dart` — `custody_ack_received` metric.
- `mobile/lib/core/data/outbox_sender.dart` — scoped active-row state updates.
- `mobile/lib/app/mesh_bridge.dart` — preserves diagnostic details across the isolate boundary.
- `mobile/lib/app/mesh_bridge_client.dart` — consumes durable foreground ACK markers.
- `admin/server/src/store.ts` — compact/rich event correlation by site, UID/prefix, and sequence.
- `admin/server/src/server.ts` — upgrades compact incidents with verified GATT objects and protects verified records from compact fallback overwrites.
- `admin/client/src/App.jsx` — updates a queued compact alert when its event becomes verified.
- `mobile/test/core/ble/mesh_transport_test.dart` — end-to-end ACK return, failed ACK, and subscription-before-connection coverage.
- `mobile/test/core/protocol/relay_engine_test.dart` — timeout retry, wrong-peer rejection, and duplicate delivery coverage.
- `mobile/test/feature/dev_b_test.dart` — outbox update scoping coverage.
- `admin/server/src/notifications.test.ts` — compact-first/encrypted-GATT-second event upgrade coverage.

There is also an unrelated untracked `Ceal/` directory. It was not inspected, changed, or included in this work; preserve it unless its owner explicitly requests otherwise.

Before committing, review the diff and run `git diff --check`. No commit was created for the latest ACK changes.

## 7. Validation completed

The following checks passed after the implementation:

```sh
cd mobile
flutter test test/core/ble/mesh_transport_test.dart \
  test/core/protocol/relay_engine_test.dart \
  test/feature/dev_b_test.dart
# 52 tests passed

flutter analyze
# No issues found

flutter test
# 125 tests passed; All tests passed!
```

The follow-up validation also passed:

```sh
cd admin/server
npm test                 # 9 tests passed
npm run build            # TypeScript build passed

cd ../client
npm run build            # Vite production build passed
```

`git diff --check` also passed. The full test run contains existing informational Drift/widget logs, but it exits successfully.

The physical BLE path has **not** yet been validated in this session. Automated fake-link tests cannot prove Android radio behavior, background/foreground lifecycle behavior, permissions, or timing on two real devices.

## 8. Required two-phone validation

Use two Android phones with fresh debug builds. The mobile README requires Flutter 3.47-era tooling, Android SDK platform 36, and Android API 29+ devices.

1. Build/install the current branch on both phones:

   ```sh
   cd mobile
   flutter pub get
   flutter build apk --debug
   ```

2. Grant Bluetooth, nearby-device, location (if requested by the OS), notification, and microphone permissions. Keep both apps in Event Mode with the foreground mesh service running.
3. Keep the phones close together and wait until each shows a peer/mesh connection. On the origin phone, send one SOS with optional text, voice, and GPS.
4. Expected origin progression:

   ```text
   Delivery: saved on this phone; waiting for Event Mode.
   Delivery: queued for mesh; waiting for a peer acknowledgement.
   Delivery: acknowledged by a mesh peer.
   ```

5. On the relay phone, verify the SOS is received/persisted. In the Event Mode diagnostics, look for `custody_ack_sent`; on the origin phone, look for `custody_ack_received` and the outbox row becoming `acked`.
6. Repeat while temporarily disabling Bluetooth or moving the phones apart after the data is sent but before the ACK can return. The origin should remain pending or show retry/expiry, not become falsely `acked`.
7. Restore Bluetooth/radio proximity and restart or reconnect Event Mode. Verify the pending object is retried and eventually acknowledged by the peer. A duplicate arriving at the relay should still produce an ACK without duplicate persistence.
8. Capture both screens/logs for each run, including object ID, peer ID, last metric, and latest link event. This is the evidence needed for production sign-off.

For broader sign-off, repeat the report's three-phone forwarding test and the four-active-peer plus fifth-waiting capacity test. The report also calls for a real assigned Bluetooth SIG Company Identifier; release builds must not ship with the debug `0xFFFF` identifier.

## 9. Known limitations and boundaries

- The success definition agreed in this session is **first relay custody ACK**. There is no end-to-end final-destination or admin-backend delivery ACK in this change.
- `gatt_server_disconnected` remains a valid diagnostic event and may appear after a normal peer disconnect. It is now explained in the UI rather than removed.
- ACK return depends on the reverse GATT control path being live. If the receiver persists an object but its ACK send fails, it reports `custody_ack_send_failed`; the source remains pending and retries.
- Debug advertisements use the reserved test company ID. A real assigned company ID is still required for release deployment.
- The full outbox taxonomy (`waiting_for_peer`, `frames_sent`, etc.) was not introduced; existing states are presented with clearer text.
- The physical two-phone test, reconnect/churn test, multi-hop test, and capacity saturation test remain open.
- The `Ceal/` directory is unrelated untracked workspace content and is intentionally excluded from this handoff's implementation.

## 10. Recommended continuation checklist

1. Inspect the latest diff and commit the nine ACK/UI/test changes atomically after review.
2. Build/install on two Android phones and execute the validation in Section 8.
3. If the origin stays in `relaying`, compare the origin's `custody_ack_received`, `ack_timeout`, and `gatt_*` metrics with the relay's `custody_ack_sent`/`custody_ack_send_failed` metrics for the same object ID.
4. If no `custody_ack_sent` appears, investigate receiver admission, peer capacity, TX subscription, and reverse notification/write permissions first.
5. If `custody_ack_sent` appears but the origin has no `custody_ack_received`, investigate reverse-link delivery, frame decoding, peer identity, and disconnect timing.
6. Only after radio tests pass should the release company ID and broader production sign-off be finalized.

## 11. Event Mode crash audit (2026-08-21)

The connected Android 15 phone reproduced the Event Mode crash while a GATT
peer was sending traffic. The fatal log was:

```text
java.lang.IllegalArgumentException: notification should not be longer than max length of an attribute value
  at android.bluetooth.BluetoothGattServer.notifyCharacteristicChanged(...)
  at UniversalBlePeripheralPlugin.updateCharacteristicInternal(...)
```

Root cause: at ATT MTU 517, `mtu - 3` is 514, but Android caps a GATT
characteristic value at 512 bytes. The frame fragmenter therefore emitted a
514-byte notification. The fix is now in:

- `mobile/lib/core/ble/mesh_gatt.dart` — caps the characteristic value at 512.
- `mobile/lib/core/protocol/frame.dart` — caps fragment payload calculation so
  encoded frames never exceed 512 bytes.
- `mobile/third_party/universal_ble/android/.../UniversalBlePeripheralPlugin.kt`
  — catches Android notification exceptions, clears the pending notification,
  and reports GATT failure instead of crashing the process.
- `mobile/test/core/protocol/frame_test.dart` — regression test for MTU 517.

Validation after the fix:

```sh
cd mobile
flutter test                         # 126 tests passed
flutter analyze                      # No issues found
flutter build apk --debug --target-platform android-arm64
```

The patched APK was installed and Event Mode was run again on the same phone;
the process remained alive and no `FATAL EXCEPTION` or oversized-notification
log was observed during the smoke window. Repeat the two-phone test with a
large fragmented SOS/voice object and capture `adb logcat` before release.

The subagent audit also identified secondary hardening opportunities (queued
site-configuration updates during `onStart`, rapid duplicate Start taps, and
uncaught asynchronous restart/callback futures). They were not the reproduced
crash and remain separate follow-up work unless a device log points to them.
