import 'dart:async';

import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// First sign-in: create a household or join one with an invite code.
class const WelcomeScreen({super.key, final String? invite})
    extends StatefulWidget {
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState() extends State<WelcomeScreen> {
  late final _name = TextEditingController();
  late final _code = TextEditingController(text: widget.invite ?? '');
  var _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(SessionCubit session) action) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final session = context.read<SessionCubit>();
    setState(() => _busy = true);
    try {
      await action(session);
    } on HouseholdError catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'invalid_invite'
                ? l10n.invalidInvite
                : l10n.genericError(e.code),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasInvite = widget.invite != null;
    final join = [
      TextField(
        key: const ValueKey('invite-code'),
        controller: _code,
        autofocus: hasInvite,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(labelText: l10n.inviteCode),
        onSubmitted: (_) => unawaited(_join()),
      ),
      const SizedBox(height: 12),
      FilledButton.tonal(
        onPressed: _busy ? null : () => unawaited(_join()),
        child: Text(l10n.joinHousehold),
      ),
    ];
    final create = [
      TextField(
        key: const ValueKey('household-name'),
        controller: _name,
        decoration: InputDecoration(
          labelText: l10n.householdName,
          hintText: l10n.householdNameDefault,
        ),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: _busy
            ? null
            : () => unawaited(
                _run(
                  (s) => s.createHousehold(
                    _name.text.trim().isEmpty
                        ? l10n.householdNameDefault
                        : _name.text.trim(),
                  ),
                ),
              ),
        child: Text(l10n.createHousehold),
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.onboardingTitle),
        actions: [
          IconButton(
            tooltip: l10n.signOut,
            icon: const Icon(Icons.logout),
            onPressed: () => unawaited(context.read<SessionCubit>().signOut()),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              Text(l10n.onboardingBody),
              const SizedBox(height: 24),
              // With an invite link, joining is what the user came for.
              ...hasInvite ? join : create,
              const Divider(height: 48),
              ...hasInvite ? create : join,
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _join() => _run((s) => s.join(_code.text));
}
