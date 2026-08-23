# MeshSetu

Android-first, offline emergency communication over a BLE store-and-forward overlay.

## Repository layout

```text
mobile/        Flutter Android app (mesh transport, SOS, rooms, STT, gestures)
admin/server/  Node + TypeScript control-room API (Postgres, SMS fan-out)
admin/client/  React operator dashboard
context.md     Frozen product/architecture specification
REMAINING_WORK.md  Implemented vs. outstanding scope against context.md
```

## Build and test

The Flutter build targets Android SDK 36. Use a Flutter SDK compatible with the Dart constraint in `mobile/pubspec.yaml`.

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Control room:

```bash
cd admin/server && npm ci && npm test && npm run build
cd admin/client && npm ci && npm run build
```

Install `mobile/build/app/outputs/flutter-apk/app-debug.apk` on physical BLE-capable Android phones. Tap **Start event mode** to request permissions and start the visible connected-device foreground service. The foreground task owns scanning and relay processing, so leaving the screen does not stop the mesh; use **Stop event mode** to shut it down.

## Current transport slice

- Protobuf-lite application envelope and strict 16-byte transport frames.
- MTU-aware fragmentation, bounded out-of-order reassembly, duplicate suppression, and expiry.
- AES-GCM object authentication before fragmentation; Android Keystore helper for local key wrapping.
- Priority scheduling and store-and-forward relay with hop limits, custody ACKs, NACK bitmaps, and retry hooks.
- BLE advertising discovery metadata, deterministic connection ownership, GATT server/client, MTU negotiation, and serialized writes.
- Approximate beacon-to-zone resolution with explicit uncertainty.
- Privacy-safe newline-delimited protocol metrics and a deterministic lossy-frame test hook.

The phone implementation is an application-layer BLE overlay. It is not Bluetooth SIG Mesh certification, live voice streaming, or a production enrollment/security ceremony. Room persistence, the control-room backend, audio/Opus, STT, triage, and QR UX attach through the frozen interfaces described in `context.md`.


## How did we meaningfully integrate Kiro into this product?

Kiro stepped in as our AI development partner. It sits inside the terminal and understands the entire codebase—from the Protobuf frame definitions and BLE GATT layer to the Postgres-backed control-room API. When we're debugging fragmentation logic or wiring up a new triage endpoint, Kiro reads the relevant files, suggests fixes, writes tests, and catches regressions before they hit the build.

The model selection and reasoning-effort controls to match the task at hand—lightweight models for quick refactors, heavier reasoning for protocol design decisions really came in clutch. Specialized agents let us carve out focused workflows: one tuned for Flutter widget trees, another for infrastructure and deployment scripts. MCP tool integrations tie Kiro into our linters and test runners so verification happens in-loop, not after the fact.

The hackathon's extra two thousand credits give us headroom to iterate aggressively on a project this complex. We track spend with /usage and use model credit multipliers to stay within budget while still pulling in the capability we need. The result: a reliable offline emergency network, shipped faster because Kiro handles the mechanical weight of development so we can focus on architecture, user experience, and getting the mesh right.
