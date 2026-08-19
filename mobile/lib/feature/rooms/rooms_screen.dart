import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/providers.dart';
import '../gateway/gateway_screen.dart';
import '../join/manifest.dart';
import '../sos/sos_screen.dart';
import '../voice/voice_inbox_screen.dart';
import 'room_chat_screen.dart';
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
  bool _openedInitialRoom = false;

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
          final readableRooms = [
            for (final room in manifest.rooms)
              if (canRead(
                policyForRole(
                  room.roomId,
                  room.role,
                  ttlSeconds: room.ttlSeconds,
                ),
                userRoles,
              ))
                room,
          ];
          _openInitialRoomIfAvailable(context, manifest, readableRooms);
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: FilledButton.icon(
                  icon: const Icon(Icons.add_home_work_outlined),
                  label: const Text('Create room · Generate QR'),
                  onPressed: () => _createRoom(context, ref),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  'Share a room QR so another phone can join this event and open the same room.',
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
                    tooltip: 'Generate room QR',
                    icon: const Icon(Icons.qr_code_2),
                    onPressed: () => _showRoomQr(context, manifest, room),
                  ),
                  onTap: () => Navigator.of(context).push(
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
            ],
          );
        },
      ),
    );
  }

  void _openInitialRoomIfAvailable(
    BuildContext context,
    EventManifest manifest,
    List<RoomManifest> rooms,
  ) {
    final roomId = widget.initialRoomId;
    if (_openedInitialRoom || roomId == null) return;
    _openedInitialRoom = true;
    final matches = rooms.where((room) => room.roomId == roomId);
    if (matches.isEmpty) return;
    final room = matches.first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RoomChatScreen(
            siteId: manifest.siteId,
            roomId: room.roomId,
            roomName: room.name,
            role: room.role,
          ),
        ),
      );
    });
  }

  Future<void> _createRoom(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    var role = 'public';
    final room = await showDialog<RoomManifest>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create room'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Room name',
                  hintText: 'e.g. Registration Desk',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Room access'),
                items: const [
                  DropdownMenuItem(value: 'public', child: Text('Public')),
                  DropdownMenuItem(
                    value: 'volunteer',
                    child: Text('Volunteer'),
                  ),
                  DropdownMenuItem(value: 'medical', child: Text('Medical')),
                  DropdownMenuItem(
                    value: 'responder',
                    child: Text('Responder'),
                  ),
                ],
                onChanged: (value) => setDialogState(() => role = value!),
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
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.of(context).pop(
                  RoomManifest(
                    roomId: _roomIdFromName(name),
                    name: name,
                    role: role,
                    ttlSeconds: 3600,
                  ),
                );
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    if (room == null || !context.mounted) return;
    try {
      final updated = await ref
          .read(joinRepositoryProvider)
          .addRoomToActiveManifest(room);
      refreshActiveSite(ref);
      if (!context.mounted) return;
      _showRoomQr(context, updated, room);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not create room: $error')));
    }
  }

  void _showRoomQr(
    BuildContext context,
    EventManifest manifest,
    RoomManifest room,
  ) {
    final payload = EventManifestCodec.encode(manifest, roomId: room.roomId);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${room.name} QR'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                  data: payload,
                  version: QrVersions.auto,
                  size: 260,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(manifest.siteName),
              Text('${room.name} · ${room.role}'),
              const SizedBox(height: 8),
              const Text(
                'On the other phone, choose Join event and scan this code.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
