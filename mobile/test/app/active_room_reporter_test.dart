import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/app/active_room_reporter.dart';

void main() {
  group('ActiveRoomReporter', () {
    test('sends active_room: roomId on reportActive', () {
      final sent = <Object>[];
      final reporter = ActiveRoomReporter(
        roomId: 'public',
        sendToTask: sent.add,
      );

      reporter.reportActive();

      expect(sent, hasLength(1));
      expect(sent.first, {'active_room': 'public'});
    });

    test('sends active_room: null on reportInactive', () {
      final sent = <Object>[];
      final reporter = ActiveRoomReporter(
        roomId: 'public',
        sendToTask: sent.add,
      );

      reporter.reportInactive();

      expect(sent, hasLength(1));
      expect(sent.first, {'active_room': null});
    });

    test('does not send duplicate consecutive active reports', () {
      final sent = <Object>[];
      final reporter = ActiveRoomReporter(
        roomId: 'public',
        sendToTask: sent.add,
      );

      reporter.reportActive();
      reporter.reportActive();
      reporter.reportActive();

      expect(sent, hasLength(1));
    });

    test('does not send duplicate consecutive inactive reports', () {
      final sent = <Object>[];
      final reporter = ActiveRoomReporter(
        roomId: 'public',
        sendToTask: sent.add,
      );

      reporter.reportInactive();
      reporter.reportInactive();

      expect(sent, hasLength(1));
    });

    test('sends again after a state change', () {
      final sent = <Object>[];
      final reporter = ActiveRoomReporter(
        roomId: 'public',
        sendToTask: sent.add,
      );

      reporter.reportActive();
      reporter.reportInactive();
      reporter.reportActive();

      expect(sent, hasLength(3));
      expect(sent[0], {'active_room': 'public'});
      expect(sent[1], {'active_room': null});
      expect(sent[2], {'active_room': 'public'});
    });
  });
}
