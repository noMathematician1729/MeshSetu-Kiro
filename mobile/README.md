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

The app requests Bluetooth and notification permissions before starting event
mode. The foreground notification can be stopped from the screen; the BLE
controller and its metrics sink are stopped with it.
