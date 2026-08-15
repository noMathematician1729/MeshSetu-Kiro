import 'package:collection/collection.dart';

import '../model/model.dart';

/// Port of `in.meshsetu.protocol.OutboundScheduler` /
/// `RecentObjectCache` (Kotlin `OutboundScheduler.kt`).
class OutboundScheduler {
  final PriorityQueue<EncryptedObject> _queue = PriorityQueue<EncryptedObject>(
    _compare,
  );

  static int _compare(EncryptedObject a, EncryptedObject b) {
    final rank = a.trafficClass.rank.compareTo(b.trafficClass.rank);
    if (rank != 0) return rank;
    final expiry = a.expiresAtMs.compareTo(b.expiresAtMs);
    if (expiry != 0) return expiry;
    // objectId is an unsigned 64-bit tie-break in the Kotlin source; compare
    // by unsigned magnitude, matching model.dart's ULong-as-int convention.
    return a.objectId.toUnsigned(64).compareTo(b.objectId.toUnsigned(64));
  }

  void enqueue(EncryptedObject value, int nowMs) {
    if (value.bytes.isEmpty) {
      throw ArgumentError('EncryptedObject.bytes must not be empty');
    }
    if (value.expiresAtMs > nowMs) _queue.add(value);
  }

  EncryptedObject? next(int nowMs) {
    while (_queue.isNotEmpty && _queue.first.expiresAtMs <= nowMs) {
      _queue.removeFirst();
    }
    return _queue.isEmpty ? null : _queue.removeFirst();
  }

  int size() => _queue.length;
}

class RecentObjectCache {
  RecentObjectCache({this.maxEntries = 4096});

  final int maxEntries;
  final Map<int, int> _seen = <int, int>{};

  bool markIfNew(int id, int expiresAtMs, int nowMs) {
    _seen.removeWhere((_, expiry) => expiry <= nowMs);
    if (_seen.containsKey(id)) return false;
    _seen[id] = expiresAtMs;
    if (_seen.length > maxEntries) {
      _seen.remove(_seen.keys.first);
    }
    return true;
  }
}
