import 'dart:async';

/// Serializes asynchronous operations that mutate one BLE link's state.
class AsyncLock {
  Future<void> _tail = Future<void>.value();

  Future<void> get idle => _tail;

  Future<T> synchronized<T>(Future<T> Function() action) {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    return previous.then((_) async {
      try {
        return await action();
      } finally {
        release.complete();
      }
    });
  }
}
