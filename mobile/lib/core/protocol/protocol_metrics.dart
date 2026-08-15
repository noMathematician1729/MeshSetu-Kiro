import 'dart:typed_data';

/// Port of `in.meshsetu.protocol` metrics/debug helpers
/// (Kotlin `ProtocolMetrics.kt`).
class ProtocolMetric {
  const ProtocolMetric({
    required this.timeMs,
    this.eventId,
    this.peer,
    required this.kind,
    this.value,
    this.detail,
  });

  final int timeMs;
  final String? eventId;
  final String? peer;
  final String kind;
  final int? value;
  final String? detail;
}

class JsonLineMetricSink {
  JsonLineMetricSink(this._sink);

  final StringSink _sink;

  static String _quote(String value) =>
      '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n')}"';

  void write(ProtocolMetric metric) {
    final fields = <String>[
      '"time_ms":${metric.timeMs}',
      '"kind":${_quote(metric.kind)}',
    ];
    if (metric.eventId != null) {
      fields.add('"event_id":${_quote(metric.eventId!)}');
    }
    if (metric.peer != null) {
      final truncated = metric.peer!.length > 12
          ? metric.peer!.substring(0, 12)
          : metric.peer!;
      fields.add('"peer":${_quote(truncated)}');
    }
    if (metric.value != null) fields.add('"value":${metric.value}');
    if (metric.detail != null) fields.add('"detail":${_quote(metric.detail!)}');
    _sink.write('{${fields.join(',')}}\n');
  }
}

class LossyFrameInterceptor {
  LossyFrameInterceptor({this.dropEvery = 0, this.corruptEvery = 0});

  final int dropEvery;
  final int corruptEvery;
  int _count = 0;

  Uint8List? apply(Uint8List frame) {
    _count++;
    if (dropEvery > 0 && _count % dropEvery == 0) return null;
    if (corruptEvery > 0 && _count % corruptEvery == 0) {
      final corrupted = Uint8List.fromList(frame);
      corrupted[corrupted.length - 1] ^= 1;
      return corrupted;
    }
    return frame;
  }
}
