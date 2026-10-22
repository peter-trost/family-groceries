import 'dart:async';

import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// An invite opened by someone who already has a household.
class const JoinScreen({required final String code, super.key})
    extends StatefulWidget {
  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState() extends State<JoinScreen> {
  var _busy = false;

  Future<void> _join() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() => _busy = true);
    try {
      await context.read<SessionCubit>().join(widget.code);
      router.go(listPath);
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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.joinOtherHousehold)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              Text(
                widget.code,
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(l10n.switchHouseholdWarning),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : () => unawaited(_join()),
                child: Text(l10n.joinHousehold),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.go(listPath),
                child: Text(l10n.cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
