# MeshSetu testing runbook

This document covers the checks you can run locally and the Android demo you
can run on physical BLE-capable phones. The local suite uses synthetic BLE
links; it does not prove radio behavior.

## 1. Prerequisites

- Flutter/Dart compatible with `mobile/pubspec.yaml` (the verified toolchain
  uses Dart 3.12 and Flutter 3.47).
- Android SDK platform 36 and an Android device/API 29 or newer.
- Node.js 22+ for the backend and admin dashboard.
- For the mesh demo: three Android phones are preferred — source phone,
  relay phone, and gateway phone.
- All demo phones must have Bluetooth enabled. The gateway phone and laptop
  must share the same local Wi-Fi or hotspot.

## 2. Automated local checks

From the repository root:

```bash
cd mobile
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter build apk --debug
```

Expected result:

- Analyzer reports no issues.
- All Flutter tests pass.
- The APK is written to
  `mobile/build/app/outputs/flutter-apk/app-debug.apk`.

Test the backend and admin dashboard in separate terminals:

```bash
cd backend
npm ci
npm run build

cd ../admin-dashboard
npm ci
npm run build
```

## 3. Control-room smoke test

Start the local backend from the `backend/` directory:

```bash
npm run dev
```

The default demo key is `change-me`; use a different key for a shared demo by
setting `MESHSETU_GATEWAY_SECRET` before starting the server, for example:

```bash
MESHSETU_GATEWAY_SECRET=my-demo-key npm run dev
```

In another terminal, verify the HTTP contract:

```bash
curl -i http://127.0.0.1:8000/health
curl -i http://127.0.0.1:8000/api/events

curl -i -X POST http://127.0.0.1:8000/api/events \
  -H 'content-type: application/json' \
  -H 'x-meshsetu-demo-key: change-me' \
  -d '{"event_id":"smoke-1","priority":"p0Critical","incident_type":"medical","transcript":"dashboard smoke test"}'

curl -s http://127.0.0.1:8000/api/events
```

The POST must return HTTP 200. A POST without the demo-key header must return
HTTP 401.

To run the dashboard UI locally:

```bash
cd admin-dashboard
VITE_API_BASE_URL=http://127.0.0.1:8000 npm run dev
```

## 4. Install the Android build

Connect a physical Android phone and verify it is visible:

```bash
adb devices
adb install -r mobile/build/app/outputs/flutter-apk/app-debug.apk
```

Alternatively, run directly from Flutter:

```bash
cd mobile
flutter devices
flutter run -d <DEVICE_ID>
```

The package/application ID is `in.meshsetu.meshsetu_mobile`. Android will ask
for Bluetooth, notification, and microphone permissions as those features are
used. Grant them for the demo.

## 5. Single-phone UI smoke test

1. Open MeshSetu.
2. Tap **Start event mode**.
3. Confirm the foreground notification appears and the screen reports that
   the BLE relay service is running.
4. Tap **Join event / Rooms / SOS**.
5. Enter `DEMO01` and tap **Join with code**.
6. Confirm the Rooms screen shows Public Alerts, Gate-B, Medical,
   Responders, Voice evidence, and Gateway.
7. Tap **Send SOS**, enter `there is smoke everywhere`, and tap **Send SOS**.
8. Confirm the screen reports a P0 critical SOS and the event is persisted.
9. Return to the event screen and tap **Stop event mode**. Confirm the
   foreground service stops.

The default role is `public`, so restricted rooms should reject unauthorized
sends. This is an expected ACL result, not a transport failure.

The **Send 100-byte test SOS** button is only a transport smoke test. Its
payload is deliberately raw synthetic bytes, so it should not be expected to
produce a valid dashboard SOS card.

## 6. Three-phone offline mesh demo

Use three phones:

- Phone A: source/citizen.
- Phone B: relay.
- Phone C: gateway and receiver.

1. Start the control-room backend on the laptop.
2. Find the laptop's LAN address, for example `192.168.1.20`.
3. On Phone C, open **Join event / Rooms / SOS → Gateway**.
4. Set the dashboard URL to `http://192.168.1.20:8000`.
5. Set the dashboard key to match `MESHSETU_GATEWAY_SECRET` (or leave both as
   `change-me` for a local-only demo) and enable **Act as gateway**.
6. On all three phones, start event mode and join with `DEMO01`.
7. Disable mobile data and use an isolated local Wi-Fi/hotspot with no internet
   uplink. Keep Phone C and the laptop on that local link so only the dashboard
   path remains.
8. Place Phone B between Phone A and Phone C and wait for peer counts and BLE
   status to update.
9. On Phone A, send the smoke SOS from the UI.
10. On the laptop, confirm the dashboard eventually shows the incident,
    priority, transcript, room, hop count, latency, and audio state.
11. On Phone A, use **Record voice SOS** or **Attach voice evidence**, speak a
    short clip, and stop before the 10-second cap.
12. On Phone C, open **Voice evidence**. Playback should be available only for
    a voice object whose digest passes verification.
13. Confirm the dashboard's audio state changes to `complete` when the linked
    voice object reaches the gateway.

BLE discovery and connection ownership are opportunistic. If the phones do not
connect, keep them awake, bring them closer, confirm all Bluetooth permissions,
and restart event mode on all phones.

## 7. Failure and recovery checks

Run these individually and record the observed result:

### Frame loss

1. Start event mode.
2. Enable **Debug: drop/corrupt test frames**.
3. Send the 100-byte transport test or a real SOS.
4. Watch the metric and peer status fields.
5. Disable the switch and confirm later traffic can proceed.

### Dashboard unavailable

1. Enable gateway mode with an incorrect URL or key.
2. Send an SOS through the mesh.
3. Confirm the gateway forwarding failure does not stop local BLE operation.
4. Restore the URL/key and send another event.

### Process restart

1. Create a pending event or stop a demo phone while an object is relaying.
2. Relaunch the app and start event mode again.
3. Confirm the durable outbox can resume the relaying row rather than silently
   losing it.

### Voice tampering

Run the automated test that mutates a voice payload and confirm it fails with a
voice-integrity error rather than exposing a playable clip:

```bash
cd mobile
flutter test test/feature/dev_b_test.dart --plain-name 'VoiceObjectPayload rejects tampering before playback'
```

### STT fallback

The current build intentionally uses `NullSttEngine`; no real offline STT
model is installed. A manual or voice SOS must still be created and triaged by
the deterministic fallback rules. Do not treat the absence of a transcript as
a test failure for this build.

## 8. Resetting demo state

The in-memory fallback state in the backend is cleared by restarting its
process. To clear the mobile database and local demo state on a test phone:

```bash
adb shell pm clear in.meshsetu.meshsetu_mobile
```

This removes app data, including joined manifests, outbox rows, inbox rows,
and local relay state. Reinstall or relaunch the app afterward and grant
permissions again if Android requests them.

## 9. What this runbook cannot prove locally

- Ten consecutive two-hop deliveries on real phones.
- Android OEM-specific background behavior.
- Real microphone capture success on every target phone.
- A production offline STT engine or triage classifier.
- Zone precursor scoring or operator ACK/dispatch workflow.
- Production signing/enrollment security; the bundled manifest key and default
  dashboard key are demo-only credentials.
