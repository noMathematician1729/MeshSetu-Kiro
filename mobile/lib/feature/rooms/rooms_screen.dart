import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../gateway/gateway_screen.dart';
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
}
