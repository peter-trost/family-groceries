import 'dart:async';

import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class const LoginScreen({
  super.key,

  /// Carried through so a magic link lands back on the invite.
  final String? invite,
}) extends StatefulWidget {
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState() extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _busy = false;
  var _passwordRequired = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  GoTrueClient get _auth => Supabase.instance.client.auth;

  String? get _redirectTo {
    if (!kIsWeb) {
      return null;
    }
    final invite = widget.invite;
    return '${Uri.base.origin}${invite == null ? '/' : '/join/$invite'}';
  }

  /// Runs an auth call; a returned message is shown to the user.
  Future<void> _run(
    Future<String?> Function() action, {
    bool needsPassword = true,
  }) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    _passwordRequired = needsPassword;
    if (!_form.currentState!.validate()) {
      return;
    }
    setState(() => _busy = true);
    try {
      if (await action() case final message?) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } on AuthException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.authFailed(e.message))),
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
      appBar: AppBar(title: Text(l10n.signInTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
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
                          _run(() async {
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
                          _run(() async {
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
        ),
      ),
    );
  }

  Future<void> _signIn() => _run(() async {
    await _auth.signInWithPassword(
      email: _email.text.trim(),
      password: _password.text,
    );
    return null;
  });
}
