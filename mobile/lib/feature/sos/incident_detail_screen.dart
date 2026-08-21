import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/data/database.dart';
import '../../core/model/model.dart';
import '../voice/voice_repository.dart';
import 'sos_payload.dart';

class IncidentDetailScreen extends ConsumerWidget {
  const IncidentDetailScreen({
    super.key,
    required this.siteId,
    required this.eventId,
    required this.objectId,
  });

  final String siteId;
  final String eventId;
  final int objectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('SOS incident')),
      body: StreamBuilder<List<InboxEvent>>(
        stream: db.watchInboxSite(siteId),
        builder: (context, snapshot) {
          final rows = snapshot.data ?? const <InboxEvent>[];
          InboxEvent? incident;
          for (final row in rows) {
            if (row.eventId == eventId &&
                row.payloadType == PayloadType.structuredSos.name) {
              incident = row;
              break;
            }
          }
          if (incident == null) {
            return const Center(
              child: Text('Incident details are still syncing.'),
            );
          }
          try {
            final sos = StructuredSosPayload.decode(incident.payload);
            var hasVoice = false;
            for (final row in rows) {
              if (row.payloadType != PayloadType.voiceObject.name) continue;
              try {
                hasVoice |=
                    VoiceObjectPayload.decode(row.payload).sosEventId ==
                    eventId;
              } catch (_) {
                // An unrelated/corrupt voice object does not affect this SOS.
              }
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  sos.incidentType,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text('Priority: ${sos.triagePriority.name}'),
                const SizedBox(height: 16),
                _section('Reporter', sos.reporter?.name ?? 'Unknown'),
                _section(
                  'Contact',
                  sos.reporter == null
                      ? 'Unavailable'
                      : '${sos.reporter!.primaryContactName} · ${sos.reporter!.primaryContactPhone}',
                ),
                _section(
                  'Transcript',
                  sos.transcript.isEmpty ? 'Unavailable' : sos.transcript,
                ),
                _section(
                  'Location',
                  sos.latitude == null || sos.longitude == null
                      ? 'Unavailable'
                      : '${sos.latitude!.toStringAsFixed(5)}, ${sos.longitude!.toStringAsFixed(5)}'
                            '${sos.accuracyM == null ? '' : ' · ±${sos.accuracyM!.round()} m'}',
                ),
                _section(
                  'Route',
                  '${incident.peerId} · ${incident.receivedAtMs}',
                ),
                _section(
                  'Voice evidence',
                  hasVoice
                      ? 'Received — open Voice evidence to play.'
                      : 'Pending or unavailable.',
                ),
              ],
            );
          } catch (_) {
            return const Center(
              child: Text('Incident payload could not be decoded.'),
            );
          }
        },
      ),
    );
  }

  Widget _section(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(value),
      ],
    ),
  );
}
