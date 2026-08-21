/// Shared formatting for control-room resolved incidents.
///
/// The backend returns the same record the admin dashboard renders. Peers and
/// emergency contacts get a compact summary of it in their notification, and
/// the notification itself links to the dedicated incident page.
library;

/// Origin of the public incident page. The backend also embeds a `public_url`
/// in fan-out records; this is the fallback when only an event id is known.
String publicIncidentUrl(String backendBaseUrl, String eventId) {
  final normalized = backendBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final base = normalized.isEmpty
      ? 'https://meshsetu.vercel.app'
      : normalized.replaceFirst(
          RegExp(r'^https://sih26-1xdevs\.onrender\.com$'),
          'https://meshsetu.vercel.app',
        );
  return '$base/sos/${Uri.encodeComponent(eventId)}';
}

/// One-line summary of a resolved incident, using the same fields the admin
/// dashboard shows. Unresolved values are omitted rather than shown as null.
String describeIncident(Map<String, Object?> incident) {
  final reporter = _text(incident['reporter_name']);
  final phone = _text(incident['reporter_phone']);
  final type = _text(incident['incident_type']);
  final priority = _text(incident['priority']);
  final zone = _text(incident['zone']);
  final transcript = _text(incident['transcript']);
  final blood = _text(incident['reporter_blood_group']);
  final latitude = _number(incident['latitude']);
  final longitude = _number(incident['longitude']);

  final parts = <String>[
    if (reporter.isNotEmpty) phone.isEmpty ? reporter : '$reporter · $phone',
    if (type.isNotEmpty) type.replaceAll('_', ' '),
    if (priority.isNotEmpty) priority,
    if (zone.isNotEmpty) zone,
    if (latitude != null && longitude != null)
      'GPS ${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
    if (blood.isNotEmpty) 'Blood $blood',
    if (transcript.isNotEmpty) '“$transcript”',
  ];
  if (parts.isEmpty) return 'Emergency details available. Tap to open.';
  return '${parts.join(' · ')}\nTap to open the full incident page.';
}

String _text(Object? value) {
  final text = '${value ?? ''}'.trim();
  return text == 'null' ? '' : text;
}

double? _number(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('${value ?? ''}');
