import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/providers.dart';
import 'manifest.dart';

/// Mesh Code / QR join screen (Bible §9.3, `feature/join`). Typed code and
/// QR scan both resolve to the same [JoinResult] path.
class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key, this.onJoined});

  final ValueChanged<String?>? onJoined;

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
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Joined ${manifest.siteName}')));
        widget.onJoined?.call(roomId);
      case JoinInvalid(:final reason):
        setState(() => _error = 'Join failed: $reason');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join event')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Enter the Mesh Code the site organizer shared, or scan its QR.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Mesh Code',
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
