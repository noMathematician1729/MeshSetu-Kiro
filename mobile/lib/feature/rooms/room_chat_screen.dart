import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/active_room_reporter.dart';
import '../../app/event_mode_screen.dart' show meshEventTaskCallback;
import '../../app/mesh_bridge_client.dart' show MeshStatus;
import '../../app/providers.dart';
import '../../app/room_mesh_bootstrap.dart';
import 'room_message_dispatcher.dart';
import 'room_policy.dart';
import 'room_presence_socket.dart';
import 'room_repository.dart';

class RoomChatScreen extends ConsumerStatefulWidget {
  const RoomChatScreen({
    super.key,
    required this.siteId,
    required this.roomId,
    required this.roomName,
    required this.role,
  });

  final String siteId, roomId, roomName, role;

  @override
  ConsumerState<RoomChatScreen> createState() => _RoomChatScreenState();
}

class _RoomChatScreenState extends ConsumerState<RoomChatScreen>
    with WidgetsBindingObserver {
  final _textController = TextEditingController();
  RoomPresenceSocket? _liveTransport;
  String _liveStatus = 'Connecting…';
  String? _error;
  var _startingEventMode = false;
  late final ActiveRoomReporter _activeRoomReporter;

  @override
  void initState() {
    super.initState();
    _activeRoomReporter = ActiveRoomReporter(roomId: widget.roomId);
    WidgetsBinding.instance.addObserver(this);
    // Report this room as active immediately — any notifications for it
    // that arrive while the screen is mounted and foregrounded are suppressed.
    _activeRoomReporter.reportActive();
    unawaited(_connectLiveTransport());
    unawaited(_announcePresence());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // App returned to foreground with this screen still on top.
        _activeRoomReporter.reportActive();
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // App moved to background — notifications should fire.
        _activeRoomReporter.reportInactive();
    }
  }

  /// Closes the same presence gap as [RoomLobbyScreen]: entering chat
  /// directly (e.g. from a deep link) should still put this device on
  /// peers' member lists without requiring a lobby visit first.
  Future<void> _announcePresence() async {
    final profile = await ref.read(onboardingRepositoryProvider).load();
    if (!mounted || profile == null) return;
    try {
      await ref
          .read(roomRepositoryProvider(widget.siteId))
          .announceMember(
            roomId: widget.roomId,
            memberId: profile.profileId,
            displayName: profile.name,
          );
    } catch (_) {
      // Best-effort; the lobby's periodic re-announce also covers this room.
    }
  }

  Future<void> _connectLiveTransport() async {
    if (!ref.read(gatewayEnabledProvider)) {
      if (mounted) setState(() => _liveStatus = 'disabled');
      return;
    }
    final profile = await ref.read(onboardingRepositoryProvider).load();
    if (!mounted || profile == null) return;
    final rawUrl = ref.read(gatewayUrlProvider).trim();
    final baseUrl = Uri.tryParse(rawUrl);
    if (baseUrl == null || !baseUrl.hasScheme) {
      if (mounted) setState(() => _liveStatus = 'not configured');
      return;
    }
    final socket = RoomPresenceSocket(
      baseUrl: baseUrl,
      gatewayKey: ref.read(gatewayDemoKeyProvider),
      siteId: widget.siteId,
      roomId: widget.roomId,
      memberId: profile.profileId,
      displayName: profile.name,
    );
    _liveTransport = socket;
    socket.debug.listen((status) {
      if (mounted) setState(() => _liveStatus = status);
    });
    socket.messages.listen((message) {
      if (!mounted || message.memberId == profile.profileId) return;
      // A message the socket delivers from someone else is durably stored
      // so it renders alongside mesh-delivered messages from `watch()` and
      // survives navigating away and back.
      unawaited(
        ref
            .read(roomRepositoryProvider(widget.siteId))
            .storeSocketMessage(
              roomId: widget.roomId,
              eventId: message.messageId,
              text: message.text,
              fromPeerId: message.displayName,
              sentAtMs: message.sentAtMs,
            ),
      );
    });
    socket.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Room is no longer visible — re-enable notifications for it.
    _activeRoomReporter.reportInactive();
    _textController.dispose();
    unawaited(_liveTransport?.dispose());
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final policy = policyForRole(widget.roomId, widget.role);
    final userRoles = ref.read(userRolesProvider);
    try {
      await RoomMessageDispatcher(
        ref.read(roomRepositoryProvider(widget.siteId)),
        _liveTransport,
      ).send(policy: policy, userRoles: userRoles, text: text);
      _textController.clear();
      setState(() => _error = null);
    } on StateError catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _startEventModeFromRoom() async {
    if (_startingEventMode) return;
    setState(() => _startingEventMode = true);
    try {
      await RoomMeshBootstrap.startForSite(
        ref: ref,
        siteId: widget.siteId,
        taskCallback: meshEventTaskCallback,
      );
    } finally {
      if (mounted) setState(() => _startingEventMode = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userRoles = ref.watch(userRolesProvider);
    final policy = policyForRole(widget.roomId, widget.role);
    if (!canRead(policy, userRoles)) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.roomName)),
        body: const Center(
          child: Text('You are not authorized to view this room.'),
        ),
      );
    }
    final messages = ref.watch(
      roomMessagesProvider((
        siteId: widget.siteId,
        roomId: widget.roomId,
        role: widget.role,
        userRoles: userRoles,
      )),
    );
    final meshStatus = ref.watch(meshStatusProvider);
    return Scaffold(
      appBar: AppBar(title: Text(widget.roomName)),
      body: Column(
        children: [
          meshStatus.when(
            data: (status) => _MeshStatusBar(
              status: status,
              starting: _startingEventMode,
              onStartEventMode: _startEventModeFromRoom,
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (items) {
                final visible = items.toList()
                  ..sort((a, b) => a.atMs.compareTo(b.atMs));
                return ListView.builder(
                  reverse: true,
                  itemCount: visible.length,
                  itemBuilder: (context, i) {
                    final m = visible[visible.length - 1 - i];
                    final status = meshStatus.valueOrNull;
                    final reason = m.mine
                        ? queuedReasonFor(
                            m,
                            eventModeRunning: status?.eventModeRunning ?? false,
                            peerCount: status?.peerCount ?? 0,
                            blockedReason: status?.blockedReason,
                            siteMismatchDetected:
                                status?.siteMismatchDetected ?? false,
                            nowMs: DateTime.now().millisecondsSinceEpoch,
                          )
                        : null;
                    return ListTile(
                      dense: true,
                      title: Text(m.text),
                      subtitle: reason != null
                          ? Text(
                              reason,
                              style: Theme.of(context).textTheme.bodySmall,
                            )
                          : Text(m.mine ? 'you' : (m.fromPeerId ?? 'peer')),
                      trailing: m.mine
                          ? _DeliveryStateIcon(state: m.state)
                          : null,
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              'Cloud: $_liveStatus',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    maxLength: policy.maxMessageBytes,
                    decoration: const InputDecoration(hintText: 'Message'),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                IconButton(icon: const Icon(Icons.send), onPressed: _send),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Mesh-first status strip shown above the message list, primary over the
/// muted internet-socket line at the bottom of the screen.
class _MeshStatusBar extends StatelessWidget {
  const _MeshStatusBar({
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
      return Material(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.bluetooth_disabled, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  blockedReason ?? 'Event mode is off — messages will queue.',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: starting ? null : onStartEventMode,
                child: starting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Start'),
              ),
            ],
          ),
        ),
      );
    }
    final peerCount = status.peerCount;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  peerCount > 0
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_searching,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  peerCount > 0
                      ? 'Mesh: $peerCount peer${peerCount == 1 ? '' : 's'}'
                      : 'Mesh: no peers yet · queued',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            if (status.siteMismatchDetected)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'A nearby device is using a different event/site '
                        'code — it will not connect.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DeliveryStateIcon extends StatelessWidget {
  const _DeliveryStateIcon({required this.state});

  final RoomMessageState state;

  @override
  Widget build(BuildContext context) => switch (state) {
    RoomMessageState.queued => const Icon(
      Icons.schedule,
      size: 16,
      color: Colors.grey,
    ),
    RoomMessageState.sending => const SizedBox(
      width: 14,
      height: 14,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
    RoomMessageState.delivered => const Icon(
      Icons.check_circle,
      size: 16,
      color: Colors.green,
    ),
    RoomMessageState.failed => const Icon(
      Icons.error_outline,
      size: 16,
      color: Colors.red,
    ),
  };
}
