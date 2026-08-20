import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../gateway/gateway_screen.dart';
import '../join/manifest.dart';
import '../sos/sos_screen.dart';
import '../voice/voice_inbox_screen.dart';
import 'room_lobby_screen.dart';
import 'room_policy.dart';

String _roomIdFromName(String name) {
  final slug = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final suffix = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  return '${slug.isEmpty ? 'room' : slug}-$suffix';
}

/// Room list for the joined site (Bible §20.5: "Join -> Rooms -> SOS flow
/// is understandable in under 30 seconds").
class RoomsScreen extends ConsumerStatefulWidget {
  const RoomsScreen({super.key, this.initialRoomId});

  final String? initialRoomId;

  @override
  ConsumerState<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends ConsumerState<RoomsScreen> {
  var _openedInitialRoom = false;

  @override
  Widget build(BuildContext context) {
    final site = ref.watch(activeSiteProvider);
    final userRoles = ref.watch(userRolesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Rooms')),
      body: site.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load site: $e')),
        data: (manifest) {
          if (manifest == null) {
            return const Center(child: Text('Join an event first.'));
          }
          final readableRooms = manifest.rooms
              .where(
                (room) =>
                    canRead(policyForRole(room.roomId, room.role), userRoles),
              )
              .toList();
          final initialRoomId = widget.initialRoomId;
          final matchingRooms = initialRoomId == null
              ? const <RoomManifest>[]
              : readableRooms
                    .where((room) => room.roomId == initialRoomId)
                    .toList();
          final initialRoom = matchingRooms.isEmpty
              ? null
              : matchingRooms.first;
          if (!_openedInitialRoom && initialRoom != null) {
            _openedInitialRoom = true;
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _openLobby(context, manifest, initialRoom),
            );
          }
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: FilledButton.icon(
                  icon: const Icon(Icons.add_home_work_outlined),
                  label: const Text('Create another room'),
                  onPressed: () => _createRoom(context, ref),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  'Open a room lobby to share its QR, room code, and see who has joined.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.sos, color: Colors.red),
                title: const Text('Send SOS'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SosScreen(
                      siteId: manifest.siteId,
                      roomId: manifest.rooms.isEmpty
                          ? 'public'
                          : manifest.rooms.first.roomId,
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.graphic_eq),
                title: const Text('Voice evidence'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => VoiceInboxScreen(siteId: manifest.siteId),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.router_outlined),
                title: const Text('Gateway'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GatewayScreen()),
                ),
              ),
              const Divider(),
              for (final room in readableRooms)
                ListTile(
                  leading: const Icon(Icons.forum_outlined),
                  title: Text(room.name),
                  subtitle: Text(room.role),
                  trailing: IconButton(
                    tooltip: 'Open room lobby',
                    icon: const Icon(Icons.meeting_room_outlined),
                    onPressed: () => _openLobby(context, manifest, room),
                  ),
                  onTap: () => _openLobby(context, manifest, room),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createRoom(BuildContext context, WidgetRef ref) async {
    final room = await showDialog<RoomManifest>(
      context: context,
      builder: (_) => const _CreateRoomDialog(),
    );
    if (room == null || !context.mounted) return;
    try {
      final updated = await ref
          .read(joinRepositoryProvider)
          .addRoomToActiveManifest(room);
      refreshActiveSite(ref);
      if (!context.mounted) return;
      _openLobby(context, updated, room);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not create room: $error')));
    }
  }

  void _openLobby(
    BuildContext context,
    EventManifest manifest,
    RoomManifest room,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoomLobbyScreen(manifest: manifest, room: room),
      ),
    );
  }
}

class _CreateRoomDialog extends StatefulWidget {
  const _CreateRoomDialog();

  @override
  State<_CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<_CreateRoomDialog> {
  final _nameController = TextEditingController();
  var _role = 'public';

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create room'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _nameController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Room name',
            hintText: 'e.g. Registration Desk',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _role,
          decoration: const InputDecoration(labelText: 'Room access'),
          items: const [
            DropdownMenuItem(value: 'public', child: Text('Public')),
            DropdownMenuItem(value: 'volunteer', child: Text('Volunteer')),
            DropdownMenuItem(value: 'medical', child: Text('Medical')),
            DropdownMenuItem(value: 'responder', child: Text('Responder')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _role = value);
          },
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final name = _nameController.text.trim();
          if (name.isEmpty) return;
          Navigator.of(context).pop(
            RoomManifest(
              roomId: _roomIdFromName(name),
              name: name,
              role: _role,
              ttlSeconds: 3600,
            ),
          );
        },
        child: const Text('Create'),
      ),
    ],
  );
}
