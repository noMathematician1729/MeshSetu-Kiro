import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/event_mode_screen.dart' show meshEventTaskCallback;
import '../../app/mesh_bridge_client.dart' show MeshStatus;
import '../../app/providers.dart';
import '../../app/room_mesh_bootstrap.dart';
import '../join/manifest.dart';
import 'room_chat_screen.dart';
import 'room_presence.dart';
import 'room_presence_socket.dart';

/// Module-level so re-opening the same room lobby within one app session
/// does not re-announce over the mesh every time — announcements persist in
/// the outbox and re-sending is wasted radio time, not a correctness fix.
/// Cleared implicitly on app restart, which is exactly when a fresh
/// announcement is wanted again.
final Set<String> _announcedRoomMembers = {};

/// Presence announcements use the same `RoomPresenceCodec` 24h TTL as the
/// mesh outbox row; re-announcing well inside that window keeps a lobby's
/// mesh-observed member list from expiring while the room stays open.
const _reannounceInterval = Duration(minutes: 5);

class RoomLobbyScreen extends ConsumerStatefulWidget {
  const RoomLobbyScreen({
    super.key,
    required this.manifest,
    required this.room,
  });

  final EventManifest manifest;
  final RoomManifest room;

  @override
  ConsumerState<RoomLobbyScreen> createState() => _RoomLobbyScreenState();
}

class _RoomLobbyScreenState extends ConsumerState<RoomLobbyScreen> {
  StreamSubscription<List<RoomMember>>? _meshMembersSubscription;
  RoomPresenceSocket? _presenceSocket;
  List<RoomMember> _meshMembers = const [];
  List<RoomMember> _liveMembers = const [];
  var _receivedLiveSnapshot = false;
  Timer? _reannounceTimer;
  var _startingEventMode = false;

  @override
  void initState() {
    super.initState();
    _meshMembersSubscription = ref
        .read(roomRepositoryProvider(widget.manifest.siteId))
        .watchMembers(widget.room.roomId)
        .listen((members) {
          if (mounted) setState(() => _meshMembers = members);
        });
    unawaited(_connectLivePresence());
    unawaited(_announcePresence());
    _reannounceTimer = Timer.periodic(
      _reannounceInterval,
      (_) => unawaited(_announcePresence(force: true)),
    );
  }

  /// Announces this device's membership over the mesh so peers with no
  /// internet still see who is in the room (closes the gap where presence
  /// was only ever announced from the join screen, never from a room a user
  /// opens later). Deduped per room+profile for the life of the app process;
  /// [force] bypasses the dedupe for the periodic re-announce.
  Future<void> _announcePresence({bool force = false}) async {
    final profile = await ref.read(onboardingRepositoryProvider).load();
    if (!mounted || profile == null) return;
    final key =
        '${widget.manifest.siteId}\u0000${widget.room.roomId}\u0000'
        '${profile.profileId}';
    if (!force && !_announcedRoomMembers.add(key)) return;
    _announcedRoomMembers.add(key);
    try {
      await ref
          .read(roomRepositoryProvider(widget.manifest.siteId))
          .announceMember(
            roomId: widget.room.roomId,
            memberId: profile.profileId,
            displayName: profile.name,
          );
    } catch (_) {
      // Best-effort; the periodic timer retries, and watchMembers doesn't
      // depend on this device's own announcement to show other peers.
    }
  }

  Future<void> _connectLivePresence() async {
    final profile = await ref.read(onboardingRepositoryProvider).load();
    if (!mounted || profile == null) return;
    if (!ref.read(gatewayEnabledProvider)) return;
    final rawUrl = ref.read(gatewayUrlProvider).trim();
    if (rawUrl.isEmpty) return;
    final baseUrl = Uri.tryParse(rawUrl);
    if (baseUrl == null || !baseUrl.hasScheme) return;
    final presence = RoomPresenceSocket(
      baseUrl: baseUrl,
      gatewayKey: ref.read(gatewayDemoKeyProvider),
      siteId: widget.manifest.siteId,
      roomId: widget.room.roomId,
      memberId: profile.profileId,
      displayName: profile.name,
    );
    _presenceSocket = presence;
    presence.members.listen((members) {
      if (!mounted) return;
      setState(() {
        _receivedLiveSnapshot = true;
        _liveMembers = members;
      });
    });
    presence.start();
  }

  Future<void> _startEventModeFromRoom() async {
    if (_startingEventMode) return;
    setState(() => _startingEventMode = true);
    try {
      await RoomMeshBootstrap.startForSite(
        ref: ref,
        siteId: widget.manifest.siteId,
        taskCallback: meshEventTaskCallback,
      );
    } finally {
      if (mounted) setState(() => _startingEventMode = false);
    }
  }

  @override
  void dispose() {
    unawaited(_meshMembersSubscription?.cancel());
    unawaited(_presenceSocket?.dispose());
    _reannounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final meshStatus = ref.watch(meshStatusProvider);
    // A live socket snapshot is additive evidence, not a replacement: a
    // member who only ever appears over the mesh (no internet) must still
    // show up even after the socket connects.
    final members = <String, RoomMember>{
      for (final member in _meshMembers) member.memberId: member,
      if (_receivedLiveSnapshot)
        for (final member in _liveMembers) member.memberId: member,
    }.values.toList()..sort((a, b) => a.joinedAtMs.compareTo(b.joinedAtMs));
    final manifest = widget.manifest;
    final room = widget.room;
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
          const SizedBox(height: 12),
          meshStatus.when(
            data: (status) => _MeshStatusBanner(
              status: status,
              starting: _startingEventMode,
              onStartEventMode: _startEventModeFromRoom,
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
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
          members.isEmpty
              ? const ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('Waiting for people to join'),
                  subtitle: Text(
                    'Members appear here over the mesh or once they scan '
                    'the QR.',
                  ),
                )
              : Column(
                  children: [
                    for (final member in members)
                      ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            member.displayName.characters.first.toUpperCase(),
                          ),
                        ),
                        title: Text(member.displayName),
                        subtitle: Text(
                          _liveMembers.any((m) => m.memberId == member.memberId)
                              ? 'Active now'
                              : 'Seen over mesh',
                        ),
                      ),
                  ],
                ),
        ],
      ),
    );
  }
}

/// Mesh-first connectivity summary. This is deliberately the primary status
/// surface for the lobby — the internet socket status shown inside
/// [RoomChatScreen] is secondary/muted, since a healthy offline BLE mesh
/// with zero internet must not look like a broken room.
class _MeshStatusBanner extends StatelessWidget {
  const _MeshStatusBanner({
    required this.status,
    required this.starting,
    required this.onStartEventMode,
  });

  final MeshStatus status;
  final bool starting;
  final VoidCallback onStartEventMode;

  @override
  Widget build(BuildContext context) {
    if (!status.eventModeRunning) {
      final blockedReason = status.blockedReason;
      return Card(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: ListTile(
          leading: const Icon(Icons.bluetooth_disabled),
          title: Text(blockedReason != null ? 'Event mode is blocked' : 'Event mode is off'),
          subtitle: Text(
            blockedReason ??
                'Messages will queue until you start the BLE relay service.',
          ),
          trailing: FilledButton(
            onPressed: starting ? null : onStartEventMode,
            child: starting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Start'),
          ),
        ),
      );
    }
    final peerCount = status.peerCount;
    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(
              peerCount > 0
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_searching,
            ),
            title: Text(
              peerCount > 0
                  ? 'Mesh: $peerCount peer${peerCount == 1 ? '' : 's'} connected'
                  : 'Mesh: no peers yet',
            ),
            subtitle: Text(
              peerCount > 0
                  ? 'Messages relay over Bluetooth.'
                  : 'Move closer to another device with event mode on.',
            ),
          ),
          if (status.siteMismatchDetected)
            const ListTile(
              dense: true,
              leading: Icon(Icons.warning_amber, size: 20),
              title: Text(
                'A nearby device is using a different event/site code',
                style: TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                'It will not appear here or connect until it joins this event.',
                style: TextStyle(fontSize: 12),
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
