# **MESHSETU Technical Development Bible** 

_End-to-end engineering specification, reference code, dependency documentation, build plan and 3-person team execution plan_ 

**<mark>Version: 1.0  |  Prepared: 15 August 2026  |  Target: Android-frst hackathon MVP leading to controlled feld pilot</mark>** 

Product contract: offline-first emergency communication using participating Android phones and fixed relay/beacon nodes; scoped Rooms; Mesh Code/QR join; local Speech-to-Text; short compressed voice-note store-and-forward over BLE; ondevice incident triage; localization/density/precursor intelligence; local authority dashboard and optional uplink bridge. 

**IMPORTANT: There is no Text-to-Speech feature. Voice is captured by the sender. Speech-to-Text runs locally. The original short voice clip is compressed, chunked, relayed over BLE, reassembled and played by an authorized receiver. The design is explicitly not live voice streaming.** 

The previously mentioned “fourth feature” remains unspecified by the product team. This document does not invent it. A clean extension point is reserved for it. 

Note: this document is a frozen product and architecture spec. Parts of it still describe an earlier FastAPI dashboard design; the live implementation in this repository is `admin/server/` plus `admin/client/`.

MeshSetu Technical Development Bible  |  1 

## **Table of contents** 

1. Technical scope and requirements freeze 

2. Engineering decisions that make the hackathon build feasible 

3. End-to-end system architecture 

4. Repository and module architecture 

5. Toolchain, packages and official documentation 

6. Core data contracts and Protocol Buffers 

7. BLE discovery, GATT transport and phone-to-phone relay 

8. Store-and-forward mesh protocol 

9. Mesh Code / QR provisioning 

10. Rooms and operational message routing 

11. Voice capture, compression, packetization and playback 

12. Offline Speech-to-Text architecture and inference plan 

13. On-device AI triage and structured SOS 

14. Localization, density and zone precursor scoring 

15. Gateway and local control-room dashboard 

16. Security, privacy and key management 

17. Persistence, background execution and observability 

18. Testing, benchmarking and failure injection 

19. Complete hackathon build plan 

20. Three-person team split and integration contracts 

21. Demo runbook and definition of done 

22. Production hardening roadmap 

Appendix A. Reference code snippets Appendix B. Command and debugging cheat sheet Appendix C. Official documentation index 

MeshSetu Technical Development Bible  |  2 

## **1. Technical scope and requirements freeze** 

### **1.1 What must exist in the hackathon MVP** 

- Android app installed on at least 3 physical BLE-capable phones, with 4-5 preferred for the final demo. 

- Internet/cellular can be disabled and a structured SOS still travels from Phone A to a gateway/receiver through at least one intermediate phone. 

- Mesh Code: user enters a short code or scans a QR to load the event/site manifest and allowed Rooms. The human code is never treated as the cryptographic root key. 

- Rooms: at minimum Public Alerts, a zone Room, Medical and Responders. Room traffic is lower priority than SOS. 

- Voice SOS: sender records a short clip; local STT produces a transcript; the original audio is compressed; transcript/structured SOS is relayed first; voice bytes follow as bounded chunks; receiver reassembles and can play the clip. 

- On-device triage: raw typed/STT text becomes a schema-constrained Structured SOS with incident type, priority, hazards, confidence and rationale. Model failure never suppresses a manual SOS. 

- Local persistence: pending messages survive process restarts long enough to retry; duplicate messages are not shown repeatedly. 

- Local control-room dashboard: incident list, priority, transcript, Room/zone, hop count, relay latency, voice transfer completeness and playback. 

- At least one localization signal: nearest fixed beacon/relay mapped to a logical zone. RSSI-based distance must be labelled approximate. 

- Zone-level precursor score can be demonstrated with simulated density/SOS inputs; it is separate from per-incident triage. 

- All critical behavior produces timestamped logs so the team can prove latency, hop count, delivery success and failure behavior. 

### **1.2 Explicit non-goals for the hackathon** 

- No claim of Bluetooth SIG Mesh certification. The phone MVP is an application-layer BLE store-and-forward overlay built with Android scan/advertise + GATT. Production fixed relays may use a standards-compliant Bluetooth Mesh stack. 

- No live voice call or continuous audio streaming over the emergency mesh. 

- No exact crowd headcount, facial recognition, identity tracking or autonomous life-critical dispatch. 

- No promise of perfect background operation on every Android OEM. The MVP uses a visible connected-device foreground service during active event mode. 

- No production-grade public-key enrollment ceremony in the 48-hour demo. The demo provisioning shortcut is documented and isolated from the production security design. 

- No invented fourth feature. Implement only after the product team names it. 

### **1.3 Safety invariants** 

|**Invariant**|**Implementation rule**|
|---|---|
|Manual SOS is never blocked|STT/triage exceptions degrade to raw SOS + audio; the send action persists<br>before inference completes.|
|SOS always outranks chat/audio|Scheduler priorities are enforced centrally; Room chat cannot starve<br>emergency metadata.|
|Uncertainty is visible|STT confdence, triage confdence and localization uncertainty are felds, not<br>hidden model internals.|
|No live-stream assumption|Voice clips are duration-capped and store-and-forward; transfer status is<br>explicit.|
|Human authority remains fnal|Triage/precursor outputs recommend; they do not dispatch or open gates<br>automatically.|
|Graceful degradation|If MTU, audio codec, STT or beacon data is unavailable, compact SOS<br>transport continues.|



MeshSetu Technical Development Bible  |  3 

## **2. Engineering decisions that make the hackathon build feasible** 

### **2.1 Android-first, physical-device-first** 

Use Android for the MVP because the platform exposes BLE central/client and peripheral/advertiser/GATT-server primitives required to make phones relay for one another. Android documentation positions BLE for transferring small amounts of data; that is consistent with MeshSetu’s “structured SOS first, bounded voice evidence second” design. [SRC-A01][SRC-A02] 

Test on physical phones from hour 1. The Android emulator is not a substitute for real radio, microphone, OEM background behavior or codec testing. 

### **2.2 Do not claim full Bluetooth SIG Mesh on phones in the MVP** 

Bluetooth Mesh is a standardized many-to-many, multi-hop technology, but the SIG documentation also notes smartphone OS constraints around the advertising bearer and provides Mesh Proxy/GATT as an interoperability path. The hackathon implementation should therefore be described precisely as a MeshSetu BLE relay overlay, not as certified Bluetooth Mesh. [SRC-B01] 

Fixed beacon/relay hardware can later use nRF52/ESP32 or another embedded platform with a standards-compliant Mesh stack. Keep application envelopes independent of the underlying bearer so the transport can evolve. 

### **2.3 Discovery via advertising; data via GATT** 

- BLE advertising is used only to discover nearby MeshSetu peers and advertise a compact protocol/site fingerprint. 

- Actual messages travel over a GATT connection. Each phone exposes a small GATT server and can also connect as a GATT client. 

- Transport negotiates MTU and fragments every object. Do not assume a 517-byte MTU even though modern Android may request it; remote capabilities still determine the effective size. [SRC-A03] 

- If effective MTU is too small for practical voice transfer, send structured SOS/transcript and mark voice as deferred/unavailable. This is graceful degradation, not failure. 

### **2.4 Object encryption before fragmentation** 

Serialize the complete application object, encrypt/authenticate it once, then fragment ciphertext into transport frames. This avoids paying an AEAD authentication tag on every tiny BLE frame. Transport frames can be dropped/reordered by untrusted relays; final object integrity is checked after reassembly. 

### **2.5 Local-first database is the queue** 

The Room database is not merely UI storage. It is the durable outbox/inbox: every event has a state machine (CREATED → READY → RELAYING → ACKED/EXPIRED). This makes retries, process restarts and dashboard evidence much easier. 

### **2.6 Model work is an adapter, not a dependency trap** 

The app depends on an `OfflineSttEngine` interface and a `TriageEngine` interface. The STT developer can switch between whisper.cpp and sherpa-onnx without forcing the networking developers to rewrite UI or transport. The raw voice clip and manual SOS remain usable even when the model is not loaded. 

## **3. End-to-end system architecture** 

### **3.1 Logical topology** 

##### **Architecture sketch** 

```
[Phone A: citizen]
  Capture SOS / voice
      |
      v
  Local STT -> Structured SOS -> Triage
      |
      v
  Durable Outbox -> Encrypt -> Fragment
      |
   BLE GATT
      v
[Phone B: relay] -> [Phone C: relay] -> [Gateway phone]
```

MeshSetu Technical Development Bible  |  4 

```
                                      |      \
                                      |       \ optional internet/cellular bridge
                                      v        v
                                 Local LAN   ERSS/authority adapter (future)
                                      |
                                      v
                            [Laptop control-room dashboard]
```

```
Fixed BLE beacons/relays provide stable zone IDs, extra relay capacity and optional gateways.
```

### **3.2 Source-phone pipeline** 

1. Create a local SOS draft immediately and persist it with a UUID/event timestamp. 

2. Capture typed/tap input or short PCM voice. Voice capture is capped (recommended demo default: 10 seconds). 

3. Run STT locally on PCM. In parallel, encode PCM to Opus or the selected low-bitrate speech codec. 

4. Run deterministic safety rules first, then optional compact classifier, producing Structured SOS + confidence/rationale. 

5. Serialize event envelope (Protocol Buffers), encrypt/authenticate, fragment for current GATT MTU. 

6. Place metadata/transcript object at SOS priority. Place voice object at VOICE_EVIDENCE priority. 

7. Advertise availability, discover peers, connect, transfer missing frames, retry until complete/acknowledged or expired. 

### **3.3 Relay-phone pipeline** 

8. Receive a frame; validate protocol version and coarse size limits. 

9. Persist frame/object state before acknowledging when reliability requires it. 

10. Dedupe using object ID + chunk index and suppress repeated forwarding. 

11. When object completes, verify authenticated envelope, expiry and site/room scope. 

12. If relay policy permits, enqueue for additional peers with hop count/TTL updated. 

13. Never let voice chunks or Room chat consume all transfer slots while SOS metadata is waiting. 

### **3.4 Gateway/control-room pipeline** 

14. Gateway phone receives exactly like any other peer and marks itself as a sink/bridge capability in HELLO. 

15. Reassembled, verified incidents are sent over a local Wi-Fi LAN to a laptop HTTP endpoint. Internet is not required. 

16. FastAPI stores current demo state and broadcasts incident updates to browser dashboards over WebSocket. 

17. Operators acknowledge/dispatch in the dashboard; a signed responder update can be sent back through the gateway into the mesh as a high-priority control event. 

### **3.5 Failure domains** 

|**Failure**|**Expected behavior**|
|---|---|
|Internet/cellular loss|No efect on local BLE loop; dashboard stays local if gateway and laptop<br>share LAN.|
|STT fails or model not loaded|Manual/voice SOS persists; transcript marked unavailable; audio + raw<br>category sent.|
|Triage model uncertain|Manual SOS remains; priority falls back to rules/default; uncertainty<br>displayed.|
|Voice transfer incomplete|Structured SOS remains actionable; receiver shows missing chunk count<br>and retries until expiry.|
|Relay leaves range|Store-and-forward retries with other peers; TTL/expiry prevents indefnite<br>propagation.|
|Beacon missing|Use logical zone chosen by user / nearest available anchor; uncertainty<br>increases.|
|Gateway fails|Incidents remain locally cached and continue peer-to-peer; another node<br>can be promoted as gateway.|



MeshSetu Technical Development Bible  |  5 

## **4. Repository and module architecture** 

### **4.1 Recommended monorepo** 

```
meshsetu/
  android/
    app/                         # Compose UI, navigation, foreground event mode
    core-model/                  # Kotlin domain models, enums, mapper interfaces
    core-protocol/               # protobuf schemas, frame codec, crypto envelope
    core-data/                   # Room DB, DAOs, repositories, outbox state machine
    core-ble/                    # scanner, advertiser, GATT server/client, peer sessions
    feature-join/                # Mesh Code / QR provisioning
    feature-rooms/               # Room list/message UI and policies
    feature-sos/                 # SOS compose screen + structured incident card
    feature-voice/               # AudioRecord, Opus codec, playback, voice object store
    feature-stt/                 # OfflineSttEngine adapter; native/model assets
    feature-triage/              # rules + compact local classifier adapter
    feature-map/                 # zone/beacon model, demo localization
    feature-gateway/             # local HTTP bridge + authority command receive
    benchmark/                   # radio/model/codec benchmark instrumentation
  protocol/
    meshsetu.proto
    README.md
    test-vectors/
  dashboard/
    main.py                      # FastAPI
    static/index.html
    static/app.js
    requirements.txt
  ml/
    stt-bench/                   # benchmark scripts, sample audio, model manifests
    triage-training/             # optional training/conversion notebook/scripts
    datasets/README.md
  tools/
    packet_simulator.py
    log_parser.py
    demo_seed.py
  docs/
    ADR-001-phone-overlay.md
    ADR-002-voice-store-forward.md
    THREAT_MODEL.md
    DEMO_RUNBOOK.md
  .github/workflows/
  README.md
```

### **4.2 Dependency direction** 

UI features may depend on core modules. `core-ble` and `core-data` depend on `core-model` / `core-protocol`. The STT implementation is behind an interface and must not directly call BLE. The BLE layer never knows what Whisper is. This isolation is the single most important team-parallelization choice. 

```
UI/features -> repositories/use-cases -> core-data/core-protocol -> core-ble
                          |                     |
                          +-> feature-stt ------+
                          +-> feature-triage ---+
```

```
Dashboard is a separate process; it communicates only with the gateway API contract.
```

## **5. Toolchain, packages and official documentation** 

### **5.1 Baseline toolchain** 

Versions below are an implementation baseline checked against official release pages around 15 Aug 2026. Pin them in the repository. If a version conflict appears during setup, resolve against official compatibility guidance rather than blindly upgrading one library. 

|**Component**|**Recommended baseline**|**Why**|
|---|---|---|
|JDK|17|Android Gradle Plugin baseline; predictable CI.|
|Android Gradle Plugin|9.3.x|Current 2026-era Android build line; pin exact<br>tested patch.|
|Gradle|compatible version required by AGP|Use AGP compatibility table; do not<br>independently chase newest Gradle.|



MeshSetu Technical Development Bible  |  6 

|Kotlin|2.4.10|Current stable line checked 15 Aug 2026. [SRC-<br>K01]|
|---|---|---|
|compile/target SDK|latest stable supported by chosen AGP|Use Android Studio SDK manager; test runtime<br>permissions on Android 12+.|
|minSdk for hackathon|29 (Android 10)|Simplifes platform Opus encoder availability and<br>narrows OEM test matrix. Production can widen<br>later.|
|Compose BOM|pin current stable BOM|Keeps Compose artifacts compatible. [SRC-A10]|
|Activity Compose|1.13.0|Stable as of Mar 2026. [SRC-A11]|
|Lifecycle|2.11.0|Stable as of Jun 2026. [SRC-A12]|
|Room|pin current stable|Durable message outbox/inbox with compile-time<br>SQL verifcation.|
|Hilt/Dagger|pin current stable|Dependency injection; can be replaced by manual<br>DI if setup time becomes critical.|
|Protobuf Lite|pin current stable|Compact schema-evolving event serialization.|
|FastAPI|pin current stable in venv|Local dashboard HTTP + WebSocket server. [SRC-<br>W01]|
|Opus|libopus 1.6 or Android MediaCodec|Speech-oriented codec; Android platform<br>encoder available on Android 10+. [SRC-O01]<br>[SRC-A05]|



### **5.2 Package/library decision matrix** 

|**Area**|**Primary choice**|**Alternative**|**Decision rule**|
|---|---|---|---|
|BLE|Android<br>BluetoothLeScanner/Advertiser +<br>BluetoothGatt/GattServer|Embedded SIG Mesh for fxed relays|Phone MVP uses native Android<br>APIs.|
|UI|Jetpack Compose|Views/XML|Compose accelerates state-driven<br>demo UI.|
|Persistence|Room|Raw SQLite|Room is safer and easier for queue<br>state.|
|Serialization|Protocol Bufers Lite|CBOR/custom binary|Use protobuf for application objects;<br>custom compact framing only at<br>transport layer.|
|Voice capture|AudioRecord|MediaRecorder|AudioRecord gives PCM<br>simultaneously usable by STT and<br>Opus encoder.|
|Voice codec|Opus via MediaCodec (API 29+)|Native libopus via NDK|Start with MediaCodec; move native<br>if bitrate/control/device issues<br>appear.|
|STT|whisper.cpp quantized multilingual<br>OR sherpa-onnx ofline|Platform SpeechRecognizer only if<br>verifed ofline|Benchmark physical target devices<br>before committing.|
|Triage runtime|Rules + LiteRT small classifer|ONNX Runtime|Rules are mandatory safety fallback;<br>runtime follows trained model<br>format.|
|QR scan|ML Kit bundled barcode scanner +<br>CameraX|Manual code entry|Bundled scanner avoids frst-run<br>network model download. [SRC-<br>G01]|
|Gateway|Local HTTP POST from phone|WebSocket client on phone|HTTP is simpler/reliable; browser<br>dashboard receives WebSocket<br>updates.|
|Dashboard|FastAPI + static HTML/JS|Ktor/Node|Fast to build and inspect in<br>hackathon.|



MeshSetu Technical Development Bible  |  7 

### **5.3 Gradle project skeleton** 

```
// settings.gradle.kts
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "MeshSetu"
include(":app", ":core-model", ":core-protocol", ":core-data", ":core-ble")
include(":feature-join", ":feature-rooms", ":feature-sos", ":feature-voice")
include(":feature-stt", ":feature-triage", ":feature-map", ":feature-gateway")
// app/build.gradle.kts - representative, not a substitute for the checked-in version catalog
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.kapt")
    id("com.google.dagger.hilt.android")
}
android {
    namespace = "in.meshsetu.app"
    compileSdk = /* team-pinned stable SDK */ 37
    defaultConfig {
        applicationId = "in.meshsetu.app"
        minSdk = 29
        targetSdk = 37
        versionCode = 1
        versionName = "0.1.0-hackathon"
    }
    buildFeatures { compose = true; buildConfig = true }
}
dependencies {
    implementation(platform("androidx.compose:compose-bom:<PINNED_BOM>"))
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.11.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.11.0")
    implementation("androidx.navigation:navigation-compose:<PINNED_STABLE>")
    implementation("androidx.room:room-runtime:<PINNED_STABLE>")
    implementation("androidx.room:room-ktx:<PINNED_STABLE>")
    kapt("androidx.room:room-compiler:<PINNED_STABLE>")
    implementation("com.google.dagger:hilt-android:<PINNED_STABLE>")
    kapt("com.google.dagger:hilt-compiler:<PINNED_STABLE>")
    implementation("com.google.protobuf:protobuf-kotlin-lite:<PINNED_STABLE>")
}
```

Why placeholders appear in dependency coordinates: these lines change more often than the architecture. The repository must pin the exact combination that is tested on the hackathon machines. The official documentation index at the end gives the source of truth. 

## **6. Core data contracts and Protocol Buffers** 

### **6.1 Application event envelope** 

Use a stable application schema independent of BLE. A structured SOS and a voice clip are separate objects linked by `event_id` / `voice_clip_id`. This is what allows metadata to arrive even when audio is incomplete. 

```
// protocol/meshsetu.proto
syntax = "proto3";
package meshsetu.v1;
option java_package = "in.meshsetu.protocol";
option java_multiple_files = true;
message MeshEnvelope {
  string event_id = 1;          // UUID string in MVP; production may use bytes
  string site_id = 2;
  string room_id = 3;
  int64 created_at_ms = 4;
  int64 expires_at_ms = 5;
  uint32 hop_count = 6;
  uint32 hop_limit = 7;
  Priority priority = 8;
  PayloadType payload_type = 9;
  bytes payload = 10;           // serialized StructuredSos / RoomMessage / VoiceManifest...
  string origin_ephemeral_id = 11;
```

MeshSetu Technical Development Bible  |  8 

```
  bytes trace_id = 12;
}
enum Priority { P_UNSPECIFIED=0; P0_CRITICAL=1; P1_HIGH=2; P2_NORMAL=3; P3_BULK=4; }
enum PayloadType {
  PT_UNSPECIFIED=0; STRUCTURED_SOS=1; ROOM_MESSAGE=2; VOICE_MANIFEST=3;
  VOICE_OBJECT=4; ACK=5; RESPONDER_UPDATE=6; BEACON_OBSERVATION=7;
}
message StructuredSos {
  string incident_type = 1;
  string transcript = 2;
  float stt_confidence = 3;
  Priority triage_priority = 4;
  float triage_confidence = 5;
  repeated string hazards = 6;
  repeated string symptoms = 7;
  string location_hint = 8;
  string logical_zone = 9;
  repeated string rationale = 10;
  repeated string missing_info = 11;
  string voice_clip_id = 12;
  InputMode input_mode = 13;
}
```

```
enum InputMode { INPUT_UNSPECIFIED=0; TAP=1; TEXT=2; VOICE=3; }
message VoiceManifest {
  string voice_clip_id = 1;
  string event_id = 2;
  string codec = 3;             // "opus"
  uint32 sample_rate_hz = 4;    // e.g. 16000
  uint32 channels = 5;          // 1
  uint32 duration_ms = 6;
  uint32 encoded_bytes = 7;
  bytes sha256 = 8;
}
message RoomMessage {
  string message_id = 1;
  string sender_ephemeral_id = 2;
  string text = 3;
  int64 sent_at_ms = 4;
  bool authority_signed = 5;
}
```

### **6.2 Kotlin domain model** 

```
data class StructuredIncident(
    val eventId: String,
    val siteId: String,
    val roomId: String,
    val incidentType: IncidentType,
    val priority: PriorityBand,
    val transcript: String?,
    val sttConfidence: Float?,
    val triageConfidence: Float,
    val hazards: Set<String>,
    val symptoms: Set<String>,
    val locationHint: String?,
    val logicalZone: String?,
    val rationale: List<String>,
    val missingInfo: List<String>,
    val voiceClipId: String?,
    val createdAtMs: Long,
    val expiresAtMs: Long,
)
enum class PriorityBand { P0_CRITICAL, P1_HIGH, P2_NORMAL, P3_BULK }
enum class IncidentType { MEDICAL, FIRE, CROWD_PRESSURE, SECURITY, LOST_PERSON, OTHER }
```

### **6.3 Transport frame vs application envelope** 

Do not serialize a full protobuf envelope into every BLE write. Encrypt the envelope once, then fragment it into compact transport frames. The frame header exists only for reassembly and scheduling. 

```
// 16-byte MeshSetu frame header (network byte order)
// [0] version
// [1] frameType
// [2] priority
// [3] flags
// [4..11] objectId64
// [12..13] sequenceNo (uint16)
// [14..15] chunkCount (uint16)
// [16..] fragment payload
const val FRAME_HEADER_BYTES = 16
```

MeshSetu Technical Development Bible  |  9 

```
fun maxFragmentPayload(mtu: Int): Int {
    val attValueBytes = (mtu - 3).coerceAtLeast(20) // ATT protocol overhead
    return (attValueBytes - FRAME_HEADER_BYTES).coerceAtLeast(1)
}
```

Voice policy: if `maxFragmentPayload` is too small for bounded audio within the configured expiry (for example effective MTU below a team-tested threshold), transmit only the Structured SOS and set `audio_state=DEFERRED_MTU`. Do not saturate the mesh trying to force audio through an unsuitable link. 

## **7. BLE discovery, GATT transport and phone-to-phone relay** 

### **7.1 Android permissions** 

```
<!-- AndroidManifest.xml -->
<uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

```
<!-- Android 12+ -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
```

```
<!-- Legacy only -->
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE" />
```

Request `BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT` and `RECORD_AUDIO` at runtime where required. Bluetooth permissions changed on Android 12+, so test on at least one Android 12/13 device and one recent device. [SRC-A04] 

### **7.2 UUID contract** 

```
object MeshGatt {
    val SERVICE = UUID.fromString("6e400001-b5a3-f393-e0a9-e50e24dcca9e")
    val RX      = UUID.fromString("6e400002-b5a3-f393-e0a9-e50e24dcca9e") // peer writes frames here
    val TX      = UUID.fromString("6e400003-b5a3-f393-e0a9-e50e24dcca9e") // server notifies frames/control
    val CTRL    = UUID.fromString("6e400004-b5a3-f393-e0a9-e50e24dcca9e") // hello/ack/inventory
    val CCCD    = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
}
```

These UUIDs are example development UUIDs. Generate and freeze project-specific UUIDs before publishing the repo. Never reuse vendor UUIDs from unrelated products. 

### **7.3 Advertise only discovery metadata** 

```
@SuppressLint("MissingPermission")
fun startAdvertising(adapter: BluetoothAdapter, siteFingerprint: ByteArray) {
    val advertiser = adapter.bluetoothLeAdvertiser ?: return
    val settings = AdvertiseSettings.Builder()
        .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
        .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
        .setConnectable(true)
        .build()
    val data = AdvertiseData.Builder()
        .setIncludeDeviceName(false)
        .addServiceUuid(ParcelUuid(MeshGatt.SERVICE))
        .addServiceData(ParcelUuid(MeshGatt.SERVICE), siteFingerprint.take(6).toByteArray())
        .build()
    advertiser.startAdvertising(settings, data, advertiseCallback)
}
```

### **7.4 Scan with a time-bounded window** 

```
@SuppressLint("MissingPermission")
suspend fun scanPeers(scanner: BluetoothLeScanner, windowMs: Long = 4_000): List<ScanResult> =
    suspendCancellableCoroutine { cont ->
        val found = linkedMapOf<String, ScanResult>()
        val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(MeshGatt.SERVICE)).build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        val cb = object : ScanCallback() {
            override fun onScanResult(type: Int, result: ScanResult) {
                found[result.device.address] = result
            }
```

MeshSetu Technical Development Bible  |  10 

```
            override fun onScanFailed(errorCode: Int) {
```

```
                if (cont.isActive) cont.resumeWith(Result.failure(IllegalStateException("BLE scan $errorCode")))
            }
        }
        scanner.startScan(listOf(filter), settings, cb)
        val handler = Handler(Looper.getMainLooper())
        handler.postDelayed({
            scanner.stopScan(cb)
            if (cont.isActive) cont.resume(found.values.toList()) {}
        }, windowMs)
        cont.invokeOnCancellation { scanner.stopScan(cb) }
    }
```

Android explicitly recommends stopping a scan rather than scanning indefinitely. In event mode, use alternating scan/connect/idle cycles and measure battery cost. [SRC-A06] 

### **7.5 GATT server: receive frames** 

```
@SuppressLint("MissingPermission")
fun openMeshGattServer(context: Context, manager: BluetoothManager): BluetoothGattServer {
    val server = manager.openGattServer(context, object : BluetoothGattServerCallback() {
        override fun onCharacteristicWriteRequest(
```

```
            device: BluetoothDevice, requestId: Int, characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray
        ) {
            if (characteristic.uuid == MeshGatt.RX && !preparedWrite && offset == 0) {
                frameInbox.tryEmit(PeerFrame(device.address, value))
                if (responseNeeded) serverRef?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            } else if (responseNeeded) {
                serverRef?.sendResponse(device, requestId, BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED, 0, null)
            }
        }
    })
    val service = BluetoothGattService(MeshGatt.SERVICE, BluetoothGattService.SERVICE_TYPE_PRIMARY)
    val rx = BluetoothGattCharacteristic(
        MeshGatt.RX,
        BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
        BluetoothGattCharacteristic.PERMISSION_WRITE
    )
    val tx = BluetoothGattCharacteristic(
        MeshGatt.TX,
        BluetoothGattCharacteristic.PROPERTY_NOTIFY,
        BluetoothGattCharacteristic.PERMISSION_READ
    )
    service.addCharacteristic(rx); service.addCharacteristic(tx)
    server.addService(service)
    return server
}
```

### **7.6 GATT client and MTU negotiation** 

```
@SuppressLint("MissingPermission")
fun connect(context: Context, device: BluetoothDevice): BluetoothGatt =
    device.connectGatt(context, false, object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, state: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS) { gatt.close(); return }
            if (state == BluetoothProfile.STATE_CONNECTED) {
                gatt.requestMtu(247)       // request; never assume the result
                gatt.discoverServices()
            } else if (state == BluetoothProfile.STATE_DISCONNECTED) gatt.close()
        }
        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            peerSessions.updateMtu(gatt.device.address, if (status == BluetoothGatt.GATT_SUCCESS) mtu else 23)
        }
        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) peerSessions.ready(gatt)
        }
    }, BluetoothDevice.TRANSPORT_LE)
```

On Android 14+, the platform may request a 517-byte ATT MTU on the first GATT-client request, but the negotiated value still depends on the remote side. The fragmentation code must use the callback result. [SRC-A03] 

### **7.7 Write compatibility helper** 

```
@SuppressLint("MissingPermission")
fun writeNoResponse(gatt: BluetoothGatt, ch: BluetoothGattCharacteristic, bytes: ByteArray): Boolean {
    return if (Build.VERSION.SDK_INT >= 33) {
```

```
        gatt.writeCharacteristic(ch, bytes, BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE) ==
BluetoothStatusCodes.SUCCESS
    } else {
        @Suppress("DEPRECATION")
        run { ch.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE; ch.value = bytes;
gatt.writeCharacteristic(ch) }
```

MeshSetu Technical Development Bible  |  11 

```
    }
}
```

## **8. Store-and-forward mesh protocol** 

### **8.1 Node identity and peer HELLO** 

Use a rotating ephemeral node ID per event/session, not a stable advertising identifier. HELLO contains only what peers need: protocol version, site fingerprint, capabilities and a short queue summary. 

```
data class Hello(
    val protocolVersion: Int = 1,
    val siteFingerprint: Long,
    val ephemeralNodeId: Long,
    val capabilities: Int,       // RELAY | GATEWAY | BEACON | VOICE | STT
    val maxObjectBytes: Int,
    val nowEpochSec: Long,
)
```

### **8.2 Priority scheduler** 

```
enum class TrafficClass(val rank: Int) {
    CONTROL_ACK(0),
    SOS_STRUCTURED(1),
    AUTHORITY_CONTROL(2),
    VOICE_EVIDENCE(3),
    ROOM_MESSAGE(4),
    TELEMETRY(5)
}
data class OutboundObject(
    val objectId: Long,
    val trafficClass: TrafficClass,
    val createdAt: Long,
    val expiresAt: Long,
    val bytes: ByteArray
)
val comparator = compareBy<OutboundObject> { it.trafficClass.rank }.thenBy { it.createdAt }
val queue = PriorityQueue(comparator)
```

### **8.3 Fragmentation** 

```
data class MeshFrame(
    val version: UByte = 1u,
    val type: UByte,
    val priority: UByte,
    val flags: UByte,
    val objectId: ULong,
    val sequence: UShort,
    val count: UShort,
    val payload: ByteArray,
)
```

```
fun fragment(objectId: ULong, priority: UByte, encrypted: ByteArray, mtu: Int): List<MeshFrame> {
    val n = maxFragmentPayload(mtu)
    require(n > 0)
    val chunks = encrypted.asList().chunked(n).map { it.toByteArray() }
    require(chunks.size <= UShort.MAX_VALUE.toInt())
    return chunks.mapIndexed { i, payload ->
        MeshFrame(type = 1u, priority = priority, flags = 0u,
            objectId = objectId, sequence = i.toUShort(), count = chunks.size.toUShort(), payload = payload)
    }
}
```

### **8.4 Reassembly and integrity** 

```
class ReassemblyBuffer(val count: Int, val createdAt: Long) {
    private val parts = arrayOfNulls<ByteArray>(count)
    var received = 0; private set
    fun add(seq: Int, bytes: ByteArray): Boolean {
        if (seq !in 0 until count || parts[seq] != null) return false
        parts[seq] = bytes; received++; return true
    }
    fun complete() = received == count
    fun join(): ByteArray {
        check(complete())
        val size = parts.sumOf { it!!.size }
        return ByteArray(size).also { out ->
            var off=0; parts.forEach { p -> p!!; p.copyInto(out, off); off += p.size }
        }
    }
}
```

MeshSetu Technical Development Bible  |  12 

### **8.5 Dedupe and anti-replay** 

```
class RecentObjectCache(private val maxEntries: Int = 4096) {
    private val seen = object : LinkedHashMap<Long, Long>(maxEntries, .75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<Long, Long>?) = size > maxEntries
    }
    @Synchronized fun markIfNew(id: Long, expiresAtMs: Long, nowMs: Long): Boolean {
        seen.entries.removeIf { it.value < nowMs }
        if (seen.containsKey(id)) return false
        seen[id] = expiresAtMs
        return true
    }
}
```

### **8.6 Relay algorithm** 

```
suspend fun onCompleteObject(ciphertext: ByteArray, transport: TransportMeta) {
    val envelope = crypto.decryptAndVerify(ciphertext) ?: return metrics.invalidObject()
    if (clock.now() > envelope.expiresAtMs) return metrics.expired()
    if (envelope.siteId != activeManifest.siteId) return
    if (!recentObjectCache.markIfNew(transport.objectId, envelope.expiresAtMs, clock.now())) return
    inbox.persist(envelope)
    uiEvents.emit(envelope)
    val canRelay = envelope.hopCount < envelope.hopLimit && !gatewayPolicy.sinkOnly
    if (canRelay) {
        val next = envelope.toBuilder().setHopCount(envelope.hopCount + 1).build()
        outbox.enqueue(crypto.encrypt(next), trafficClassFor(next))
    }
}
```

Production note: mutating hop count inside an encrypted/authenticated envelope requires decrypt/re-encrypt by trusted site members. Another design is an immutable signed origin envelope wrapped by mutable relay metadata. The MVP can use shared site encryption; production should separate origin authenticity from relay routing metadata. 

### **8.7 Reliability strategy** 

- ACK complete objects, not every frame, unless tests prove frame-level ACKs are necessary. 

- Receiver can send a compact missing-chunk bitmap/NACK for voice objects. 

- Use bounded retries with jitter; do not create synchronized retry storms. 

- Persist the outbox before transmit. Remove/age out only after ACK or expiry. 

- Cap object size, chunk count, retry count and per-peer transfer time to resist accidental or malicious exhaustion. 

- Prefer opportunistic replication to 1-2 good peers rather than flooding every byte to every discovered phone immediately; benchmark fan-out. 

## **9. Mesh Code / QR provisioning** 

### **9.1 What the Mesh Code is** 

The Mesh Code is a human UX/bootstrap identifier for the event/site namespace. A six-character code is not enough entropy to be a network root key. For a fully offline hackathon, support two paths: QR contains a signed demo manifest; typed code selects a manifest that was bundled/preloaded on the app. 

### **9.2 Event manifest** 

```
@Serializable
data class EventManifest(
    val siteId: String,
    val displayName: String,
    val namespaceId: String,
    val validFromMs: Long,
    val validUntilMs: Long,
    val rooms: List<RoomManifest>,
    val beaconMapVersion: String,
    val authorityPublicKeyB64: String,
    val demoSiteKeyB64: String? = null, // HACKATHON ONLY - remove from production public QR
    val signatureB64: String,
)
```

```
data class RoomManifest(val roomId: String, val name: String, val access: String, val priorityCeiling: Int)
```

MeshSetu Technical Development Bible  |  13 

### **9.3 QR scan** 

Use CameraX ImageAnalysis + ML Kit bundled barcode scanning. The bundled barcode model is immediately available and does not require a first-run model download. [SRC-G01][SRC-G02] 

```
val options = BarcodeScannerOptions.Builder()
    .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
    .build()
val scanner = BarcodeScanning.getClient(options)
```

```
fun analyze(proxy: ImageProxy) {
    val mediaImage = proxy.image ?: return proxy.close()
    val image = InputImage.fromMediaImage(mediaImage, proxy.imageInfo.rotationDegrees)
    scanner.process(image)
        .addOnSuccessListener { codes ->
            codes.firstOrNull()?.rawValue?.let { manifestText -> joinViewModel.importManifest(manifestText) }
        }
        .addOnCompleteListener { proxy.close() }
}
```

### **9.4 Validation checklist** 

- Verify manifest signature before activation. 

- Reject expired/not-yet-valid manifests. 

- Show site/event name and expiry to user before joining. 

- Do not leak restricted Room keys to public attendees. 

- Demo shortcut (`demoSiteKeyB64` in QR) must be compiled only into a hackathon flavor and visibly documented as non-production. 

## **10. Rooms and operational message routing** 

### **10.1 Room semantics** 

|**Room**|**Audience**|**Allowed content**|**Transport priority**|
|---|---|---|---|
|Public Alerts|All participants|Authority notices + limited user<br>acknowledgements|Authority control > normal chat|
|Zone: Gate-B|People/volunteers in a logical zone|Local guidance, queue updates|Normal|
|Medical|Authorized medical/volunteer roles|Medical coordination + SOS<br>references|High but below SOS metadata|
|Responders|Authority/responder roles|Dispatch/operational updates|Authority control|
|Family Reunifcation|Optional public/assisted role|Lost/found person coordination<br>without sensitive over-sharing|Normal|



### **10.2 Room ACL and transport policy** 

```
data class RoomPolicy(
    val roomId: String,
    val canRead: Set<Role>,
    val canPost: Set<Role>,
    val maxMessageBytes: Int = 512,
    val ttlSeconds: Int = 120,
    val trafficClass: TrafficClass = TrafficClass.ROOM_MESSAGE,
)
fun canSend(policy: RoomPolicy, role: Role, bytes: Int) =
    role in policy.canPost && bytes <= policy.maxMessageBytes
```

Room membership controls visibility and forwarding. Restricted Rooms should use separate room keys in production. A public participant should not be able to decrypt responder traffic simply because they know the event Mesh Code. 

### **10.3 SOS transcends Room chat** 

An SOS may carry a `room_id` for operator context, but relay eligibility must not depend on ordinary Room subscription. Emergency metadata is an event-level safety object. This prevents a phone outside “Medical” from refusing to relay a medical SOS. 

MeshSetu Technical Development Bible  |  14 

## **11. Voice capture, compression, packetization and playback** 

### **11.1 Exact feature behavior** 

Voice is an input and evidence mode, not a voice-call feature. Sender records a short clip; the app produces two outputs in parallel: (A) PCM for on-device STT and (B) an Opus-encoded bounded voice object. The structured/transcribed SOS is sent at emergency priority before the voice object. Bluetooth Mesh itself is not an audio-streaming technology; the design deliberately uses store-and-forward short messages. [SRC-B01][SRC-O01] 

### **11.2 Audio capture format** 

Recommended MVP: 16 kHz, mono, PCM 16-bit. This is a common STT input rate and is easy to hand to both whisper-style ASR and an Opus encoder. Capture with `AudioRecord`, which exposes PCM buffers directly. [SRC-A07] 

```
class PcmRecorder {
    private val sampleRate = 16_000
    private val channel = AudioFormat.CHANNEL_IN_MONO
    private val encoding = AudioFormat.ENCODING_PCM_16BIT
    private val minBuffer = AudioRecord.getMinBufferSize(sampleRate, channel, encoding)
    @SuppressLint("MissingPermission")
    fun open(): AudioRecord = AudioRecord(
        MediaRecorder.AudioSource.VOICE_RECOGNITION,
        sampleRate, channel, encoding,
        maxOf(minBuffer * 2, 4096)
    )
    suspend fun recordMax(record: AudioRecord, maxMs: Long = 10_000): ShortArray = withContext(Dispatchers.IO) {
        val out = ShortArrayOutput()
        val buf = ShortArray(2048)
        record.startRecording()
        val deadline = SystemClock.elapsedRealtime() + maxMs
        try {
            while (SystemClock.elapsedRealtime() < deadline && currentCoroutineContext().isActive) {
                val n = record.read(buf, 0, buf.size)
                if (n > 0) out.write(buf, n)
            }
        } finally { record.stop(); record.release() }
        out.toShortArray()
    }
}
```

### **11.3 Opus design** 

Opus is designed for speech and audio across a wide bitrate range. For the demo, benchmark approximately 8-12 kbit/s mono speech; do not hard-code a bitrate claim until listening tests and transfer tests succeed. A 10-second clip at 8 kbit/s is about 10 KB before container/protocol overhead, which is small enough to test as a bounded object but still large relative to a normal BLE message. [SRC-O01][SRC-O02] 

#### **Option A - Android MediaCodec (fastest MVP path, API 29+)** 

```
fun createOpusEncoder(bitRate: Int = 10_000): MediaCodec {
    val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_OPUS, 16_000, 1).apply {
        setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
        setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 4096)
    }
    return MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_OPUS).apply {
        configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        start()
    }
}
```

The full MediaCodec loop must queue PCM input buffers and drain encoded output buffers until end-of-stream. Keep that loop in `OpusEncoder` and unit-test it against a short known PCM sample. Android’s supported media-format table lists Opus encoding support on Android 10+. [SRC-A05] 

#### **Option B - native libopus (more control, more setup)** 

```
// C/C++ conceptual encoder setup using libopus
int err = OPUS_OK;
OpusEncoder* enc = opus_encoder_create(16000, 1, OPUS_APPLICATION_VOIP, &err);
opus_encoder_ctl(enc, OPUS_SET_BITRATE(10000));
opus_encoder_ctl(enc, OPUS_SET_VBR(1));
```

```
// For each 20 ms frame: 320 samples at 16 kHz
unsigned char packet[4000];
int bytes = opus_encode(enc, pcmFrame, 320, packet, sizeof(packet));
```

MeshSetu Technical Development Bible  |  15 

Use `OPUS_APPLICATION_VOIP` for speech-oriented encoding. Native libopus is the fallback if platform MediaCodec behavior varies or if precise bitrate/FEC controls are needed. [SRC-O03] 

### **11.4 Voice object transfer** 

```
suspend fun enqueueVoiceEvidence(eventId: String, opusBytes: ByteArray, durationMs: Int) {
    val clipId = UUID.randomUUID().toString()
    val manifest = VoiceManifest.newBuilder()
        .setVoiceClipId(clipId).setEventId(eventId).setCodec("opus")
        .setSampleRateHz(16000).setChannels(1).setDurationMs(durationMs)
        .setEncodedBytes(opusBytes.size).setSha256(ByteString.copyFrom(sha256(opusBytes)))
        .build()
    outbox.enqueue(manifest.toByteArray(), TrafficClass.SOS_STRUCTURED) // tiny manifest first
    outbox.enqueue(opusBytes, TrafficClass.VOICE_EVIDENCE, objectKey = clipId)
}
```

### **11.5 Receiver playback** 

After all chunks arrive, verify hash/integrity, persist the Opus file, then play with an Android decoder (MediaCodec/MediaPlayer as appropriate). Dashboard playback can use a server-converted browser-compatible file in the demo, or simply let the gateway phone play the verified clip. 

### **11.6 Voice acceptance tests** 

|**Metric**|**Hackathon test**|
|---|---|
|Capture success|10/10 clips recorded on each demo device with internet of.|
|STT latency|Measure recording-end → transcript-ready; report median and worst of 10<br>clips.|
|Encoded size|Record encoded bytes, duration and bitrate confguration.|
|Mesh transfer|Record chunks sent/received/retried and reassembly time across 1-hop and<br>2-hop.|
|Priority isolation|While voice transfers, inject a new SOS and prove structured SOS overtakes<br>remaining audio chunks.|
|Corruption|Drop/alter one chunk; verify reassembly remains incomplete or integrity<br>check fails, not silent bad playback.|



## **12. Offline Speech-to-Text architecture and inference plan** 

### **12.1 Interface contract** 

```
data class SttResult(
    val text: String,
    val confidence: Float?,
    val language: String?,
    val inferenceMs: Long,
    val modelId: String,
)
interface OfflineSttEngine {
    suspend fun warmUp(): Result<Unit>
    suspend fun transcribe(pcm16: ShortArray, sampleRateHz: Int = 16_000): Result<SttResult>
    fun close()
}
```

Networking and UI code call only this interface. This lets the STT developer benchmark and swap engines independently. 

### **12.2 Candidate A: whisper.cpp** 

whisper.cpp supports Android and integer quantization, making it a practical local multilingual ASR candidate. The team should start with a quantized tiny or base multilingual model and measure memory, real-time factor and accuracy on the actual demo phones. [SRC-S01] 

> `// Kotlin JNI wrapper - interface stays stable even if native internals change class WhisperCppStt(private val modelPath: String) : OfflineSttEngine { private var ctx: Long = 0L override suspend fun warmUp() = runCatching { ctx = nativeInit(modelPath); require(ctx != 0L) } override suspend fun transcribe(pcm16: ShortArray, sampleRateHz: Int) = withContext(Dispatchers.Default) {` 

MeshSetu Technical Development Bible  |  16 

```
        runCatching {
            require(sampleRateHz == 16_000)
            val started = SystemClock.elapsedRealtime()
            val json = nativeTranscribe(ctx, pcm16)
            parseSttJson(json, SystemClock.elapsedRealtime() - started, modelId = "whisper.cpp")
        }
    }
    override fun close() { if (ctx != 0L) nativeFree(ctx); ctx = 0L }
    private external fun nativeInit(path: String): Long
    private external fun nativeTranscribe(ctx: Long, pcm: ShortArray): String
    private external fun nativeFree(ctx: Long)
}
// CMakeLists.txt sketch
cmake_minimum_required(VERSION 3.22.1)
project(meshsetu_stt)
add_subdirectory(whisper.cpp)
add_library(meshsetu_stt SHARED stt_jni.cpp)
target_link_libraries(meshsetu_stt PRIVATE whisper log android)
```

### **12.3 Candidate B: sherpa-onnx** 

sherpa-onnx is built specifically for offline speech/audio tasks and documents Android deployments with on-device processing. It is an excellent candidate when a suitable language/model combination meets the latency/memory target. [SRC-S02] 

The STT developer should not choose a model from name recognition. Choose it only after the benchmark matrix below. For Hindi/English or code-switched Indian use, confirm actual model language coverage and test your own noisy samples. 

### **12.4 STT model decision gate - first 6 hours** 

|**Criterion**|**whisper.cpp candidate**|**sherpa-onnx candidate**|**Pass condition**|
|---|---|---|---|
|Ofline|Yes by architecture|Yes by architecture|Airplane mode; no network<br>permission required for inference.|
|Language|Use multilingual model|Depends on selected model|Required demo languages<br>recognized on real samples.|
|Model load|Measure|Measure|No OOM on weakest demo device.|
|Latency|Measure RTF / end latency|Measure RTF / end latency|10 s clip returns in team-defned<br>acceptable time.|
|Accuracy|Measure keyword/WER proxy|Measure keyword/WER proxy|Critical emergency terms preserved<br>reliably enough for demo.|
|Integration|JNI/NDK|ONNX/sherpa Android APIs|One stable `OflineSttEngine`<br>implementation by hour 12.|



### **12.5 Benchmark harness** 

```
data class SttBenchmarkCase(val id: String, val pcm: ShortArray, val expectedKeywords: Set<String>)
```

```
data class SttBenchmarkResult(
    val caseId: String, val inferenceMs: Long, val text: String,
    val keywordRecall: Float, val peakRssMb: Float?, val modelId: String
)
```

```
fun keywordRecall(text: String, expected: Set<String>): Float {
    val normalized = text.lowercase()
    return expected.count { it.lowercase() in normalized }.toFloat() / expected.size.coerceAtLeast(1)
}
```

### **12.6 Data for STT testing** 

- Record 20-30 consented synthetic emergency phrases spoken by the team, not real victim data. 

- Include quiet room, crowd-noise playback, fast speech, different accents, Hindi/English/code-switching if that is the demo goal. 

- Label critical keywords separately from exact wording: “fire”, “unconscious”, “cannot breathe”, “Gate B”, “child”, “bleeding”, “pushing”. 

- Keep test clips outside app analytics and delete after benchmark unless consent explicitly allows retention. 

MeshSetu Technical Development Bible  |  17 

### **12.7 STT confidence policy** 

Many ASR engines do not expose a calibrated single “confidence” directly. Do not fabricate one. If the selected engine offers token/log-probability information, map it to a clearly documented heuristic. Otherwise set `stt_confidence=null` and show “confidence unavailable”; use transcript + original audio as evidence. 

### **12.8 Optimization sequence** 

18. Get one model working on one physical phone before any quantization work. 

19. Profile model load time, inference time, memory and thermals. 

20. Try quantized model; compare critical-keyword retention, not just WER. 

21. Limit threads to avoid starving BLE/UI. Start with 2-4 CPU threads and benchmark. 

22. Warm the model when user enters active event mode if memory permits. 

23. Use device acceleration (NNAPI/QNN/LiteRT NPU) only after a CPU baseline is stable; acceleration support varies by operators/model. [SRC-M01][SRC-M02] 

## **13. On-device AI triage and structured SOS** 

### **13.1 Design principle: hybrid, conservative, explainable** 

For a safety-critical hackathon, the fastest credible design is deterministic critical-phrase rules + a small local text classifier. Do not use a generative LLM as the only triage engine. The model proposes structure/priority; rules can force escalation for a narrow list of safety-critical phrases; human operators remain final. 

### **13.2 Structured SOS recipe** 

```
data class TriageOutput(
    val incidentType: IncidentType,
    val priority: PriorityBand,
    val confidence: Float,
    val hazards: Set<String>,
    val symptoms: Set<String>,
    val peopleAffected: Int?,
    val locationHint: String?,
    val rationale: List<String>,
    val missingInfo: List<String>
)
```

### **13.3 Deterministic safety rules** 

```
object SafetyRules {
    private val p0 = listOf(
        Regex("\\b(unconscious|not breathing|cannot breathe|severe bleeding|fire|stampede|crush)\\b",
RegexOption.IGNORE_CASE)
    )
    private val crowd = Regex("\\b(pushing|crush|crowd pressure|trapped)\\b", RegexOption.IGNORE_CASE)
    fun evaluate(text: String): RuleDecision {
        val reasons = mutableListOf<String>()
        if (p0.any { it.containsMatchIn(text) }) reasons += "critical phrase"
        if (crowd.containsMatchIn(text)) reasons += "crowd pressure indicator"
        val forced = if (reasons.isNotEmpty()) PriorityBand.P0_CRITICAL else null
        return RuleDecision(forcedPriority = forced, rationale = reasons)
    }
}
```

### **13.4 Small classifier training pipeline (optional but recommended)** 

Train on a laptop; infer on-device. Keep the model small and the input contract simple: tokenizer maps a fixed vocabulary to integer IDs; model predicts incident type / base priority. Export vocabulary alongside the model. The rules engine still owns hard safety overrides. 

```
# ml/triage-training/train.py  (reference baseline)
import json, numpy as np, tensorflow as tf
from tensorflow import keras
MAX_LEN = 48
VOCAB = json.load(open("vocab.json"))
NUM_TYPES = 6
inp = keras.Input(shape=(MAX_LEN,), dtype="int32", name="token_ids")
x = keras.layers.Embedding(len(VOCAB), 48, mask_zero=True)(inp)
x = keras.layers.GlobalAveragePooling1D()(x)
x = keras.layers.Dense(48, activation="relu")(x)
```

MeshSetu Technical Development Bible  |  18 

```
out = keras.layers.Dense(NUM_TYPES, activation="softmax", name="incident_type")(x)
model = keras.Model(inp, out)
model.compile(optimizer="adam", loss="sparse_categorical_crossentropy", metrics=["accuracy"])
model.fit(train_ids, train_labels, validation_data=(val_ids, val_labels), epochs=12, batch_size=32)
converter = tf.lite.TFLiteConverter.from_keras_model(model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
open("incident_classifier.tflite", "wb").write(converter.convert())
```

### **13.5 On-device inference contract** 

```
interface TriageClassifier {
    fun classify(tokenIds: IntArray): ClassifierResult
}
class TriageEngineImpl(
    private val rules: SafetyRules,
    private val classifier: TriageClassifier,
    private val extractor: EntityExtractor,
) {
    fun triage(text: String): TriageOutput {
        val rule = rules.evaluate(text)
        val model = classifier.classify(tokenizer.encode(text, maxLen = 48))
        val extracted = extractor.extract(text)
        val priority = rule.forcedPriority ?: mapProbabilityToPriority(model)
        return TriageOutput(
            incidentType = model.incidentType,
            priority = priority,
            confidence = model.confidence,
            hazards = extracted.hazards,
            symptoms = extracted.symptoms,
            peopleAffected = extracted.peopleAffected,
            locationHint = extracted.location,
            rationale = rule.rationale + model.rationale,
            missingInfo = requiredFieldsMissing(extracted)
        )
    }
}
```

### **13.6 LiteRT vs ONNX Runtime** 

If the triage model is exported as TFLite/LiteRT, use Google AI Edge LiteRT. Its current Android guidance recommends the CompiledModel API as the modern accelerator-first interface. If model development lands in ONNX, ONNX Runtime Mobile and NNAPI are viable. Choose one runtime; do not ship both in the hackathon APK unless necessary. [SRC-M01][SRC-M03] 

### **13.7 Priority mapping** 

|**Band**|**Meaning**|**Examples**|**Action**|
|---|---|---|---|
|P0 Critical|Immediate life/safety threat|Not breathing, unconscious, active<br>fre, severe crush indicators|Relay frst; control room<br>visually/audibly fags; human<br>dispatch.|
|P1 High|Urgent but not proven immediately<br>life-threatening|Injury, escalating crowd pressure,<br>trapped person|High relay priority; operator review.|
|P2 Normal|Needs assistance|Lost person, non-urgent help request|Standard queue.|
|P3 Bulk|Non-emergency evidence/telemetry|Voice chunks, routine Room<br>messages|Never block SOS.|



### **13.8 Model evaluation** 

For the hackathon, report confusion matrix / per-class recall on a small held-out synthetic set, but label it a prototype benchmark. Safety acceptance should emphasize recall on P0/P1 examples and false escalation burden. Do not claim clinical or emergency-dispatch validation. 

## **14. Localization, density and zone precursor scoring** 

### **14.1 Beacon observations** 

```
data class BeaconObservation(
    val beaconId: String,
    val logicalZone: String,
```

MeshSetu Technical Development Bible  |  19 

```
    val rssi: Int,
    val observedAtMs: Long,
)
```

```
fun smoothedRssi(samples: List<Int>): Double {
    if (samples.isEmpty()) return Double.NaN
    val sorted = samples.sorted()
    val trimmed = if (sorted.size >= 5) sorted.drop(1).dropLast(1) else sorted
    return trimmed.average()
}
```

### **14.2 Zone-first localization** 

The hackathon should prioritize reliable logical-zone localization over fake sub-meter precision. Assign each fixed beacon a known zone. If multiple anchors are visible, use strongest/smoothed RSSI and report a confidence class. RSSI is noisy around bodies and reflective structures; the UI should show “Zone B / approximate” rather than a precise dot unless calibrated. 

```
fun estimateZone(obs: List<BeaconObservation>): ZoneEstimate? = obs
    .groupBy { it.logicalZone }
    .mapValues { (_, xs) -> xs.map { it.rssi }.average() }
    .maxByOrNull { it.value }
    ?.let { ZoneEstimate(zone = it.key, confidence = if (it.value > -65) "HIGH" else "COARSE") }
```

### **14.3 Density estimate - demo method** 

Density is a zone-level operational estimate from ephemeral observations, not an exact human count. In the hackathon, use either a controlled number of participating devices or a simulation feed, and expose the calibration assumption. 

```
fun estimateDensity(distinctEphemeralIds: Int, calibrationFactor: Double, coverage: Double): Double {
    require(coverage in 0.1..1.0)
```

```
    return distinctEphemeralIds * calibrationFactor / coverage
}
```

### **14.4 Precursor score** 

```
data class ZoneSignals(val densityTrend: Double, val sosCluster: Double, val motionAnomaly: Double, val persistence:
Double)
```

```
data class ScoreWeights(val d: Double=.35, val s: Double=.35, val m: Double=.15, val p: Double=.15)
```

```
fun precursorScore(x: ZoneSignals, w: ScoreWeights = ScoreWeights()): Double =
```

```
    (w.d*x.densityTrend + w.s*x.sosCluster + w.m*x.motionAnomaly + w.p*x.persistence).coerceIn(0.0, 1.0)
```

Keep this score separate from incident triage in code, data model and UI. It answers “is this zone becoming risky?” rather than “how urgent is this person’s SOS?” 

## **15. Gateway and local control-room dashboard** 

### **15.1 Gateway API** 

Simplest hackathon bridge: gateway phone and laptop join the same local Wi-Fi hotspot. The phone POSTs verified incident JSON to the laptop. No internet access is required. The laptop broadcasts updates to browsers via WebSocket. 

```
// Android gateway - dependency-free JSON POST sketch
suspend fun postToDashboard(baseUrl: String, json: String) = withContext(Dispatchers.IO) {
    val conn = (URL("$baseUrl/api/events").openConnection() as HttpURLConnection).apply {
        requestMethod = "POST"
        connectTimeout = 1500; readTimeout = 1500
        doOutput = true
        setRequestProperty("Content-Type", "application/json")
        setRequestProperty("X-MeshSetu-Demo-Key", BuildConfig.DASHBOARD_DEMO_KEY)
    }
    conn.outputStream.use { it.write(json.toByteArray()) }
    val code = conn.responseCode
    conn.disconnect()
    require(code in 200..299) { "dashboard HTTP $code" }
}
```

### **15.2 FastAPI server** 

```
# dashboard/main.py
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Header, HTTPException
from pydantic import BaseModel
from typing import Optional
```

```
app = FastAPI(title="MeshSetu Local Control Room")
clients: set[WebSocket] = set()
latest: dict[str, dict] = {}
DEMO_KEY = "change-me"
```

MeshSetu Technical Development Bible  |  20 

```
class Event(BaseModel):
    event_id: str
    priority: str
    incident_type: str
    transcript: Optional[str] = None
    zone: Optional[str] = None
    room: Optional[str] = None
    hops: int = 0
    relay_latency_ms: Optional[int] = None
    voice_clip_id: Optional[str] = None
    audio_state: Optional[str] = None
@app.post("/api/events")
async def ingest(event: Event, x_meshsetu_demo_key: str = Header(default="")):
    if x_meshsetu_demo_key != DEMO_KEY:
        raise HTTPException(401, "bad demo key")
    latest[event.event_id] = event.model_dump()
    dead = []
    for ws in clients:
        try: await ws.send_json({"type":"event", "data":latest[event.event_id]})
        except Exception: dead.append(ws)
    for ws in dead: clients.discard(ws)
    return {"ok": True}
@app.get("/api/events")
def list_events():
    return list(latest.values())
@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket):
    await ws.accept(); clients.add(ws)
    await ws.send_json({"type":"snapshot", "data":list(latest.values())})
    try:
        while True: await ws.receive_text()
    except WebSocketDisconnect:
        clients.discard(ws)
```

FastAPI supports WebSocket endpoints directly; this is enough for a local demo dashboard without introducing a message broker. [SRC-W01] 

### **15.3 Minimal browser client** 

```
<!-- dashboard/static/index.html -->
<!doctype html><meta charset="utf-8"><title>MeshSetu Control Room</title>
<h1>MeshSetu Local Control Room</h1><div id="events"></div>
<script>
const root = document.getElementById('events');
const state = new Map();
function render(){
  root.innerHTML = [...state.values()].sort((a,b)=>a.priority.localeCompare(b.priority)).map(e => `
    <article><h3>${e.priority} · ${e.incident_type} · ${e.zone||'unknown zone'}</h3>
    <p>${e.transcript||'No transcript'}</p>
    <small>${e.hops} hops · ${e.relay_latency_ms??'?'} ms · audio
${e.audio_state||'n/a'}</small></article>`).join('');
}
const ws = new WebSocket(`ws://${location.host}/ws`);
ws.onmessage = ev => { const m=JSON.parse(ev.data); (m.type==='snapshot'?m.data:
[m.data]).forEach(e=>state.set(e.event_id,e)); render(); };
</script>
```

### **15.4 Dashboard fields** 

- Event ID, priority, incident type, received timestamp. 

- Transcript + STT status; button to play reassembled original voice evidence when complete. 

- Room, logical zone, localization uncertainty/anchor source. 

- Triage rationale and confidence; separate zone precursor score and evidence. 

- Hop count, origin-to-gateway relay latency, duplicate/retry count. 

- Operator ACK / dispatch state; responder update back into mesh (stretch goal). 

## **16. Security, privacy and key management** 

### **16.1 Threat model** 

|**Threat**|**MVP mitigation**|**Production hardening**|
|---|---|---|
|Fake SOS injection|Site-scoped shared demo auth + validation + rate<br>limits|Per-device credentials, signed enrollment,<br>authority trust chain, abuse controls.|



MeshSetu Technical Development Bible  |  21 

|Packet tampering|AEAD object integrity; hash voice bytes|Origin signatures + separate relay metadata.|
|---|---|---|
|Replay|UUID/object IDs + expiry + recent-object cache|Persistent replay windows / signed counters<br>where appropriate.|
|Eavesdropping|Encrypt restricted payloads|Per-Room keys, forward secrecy where feasible,<br>audited key lifecycle.|
|Relay exhaustion|Size caps, priorities, TTL, retries, per-peer quotas|Adaptive rate limiting, trust/reputation policy,<br>hardened relays.|
|Stolen device|Short event keys + no long-term personal data|Device revocation, hardware-backed keys, MDM<br>for responders.|
|Sensitive voice retention|Short retention; only authorized receiver|Explicit policy, encrypted at rest, deletion/audit,<br>DPDP review.|



### **16.2 Android Keystore for device key** 

Android Keystore can keep key material non-exportable and may bind it to hardware-backed security depending on the device. Use it for long-lived device/authority credentials, not a hard-coded key in source. [SRC-C01] 

```
fun getOrCreateAesKey(alias: String = "meshsetu_device_wrap"): SecretKey {
    val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    (ks.getKey(alias, null) as? SecretKey)?.let { return it }
    val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
    gen.init(KeyGenParameterSpec.Builder(alias,
        KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
        .setKeySize(256)
        .build())
    return gen.generateKey()
}
```

### **16.3 AEAD envelope** 

```
data class CipherBlob(val iv: ByteArray, val ciphertextAndTag: ByteArray)
```

```
fun encryptAesGcm(key: SecretKey, plaintext: ByteArray, aad: ByteArray): CipherBlob {
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(Cipher.ENCRYPT_MODE, key)
    cipher.updateAAD(aad)
    return CipherBlob(cipher.iv, cipher.doFinal(plaintext))
}
fun decryptAesGcm(key: SecretKey, blob: CipherBlob, aad: ByteArray): ByteArray {
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, blob.iv))
    cipher.updateAAD(aad)
    return cipher.doFinal(blob.ciphertextAndTag)
}
```

### **16.4 Key hierarchy** 

```
Authority signing key (offline-managed / production)
        |
        +-- signs EventManifest
                |
                +-- Site transport key (demo shared; production provisioned securely)
                +-- Public Room key (if confidentiality desired)
                +-- Responder Room key (restricted)
                +-- Medical Room key (restricted)
```

```
Device Keystore key wraps locally cached room/site keys at rest.
```

### **16.5 Privacy defaults** 

- Use rotating ephemeral IDs; do not broadcast phone number, name, IMEI or persistent account ID. 

- Keep zone-level aggregation rather than user trails for crowd-density features. 

- Voice clip has explicit short retention and is not used to train models by default. 

- Raw audio should never be uploaded to a cloud service in the offline demo path. 

- If optional medical/contact notes are added, encrypt separately and make them consented/role-restricted. 

- Log protocol metrics without storing sensitive transcript/audio unless needed for the controlled demo. 

MeshSetu Technical Development Bible  |  22 

## **17. Persistence, background execution and observability** 

### **17.1 Room database entities** 

```
@Entity(tableName = "outbox")
data class OutboxEntity(
    @PrimaryKey val objectId: Long,
    val eventId: String,
    val trafficClass: Int,
    val encryptedBlob: ByteArray,
    val state: String,
    val attempts: Int,
    val createdAtMs: Long,
    val expiresAtMs: Long,
)
@Dao
interface OutboxDao {
    @Query("SELECT * FROM outbox WHERE state IN ('READY','RETRY') AND expiresAtMs > :now ORDER BY trafficClass,
createdAtMs LIMIT :limit")
    suspend fun next(now: Long, limit: Int = 50): List<OutboxEntity>
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsert(x: OutboxEntity)
    @Query("UPDATE outbox SET state=:state, attempts=attempts+1 WHERE objectId=:id")
    suspend fun transition(id: Long, state: String)
}
```

### **17.2 Foreground active-event service** 

BLE background behavior is tightly constrained. During an active emergency-event session, use a user-visible foreground service with the appropriate connected-device service type and a persistent notification. Android documents multiple BLE background patterns and foreground-service restrictions; test real behavior on the exact demo devices. [SRC-A02][SRC-A08] 

```
class MeshEventService : LifecycleService() {
    override fun onCreate() {
        super.onCreate()
        startForeground(NOTIF_ID, buildNotification("MeshSetu event mode active"))
        lifecycleScope.launch { meshCoordinator.run() }
    }
}
```

### **17.3 Structured metrics** 

```
data class ProtocolMetric(
    val timeMs: Long,
    val eventId: String?,
    val peer: String?,
    val kind: String,          // scan_found, connected, frame_tx, frame_rx, object_complete, ack, retry...
    val value: Long? = null,
    val detail: String? = null,
)
```

Write metrics as newline-delimited JSON to app-private storage in a debug/hackathon flavor. The log parser can compute delivery probability, median/P95 latency, hops, retransmissions, voice chunk completeness and battery deltas. 

### **17.4 Privacy-safe logs** 

Never put raw voice bytes, long transcripts, site keys or personal notes into Logcat. Use event IDs and hashed/short peer IDs. A debug-only “show transcript in dashboard” path is separate from protocol telemetry. 

## **18. Testing, benchmarking and failure injection** 

### **18.1 Test pyramid** 

|**Layer**|**Tests**|**Owner**|
|---|---|---|
|Pure unit|Frame encode/decode,<br>fragmentation/reassembly, TTL, dedupe, priority,<br>rules, schema mapping|Dev A/B|
|Android instrumentation|Room persistence, permission fow,<br>AudioRecord/MediaCodec smoke, QR scanning|Dev B + STT|
|Radio integration|2-phone GATT, 3-phone relay, reconnect, MTU<br>variation, device churn|Dev A|



MeshSetu Technical Development Bible  |  23 

|ML benchmark|STT load/inference, keyword recall, memory;|STT Dev|
|---|---|---|
||triage class recall||
|System demo|Voice SOS → 2-hop → dashboard with internet of|All|



### **18.2 Core unit tests** 

```
@Test fun fragmentation_roundTrip() {
    val bytes = ByteArray(10_000) { (it % 251).toByte() }
    val frames = fragment(42u, 1u, bytes, mtu = 185)
    val buf = ReassemblyBuffer(frames.size, 0)
    frames.shuffled().forEach { assertTrue(buf.add(it.sequence.toInt(), it.payload)) }
    assertArrayEquals(bytes, buf.join())
```

```
}
```

```
@Test fun sos_beats_voice() {
    val q = PriorityQueue(comparator)
    q += OutboundObject(1, TrafficClass.VOICE_EVIDENCE, 1, 9999, byteArrayOf())
    q += OutboundObject(2, TrafficClass.SOS_STRUCTURED, 2, 9999, byteArrayOf())
    assertEquals(2, q.poll().objectId)
}
```

### **18.3 Failure injection checklist** 

- Disable mobile data and Wi-Fi internet before demo start. 

- Force Phone B to be the only path; prove A cannot directly reach gateway by physical separation if possible. 

- Kill/restart app on a relay; confirm outbox survives as designed. 

- Turn Bluetooth off/on; record recovery time. 

- Drop every Nth voice frame in a debug transport wrapper; prove NACK/retry or incomplete state. 

- Make STT throw intentionally; prove SOS still reaches dashboard. 

- Make triage return low confidence; prove operator sees uncertainty and no SOS suppression. 

- Remove a beacon; prove zone result degrades instead of inventing precision. 

- Flood 20 Room messages, then generate P0 SOS; prove emergency queue preempts them. 

### **18.4 Metrics the judges should see** 

|**Metric**|**How to measure**|**Do not claim before measuring**|
|---|---|---|
|SOS delivery rate|N trials at 1-hop/2-hop with internet of|“99.9% reliable”|
|Relay latency|source persisted timestamp → gateway complete<br>timestamp|“instant”|
|P95 latency|at least 20 trials if time permits|single best-case screenshot|
|Voice encoded size|bytes / seconds for selected codec settings|generic bitrate as product fact|
|Voice reassembly latency|enqueue → hash-verifed complete|live voice capability|
|STT latency|record end → transcript result|real-time on every phone|
|STT keyword recall|controlled phrase set|medical-grade ASR|
|Battery delta|controlled active-event interval|all-day impact without test|



## **19. Complete hackathon build plan** 

### **19.1 First principle** 

The vertical slice comes before feature breadth. By hour 12, the team must have a tiny object relaying from Phone A → Phone B → gateway with internet off, even if the UI is ugly and STT is stubbed. Everything else attaches to that spine. 

### **19.2 48-hour plan** 

|**Time**<br>**Dev A - Mesh/Protocol**|**Dev B - App/Product/Gateway**|<br>**Dev C - STT/Inference**|**Integration gate**|
|---|---|---|---|



MeshSetu Technical Development Bible  |  24 

|0-2h|Create modules, permissions,<br>UUIDs, packet contract|Compose shell, event mode,<br>Room DB schema, dashboard<br>skeleton|Prepare 10-20 test clips;<br>benchmark model install paths|Repo builds on all laptops;<br>shared protobuf/domain contract<br>frozen.|
|---|---|---|---|---|
|2-6h|BLE advertise+scan; 2-phone<br>connect; GATT RX/TX|SOS form + outbox; local HTTP<br>dashboard ingest|Run whisper.cpp vs sherpa<br>candidate on target phone;<br>record load/latency/memory|2 phones exchange “HELLO” and<br>one 100-byte object.|
|6-12h|Fragment/reassemble; dedupe;<br>basic store-forward; 3-phone test|Mesh Code manual entry +<br>Rooms UI; dashboard<br>WebSocket cards|Choose STT engine; implement<br>`OflineSttEngine`; transcript<br>from recorded PCM|A→B→C object visible in<br>dashboard; STT returns ofline<br>transcript.|
|12-18h|Priority scheduler; ACK/retry;<br>MTU handling; logs|Voice capture + local fle<br>lifecycle; QR stretch; incident UI|Optimize model<br>threads/quantization; expose<br>timing/model ID; failure fallback|Typed SOS travels 2 hops with<br>measured latency.|
|18-24h|Voice object transport,<br>NACK/retry or completion ACK|Opus MediaCodec pipeline +<br>voice manifest; dashboard audio<br>state|Integrate STT with voice capture;<br>test noisy phrases|Voice clip transcript and encoded<br>bytes linked to same event.|
|24-30h|Security envelope + expiry +<br>replay cache|Triage rules/schema; gateway<br>payload; operator ACK UI|Help build small classifer or<br>extraction rules; evaluate STT<br>keyword recall|Structured SOS frst, voice<br>second; queue preemption<br>proven.|
|30-36h|Beacon zone observation; failure<br>injection hooks|Zone/precursor demo UI; QR if<br>not done; polish status screens|Model packaging/warm-up;<br>performance report and fallback<br>tests|Full no-internet vertical demo<br>succeeds 5 times consecutively.|
|36-42h|Radio stability/device churn;<br>metrics parser|Dashboard polish; demo mode<br>reset/seed buttons|STT edge cases; fnal model<br>checksum/license notes|Freeze features. Only bug fxes<br>after hour 42.|
|42-48h|Run 20+ trials; fx P0 bugs only|Demo choreography, operator<br>screen, backup APK/server|Produce STT benchmark table;<br>support rehearsals|Final rehearsal with airplane<br>mode, physical phones, timer,<br>backup video/logs.|



### **19.3 If only 24 hours are available** 

- Keep manual Mesh Code; defer QR scanner. 

- Use typed + recorded voice SOS but only one chosen STT model. 

- Use completion ACK only; defer missing-chunk bitmap and advanced inventory sync. 

- Use nearest-beacon logical zone; simulate density/precursor inputs. 

- Use rules-first triage; classifier can be a stretch if training threatens integration. 

- Use one laptop dashboard and one gateway phone on local hotspot. 

### **19.4 Build order dependencies** 

`1. Domain/schema freeze -> 2. Durable outbox` 

   - `-> 3. BLE two-phone transfer` 

   - `-> 4. 3-phone store-and-forward` 

   - `-> 5. Priority + retry + metrics -> 6. Voice encoded object` 

   - `-> 7. STT transcript attachment -> 8. Triage structured SOS` 

```
QR, advanced localization, density and visual polish must never block steps 1-8.
```

## **20. Three-person team split and integration contracts** 

### **20.1 Team ownership** 

|**Person**|**Primary ownership**|**Secondary ownership**|**Must not become bottleneck for**|
|---|---|---|---|
|Developer A - Mesh/Protocol|BLE scanner/advertiser, GATT<br>server/client, frame codec,<br>fragmentation/reassembly, relay,<br>scheduler, ACK/retry, metrics, crypto<br>envelope|Beacon discovery, radio failure tests|UI, STT model internals, dashboard<br>styling|
|Developer B - App/Product/Integration|Compose UI, Mesh Code/QR, Rooms,<br>SOS state machine, Room DB,<br>AudioRecord/Opus, gateway HTTP,<br>dashboard, demo fow|Triage integration, playback,<br>event/reset tooling|BLE internals, ASR model optimization|



MeshSetu Technical Development Bible  |  25 

Developer C - STT/On-device inference 

STT model selection, native/ONNX Triage classifier/data/evaluation, BLE transport and general UI integration, preprocessing, model telemetry quantization/threads, offline benchmarks, model packaging, inference adapter 

### **20.2 Frozen interfaces at hour 2** 

```
// Dev A provides
interface MeshTransport {
    val incoming: Flow<ReceivedObject>
    val peerState: StateFlow<List<PeerState>>
    suspend fun send(object: MeshObject): SendTicket
}
// Dev B provides
interface SosRepository {
    suspend fun createDraft(input: SosInput): String
    suspend fun attachTranscript(eventId: String, stt: SttResult)
    suspend fun attachVoice(eventId: String, encoded: EncodedVoice)
    suspend fun finalizeAndEnqueue(eventId: String)
}
// Dev C provides
interface OfflineSttEngine {
    suspend fun warmUp(): Result<Unit>
    suspend fun transcribe(pcm16: ShortArray, sampleRateHz: Int = 16_000): Result<SttResult>
    fun close()
}
```

### **20.3 Daily/periodic merge discipline** 

- No long-lived branches. Merge small vertical commits every 2-3 hours. 

- Any contract change requires a 5-minute team sync and compile fix in all dependent modules immediately. 

- All three developers keep a “known good demo” git tag/commit after each integration gate. 

- No library upgrade after hour 30 unless it fixes a blocking defect. 

   - Feature flags allow STT, voice, triage, QR and precursor UI to be disabled independently for debugging. 

- 

### **20.4 Developer A checklist** 

- Two-way scan/advertise works on every demo phone. 

- GATT server and client coexist without crashes; peer session state is observable. 

- Fragmentation works at multiple synthetic MTUs; voice path has a low-MTU cutoff. 

- Dedupe prevents loops; hop/expiry bounds are enforced. 

- Priority queue demonstrably preempts voice/chat with SOS. 

- Outbox/ACK/retry behavior produces metrics for judges. 

- One debug switch can drop/corrupt frames for failure demo. 

### **20.5 Developer B checklist** 

- Join → Rooms → SOS flow is understandable in under 30 seconds. 

- SOS is persisted before model work begins. 

- AudioRecord captures 16 kHz mono and Opus object is bounded/duration-capped. 

- Gateway sends verified events to local dashboard without internet. 

- Dashboard clearly separates incident priority from zone precursor score. 

- Voice state shows queued/transferring/complete/failed; playback appears only after integrity passes. 

- Demo reset clears only demo data, not required model assets. 

### **20.6 Developer C checklist** 

- One STT engine is selected from measured results, not preference. 

- Model is fully local after installation; no cloud request occurs during inference. 

- Input contract is exactly 16 kHz mono PCM16 or a documented converter exists. 

- Warm-up/load/inference time and model size are recorded. 

- No fake confidence number is emitted if model cannot support it. 

- Critical keyword test set is run and results saved. 

- App can continue when `OfflineSttEngine` returns failure. 

MeshSetu Technical Development Bible  |  26 

- Triage classifier (if built) exports fixed labels/version/model hash and never overrides hard safety rules downward. 

### **20.7 Integration handshake schedule** 

|**Checkpoint**|**Required demo**|
|---|---|
|Hour 6|A↔B 100-byte object + STT model can transcribe one local sample<br>independently.|
|Hour 12|A→B→C relay + STT adapter callable from app.|
|Hour 18|SOS from UI reaches dashboard; voice capture and STT linked locally.|
|Hour 24|Voice encoded/chunked across mesh; metadata preemption shown.|
|Hour 30|Triage card + security envelope + dashboard felds integrated.|
|Hour 36|Full sequence repeated fve times with internet of.|
|Hour 42|Feature freeze; only reliability/presentation work.|



## **21. Demo runbook and definition of done** 

### **21.1 Physical setup** 

- Phone A: citizen sender, microphone permission granted, event manifest loaded. 

- Phone B: relay only; physically placed so it is necessary for the path if possible. 

- Phone C: gateway/receiver connected to laptop’s local hotspot; mobile data disabled. 

- Optional Phone D/E: additional relay or beacon simulator. 

- Laptop: FastAPI dashboard server; browser full-screen operator view. 

- All phones: time approximately synchronized; debug logs enabled; battery >50%. 

### **21.2 90-second technical demo** 

24. Show mobile data/internet disabled. Start active event mode on all phones. 

25. Phone A enters Mesh Code or scans QR and lands in Gate-B/Public Rooms. 

26. Hold voice SOS and say a short emergency phrase such as “I cannot breathe, people are pushing near Gate B.” 

27. On Phone A show local transcript and Structured SOS card. Point out model/triage are on-device. 

28. Show packet animation/status: structured SOS queued at P0/P1; voice evidence below it. 

29. Move/position so Phone B relays. Dashboard receives incident, displays hops/latency/transcript/zone. 

30. While voice is still transferring, inject another SOS or Room message and show priority ordering. 

31. When audio completes, dashboard/gateway shows integrity-verified voice available and plays it. 

32. Show zone precursor score separately and state it is advisory, not auto-dispatch. 

33. Open metrics panel/log summary: delivery trials, latency, encoded size, STT benchmark. 

### **21.3 Definition of done** 

|**Area**|**Pass**|
|---|---|
|Ofline relay|At least 10 consecutive 2-hop structured SOS trials succeed in fnal setup or<br>failures are quantifed and explained.|
|Priority|New structured SOS overtakes queued voice/Room trafic in a controlled<br>test.|
|Voice|Short Opus clip is compressed, chunked, reassembled and integrity-verifed;<br>transcript arrives frst.|
|STT|Chosen model transcribes locally with internet of; benchmark report<br>includes latency/model ID and phrase-set result.|
|Triage|Structured fxed-schema card appears with rationale/confdence; forced<br>model error does not suppress SOS.|



MeshSetu Technical Development Bible  |  27 

|Join/Rooms|Mesh Code loads correct event/Rooms; restricted role behavior is at least<br>simulated and documented.|
|---|---|
|Dashboard|Operator sees event, transcript, priority, zone, hops/latency and audio state.|
|Failure behavior|At least STT failure + relay churn + voice chunk drop are<br>demonstrated/tested.|
|Claims|Slides/docs say “prototype measured result” for measured fgures and avoid<br>standards/certifcation overclaim.|



## **22. Production hardening roadmap** 

### **22.1 After hackathon: protocol** 

- Replace ad-hoc shared site authentication with signed provisioning and per-role/per-room keys. 

- Formalize immutable origin-signed envelope + mutable relay header; fuzz parser and cap allocations. 

- Implement inventory summaries and efficient missing-object synchronization rather than opportunistic push alone. 

- Test dozens/hundreds of nodes in a simulator and progressively larger controlled RF drills. 

- Add embedded relay/beacon firmware and evaluate standards-compliant Bluetooth Mesh / proxy interoperability where it benefits deployment. 

### **22.2 After hackathon: Android reliability** 

- Broaden device/API matrix and document OEM-specific background constraints. 

- Profile battery/thermal impact for hours-long event mode. 

- Add Companion Device / WorkManager/foreground-service strategies appropriate to the actual deployment policy. 

- Implement robust BLE connection concurrency limits and adaptive scan duty cycles. 

- Perform accessibility review and multilingual UI/localization. 

### **22.3 After hackathon: ML** 

- Create governed, consented emergency-phrase evaluation datasets; stratify by language/noise/device. 

- Calibrate STT and triage uncertainty; keep original evidence available to operators. 

- Evaluate model update signatures, rollback and offline model-package distribution. 

- Validate triage with emergency-domain experts before field use; keep automation advisory unless explicitly authorized. 

- Run on-device profiling across CPU/GPU/NPU variants; select runtime/model per device class if needed. 

### **22.4 After hackathon: public-sector integration** 

- Define signed authority API adapter instead of direct coupling to one emergency system. 

- Add deployment manifest tooling: site geometry, beacon IDs, rooms, escalation contacts, model versions and retention policies. 

- Create audit/export format for incident timeline and operator actions. 

- Complete threat model, privacy impact assessment, DPDP/legal review and retention policy before real-event deployment. 

- Run drills with local authorities before any public mass deployment. 

## **Appendix A. Reference code snippets** 

### **A.1 Feature flags** 

```
data class FeatureFlags(
    val qrJoin: Boolean = true,
    val voice: Boolean = true,
    val stt: Boolean = true,
    val triageModel: Boolean = true,
    val beaconZone: Boolean = true,
    val precursor: Boolean = true,
)
```

MeshSetu Technical Development Bible  |  28 

### **A.2 SOS orchestration use case** 

```
class SubmitVoiceSos(
    private val repo: SosRepository,
    private val stt: OfflineSttEngine,
    private val encoder: VoiceEncoder,
    private val triage: TriageEngineImpl,
) {
    suspend operator fun invoke(pcm: ShortArray, zoneHint: String?): String = coroutineScope {
        val eventId = repo.createDraft(SosInput.Voice(zoneHint)) // persisted FIRST
        val sttJob = async { stt.transcribe(pcm) }
```

```
        val voiceJob = async { encoder.encodeOpus(pcm, 16_000) }
```

```
        val sttResult = sttJob.await().getOrNull()
        if (sttResult != null) repo.attachTranscript(eventId, sttResult)
```

```
        val structured = triage.triage(sttResult?.text.orEmpty())
        repo.attachTriage(eventId, structured)
```

```
        val encoded = voiceJob.await()
        repo.attachVoice(eventId, encoded)
        repo.finalizeAndEnqueue(eventId)
        eventId
    }
}
```

If STT fails, the orchestration must still attach the raw voice evidence and a fallback structured record such as `incidentType=OTHER`, `priority=P1_HIGH` for an explicit emergency button, with `missingInfo=[transcript]`. Product policy should decide the safe fallback band. 

### **A.3 Priority-aware per-peer sender loop** 

```
suspend fun PeerSession.sendLoop() {
    while (isActive) {
        val next = scheduler.nextFor(peerId) ?: run { delay(80); continue }
        val frames = fragment(next.objectId.toULong(), next.trafficClass.rank.toUByte(), next.bytes, mtu)
        for (frame in frames) {
            if (scheduler.hasHigherPriorityThan(next.trafficClass)) break // preempt between chunks
            awaitWritable()
            writeNoResponse(gatt, rxCharacteristic, frameCodec.encode(frame))
            metrics.frameTx(next.objectId, frame.sequence.toInt())
        }
    }
}
```

### **A.4 Missing chunk bitmap** 

```
fun missingBitmap(count: Int, received: BooleanArray): ByteArray {
    val out = ByteArray((count + 7) / 8)
    for (i in 0 until count) if (!received[i]) out[i / 8] = (out[i / 8].toInt() or (1 shl (i % 8))).toByte()
    return out
}
```

### **A.5 Site fingerprint** 

```
fun siteFingerprint(siteId: String, namespace: String): ByteArray {
    val digest = MessageDigest.getInstance("SHA-256").digest("$siteId|$namespace".toByteArray())
    return digest.copyOfRange(0, 6) // discovery hint only; NOT a secret or authentication token
}
```

### **A.6 RSSI debug panel model** 

```
data class PeerDebug(
    val id: String,
    val rssi: Int,
    val mtu: Int,
    val connected: Boolean,
    val queuedObjects: Int,
    val lastSeenMs: Long,
)
```

### **A.7 Trace timing** 

```
data class TraceStamp(val name: String, val elapsedRealtimeMs: Long)
```

```
class EventTrace(val eventId: String) {
    private val stamps = mutableListOf<TraceStamp>()
    fun mark(name: String) { stamps += TraceStamp(name, SystemClock.elapsedRealtime()) }
    fun delta(from: String, to: String): Long? {
        val a = stamps.lastOrNull { it.name == from }?.elapsedRealtimeMs ?: return null
        val b = stamps.lastOrNull { it.name == to }?.elapsedRealtimeMs ?: return null
        return b - a
```

MeshSetu Technical Development Bible  |  29 

```
    }
}
```

### **A.8 Python log summary** 

```
# tools/log_parser.py
import json, statistics, sys
rows=[json.loads(x) for x in open(sys.argv[1], encoding='utf8') if x.strip()]
lat=[r['value'] for r in rows if r.get('kind')=='relay_latency_ms' and r.get('value') is not None]
print('trials', len(lat))
if lat:
    print('median_ms', statistics.median(lat))
    print('max_ms', max(lat))
    if len(lat)>=20:
        s=sorted(lat); print('p95_ms', s[int(.95*(len(s)-1))])
```

### **A.9 Triage test examples** 

```
val cases = listOf(
  "I cannot breathe, people are pushing near Gate B" to PriorityBand.P0_CRITICAL,
  "A person is unconscious near the stairs" to PriorityBand.P0_CRITICAL,
  "Small cut, need first aid" to PriorityBand.P2_NORMAL,
  "My child is missing near the north gate" to PriorityBand.P1_HIGH,
  "The queue is getting dense but no one is injured" to PriorityBand.P2_NORMAL,
)
```

### **A.10 Debug frame-loss interceptor** 

```
class LossyTransport(private val delegate: FrameTransport, private val dropEvery: Int) : FrameTransport {
    private var n = 0
    override suspend fun send(frame: ByteArray): Boolean {
        n++
        if (dropEvery > 0 && n % dropEvery == 0) return true // pretend sent; used only in debug tests
        return delegate.send(frame)
    }
}
```

## **Appendix B. Command and debugging cheat sheet** 

### **B.1 Android build** 

```
./gradlew clean :app:assembleDebug
./gradlew test
./gradlew connectedAndroidTest
adb devices
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb logcat | grep -i MeshSetu
```

### **B.2 Dashboard** 

```
cd dashboard
python -m venv .venv
# macOS/Linux: source .venv/bin/activate
# Windows: .venv\\Scripts\\activate
pip install fastapi "uvicorn[standard]"
uvicorn main:app --host 0.0.0.0 --port 8080 --reload
```

### **B.3 Network check** 

```
# Laptop local IP (examples only)
ipconfig        # Windows
ifconfig        # macOS/Linux
# From Android device connected to same hotspot, dashboard URL is:
http://<LAPTOP_LAN_IP>:8080
```

### **B.4 BLE debugging reminders** 

- Keep screen/dev debug panel showing Bluetooth enabled, advertising, scanning, peers, GATT state, MTU and queue length. 

- If connect fails: log status code, close GATT, back off, retry. Do not reuse a dead `BluetoothGatt` instance. 

- If frames stall: check write-without-response pacing; some stacks require a small credit/delay strategy. 

- If voice destroys latency: lower bitrate/duration, reduce fan-out, increase SOS preemption, or disable voice on low-MTU peers. 

- If relay loops: inspect dedupe cache, event/object ID generation and whether re-encryption creates a new object ID each hop. Preserve origin object identity across hops. 

MeshSetu Technical Development Bible  |  30 

### **B.5 STT debugging** 

- Always log model ID/hash, load ms, inference ms, PCM sample count, sample rate and thread count. 

- Validate PCM amplitude and duration before blaming the model. 

- Whisper-style models generally expect 16 kHz audio; resample explicitly if source differs. 

- Benchmark airplane mode to prove local inference. 

- Thermal throttling can make repeated inference slower; include warm/cold and repeated runs. 

## **Appendix C. Official documentation index** 

Use these links as the source of truth while implementing. The architecture deliberately relies on primary/official documentation rather than random tutorials. Versions/APIs can change after this document date. 

**[SRC-A01] Android BLE overview:** <u>https://developer.android.com/develop/connectivity/bluetooth/ble/ble-overview</u> **[SRC-A02] Android BLE in the background:** <u>https://developer.android.com/develop/connectivity/bluetooth/ble/background</u> 

**[SRC-A03] Android BluetoothGatt / MTU API:** <u>https://developer.android.com/reference/android/bluetooth/BluetoothGatt</u> 

**[SRC-A04] Android Bluetooth permissions:** <u>https://developer.android.com/develop/connectivity/bluetooth/bt-permissions</u> 

**[SRC-A05] Android supported media formats (Opus encode/decode):** <u>https://developer.android.com/media/platform/supportedformats</u> 

**[SRC-A06] Android BLE scanning guidance:** <u>https://developer.android.com/develop/connectivity/bluetooth/ble/fnd-ble-devices</u> **[SRC-A07] Android AudioRecord API:** <u>https://developer.android.com/reference/kotlin/android/media/AudioRecord</u> 

**[SRC-A08] Android foreground services / connected-device type:** <u>https://developer.android.com/develop/background-work/services/fgs/service-types</u> 

**[SRC-A09] Room persistence library:** <u>https://developer.android.com/training/data-storage/room</u> 

**[SRC-A10] Jetpack Compose BOM:** <u>https://developer.android.com/develop/ui/compose/bom</u> 

**[SRC-A11] AndroidX Activity releases:** <u>https://developer.android.com/jetpack/androidx/releases/activity</u> 

**[SRC-A12] AndroidX Lifecycle releases:** <u>https://developer.android.com/jetpack/androidx/releases/lifecycle</u> 

**[SRC-A13] Hilt on Android:** <u>https://developer.android.com/training/dependency-injection/hilt-android</u> 

**[SRC-A14] Android app architecture:** <u>https://developer.android.com/topic/architecture</u> 

**[SRC-A15] Kotlin coroutines on Android:** <u>https://developer.android.com/kotlin/coroutines</u> 

**[SRC-B01] Bluetooth SIG Mesh FAQ / concepts:** <u>https://www.bluetooth.com/learn-about-bluetooth/feature-enhancements/mesh/</u> - **[SRC-B02] Bluetooth Mesh Protocol specification landing page:** <u>https://www.bluetooth.com/specifcations/specs/mesh protocol/</u> - **[SRC-O01] Opus codec official site:** <u>https://opus codec.org/</u> 

**[SRC-O02] IETF/RFC 6716 - Opus codec:** <u>https://www.rfc-editor.org/rfc/rfc6716</u> 

**[SRC-O03] libopus encoder API:** <u>https://opus-codec.org/docs/opus_api-1.6/group__opus__encoder.html</u> 

- **[SRC-S01] whisper.cpp official GitHub:** <u>https://github.com/ggml org/whisper.cpp</u> 

- **[SRC-S02] sherpa-onnx official documentation:** <u>https://k2 fsa.github.io/sherpa/onnx/</u> 

**[SRC-M01] LiteRT for Android:** <u>https://ai.google.dev/edge/litert/android</u> 

**[SRC-M02] LiteRT CompiledModel Kotlin API:** <u>https://ai.google.dev/edge/litert/next/android_kotlin</u> 

**[SRC-M03] ONNX Runtime NNAPI execution provider:** <u>https://onnxruntime.ai/docs/execution-providers/NNAPI-</u> 

#### <u>ExecutionProvider.html</u> 

**[SRC-G01] ML Kit barcode scanning on Android:** <u>https://developers.google.com/ml-kit/vision/barcode-scanning/android</u> 

**[SRC-G02] CameraX image analysis:** <u>https://developer.android.com/media/camera/camerax/analyze</u> 

- **[SRC-P01] Protocol Buffers Kotlin generated code guide:** <u>https://protobuf.dev/reference/kotlin/kotlin generated/</u> 

**[SRC-C01] Android Keystore:** <u>https://developer.android.com/privacy-and-security/keystore</u> 

**[SRC-W01] FastAPI WebSockets:** <u>https://fastapi.tiangolo.com/advanced/websockets/</u> 

**[SRC-K01] Kotlin releases:** <u>https://kotlinlang.org/docs/releases.html</u> 

### **C.1 Foundational MeshSetu documents** 

The original MeshSetu research paper defines the five-layer architecture, multi-hop SOS, beacon-referenced localization, privacy-preserving density, precursor scoring, authority bridge, evaluation metrics and human-in-the-loop constraints. The 

MeshSetu Technical Development Bible  |  31 

later product-content bible adds Mesh Code, Rooms, local Speech-to-Text + compressed voice-note relay and on-device triage. Treat the research paper as architectural foundation and this technical bible as the implementation contract for the MVP. 

Local project source files used while preparing this document: `MeshSetu Research Paper.pdf` and 

`MeshSetu_PPT_Master_Content_Bible_Research_Evidence_Updated.docx`. 

## **Final engineering checklist** 

**☐** One README command gets Android app building on all developer machines. 

**☐** Physical BLE 2-hop vertical slice works before polish. 

**☐** No Text-to-Speech code, UI or claim exists. 

**☐** Voice clip is bounded, compressed, chunked and store-and-forward; no live stream claim. 

**☐** Offline STT model is packaged/tested and has a measured benchmark on real phones. 

**☐** Structured SOS is durable and prioritized ahead of voice/chat. 

**☐** Triage is schema-constrained, conservative and cannot suppress a user-triggered SOS. 

**☐** Mesh Code is bootstrap/namespace UX, not a short cryptographic key. 

**☐** Rooms have ACL/priority/TTL policy; responder traffic is not exposed to public users in production design. 

**☐** Every object has ID, creation/expiry, site/room scope and integrity protection. 

**☐** Dedupe/TTL prevents infinite relay loops. 

**☐** Low MTU / STT failure / audio failure / relay churn all have visible graceful-degradation behavior. 

**☐** Dashboard works on local LAN with internet disabled. 

**☐** Final demo report includes actual delivery, latency, voice-size and STT measurements. 

**☐** Unknown fourth product feature remains a documented extension point, not an invented claim. 

MeshSetu Technical Development Bible  |  32 
