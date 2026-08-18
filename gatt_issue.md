# GATT SOS delivery issue

## Summary

The sender could discover the other phone, but that did not create a BLE data
connection. The SOS entered the MeshSetu GATT scheduler, which correctly kept
it queued because it had no usable peer session. No frames reached the receiver,
so the receive callback and notification code could not run.

This was not caused by the dashboard, ngrok, internet, or gateway server.
Those run only after a device has received an SOS over BLE.

## Why `accepted 1` was misleading

The screen showed states such as:

```text
Scan: ... accepted 1
Mesh: scanning / idle · peers: 0
Last object: none
Last metric: scan_found
```

`accepted 1` means only that the scanner saw MeshSetu advertisement metadata
whose site fingerprint passed validation. It does not prove a GATT connection,
service discovery, notification subscription, frame write, or object receipt.

`peers: 0` and `Last object: none` prove there was no transport link. The SOS
could not leave the local scheduler through GATT at that point.

## Original rich-SOS path

```text
SOS screen
  -> Drift outbox
  -> OutboxSender
  -> foreground-task isolate
  -> MeshTransportCoordinator scheduler
  -> GATT peer session
  -> remote GATT RX characteristic
  -> frame reassembly / decrypt / durable inbox
  -> notification and optional gateway/dashboard forwarding
```

Before a queued object can be written, one device must complete:

```text
scan accepted
  -> initiator selected from advertising tokens
  -> connect
  -> request MTU
  -> discover services
  -> subscribe to TX notifications
  -> attach peer session
  -> scheduler writes fragmented frames
```

The scheduler intentionally returns without sending when its peer-session map
is empty. It preserves the encrypted object for a later connection. This was
safe behavior, but it looked broken because the UI hid the connection failure.

## Problems found

### Connection failures were overwritten in the UI

The controller emitted `peer_connect_failed` with the exact failed phase
(`connect`, `discover_services`, or `subscribe_notifications`). Each later
scan emitted `scan_found`, and the UI stored only one `Last metric`, replacing
the useful failure with scan status.

The UI now keeps a separate **Connection** value for connection and write
failures.

### GATT service registration had a startup race

Android registers a GATT service asynchronously. The previous code called
`addService()` and began advertising immediately. A nearby phone could connect
and discover services before Android had published MeshSetu's GATT service.
That causes discovery/subscription failure and leaves `peers: 0`.

The server now waits for the native `serviceAdded` event before event mode
starts advertising.

### The durable outbox never got submission acknowledgement

`MeshBridgeClient` sends an envelope to the foreground BLE task and waits for
`mesh_submit_result`. The task previously called the scheduler but never sent
that result. After ten seconds the outbox assumed failure and returned the row
to `ready`, even if the scheduler had accepted it. This produced repeated sends
and misleading outbox state.

The foreground task now replies with `accepted: true` after scheduler acceptance
or a specific failure reason. Acceptance means *locally queued*, not delivered:
remote delivery still needs a GATT peer.

### The 100-byte test could never show an SOS popup

The old test sent padded text while marking it `structuredSos`. The notification
code correctly attempts to decode a real JSON `StructuredSosPayload`; it rejects
the padded test text. Therefore even a successful GATT delivery of the old test
would not show an SOS notification.

## Implemented reliability fix

MeshSetu now uses the proven Ceal-style idea for the emergency alert while
retaining GATT for rich data:

```text
Real SOS
  -> immediately advertise compact BLE SOS alert for 12 seconds
  -> receiving scanner validates CRC, site ID, TTL, and deduplicates it
  -> receiver displays high-priority SOS notification
  -> full encrypted voice/GPS SOS independently remains queued for GATT
```

The compact alert is 14 bytes:

```text
version | site fingerprint | sender ID | sequence | flags | TTL | CRC-8
```

It deliberately contains no voice, transcript, or precise GPS. Those remain in
the encrypted GATT envelope. The user-visible alert therefore no longer waits
for GATT connect, MTU negotiation, service discovery, subscription, or a frame
write to succeed.

The test button is now **Send BLE SOS notification test**. It sends the compact
test alert, which causes the receiver to show `TEST SOS RECEIVED` even when the
GATT peer count is zero.

When the matching rich envelope later arrives through GATT, the app avoids a
duplicate popup and continues normal durable-inbox and gateway processing.

## Verification procedure

1. Install the new debug APK on two physical Android phones.
2. Grant Nearby devices and Notifications permissions on both phones.
3. Start event mode on both; background the receiving app.
4. Press **Send BLE SOS notification test** on the sender.
5. During the 12-second advertising window, the receiver must show
   `TEST SOS RECEIVED`, even if it still shows `peers: 0`.
6. Send a real voice/GPS SOS. The receiver must immediately show
   `SOS RECEIVED`. If GATT succeeds it will later show `object_received` and
   process rich payload data.
7. For any GATT problem, read the new **Connection** field. It now retains the
   failing stage instead of being replaced by `scan_found`.

## Production note

The compact fallback is an unauthenticated emergency alert using development
manufacturer identifiers. It proves the Android radio path; production needs
an assigned Bluetooth company identifier plus authenticated/rate-limited alert
policy.
