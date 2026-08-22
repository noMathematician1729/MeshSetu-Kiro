import 'package:flutter/material.dart';

import '../../core/ble/sos_advertisement.dart';

/// Recipient-facing view for the information available in a compact BLE SOS.
/// The packet intentionally excludes identity, contacts, and precise location.
class CompactSosPacketScreen extends StatelessWidget {
  const CompactSosPacketScreen({super.key, required this.alert});

  final MeshSosAdvertisement alert;

  @override
  Widget build(BuildContext context) {
    final sender = alert.hasReporterUid
        ? 'CEAL ID ${alert.reporterUidHex.toUpperCase()}'
        : 'Anonymous mesh sender';
    final packet =
        '${alert.originId.toRadixString(16).padLeft(8, '0').toUpperCase()}-${alert.sequence.toString().padLeft(5, '0')}';
    return Scaffold(
      appBar: AppBar(title: const Text('SOS packet')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                alert.emergencyType.label.toUpperCase(),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _Fact(label: 'Sender', value: sender),
          _Fact(label: 'Packet', value: packet),
          _Fact(
            label: 'Mesh relay',
            value: alert.ttl == 1
                ? '1 Bluetooth hop remaining'
                : '${alert.ttl} Bluetooth hops remaining',
          ),
          const SizedBox(height: 16),
          Card(
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'This compact SOS is safe to relay without internet. '
                'Name, emergency contacts, and precise location are encrypted. '
                'When the control room resolves the packet, this notification '
                'updates to the full incident details.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 104,
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
