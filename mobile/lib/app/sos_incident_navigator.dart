import 'package:flutter/material.dart';

import '../core/ble/sos_advertisement.dart';
import '../feature/sos/compact_sos_packet_screen.dart';
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
  static MeshSosAdvertisement? _pendingCompactAlert;

  static String payloadForEvent(String eventId) =>
      '$_scheme://$_host/${Uri.encodeComponent(eventId)}';

  /// Payload for an unresolved compact packet. Tapping it opens the exact
  /// packet details that are safe to disclose without control-room lookup.
  static String payloadForCompactAlert(MeshSosAdvertisement alert) => Uri(
    scheme: _scheme,
    host: 'packet',
    queryParameters: {
      'site': alert.siteFingerprint.toString(),
      'origin': alert.originId.toString(),
      'sequence': alert.sequence.toString(),
      'flags': alert.flags.toString(),
      'ttl': alert.ttl.toString(),
      if (alert.hasReporterUid) 'uid': alert.reporterUidHex,
    },
  ).toString();

  static MeshSosAdvertisement? compactAlertFromPayload(String? payload) {
    final uri = Uri.tryParse((payload ?? '').trim());
    if (uri == null || uri.scheme != _scheme || uri.host != 'packet') {
      return null;
    }
    final site = int.tryParse(uri.queryParameters['site'] ?? '');
    final origin = int.tryParse(uri.queryParameters['origin'] ?? '');
    final sequence = int.tryParse(uri.queryParameters['sequence'] ?? '');
    final flags = int.tryParse(uri.queryParameters['flags'] ?? '');
    final ttl = int.tryParse(uri.queryParameters['ttl'] ?? '');
    if (site == null ||
        origin == null ||
        sequence == null ||
        flags == null ||
        ttl == null) {
      return null;
    }
    return MeshSosAdvertisement(
      siteFingerprint: site,
      originId: origin,
      sequence: sequence,
      flags: flags,
      ttl: ttl,
      reporterUidHex: MeshSosAdvertisement.normalizeReporterUid(
        uri.queryParameters['uid'],
      ),
    );
  }

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
    final compactAlert = compactAlertFromPayload(payload);
    if (compactAlert != null) {
      openCompactAlert(compactAlert);
      return;
    }
    final eventId = eventIdFromPayload(payload);
    if (eventId == null) return;
    openEvent(eventId);
  }

  static void openCompactAlert(MeshSosAdvertisement alert) {
    if (_pushCompactAlert(alert)) return;
    _pendingCompactAlert = alert;
  }

  static void openEvent(String eventId) {
    if (_push(eventId)) return;
    // A tap can cold-start the app, arriving before the navigator is mounted.
    // Hold the destination; [openPending] delivers it on the first frame so
    // the user is not left on the home screen.
    _pendingEventId = eventId;
  }

  /// Flushes a tap that arrived before the navigator existed.
  static void openPending() {
    final eventId = _pendingEventId;
    if (eventId != null) {
      if (_push(eventId)) return;
      _pendingEventId = eventId;
      return;
    }
    final compactAlert = _pendingCompactAlert;
    if (compactAlert == null) return;
    if (_pushCompactAlert(compactAlert)) return;
    _pendingCompactAlert = compactAlert;
  }

  static bool _pushCompactAlert(MeshSosAdvertisement alert) {
    final navigator = key.currentState;
    if (navigator == null) return false;
    _pendingCompactAlert = null;
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => CompactSosPacketScreen(alert: alert),
        settings: RouteSettings(name: '/sos-packet/${alert.dedupeKey}'),
      ),
    );
    return true;
  }

  static bool _push(String eventId) {
    final navigator = key.currentState;
    if (navigator == null) return false;
    _pendingEventId = null;
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => SosIncidentScreen(eventId: eventId),
        settings: RouteSettings(name: '/sos/$eventId'),
      ),
    );
    return true;
  }
}
