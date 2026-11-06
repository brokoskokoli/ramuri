import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'profile_form.dart';

/// Profilseite (FR-0002 bis FR-0005).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.session, required this.clock});

  final StorageSession session;
  final Clock clock;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.profileIntro),
          const SizedBox(height: 16),
          ProfileForm(
            service: ProfileService(session.profile, clock),
            clock: clock,
            onSaved: (_) =>
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(l10n.profileSaved))),
          ),
        ],
      ),
    );
  }
}
