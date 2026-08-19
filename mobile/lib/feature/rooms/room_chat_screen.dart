import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'room_policy.dart';

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
  String? _error;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final policy = policyForRole(widget.roomId, widget.role);
    final userRoles = ref.read(userRolesProvider);
    try {
      await ref
          .read(roomRepositoryProvider(widget.siteId))
          .sendMessage(policy: policy, userRoles: userRoles, text: text);
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
              data: (items) => ListView.builder(
                reverse: true,
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final m = items[items.length - 1 - i];
                  return ListTile(
                    dense: true,
                    title: Text(m.text),
                    subtitle: Text(m.mine ? 'you' : (m.fromPeerId ?? 'peer')),
                  );
                },
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
