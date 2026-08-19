import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// CEAL-inspired personal profile retained locally until an SOS is finalized.
/// Medical details remain on-device; only the compact [SosReporter] snapshot
/// selected by the SOS repository is added to an encrypted mesh envelope.
final class OnboardingProfile {
  const OnboardingProfile({
    required this.profileId,
    required this.reporterUid,
    required this.name,
    required this.phone,
    required this.language,
    required this.emergencyContacts,
    required this.medicalProfile,
  });

  factory OnboardingProfile.create({
    required String name,
    required String phone,
    required String language,
    required List<EmergencyContact> emergencyContacts,
    required MedicalProfile medicalProfile,
    String? profileId,
  }) => OnboardingProfile(
    profileId: profileId ?? _uuid.v4(),
    reporterUid: '',
    name: name.trim(),
    phone: phone.trim(),
    language: language.trim(),
    emergencyContacts: List.unmodifiable(emergencyContacts),
    medicalProfile: medicalProfile,
  );

  factory OnboardingProfile.fromJson(Map<String, Object?> json) =>
      OnboardingProfile(
        profileId: json['profileId'] as String? ?? '',
        reporterUid: json['reporterUid'] as String? ?? '',
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        language: json['language'] as String? ?? '',
        emergencyContacts: [
          for (final item in (json['emergencyContacts'] as List? ?? const []))
            if (item is Map)
              EmergencyContact.fromJson(item.cast<String, Object?>()),
        ],
        medicalProfile: json['medicalProfile'] is Map
            ? MedicalProfile.fromJson(
                (json['medicalProfile'] as Map).cast<String, Object?>(),
              )
            : const MedicalProfile(),
      );

  final String profileId;
  final String reporterUid;
  final String name;
  final String phone;
  final String language;
  final List<EmergencyContact> emergencyContacts;
  final MedicalProfile medicalProfile;

  String? get validationError {
    if (profileId.trim().isEmpty) return 'Profile ID is missing.';
    if (name.trim().isEmpty) return 'Enter your name.';
    if (!_validPhone(phone)) return 'Enter a valid phone number.';
    if (language.trim().isEmpty) return 'Select a language.';
    if (emergencyContacts.isEmpty) {
      return 'Add at least one emergency contact.';
    }
    if (emergencyContacts.length > 10) {
      return 'A maximum of 10 emergency contacts is supported.';
    }
    for (final contact in emergencyContacts) {
      if (contact.validationError != null) return contact.validationError;
    }
    return null;
  }

  bool get isValid => validationError == null;

  EmergencyContact get primaryContact => emergencyContacts.first;

  OnboardingProfile withReporterUid(String value) => OnboardingProfile(
    profileId: profileId,
    reporterUid: value,
    name: name,
    phone: phone,
    language: language,
    emergencyContacts: emergencyContacts,
    medicalProfile: medicalProfile,
  );

  Map<String, Object?> toJson() => {
    'profileId': profileId,
    'reporterUid': reporterUid,
    'name': name,
    'phone': phone,
    'language': language,
    'emergencyContacts': [
      for (final contact in emergencyContacts) contact.toJson(),
    ],
    'medicalProfile': medicalProfile.toJson(),
  };

  static bool _validPhone(String value) =>
      RegExp(r'^\+?[0-9][0-9 ()-]{5,23}$').hasMatch(value.trim());
}

final class EmergencyContact {
  const EmergencyContact({
    required this.name,
    required this.phone,
    this.priority = 1,
  });

  factory EmergencyContact.fromJson(Map<String, Object?> json) =>
      EmergencyContact(
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        priority: (json['priority'] as num?)?.toInt() ?? 1,
      );

  final String name;
  final String phone;
  final int priority;

  String? get validationError {
    if (name.trim().isEmpty) return 'Emergency contact name is required.';
    if (!OnboardingProfile._validPhone(phone)) {
      return 'Enter a valid emergency contact phone number.';
    }
    if (priority < 1) return 'Emergency contact priority must be positive.';
    return null;
  }

  Map<String, Object?> toJson() => {
    'name': name.trim(),
    'phone': phone.trim(),
    'priority': priority,
  };
}

final class MedicalProfile {
  const MedicalProfile({
    this.bloodGroup = '',
    this.allergies = '',
    this.conditions = '',
  });

  factory MedicalProfile.fromJson(Map<String, Object?> json) => MedicalProfile(
    bloodGroup: json['bloodGroup'] as String? ?? '',
    allergies: json['allergies'] as String? ?? '',
    conditions: json['conditions'] as String? ?? '',
  );

  final String bloodGroup;
  final String allergies;
  final String conditions;

  Map<String, Object?> toJson() => {
    'bloodGroup': bloodGroup.trim(),
    'allergies': allergies.trim(),
    'conditions': conditions.trim(),
  };
}
