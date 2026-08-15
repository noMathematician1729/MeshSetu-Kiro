import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'app/event_mode_screen.dart';

/// Port of `in.meshsetu.app.MainActivity` (Kotlin `app/` module) — the
/// runnable shell. Same scope as the Kotlin source: it shows a single
/// screen and starts a foreground service with a persistent notification.
/// It does not itself wire up BLE scanning/advertising/relay — the Kotlin
/// `MeshEventService` didn't either; both are shells for `core-ble` to be
/// driven from later.
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
