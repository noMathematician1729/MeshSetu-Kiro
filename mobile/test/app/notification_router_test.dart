import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/app/notification_router.dart';

void main() {
  test('incident notification payload retains durable incident identity', () {
    final payload = NotificationRouter.incidentPayload(
      siteId: 'demo-site',
      eventId: 'event-1',
      objectId: 42,
    );
    expect(jsonDecode(payload), {
      'siteId': 'demo-site',
      'eventId': 'event-1',
      'objectId': 42,
    });
  });
}
