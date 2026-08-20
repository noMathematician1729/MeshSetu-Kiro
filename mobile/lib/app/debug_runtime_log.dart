import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

/// Temporary runtime evidence collection for SOS/GATT debugging.
abstract final class DebugRuntimeLog {
  static const _path =
      '/Users/shantanavmukherjee/Desktop/code/hack-projects/SIH26_-1xDevs/.cursor/debug-e4e0e8.log';

  static void write({
    required String hypothesisId,
    required String location,
    required String message,
    Map<String, Object?> data = const {},
  }) {
    final payload = <String, Object?>{
      'sessionId': 'e4e0e8',
      'runId': 'initial',
      'hypothesisId': hypothesisId,
      'location': location,
      'message': message,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    final line = jsonEncode(payload);
    developer.log(line, name: 'MeshSetuDebug');
    File(_path).writeAsString('$line\n', mode: FileMode.append).catchError(
      (_) {},
    );
  }
}
