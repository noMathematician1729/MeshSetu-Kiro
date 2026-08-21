import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../gateway/gateway_bridge.dart';

/// Native recipient-facing view of a single SOS.
///
/// The API payload is the same incident record shown in the admin dashboard;
/// the app deliberately omits operator-only actions such as acknowledgement
/// and dispatch state changes.
class SosIncidentScreen extends ConsumerStatefulWidget {
  const SosIncidentScreen({super.key, required this.eventId});

  final String eventId;

  @override
  ConsumerState<SosIncidentScreen> createState() => _SosIncidentScreenState();
}

class _SosIncidentScreenState extends ConsumerState<SosIncidentScreen> {
  Map<String, Object?>? _incident;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final url = ref.read(gatewayUrlProvider);
    final key = ref.read(gatewayDemoKeyProvider);
    final incident = url.isEmpty
        ? null
        : await GatewayBridge(baseUrl: Uri.parse(url), demoKey: key)
              .fetchPublicIncident(widget.eventId);
    if (!mounted) return;
    setState(() {
      _incident = incident;
      _loading = false;
      _error = incident == null
          ? 'This SOS is unavailable or its details have not reached the server yet.'
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final incident = _incident;
    return Scaffold(
      appBar: AppBar(title: const Text('SOS details')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _UnavailableState(error: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _IncidentHeader(incident: incident!),
                  const SizedBox(height: 16),
                  _Transcript(transcript: _text(incident['transcript'])),
                  const SizedBox(height: 16),
                  Text(
                    'INCIDENT DETAILS',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  _FactsGrid(incident: incident),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'This is the live SOS detail shared with you. '
                        'Pull down to refresh updates from the response team.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _UnavailableState extends StatelessWidget {
  const _UnavailableState({required this.error, required this.onRetry});

  final String error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 48),
          const SizedBox(height: 16),
          Text(error, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

class _IncidentHeader extends StatelessWidget {
  const _IncidentHeader({required this.incident});

  final Map<String, Object?> incident;

  @override
  Widget build(BuildContext context) {
    final status = _text(incident['status']).isEmpty
        ? 'new'
        : _text(incident['status']);
    final priority = _text(incident['priority']);
    return Card(
      color: status == 'resolved'
          ? null
          : Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  status == 'resolved' ? Icons.check_circle : Icons.warning,
                  color: status == 'resolved'
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _display(_text(incident['incident_type'])),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Status: ${_display(status)}')),
                if (priority.isNotEmpty)
                  Chip(label: Text('Priority: ${_display(priority)}')),
                if (_text(incident['zone']).isNotEmpty)
                  Chip(label: Text('Zone: ${_text(incident['zone'])}')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Transcript extends StatelessWidget {
  const _Transcript({required this.transcript});

  final String transcript;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SIGNAL TRANSCRIPT', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Text(
            transcript.isEmpty ? 'No transcript was attached to this SOS.' : transcript,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    ),
  );
}

class _FactsGrid extends StatelessWidget {
  const _FactsGrid({required this.incident});

  final Map<String, Object?> incident;

  @override
  Widget build(BuildContext context) {
    final latitude = _number(incident['latitude']);
    final longitude = _number(incident['longitude']);
    final location = latitude == null || longitude == null
        ? 'Unavailable'
        : '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}'
            '${_number(incident['accuracy_m']) == null ? '' : ' · ±${_number(incident['accuracy_m'])!.round()} m'}';
    final facts = <(String, String)>[
      ('Reporter', _combine(_text(incident['reporter_name']), _text(incident['reporter_phone']))),
      ('Emergency contact', _value(incident['reporter_primary_contact'])),
      ('Blood group', _value(incident['reporter_blood_group'])),
      ('Location', location),
      ('Received', _formatTime(incident['received_at_ms'] ?? incident['created_at_ms'])),
      ('Relay hops', _value(incident['hops'])),
      ('Origin latency', _milliseconds(incident['relay_latency_ms'])),
      ('Voice evidence', _value(incident['audio_state'])),
      ('Triage confidence', _confidence(incident['triage_confidence'])),
      ('Verification', _value(incident['decrypt_status'])),
      ('Incident ID', _value(incident['event_id'])),
      ('Packet hash', _shortHash(_text(incident['packet_sha256']))),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: facts.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.7,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (_, index) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(facts[index].$1, style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  facts[index].$2,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _text(Object? value) {
  final text = '${value ?? ''}'.trim();
  return text == 'null' ? '' : text;
}

String _value(Object? value) {
  final text = _text(value);
  return text.isEmpty ? 'Unavailable' : text;
}

String _combine(String left, String right) {
  if (left.isEmpty && right.isEmpty) return 'Unavailable';
  return [left, right].where((value) => value.isNotEmpty).join(' · ');
}

double? _number(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('${value ?? ''}');

String _milliseconds(Object? value) {
  final number = _number(value);
  return number == null ? 'Unavailable' : '${number.round()} ms';
}

String _confidence(Object? value) {
  final number = _number(value);
  return number == null ? 'Unavailable' : '${(number * 100).round()}%';
}

String _shortHash(String value) => value.isEmpty
    ? 'Unavailable'
    : value.length <= 12
    ? value
    : value.substring(0, 12);

String _display(String value) => value.replaceAll('_', ' ');

String _formatTime(Object? value) {
  final milliseconds = value is num
      ? value.toInt()
      : int.tryParse('${value ?? ''}');
  if (milliseconds == null) return 'Unavailable';
  final date = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
