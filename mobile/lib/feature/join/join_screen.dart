import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/providers.dart';
import 'manifest.dart';

/// Mesh Code / QR join screen (Bible §9.3, `feature/join`). Typed code and
/// QR scan both resolve to the same [JoinResult] path.
class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key, this.onJoined, this.createRoomOnly = false});

  final ValueChanged<String?>? onJoined;
  final bool createRoomOnly;

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  final _codeController = TextEditingController();
  String? _error;
  bool _scanning = false;
  bool _submitting = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submitCode() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await ref
        .read(joinRepositoryProvider)
        .parseAndValidateTypedCode(_codeController.text);
    await _handleResult(result);
  }

  Future<void> _createLocalEvent() async {
    if (_scanning) setState(() => _scanning = false);
    final siteName = await showDialog<String>(
      context: context,
      builder: (_) => const _CreateEventDialog(),
    );
    if (siteName == null || siteName.isEmpty || !mounted) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final manifest = await ref
          .read(joinRepositoryProvider)
          .createLocalEvent(siteName: siteName);
      refreshActiveSite(ref);
      if (!mounted) return;
      setState(() => _submitting = false);
      await _announceRoomJoin(manifest, manifest.rooms.first.roomId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Created ${manifest.siteName}')));
      widget.onJoined?.call(manifest.rooms.first.roomId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not create event: $error';
      });
    }
  }

  Future<void> _announceRoomJoin(EventManifest manifest, String roomId) async {
    try {
      final profile = await ref.read(onboardingRepositoryProvider).load();
      if (profile == null) return;
      await ref
          .read(roomRepositoryProvider(manifest.siteId))
          .announceMember(
            roomId: roomId,
            memberId: profile.profileId,
            displayName: profile.name,
          );
    } catch (_) {
      // Joining remains available when an optional presence update cannot queue.
    }
  }

  Future<void> _handleQr(String raw) async {
    if (!_scanning) return;
    setState(() => _scanning = false);
    final result = await ref
        .read(joinRepositoryProvider)
        .parseAndValidateQr(raw);
    await _handleResult(result);
  }

  Future<void> _handleResult(JoinResult result) async {
    if (!mounted) return;
    setState(() => _submitting = false);
    switch (result) {
      case JoinOk(:final manifest, :final roomId):
        refreshActiveSite(ref);
        if (roomId != null) unawaited(_announceRoomJoin(manifest, roomId));
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Joined ${manifest.siteName}')));
        widget.onJoined?.call(roomId);
      case JoinInvalid(:final reason):
        setState(
          () => _error = reason == 'unknown_code'
              ? 'Unknown code. Enter the organizer code, scan their QR, or create an event below.'
              : 'Join failed: $reason',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.createRoomOnly ? 'Create room' : 'Join room'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (!widget.createRoomOnly) ...[
              Text(
                'Enter the room code the organizer shared, or scan its QR.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Room code',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _submitting ? null : _submitCode,
                child: const Text('Join with code'),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(_scanning ? 'Scanning…' : 'Scan QR instead'),
                onPressed: () => setState(() => _scanning = !_scanning),
              ),
              const SizedBox(height: 12),
            ] else ...[
              Text(
                'Create a room lobby, then share its QR with the people you want to join.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],
            FilledButton.tonalIcon(
              icon: const Icon(Icons.add_home_work_outlined),
              label: Text(
                widget.createRoomOnly ? 'Name and create room' : 'Create room',
              ),
              onPressed: _submitting ? null : _createLocalEvent,
            ),
            const SizedBox(height: 8),
            const Text(
              'This creates a room lobby and its join QR. Add more rooms later if needed.',
              textAlign: TextAlign.center,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (_scanning)
              Expanded(
                child: MobileScanner(
                  controller: MobileScannerController(
                    formats: const [BarcodeFormat.qrCode],
                  ),
                  onDetect: (capture) {
                    if (capture.barcodes.isEmpty) return;
                    final raw = capture.barcodes.first.rawValue;
                    if (raw != null) unawaited(_handleQr(raw));
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CreateEventDialog extends StatefulWidget {
  const _CreateEventDialog();

  @override
  State<_CreateEventDialog> createState() => _CreateEventDialogState();
}

class _CreateEventDialogState extends State<_CreateEventDialog> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create room'),
    content: TextField(
      controller: _nameController,
      autofocus: true,
      decoration: const InputDecoration(
        labelText: 'Room name',
        hintText: 'e.g. Campus Safety Drill',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_nameController.text.trim()),
        child: const Text('Create'),
      ),
    ],
  );
}
