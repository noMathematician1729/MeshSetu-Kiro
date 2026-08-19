import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'onboarding_profile.dart';

/// Startup gate for the sender identity requirement. The profile is read from
/// encrypted local storage; no enrollment network call is needed while offline.
class OnboardingGate extends ConsumerWidget {
  const OnboardingGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(onboardingProfileProvider);
    return profile.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Unable to load your emergency profile: $error'),
          ),
        ),
      ),
      data: (value) => value == null
          ? OnboardingScreen(
              onComplete: () => ref.invalidate(onboardingProfileProvider),
            )
          : child,
    );
  }
}

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.initialProfile, this.onComplete});

  final OnboardingProfile? initialProfile;
  final VoidCallback? onComplete;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _language;
  late final TextEditingController _bloodGroup;
  late final TextEditingController _allergies;
  late final TextEditingController _conditions;
  late final List<_ContactEditors> _contacts;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final profile = widget.initialProfile;
    _name = TextEditingController(text: profile?.name ?? '');
    _phone = TextEditingController(text: profile?.phone ?? '');
    _language = TextEditingController(text: profile?.language ?? 'English');
    _bloodGroup = TextEditingController(
      text: profile?.medicalProfile.bloodGroup ?? '',
    );
    _allergies = TextEditingController(
      text: profile?.medicalProfile.allergies ?? '',
    );
    _conditions = TextEditingController(
      text: profile?.medicalProfile.conditions ?? '',
    );
    _contacts = [
      for (final contact in profile?.emergencyContacts ?? const [])
        _ContactEditors(contact),
      if ((profile?.emergencyContacts ?? const []).isEmpty) _ContactEditors(),
    ];
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _language.dispose();
    _bloodGroup.dispose();
    _allergies.dispose();
    _conditions.dispose();
    for (final contact in _contacts) {
      contact.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final profile = OnboardingProfile.create(
      profileId: widget.initialProfile?.profileId,
      name: _name.text,
      phone: _phone.text,
      language: _language.text,
      emergencyContacts: [
        for (var index = 0; index < _contacts.length; index++)
          EmergencyContact(
            name: _contacts[index].name.text,
            phone: _contacts[index].phone.text,
            priority: index + 1,
          ),
      ],
      medicalProfile: MedicalProfile(
        bloodGroup: _bloodGroup.text,
        allergies: _allergies.text,
        conditions: _conditions.text,
      ),
    );
    final validationError = profile.validationError;
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(onboardingRepositoryProvider).save(profile);
      ref.invalidate(onboardingProfileProvider);
      widget.onComplete?.call();
      if (mounted && widget.onComplete == null) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not save profile: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Emergency profile setup')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Set up the information attached to your encrypted SOS packet. '
            'This profile is stored securely on this device.',
          ),
          const SizedBox(height: 16),
          _field(_name, 'Your name', required: true),
          const SizedBox(height: 12),
          _field(
            _phone,
            'Your phone number',
            required: true,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          _field(_language, 'Preferred language', required: true),
          const SizedBox(height: 20),
          Text(
            'Emergency contacts',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < _contacts.length; index++) ...[
            _contactFields(index),
            const SizedBox(height: 8),
          ],
          if (_contacts.length < 10)
            OutlinedButton.icon(
              onPressed: () => setState(() => _contacts.add(_ContactEditors())),
              icon: const Icon(Icons.add),
              label: const Text('Add emergency contact'),
            ),
          const SizedBox(height: 20),
          Text(
            'Medical information (optional)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _field(_bloodGroup, 'Blood group'),
          const SizedBox(height: 12),
          _field(_allergies, 'Allergies', maxLines: 2),
          const SizedBox(height: 12),
          _field(_conditions, 'Medical conditions', maxLines: 2),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving profile…' : 'Save emergency profile'),
          ),
        ],
      ),
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) => TextField(
    controller: controller,
    maxLines: maxLines,
    keyboardType: keyboardType,
    decoration: InputDecoration(
      labelText: required ? '$label *' : label,
      border: const OutlineInputBorder(),
    ),
  );

  Widget _contactFields(int index) {
    final contact = _contacts[index];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: Text('Contact ${index + 1}')),
                if (_contacts.length > 1)
                  IconButton(
                    tooltip: 'Remove contact',
                    onPressed: () => setState(() {
                      final removed = _contacts.removeAt(index);
                      removed.dispose();
                    }),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
              ],
            ),
            _field(contact.name, 'Name', required: true),
            const SizedBox(height: 8),
            _field(
              contact.phone,
              'Phone number',
              required: true,
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
      ),
    );
  }
}

final class _ContactEditors {
  _ContactEditors([EmergencyContact? contact])
    : name = TextEditingController(text: contact?.name ?? ''),
      phone = TextEditingController(text: contact?.phone ?? '');

  final TextEditingController name;
  final TextEditingController phone;

  void dispose() {
    name.dispose();
    phone.dispose();
  }
}
