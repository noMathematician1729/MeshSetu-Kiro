import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// Bible §15.1: "gateway phone and laptop join the same local Wi-Fi
/// hotspot." This screen just lets the operator point the phone at the
/// laptop's dashboard address and flip it into gateway mode — the actual
/// forwarding is `GatewayForwarder`, started from `app/mesh_event_controller.dart`
/// once a `MeshTransportCoordinator` exists.
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
              'Enable this on the one phone that shares Wi-Fi with the '
              'control-room laptop. Every other phone stays purely peer-to-peer.',
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
                labelText: 'Dashboard demo key',
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
