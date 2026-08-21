import 'package:flutter/material.dart';

import '../feature/sos/sos_incident_screen.dart';

/// App-owned deep-link format used as the payload of SOS notifications.
///
/// It deliberately does not use an https URL: Android re-enters MeshSetu and
/// the incident is rendered by [SosIncidentScreen], not in a browser.
abstract final class SosIncidentNavigator {
  static const String _scheme = 'meshsetu';
  static const String _host = 'sos';
  static final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();
  static String? _pendingEventId;

  static String payloadForEvent(String eventId) =>
      '$_scheme://$_host/${Uri.encodeComponent(eventId)}';

  static String? eventIdFromPayload(String? payload) {
    final uri = Uri.tryParse((payload ?? '').trim());
    if (uri == null || uri.scheme != _scheme || uri.host != _host) {
      return null;
    }
    if (uri.pathSegments.length != 1 || uri.pathSegments.single.isEmpty) {
      return null;
    }
    return uri.pathSegments.single;
  }

  static void openPayload(String? payload) {
    final eventId = eventIdFromPayload(payload);
    if (eventId == null) return;
    openEvent(eventId);
  }

  static void openEvent(String eventId) {
    final navigator = key.currentState;
    if (navigator == null) {
      _pendingEventId = eventId;
      return;
    }
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => SosIncidentScreen(eventId: eventId),
        settings: RouteSettings(name: '/sos/$eventId'),
      ),
    );
  }

  static void openPending() {
    final eventId = _pendingEventId;
    _pendingEventId = null;
    if (eventId != null) openEvent(eventId);
  }
}
