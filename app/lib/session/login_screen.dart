import 'dart:async';

import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/provider_buttons.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/session/social_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class const LoginScreen({
  super.key,

  /// Carried through so a magic link lands back on the invite.
  final String? invite,

  /// A consent URL to return to after sign-in, already vetted by the router.
  final String? next,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final invite = this.invite;
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).signInTitle)),
      body: Center(
        child: SignInPanel(
          returnPath: next ?? (invite == null ? '/' : '/join/$invite'),
        ),
      ),
    );
  }
}

/// Every sign-in method: Google, Apple, email and password, magic link.
/// The MCP consent page embeds it too, with its own [returnPath].
class const SignInPanel({
  /// Where a web redirect or magic link lands after sign-in, e.g.
  /// `/join/ABCD2345`. The mobile apps always return through
  /// [mobileAuthCallback].
  required final String returnPath,
  super.key,
}) extends StatefulWidget {
  @override
  State<SignInPanel> createState() => _SignInPanelState();
}

class _SignInPanelState() extends State<SignInPanel> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _busy = false;
  var _passwordRequired = true;

  @override
  void initState() {
    super.initState();
    if (context.read<SessionCubit>().state case SignedOut(:final error?)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _report(error);
        }
      });
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  GoTrueClient get _auth => Supabase.instance.client.auth;

  String get _redirectTo =>
      kIsWeb ? '${Uri.base.origin}${widget.returnPath}' : mobileAuthCallback;

  void _report(Object error) {
    final l10n = AppLocalizations.of(context);
    final message = switch (error) {
      SocialSignInCanceled() ||
      AuthException(code: 'access_denied') => l10n.signInCanceled,
      AuthException(:final message) => l10n.authFailed(message),
      _ => l10n.authFailed('$error'),
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs an auth call; a returned message is shown to the user.
  Future<void> _run(Future<String?> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      if (await action() case final message?) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } on Exception catch (e) {
      if (mounted) {
        _report(e);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _runWithForm(
    Future<String?> Function() action, {
    bool needsPassword = true,
  }) async {
    _passwordRequired = needsPassword;
    if (_form.currentState!.validate()) {
      await _run(action);
    }
  }

  Future<void> _signIn() => _runWithForm(() async {
    await _auth.signInWithPassword(
      email: _email.text.trim(),
      password: _password.text,
    );
    return null;
  });

  Future<void> _social(SocialProvider provider) => _run(() async {
    await context.read<SocialSignIn>().signIn(
      provider,
      redirectTo: _redirectTo,
    );
    return null;
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final flows = context.read<SocialSignIn>().flows;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          shrinkWrap: true,
          children: [
            if (flows.containsKey(SocialProvider.google)) ...[
              GoogleSignInButton(
                key: const ValueKey('sign-in-google'),
                label: l10n.signInWithGoogle,
                onPressed: _busy
                    ? null
                    : () => unawaited(_social(SocialProvider.google)),
              ),
              const SizedBox(height: 12),
            ],
            if (flows.containsKey(SocialProvider.apple)) ...[
              AppleSignInButton(
                key: const ValueKey('sign-in-apple'),
                label: l10n.signInWithApple,
                onPressed: _busy
                    ? null
                    : () => unawaited(_social(SocialProvider.apple)),
              ),
              const SizedBox(height: 12),
            ],
            if (flows.isNotEmpty) ...[
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(l10n.orWithEmail),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(labelText: l10n.email),
              validator: (v) =>
                  (v ?? '').trim().contains('@') ? null : l10n.invalidEmail,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(labelText: l10n.password),
              validator: (v) => !_passwordRequired || (v ?? '').length >= 6
                  ? null
                  : l10n.passwordTooShort,
              onFieldSubmitted: (_) => unawaited(_signIn()),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : () => unawaited(_signIn()),
              child: Text(l10n.signIn),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => unawaited(
                      _runWithForm(() async {
                        final res = await _auth.signUp(
                          email: _email.text.trim(),
                          password: _password.text,
                          emailRedirectTo: _redirectTo,
                        );
                        return res.session == null
                            ? l10n.signUpCheckEmail
                            : null;
                      }),
                    ),
              child: Text(l10n.signUp),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => unawaited(
                      _runWithForm(() async {
                        await _auth.signInWithOtp(
                          email: _email.text.trim(),
                          emailRedirectTo: _redirectTo,
                        );
                        return l10n.magicLinkSent;
                      }, needsPassword: false),
                    ),
              child: Text(l10n.sendMagicLink),
            ),
          ],
        ),
      ),
    );
  }
}
