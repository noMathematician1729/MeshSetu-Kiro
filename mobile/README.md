# MeshSetu mobile

This is the Flutter/Android implementation of the MeshSetu BLE relay. The
protocol and relay engine can be tested without a radio; the event-mode screen
also wires the Android peripheral and central BLE roles.

## Toolchain

- Flutter with Dart 3.12 or newer (Flutter 3.47 is the verified toolchain)
- Android SDK platform 36
- Android API 29 minimum device version

From this directory:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Debug builds use Bluetooth SIG's testing company ID. Release builds require
MeshSetu's assigned 16-bit Company Identifier:

```sh
flutter build apk --release \
  --dart-define=MESHSETU_BLE_COMPANY_ID=0x1234
```

Replace `0x1234` with the identifier assigned to MeshSetu. The release build
fails before compilation when the define is missing, invalid, or `0xFFFF`.
Discovery, SOS, and beacon advertisements share that company ID and use a
MeshSetu payload-type byte to distinguish their records.

The app requests Bluetooth and notification permissions before starting event
mode. The foreground notification can be stopped from the screen; the BLE
controller and its metrics sink are stopped with it.
