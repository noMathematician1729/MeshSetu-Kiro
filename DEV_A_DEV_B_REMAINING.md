# Dev A + Dev B end-to-end completion audit

Audit date: 16 August 2026  
Audited commit: `d2624a6` (`main`, also `origin/main`)  
Source of scope: `context.md` §§1, 18, 20 and the final engineering checklist

## Verdict

Neither Dev A nor Dev B is complete end to end yet.

The repository contains substantial implementations for both areas, but the current HEAD does not parse as a Flutter project, multiple native Android BLE correctness defects remain, and the real product path still has missing or broken links between join, Rooms, SOS/STT/voice, the mesh, and the dashboard.

The work is complete only when every P0/P1 item below is fixed, the automated gate passes from a clean checkout, and the physical-device acceptance gate passes with internet disabled.

## Current verification baseline

| Check | Current result | Meaning |
|---|---|---|
| `flutter pub get` | **FAIL** at `mobile/pubspec.yaml:57` (`Expected ':'`) | Committed merge-conflict markers make the current Flutter tree unbuildable. |
| `flutter analyze` / `flutter test` / APK build | **BLOCKED** by invalid `pubspec.yaml` | Earlier green results predate the current launcher-icon merge and are not evidence for HEAD. |
| Control-room web tests | Not fully run in this checkout | Install Node deps in `backend/` and `admin-dashboard/`, then run the documented build/test commands. |
| Physical BLE and microphone tests | **NOT PROVEN** | Synthetic tests do not establish Android radio, callback-thread, codec, background, or OEM behavior. |
| Worktree | `context.md`, `core-model/bin/`, and `core-protocol/bin/` are untracked | Do not accidentally commit generated `bin/` output. Decide separately whether `context.md` belongs in source control. |

## P0 shared integration gate

- [ ] **Resolve the committed merge conflict in `mobile/pubspec.yaml`.** Preserve both the STT model assets and launcher-icon configuration; remove all `<<<<<<<`, `=======`, and `>>>>>>>` lines. Run `flutter pub get`, `flutter analyze`, all tests, debug APK build, and a release/profile manifest check afterward.
- [ ] **Make the active manifest configure the running mesh.** `MeshEventController` currently always starts with `demo-site`, namespace `demo`, a generated demo site key, and hard-coded anchors. Joining a non-demo QR only changes the UI outbox site ID; the foreground mesh continues advertising, encrypting, filtering, and decrypting for `demo-site`. Define one startup/config message containing the validated site ID, namespace/fingerprint, provisioned key reference, room policy, and anchor map. Dev B supplies it from the active manifest; Dev A consumes it before advertising or accepting traffic. A site change must restart/re-key the mesh safely rather than merely changing `OutboxSender.siteId`.
- [ ] **Use one node identity across isolates.** The foreground mesh HELLO uses `_localToken`, while `MeshBridgeClient` independently generates `originEphemeralId`. The foreground task should generate/own the identity and report it to the UI bridge, or the UI should pass one identity into task startup. Add a bridge round-trip test proving an authored envelope and HELLO use the same node identity.
- [ ] **Add an acknowledged UI-to-foreground submission contract.** `sendDataToTask` currently returns no delivery/queue result, but the Drift row is marked `relaying`. Return an accepted/rejected message keyed by object ID; on rejection, stopped service, wrong site, or task startup failure, put the row back to `ready`. Test process death and foreground-task restart without losing or permanently stranding an event.

## Developer A — Mesh / protocol / BLE

### Already implemented

- Protocol envelope codec, AEAD envelope, framing, fragmentation/reassembly, TTL/hop bounds, dedupe, scheduler, ACK/NACK/retry, durable relay files, and metrics primitives.
- Android scan/advertise metadata, central/client session, peripheral/GATT server, MTU-aware transfer, peer limits, capacity quarantine/promotion, serialized writes/notifications, and foreground task orchestration.
- Synthetic protocol and transport tests, including priority, relay, MTU degradation, peer capacity, notification IDs, failure injection, and shutdown cases.

These are useful foundations, but do not close the following items.

### P1 correctness blockers

- [ ] **Deliver every asynchronous GATT platform reply on Android's main looper.** `connectGatt` is created without a callback `Handler`, so callbacks may arrive on Bluetooth binder threads. `onServicesDiscovered`, `onMtuChanged`, `onDescriptorWrite`/`updateSubscriptionState`, `onCharacteristicRead`, `onReadRemoteRssi`, and disconnect cleanup currently invoke Pigeon result callbacks directly. Apply the same main-looper completion pattern already used by characteristic writes. Snapshot/remove pending operations under a lock, then complete outside the lock on the main looper. Relevant file: `mobile/third_party/universal_ble/android/src/main/kotlin/com/navideck/universal_ble/UniversalBlePlugin.kt`.
- [ ] **Make all native pending-operation collections race-safe.** Registration happens on the platform method thread while GATT callbacks and cleanup can mutate the same lists. Protect discovery, MTU, subscription, read, and RSSI pending lists consistently; never execute user/Pigeon callbacks while holding their locks. Add the smallest native tests or extracted queue self-checks that prove register-before-callback, exactly-once removal, and disconnect cleanup.
- [ ] **Remove pending futures when operation initiation throws.** `setNotifiable` registers `SubscriptionResultFuture` before `writeDescriptor`, but its catch path does not remove it. `writeValue` has the same leak/double-completion risk if `writeCharacteristic` throws and only catches `FlutterError`. Track the pending value outside `try`, remove it in every failure path, catch platform exceptions, and prove each reply completes exactly once.
- [ ] **Make peripheral reconnection report real success/failure.** Native `reconnectPeripheral` silently returns when the device/server is absent and ignores the Boolean returned by `BluetoothGattServer.connect`. Dart then retains `_reconnectRequests` forever and suppresses every later retry. Return a result through Pigeon (or emit a failure event), clear the latch on failure/timeout, and use bounded backoff. Test unknown device, stopped server, `connect == false`, timeout, successful resubscription, and repeated capacity churn.
- [ ] **Confirm late MTU changes update server peer behavior.** `GattServerPeerLink` captures an MTU when attached. Verify on hardware that CCCD subscription always follows MTU negotiation; otherwise make the link consult the current server MTU before fragmentation or update the attached peer state when `mtuChangedStream` fires. Add a test where MTU changes after subscription.

### P1 required radio/system proof

- [ ] **Run the two-phone bidirectional test on every demo phone model:** both phones scan and advertise, central and peripheral roles coexist, HELLO succeeds, 100-byte object transfers both directions, and screen-off foreground operation remains alive.
- [ ] **Run a forced three-phone A → B → C test with no direct A → C path and internet/cellular disabled.** Prove B persists then forwards, C receives exactly once, hop count increases, ACK returns, and app restart on B resumes pending custody.
- [ ] **Exercise reconnect and churn:** Bluetooth off/on, relay killed/restarted, peer walking out/in range, subscriber disconnect during notify/write, capacity greater than four peers, and a rejected peer promoted when a slot opens.
- [ ] **Exercise MTU variation on real hardware:** default ATT MTU, negotiated larger MTU, late MTU callback, and a voice object above the configured low-MTU ceiling. Structured SOS must continue while voice is visibly deferred.
- [ ] **Validate notification completion on actual Android stacks.** Confirm unique native notification IDs pair each `notifyCharacteristicChanged` call with exactly one `onNotificationSent`, including identical consecutive payloads, disconnect races, failure status, and timeout.
- [ ] **Run the frame-loss/corruption switch end to end.** Prove missing-frame requests/retry recover after disabling injection and that P0 SOS preempts an in-progress voice/chat transfer.

### P1 observability/delivery evidence

- [ ] **Make metrics usable outside app-private storage.** Add a safe export/share or `adb` collection procedure and the promised log summarizer. The final output must compute trials, delivery rate, median/P95 relay latency, hop count, retransmissions, voice completeness, and failure reasons without logging transcripts, keys, or voice bytes.
- [ ] **Measure rather than claim reliability.** Record at least 20 timed 1-hop and 2-hop trials if the demo report claims P95; otherwise report the actual smaller sample without a P95 claim. Save device models, Android versions, negotiated MTUs, pass/fail logs, and battery interval.
- [ ] **Verify durable relay cleanup policy.** Expired outbox entries are removed only when `pending()` is called, while unreadable files are retained indefinitely. Define a bounded quarantine/cleanup policy and verify app-private storage cannot grow without limit during a long event.

### Dev A done criteria

Dev A is done only when native callbacks are thread-safe and exactly-once, capacity reconnect is retryable, dynamic site configuration is in use, the native/Flutter tests pass, and the physical 2-phone/3-phone matrix above has saved evidence.

## Developer B — App / product / gateway

### Already implemented

- Drift outbox/inbox and repository skeletons, join via typed code/QR, Rooms screens, SOS draft/finalize flow, deterministic safety rules, voice capture/package/playback primitives, Riverpod wiring, and cross-isolate bridge.
- Gateway HTTP client, the Node/Express control-room backend, and the React browser dashboard.
- A packaged sherpa-onnx engine now exists, but it is currently exposed only through a standalone smoke-test path rather than the SOS flow.

### P1 safety, privacy, and product-flow blockers

- [ ] **Remove fake STT from the runtime fallback.** If sherpa initialization or inference fails, the app currently substitutes `FakeOfflineSttEngine`, fabricating a transcript and confidence that can influence triage. Runtime fallback must be an explicit “transcript unavailable” failure/`NullSttEngine`; fake STT belongs only in tests/dev injection. Show the failure to the sender without blocking manual SOS.
- [ ] **Wire real offline STT into voice SOS.** The SOS voice button records only Opus, while the real PCM→sherpa path is a separate home-screen smoke test. Capture/reuse valid 16 kHz mono PCM for STT, create the durable SOS first, run STT and Opus work without suppressing the manual event, attach the actual transcript, then triage the final available text. Preserve model ID, inference time, and “confidence unavailable” semantics.
- [ ] **Persist STT metadata correctly.** `attachTranscript` stores only text, and `finalizeAndEnqueue` hard-codes `sttConfidence: 0`. Extend the schema/repository payload to store supported confidence (nullable, never invented), model ID, and inference time; add a Drift schema migration instead of editing schema version 1 in place.
- [ ] **Fix SOS ↔ voice linkage and ordering.** A structured SOS is finalized before voice is recorded, so its encoded `voiceClipId` remains empty even after `voicePath` is updated. Use a stable clip ID known when the SOS payload is finalized, or safely version/update the structured payload without changing object identity after transmission. Prove the dashboard links metadata and voice for both fast and delayed voice capture.
- [ ] **Expose outbound voice state in the UI.** `VoiceRepository.watchState` exists but no sender screen displays queued/transferring/complete/failed. Show progress and a clear low-MTU deferred/unavailable state; only receivers with verified bytes may see Play.
- [ ] **Enforce Room read ACL, not just send ACL.** `RoomsScreen` lists every room to the default public role and `RoomRepository.watch` returns restricted-room inbox content without `canRead`. Filter/lock navigation and data reads, validate role claims from provisioning rather than a local mutable toggle, and add tests proving a public user cannot view Medical/Responders content.
- [ ] **Enforce Room scope below the UI.** All site members currently share one site key and the relay/inbox path accepts every room, so a hidden tile alone cannot protect responder traffic. For the MVP, define the intended trust model explicitly and apply room membership/filtering before inbox exposure and gateway forwarding. For actual confidentiality, provision room-specific keys or equivalent authenticated authorization; do not claim private Rooms while every site client can decrypt them.
- [ ] **Carry location into each SOS.** The foreground task computes a zone estimate only for the status screen. It is never attached to `StructuredSosPayload`, so dashboard incidents have no zone. Bridge the latest estimate with timestamp/uncertainty into SOS composition and degrade visibly when stale/missing.

### P1 gateway/dashboard blockers

- [ ] **Make the local HTTP gateway work in the shipped Android manifest.** `android.permission.INTERNET` exists only in debug/profile manifests, and the app is configured to post to cleartext LAN `http://` URLs without a main-manifest network-security policy. Add release Internet permission and an intentionally scoped cleartext/LAN policy (or local HTTPS), then test the actual release candidate against a laptop hotspot with no internet uplink.
- [ ] **Do not overwrite incident severity when voice completes.** `GatewayBridge.voiceCompleteJson` sends `priority: unknown` and `incident_type: unknown`; the dashboard merge overwrites the original values. Voice completion must send only the fields it changes (`event_id`, clip ID, audio state), with a regression test using the real gateway payload.
- [ ] **Retry gateway delivery durably.** `_forwardToGateway` catches and discards every HTTP error. Keep received events in a durable gateway outbox, retry with bounded backoff, expose failed/pending state, and flush when the URL/key/dashboard becomes available. BLE processing must remain independent.
- [ ] **Populate real dashboard evidence fields.** Relay latency is always passed as null, zone is absent, and audio completeness has no byte/chunk evidence. Carry object completion metrics/timestamps into gateway records and display hop count, latency, voice size/completeness, and failure/deferred status.
- [ ] **Add authorized dashboard voice playback.** The browser receives only an `audio_state`; there is no endpoint or authenticated route for verified voice bytes. Implement bounded local storage/serving and playback only after envelope plus voice digest verification. Avoid embedding audio or transcripts in protocol logs.
- [ ] **Add operator acknowledge/dispatch workflow.** Persist the action, broadcast it to dashboards, and send a responder update back through the gateway/mesh at control priority. The UI must label it as a human action, not autonomous dispatch.
- [ ] **Add zone precursor/density demonstration separately from incident triage.** Use clearly simulated or measured inputs, show uncertainty and timestamp, and never merge the score into an individual's triage priority.
- [ ] **Add demo reset/seed tooling.** Reset only joined manifests, demo DB/outbox/inbox, relay files, gateway queue, and dashboard demo state. It must not delete packaged STT model assets. Confirm/reset actions must be explicit and scoped.

### P1 acceptance and integration tests

- [ ] Add widget/integration coverage for join → role-authorized Rooms → persisted SOS → optional STT/voice → outbox → bridge acceptance → received inbox → gateway → dashboard.
- [ ] Add negative tests for invalid/expired QR, unauthorized room read/send, STT failure, empty/failed audio capture, corrupt voice, wrong dashboard key, dashboard outage/recovery, duplicate event updates, and process restart.
- [ ] Run QR scanning, microphone capture, Opus playback, sherpa inference, and foreground/background navigation on each target phone. Record cold/warm model load time, inference time, model size, voice bytes/second, and thermal behavior.
- [ ] Run accessibility checks: semantic labels for SOS/record/stop/play, large text without overflow, screen-reader order, visible non-color-only status, and confirmation for destructive reset. Keep the SOS action reachable during model/audio failures.

### Dev B done criteria

Dev B is done only when restricted content is not exposed, manual and voice SOS use the real/failing-cleanly STT path, voice remains linked to its SOS with visible state, location reaches the incident, gateway delivery survives outage, the browser supports verified playback and operator action, and the full product flow passes on physical phones plus the local control room.

## Shared final release gate

Run from a clean clone/checkout after all fixes:

```bash
cd mobile
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --reporter expanded
flutter build apk --debug
flutter build apk --release

cd ../backend
npm ci
npm run build

cd ../admin-dashboard
npm ci
npm run build
```

Also run the vendored Android plugin/JVM tests with the repository's supported JDK, then install the exact release-candidate APK on the demo phones.

Final acceptance sequence:

1. Clean/reset three phones and the control room; join the same signed manifest and correct roles.
2. Disable cellular and internet uplink. Keep only the gateway/laptop local LAN.
3. Force A → B → C, send a typed P0 SOS, and verify persistence, priority, hops, latency, zone, dedupe, and dashboard display.
4. Send a voice SOS, verify real offline STT or explicit unavailable state, structured SOS first, bounded Opus second, integrity, progress, receiver/browser playback, and no incident-field regression.
5. Flood Room traffic, then send P0 and prove preemption. Verify public users cannot read restricted rooms.
6. Kill/restart B, disable/restore Bluetooth, take the dashboard down/up, and prove durable recovery without duplicate incidents or stranded outbox rows.
7. Have an operator acknowledge/dispatch and verify the responder update returns through the mesh.
8. Export privacy-safe metrics and produce the final measured report. Repeat the complete no-internet flow at least five consecutive times; run the larger trial count used by any reliability/P95 claim.

No “Dev A complete”, “Dev B complete”, or end-to-end reliability claim should be made before this gate is recorded with the exact commit, APK hash, phone models, Android versions, and logs.
