import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// This screen lets the operator point the phone at a reachable dashboard
/// address (local Wi-Fi or an HTTPS tunnel) and flip it into gateway mode —
/// forwarding is performed by `MeshBridgeClient` when event mode is running.
/// The gateway sends encrypted mesh objects; the Node server verifies them.
class GatewayScreen extends ConsumerStatefulWidget {
  const GatewayScreen({super.key});

  @override
  ConsumerState<GatewayScreen> createState() => _GatewayScreenState();
}

class _GatewayScreenState extends ConsumerState<GatewayScreen> {
  late final _urlController = TextEditingController(
    text: ref.read(gatewayUrlProvider),
  );
  late final _keyController = TextEditingController(
    text: ref.read(gatewayDemoKeyProvider),
  );

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(gatewayEnabledProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Gateway')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enable this on the phone that receives BLE SOS packets and can '
              'reach the control-room dashboard. Every other phone stays '
              'purely peer-to-peer.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Dashboard base URL',
                hintText: 'http://192.168.1.20:8000',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => ref.read(gatewayUrlProvider.notifier).state = v,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keyController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Dashboard gateway key',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) =>
                  ref.read(gatewayDemoKeyProvider.notifier).state = v,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Act as gateway'),
              value: enabled,
              onChanged: (v) =>
                  ref.read(gatewayEnabledProvider.notifier).state = v,
            ),
          ],
        ),
      ),
    );
  }
}
