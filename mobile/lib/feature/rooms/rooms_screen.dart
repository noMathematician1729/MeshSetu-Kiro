import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/providers.dart';
import '../gateway/gateway_screen.dart';
import '../join/manifest.dart';
import '../sos/sos_screen.dart';
import '../voice/voice_inbox_screen.dart';
import 'room_chat_screen.dart';

/// Room list for the joined site (Bible §20.5: "Join -> Rooms -> SOS flow
/// is understandable in under 30 seconds").
class RoomsScreen extends ConsumerWidget {
  const RoomsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final site = ref.watch(activeSiteProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Rooms')),
      body: site.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load site: $e')),
        data: (manifest) {
          if (manifest == null) {
            return const Center(child: Text('Join an event first.'));
          }
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
              for (final room in manifest.rooms)
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
