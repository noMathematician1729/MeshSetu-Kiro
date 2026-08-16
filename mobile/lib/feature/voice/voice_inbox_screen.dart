import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/providers.dart';
import '../../core/data/database.dart';
import '../../core/model/model.dart';
import 'voice_repository.dart';

/// Received voice evidence for a site. `InboxEvents` rows only exist once
/// `MeshRelayEngine` has decrypted and authenticated the reassembled object
/// (see `relay_engine.dart`'s `persist` call), so every row shown here has
/// already passed the envelope integrity check. Voice payload integrity is
/// checked again before playback because the audio has its own digest.
class VoiceInboxScreen extends ConsumerWidget {
  const VoiceInboxScreen({super.key, required this.siteId});

  final String siteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Voice evidence')),
      body: StreamBuilder(
        stream:
            (db.select(db.inboxEvents)..where(
                  (t) =>
                      t.siteId.equals(siteId) &
                      t.payloadType.equals(PayloadType.voiceObject.name),
                ))
                .watch(),
        builder: (context, snapshot) {
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return const Center(child: Text('No voice evidence received yet.'));
          }
          return ListView(
            children: [for (final row in rows) _VoiceRow(row: row)],
          );
        },
      ),
    );
  }
}

class _VoiceRow extends StatelessWidget {
  const _VoiceRow({required this.row});

  final InboxEvent row;

  @override
  Widget build(BuildContext context) {
    try {
      final voice = VoiceObjectPayload.decode(row.payload);
      return ListTile(
        leading: const Icon(Icons.graphic_eq),
        title: Text('From ${row.peerId}'),
        subtitle: Text('${voice.bytes.length} bytes · integrity verified'),
        trailing: IconButton(
          icon: const Icon(Icons.play_arrow),
          onPressed: () => _play(row.objectId, voice.bytes),
        ),
      );
    } on FormatException catch (error) {
      return ListTile(
        leading: const Icon(Icons.error_outline, color: Colors.red),
        title: Text('Corrupt voice evidence from ${row.peerId}'),
        subtitle: Text(error.message),
      );
    } catch (_) {
      return ListTile(
        leading: const Icon(Icons.error_outline, color: Colors.red),
        title: Text('Unreadable voice evidence from ${row.peerId}'),
      );
    }
  }

  Future<void> _play(int objectId, List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/inbox-voice-$objectId.opus');
    await file.writeAsBytes(bytes);
    await AudioPlayer().play(DeviceFileSource(file.path));
  }
}
