# MeshSetu

Android-first, offline emergency communication over a BLE store-and-forward overlay.

## Build and test

The local build baseline is JDK 17, Android SDK 36, AGP 8.13, Kotlin 2.2, and Gradle 8.13. SDK 37 was not available from the configured SDK repository, so `compileSdk` remains 36 until that platform is installed.

```bash
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
./gradlew test
./gradlew :app:assembleDebug
```

Install `app/build/outputs/apk/debug/app-debug.apk` on physical BLE-capable Android phones. Tap **Start event mode** to request permissions and start the visible connected-device foreground service.

## Current transport slice

- Protobuf-lite application envelope and strict 16-byte transport frames.
- MTU-aware fragmentation, bounded out-of-order reassembly, duplicate suppression, and expiry.
- AES-GCM object authentication before fragmentation; Android Keystore helper for local key wrapping.
- Priority scheduling and store-and-forward relay with hop limits, custody ACKs, NACK bitmaps, and retry hooks.
- BLE advertising discovery metadata, deterministic connection ownership, GATT server/client, MTU negotiation, and serialized writes.
- Approximate beacon-to-zone resolution with explicit uncertainty.
- Privacy-safe newline-delimited protocol metrics and a deterministic lossy-frame test hook.

The phone implementation is an application-layer BLE overlay. It is not Bluetooth SIG Mesh certification, live voice streaming, or a production enrollment/security ceremony. Room persistence, local dashboard, audio/Opus, STT, triage, and QR UX attach through the frozen interfaces described in `context.md`.

