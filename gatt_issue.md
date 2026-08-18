# MeshSetu GATT transport audit and repair

## Scope and conclusion

This audit follows the Android phone-to-phone path, independently of the
dashboard, ngrok, STT, rooms, and gateway forwarding. A dashboard request is
made only after a device has received and persisted an SOS; it cannot make a
missing BLE GATT connection succeed.

The repository now has an explicit client lifecycle, server-side admission
checks, callback-backed native completions, per-session GATT operation
serialization, durable scheduler wake-up, and transport diagnostics. The
automated code-level proof is green. No physical Android phones were attached
to this audit, so radio/OEM behavior remains an explicit verification step.

The most important interpretation remains:

```text
advertisement accepted != GATT connected != MeshSetu peer READY
```

## Actual MeshSetu GATT contract

The UUIDs are defined in `mobile/lib/core/ble/mesh_gatt.dart`:

```text
Service  2a6f5f10-4f7b-4c46-8cc8-cf282e4f4c01
RX       2a6f5f11-4f7b-4c46-8cc8-cf282e4f4c01
TX       2a6f5f12-4f7b-4c46-8cc8-cf282e4f4c01
CCCD     00002902-0000-1000-8000-00805f9b34fb
```

There is no separate CTRL characteristic in this repository. HELLO, ACK,
NACK, inventory, and other control frames use the same RX/TX transport.

For one logical connection, for example:

```text
Phone A = GATT client
Phone B = GATT server

A -> B: BluetoothGatt write to B's RX
       -> B's onCharacteristicWriteRequest

B -> A: B's TX notification
       -> A's onCharacteristicChanged
```

Both phones still advertise a server and can initiate a client connection;
the roles above describe one established connection, not permanent device
roles.

The actual service builder declares:

```text
RX: WRITE
TX: NOTIFY
```

The vendored Android peripheral plugin adds the CCCD to a notifiable
characteristic when it constructs the native service. The client now verifies
that the discovered remote TX characteristic really contains that CCCD before
it can become READY.

## What was confirmed

### Discovery was being over-interpreted

`scan_peers_accepted`/`scan_found` proves that the MeshSetu advertisement was
parsed and its site fingerprint was accepted. It does not prove any of the
following:

```text
connectGatt succeeded
services discovered
MeshSetu service exists remotely
RX is writable
TX is notifiable
CCCD write succeeded
peer session is attached
an RX frame reached the remote server
an object was reassembled or delivered
```

The UI now retains GATT and connection metrics separately from scan metrics,
so a later `scan_found` cannot hide `discover_services_failed`,
`cccd_write_failed`, or `send_failed`.

### The old client readiness check was too weak

The old `GattPeerSession` awaited `discoverServices()` and
`subscribeNotifications()` and then marked the peer ready. It did not inspect
the returned service database. Consequently, a successful API future could
still produce a false-ready peer when the remote service, RX, TX, property, or
CCCD was wrong or missing.

This was a confirmed code defect. The client now rejects the session with an
exact phase error such as:

```text
mesh_service_missing
rx_characteristic_missing
rx_not_writable:0x...
tx_characteristic_missing
tx_not_notifiable:0x...
cccd_missing
```

### CCCD completion was not a reliable contract

The vendored Android plugin previously treated a missing CCCD as a successful
notification setup. That could make the Dart session continue even though no
remote notification subscription existed. The native implementation now:

```text
setCharacteristicNotification
  -> find CCCD
  -> register pending future before writeDescriptor
  -> write ENABLE_NOTIFICATION_VALUE
  -> wait for onDescriptorWrite
  -> complete only on GATT_SUCCESS
```

The server handles and logs the corresponding descriptor subscription and
tracks the subscribed device. The MeshSetu server will not accept RX frames
from a device that has not subscribed to TX.

### Operation completion is callback completion, not API return

Android calls such as `requestMtu`, `discoverServices`,
`setCharacteristicNotification`/CCCD write, and characteristic write are
asynchronous. The native future lists are now registered before issuing the
platform operation, synchronized across main/binder threads, and completed by
their matching callbacks.

The original Dart calls were already written as sequential `await`s, and the
vendored command queue was already serial by default. Therefore this audit did
not find proof that MTU and service discovery were overlapping on the reported
phones. It did find that the sequencing guarantee was implicit and unsafe if a
different queue mode or a missing callback was introduced. The repair makes the
invariant explicit:

```text
one GattPeerSession
  -> one operation lock
  -> one ordered setup/write pipeline
  -> one phase-specific timeout
```

A normal MTU status failure is best-effort and falls back to effective MTU 23.
A missing MTU callback is different: the native request may still be active,
so the session fails rather than starting service discovery on top of it.
Write/setup timeouts fail the session and allow the coordinator to detach and
reconnect it instead of silently issuing another operation over a possibly
busy GATT object.

### Early TX notifications could be lost

The old coordinator attached the notification listener only after
`awaitReady()`. The server can send HELLO, ACK, or queued control immediately
after CCCD completion, which is before the coordinator necessarily attaches
the link. The client session now subscribes to the native TX stream at session
construction and buffers values until the transport listener attaches. This
closes the setup-to-attach notification race without changing the wire format.

### The application scheduler had no event-driven peer wake-up

The durable outbox correctly retained an object when there were no usable
peers, but attaching a peer did not directly wake `_pump()`. The scan loop's
periodic `tick()` eventually retried it, which made a successful connection
look like a stuck outbox and widened the timing window around the first frame.

`MeshTransportCoordinator.attach()` now emits `peer_count_changed` and wakes
the relay scheduler when a durable object is already queued. The scheduler's
priority order is unchanged. `peers = 0` still means “retain locally and wait,”
not “discard.”

### Service registration was checked separately from advertising

At the audited HEAD, Dart already waited for the asynchronous `serviceAdded`
event before the event controller called `MeshAdvertiser.start()`, so this was
not confirmed as the current phones' root cause. The implementation was
hardened anyway: it uses an explicit completer/listener, verifies the service
UUID and error, reports `gatt_service_added`/`gatt_server_ready`, and clears
handlers/subscriptions/services on failure. A test proves startup remains
pending until `serviceAdded` and fails without reporting a ready server.

### The durable submit acknowledgement was an earlier real bug

The foreground BLE task previously accepted an outbox object but did not
return `mesh_submit_result`, causing the caller to time out and return the
durable row to `ready`. That issue was fixed in the earlier application work
and is preserved here. The semantics are:

```text
accepted = true  => accepted into this device's local transport queue
accepted = true  != remote delivery
```

Remote delivery still requires frame writes, remote RX processing, reassembly,
verification, and an application ACK.

## Final state machine

`mobile/lib/core/ble/gatt_peer_session.dart` is the authoritative client
state machine:

```text
DISCOVERED
  -> CONNECTING                 UniversalBle.connect completes connected
  -> CONNECTED                  connection stream reports true
  -> MTU_NEGOTIATING            requestMtu starts
  -> CONNECTED/MTU_EFFECTIVE   onMtuChanged success, or safe MTU-23 fallback
  -> SERVICE_DISCOVERY          discoverServices starts
  -> ATTRIBUTES_VALID           onServicesDiscovered result validates service,
                                RX, TX properties, and CCCD
  -> SUBSCRIBING                local notification enable + CCCD write starts
  -> READY                      onDescriptorWrite success completes future
  -> SCHEDULER_VISIBLE          coordinator.attach()
  -> TRANSMITTING               serialized RX characteristic writes
  -> DISCONNECTED/FAILED        connection callback, error, or phase timeout
```

The application scheduler sees only `SCHEDULER_VISIBLE` links. A scan result,
bare connection, service discovery, or local notification flag is not enough.

## GATT operation scheduler

The per-session operation lock covers:

```text
request MTU
discover services
write/enable TX CCCD
write MeshSetu RX frames
```

Each operation emits `gatt_operation_queued`, `gatt_operation_started`, then
`gatt_operation_completed` or `gatt_operation_failed`. The native plugin
matches completion callbacks to the pending operation and now reports:

```text
MTU_CHANGED
SERVICES_DISCOVERED
CCCD_WRITE_COMPLETE
WRITE_FAILED
GATT_CONNECTED_FAILED
```

The operation queue is deliberately separate from the MeshSetu traffic
scheduler. The first orders Android API operations; the second retains and
prioritizes application objects:

```text
CONTROL_ACK > SOS_STRUCTURED > AUTHORITY_CONTROL
             > VOICE_EVIDENCE > ROOM_MESSAGE > TELEMETRY
```

An Android “busy”/write failure is surfaced with its operation and peer
context. It is not converted into remote delivery success.

## Server-side lifecycle

`MeshGattServer` now has the complementary path:

```text
GATT_SERVER_OPEN
  -> GATT_SERVICE_ADD_REQUESTED
  -> GATT_SERVICE_ADDED
  -> GATT_SERVER_READY
  -> advertising is started by MeshEventController
  -> server connection callback
  -> server CCCD subscription callback
  -> server peer admitted
  -> RX write request
  -> quick copy/enqueue into the async relay pipeline
```

The Android native server logs and reports:

```text
GATT_SERVER_CONNECTION
CCCD_WRITE_REQUEST
SERVER_NOTIFICATION_SUBSCRIBED
RX_WRITE_REQUEST
TX_NOTIFY_COMPLETE
```

The Dart server emits diagnostics without doing decrypt, database, or voice
work inside the native callback. `notifyAwait()` waits for Android's
`onNotificationSent` status; that proves the local server stack accepted the
notification, not that the application object has been delivered remotely.

## Bidirectional transport proof

The automated tests prove both directions independently at the transport
boundary:

```text
client write RX
  -> fake/server write-request handler
  -> gatt_rx_frame/frame_rx metric

server TX notification
  -> notification-sent completion
  -> client TX stream receives the value
```

The client lifecycle test also injects a TX value during CCCD completion and
asserts that the session's buffered `incoming` stream receives it. This is a
regression test for the early-notification race.

No physical-device result is claimed here. The two-phone test procedure below
must confirm the same transitions with real Android callbacks.

## Delivery semantics

The UI/metrics now distinguish these stages:

```text
LOCAL_QUEUED                 durable outbox/scheduler accepted the object
PEER_AVAILABLE               a validated READY session is attached
FRAME_WRITE_STARTED          write to remote RX was requested
FRAME_WRITE_ACCEPTED_LOCALLY Android/Dart write future completed successfully
REMOTE_FRAME_RECEIVED        server onCharacteristicWriteRequest accepted it
OBJECT_REASSEMBLED           all fragments joined
OBJECT_VERIFIED              decrypt/authentication succeeded
OBJECT_RECEIVED              durable inbox/application persistence completed
REMOTE_ACK                   protocol ACK frame was received
```

`frames_sent` now explicitly says `local_writes_accepted_waiting_for_ack`; it
does not claim that the remote application has delivered the SOS.

## Compact SOS fallback remains separate

The compact advertisement path is intentionally independent:

```text
SOS pressed
  ├─ compact advertisement -> nearby scanner -> immediate alert notification
  └─ encrypted rich envelope -> durable outbox -> GATT -> inbox/gateway
```

The compact test alert can therefore prove nearby BLE advertisement reception
even with `peers = 0`. It must not be used as evidence that GATT service
discovery, CCCD subscription, RX writes, or rich-object delivery works. A
matching rich object is deduplicated so it does not create a second popup.

## Files changed

| File | Change | Reason |
| --- | --- | --- |
| `mobile/lib/core/ble/gatt_peer_session.dart` | Explicit client states, attribute validation, buffered TX stream, operation lock, phase timeouts, lifecycle metrics | Prevent false READY state, lost early notifications, overlapping/stuck operations |
| `mobile/lib/core/ble/gatt_server.dart` | Callback-driven service registration cleanup, connection-aware admission, RX/TX diagnostics, notification completion status | Make the server lifecycle and subscription boundary observable and safe |
| `mobile/lib/core/ble/mesh_gatt.dart` | Central CCCD UUID | Validate the actual remote TX descriptor |
| `mobile/lib/core/ble/mesh_transport.dart` | READY/count metrics, scheduler wake, frame/object write metrics | Wake durable traffic when a peer becomes usable and separate local/remote semantics |
| `mobile/lib/core/protocol/relay_engine.dart` | Reassembly, verification, and receipt metrics | Locate failures after GATT RX |
| `mobile/lib/app/mesh_event_controller.dart` | Forward lifecycle metrics, debug native BLE logging, advertising/peer metrics, longer final guard | Make physical diagnosis possible without changing protocol behavior |
| `mobile/lib/app/event_mode_screen.dart` | Preserve GATT/server failures as the connection diagnostic | Stop later scan events hiding the failure |
| `mobile/third_party/universal_ble/android/.../UniversalBlePlugin.kt` | Callback future synchronization, missing-CCCD failure, status checks, lifecycle logs, case-insensitive device matching | Correct Android GATT client completion behavior |
| `mobile/third_party/universal_ble/android/.../UniversalBlePeripheralPlugin.kt` | Server connection/CCCD/RX/TX/service logs and failed-connection cleanup | Correct Android GATT server observability and cleanup |
| `mobile/third_party/universal_ble/android/.../UniversalBleHelper.kt` | Case-insensitive GATT lookup | Avoid address casing losing an existing connection |
| `mobile/test/core/ble/gatt_peer_session_test.dart` | Setup ordering, early TX buffering, missing CCCD, MTU timeout, CCCD failure tests | Lock down the client state machine |
| `mobile/test/core/ble/gatt_server_test.dart` | Delayed and failed service registration tests | Prove advertising cannot be treated as ready before service registration |
| `mobile/test/core/ble/mesh_gatt_test.dart` | RX/TX property and CCCD contract assertions | Lock down the attribute model |
| `mobile/test/core/ble/mesh_transport_test.dart` | Scheduler wake and server RX direction tests; existing TX notification tests retained | Prove scheduler and both transport directions |

## Tests run

```text
flutter analyze --no-pub                         PASS
flutter test --no-pub --reporter expanded        PASS (84 tests)
flutter test ...gatt...                          PASS (33 focused GATT/transport tests after final additions)
flutter build apk --debug --no-pub               PASS
```

The debug artifact is:

```text
mobile/build/app/outputs/flutter-apk/app-debug.apk
```

The tests are platform fakes and protocol tests. They prove callback ordering,
state transitions, queue retention, frame direction, and post-GATT processing;
they do not prove Android radio behavior.

## Physical two-phone verification

Install the debug APK on two physical Android phones. On both phones:

1. Grant Nearby devices/Bluetooth and notification permissions.
2. Enable Bluetooth and location services as required by the Android version.
3. Start event mode and leave it running on both phones.
4. In a debug build, native `UniversalBle` logging is enabled at debug level.
   Use `adb logcat -s UniversalBle UniversalBlePeripheral` if the device is
   attached to ADB; the app also writes structured metrics to
   `mesh-metrics.ndjson` in its application documents directory.
5. Wait for `gatt_server_ready` and `advertising_started` on both devices.
6. On the deterministic initiator, expect this order:

```text
peer_discovered
connect_initiated
gatt_connected
mtu_requested
mtu_changed                 (or mtu_failed, effective MTU 23)
service_discovery_started
services_discovered
mesh_service_found
rx_characteristic_found
tx_characteristic_found
cccd_found
cccd_write_started
server_descriptor_write_request   (on the other phone)
server_notification_subscribed   (on the other phone)
cccd_write_complete
peer_session_ready
peer_count_changed 0->1
scheduler_wake                  (when an object was already queued)
```

7. Send a valid rich SOS. On the sender, expect
   `scheduler_selected_object`, `scheduler_selected_peer`,
   `frame_write_started`, and `frame_write_api_result: accepted_locally`.
8. On the receiver, expect `gatt_rx_frame`, `frame_rx`, then
   `object_reassembled`, `object_verified`, `object_received`, and eventually
   `ack`/`REMOTE_ACK` behavior.
9. Separately exercise the compact SOS test. Its notification proves only the
   advertisement fallback and should work even if GATT remains unavailable.

Failure localization is the first missing transition. Examples:

```text
accepted advertisement, no gatt_connected
  -> connection/initiator/permission/radio problem

gatt_connected, no services_discovered
  -> GATT operation/native callback/timeout problem

services_discovered, no cccd_write_complete
  -> service/characteristic/CCCD or descriptor write problem

peer_session_ready, no gatt_rx_frame on receiver
  -> scheduler/write/server admission problem

gatt_rx_frame, no object_reassembled
  -> frame codec/fragment/reassembly problem

object_received, no popup
  -> application notification/deduplication problem, not GATT
```

Do not report a physical result as passed unless both devices show the
corresponding logs. This repository state has not had that hardware run in the
current audit environment.

## Remaining risks

- Android OEM Bluetooth stacks can still drop callbacks or reject concurrent
  physical connections; the session now fails and reconnects instead of
  silently treating them as READY.
- Background execution, notification permission, battery optimization, and
  Android foreground-service policy still need validation on the target OEM.
- The compact SOS manufacturer IDs are development IDs and its alert is not a
  replacement for authenticated rich payload delivery; production needs the
  assigned company ID and its security/rate-limit policy.
- The dashboard/gateway path is downstream of BLE receipt and was not used as
  a transport dependency in this repair.
