import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
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

class _RoomChatScreenState extends ConsumerState<RoomChatScreen> {
  final _textController = TextEditingController();
  RoomPresenceSocket? _messageSocket;
  final Map<String, RoomMessage> _liveMessages = {};
  final Map<String, String> _pendingLiveMessages = {};
  String _liveStatus = 'Connecting to live chat…';
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_connectLiveMessages());
  }

  Future<void> _connectLiveMessages() async {
    final profile = await ref.read(onboardingRepositoryProvider).load();
    if (!mounted || profile == null) return;
    final rawUrl = ref.read(gatewayUrlProvider).trim();
    final baseUrl = Uri.tryParse(rawUrl);
    if (baseUrl == null || !baseUrl.hasScheme) return;
    final socket = RoomPresenceSocket(
      baseUrl: baseUrl,
      gatewayKey: ref.read(gatewayDemoKeyProvider),
      siteId: widget.siteId,
      roomId: widget.roomId,
      memberId: profile.profileId,
      displayName: profile.name,
    );
    _messageSocket = socket;
    for (final entry in _pendingLiveMessages.entries) {
      socket.sendRoomMessage(messageId: entry.key, text: entry.value);
    }
    _pendingLiveMessages.clear();
    socket.debug.listen((status) {
      if (mounted) setState(() => _liveStatus = status);
    });
    socket.messages.listen((message) {
      if (!mounted) return;
      setState(() {
        _liveMessages[message.messageId] = RoomMessage(
          eventId: message.messageId,
          text: message.text,
          fromPeerId: message.displayName,
          atMs: message.sentAtMs,
          mine: message.memberId == profile.profileId,
        );
      });
    });
    socket.start();
  }

  @override
  void dispose() {
    _textController.dispose();
    unawaited(_messageSocket?.dispose());
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final policy = policyForRole(widget.roomId, widget.role);
    final userRoles = ref.read(userRolesProvider);
    try {
      final eventId = await ref
          .read(roomRepositoryProvider(widget.siteId))
          .sendMessage(policy: policy, userRoles: userRoles, text: text);
      final socket = _messageSocket;
      if (socket == null) {
        _pendingLiveMessages[eventId] = text;
      } else {
        socket.sendRoomMessage(messageId: eventId, text: text);
      }
      _textController.clear();
      setState(() => _error = null);
    } on StateError catch (e) {
      setState(() => _error = e.message);
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.roomName)),
      body: Column(
        children: [
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (items) {
                final merged = <String, RoomMessage>{
                  for (final message in items) message.eventId: message,
                  ..._liveMessages,
                };
                final visible = merged.values.toList()
                  ..sort((a, b) => a.atMs.compareTo(b.atMs));
                return ListView.builder(
                  reverse: true,
                  itemCount: visible.length,
                  itemBuilder: (context, i) {
                    final m = visible[visible.length - 1 - i];
                    return ListTile(
                      dense: true,
                      title: Text(m.text),
                      subtitle: Text(m.mine ? 'you' : (m.fromPeerId ?? 'peer')),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              'Live chat: $_liveStatus',
              style: Theme.of(context).textTheme.bodySmall,
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
