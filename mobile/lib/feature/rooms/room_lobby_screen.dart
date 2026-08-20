import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/providers.dart';
import '../join/manifest.dart';
import 'room_chat_screen.dart';

class RoomLobbyScreen extends ConsumerWidget {
  const RoomLobbyScreen({
    super.key,
    required this.manifest,
    required this.room,
  });

  final EventManifest manifest;
  final RoomManifest room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(
      roomMembersProvider((siteId: manifest.siteId, roomId: room.roomId)),
    );
    final invite = EventManifestCodec.encode(manifest, roomId: room.roomId);
    return Scaffold(
      appBar: AppBar(title: Text(room.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('ROOM LOBBY', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            manifest.siteName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Center(
            child: SizedBox.square(
              dimension: 284,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                  data: invite,
                  version: QrVersions.auto,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _CodeTile(label: 'Room code', value: room.roomId),
          _CodeTile(label: 'Event code', value: manifest.meshCode),
          const SizedBox(height: 20),
          FilledButton.icon(
            icon: const Icon(Icons.forum_outlined),
            label: const Text('Open room chat'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RoomChatScreen(
                  siteId: manifest.siteId,
                  roomId: room.roomId,
                  roomName: room.name,
                  role: room.role,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'PEOPLE IN THIS ROOM',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          members.when(
            loading: () => const ListTile(
              leading: Icon(Icons.people_outline),
              title: Text('Checking room members…'),
            ),
            error: (error, _) => Text('Could not load members: $error'),
            data: (items) => items.isEmpty
                ? const ListTile(
                    leading: Icon(Icons.person_outline),
                    title: Text('Waiting for people to join'),
                    subtitle: Text('Members appear after they scan the QR.'),
                  )
                : Column(
                    children: [
                      for (final member in items)
                        ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              member.displayName.characters.first.toUpperCase(),
                            ),
                          ),
                          title: Text(member.displayName),
                          subtitle: const Text('Joined room'),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CodeTile extends StatelessWidget {
  const _CodeTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.key_outlined),
      title: Text(label),
      subtitle: SelectableText(value),
    ),
  );
}
