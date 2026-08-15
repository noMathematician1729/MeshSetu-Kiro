import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'app/event_mode_screen.dart';

/// Port of `in.meshsetu.app.MainActivity` (Kotlin `app/` module) — the
/// runnable shell. The foreground task owns BLE discovery, relay transport,
/// metrics, and the small diagnostic bridge displayed by the event screen.
void main() {
  FlutterForegroundTask.initCommunicationPort();
  runApp(const MeshSetuApp());
}

class MeshSetuApp extends StatelessWidget {
  const MeshSetuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MeshSetu',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const EventModeScreen(),
    );
  }
}
