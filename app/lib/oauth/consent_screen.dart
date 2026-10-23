import 'dart:async';

import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// What the authorization server asks the user to approve.
sealed class const ConsentRequest();

/// The user approved this client before; the server already decided.
final class const AlreadyApproved(final Uri redirect) extends ConsentRequest;

@immutable
final class const NeedsConsent({
  required final String clientName,
  required final List<String> scopes,
  final String? clientUri,
  final String? email,
}) extends ConsentRequest;

/// Supabase Auth's OAuth server, as the consent screen needs it. Approve and
/// deny return where to send the browser next.
abstract interface class ConsentApi() {
  Future<ConsentRequest> getDetails(String authorizationId);

  Future<Uri> approve(String authorizationId);

  Future<Uri> deny(String authorizationId);
}

class SupabaseConsentApi(final GoTrueOAuthApi _oauth) implements ConsentApi {
  @override
  Future<ConsentRequest> getDetails(String authorizationId) async =>
      switch (await _oauth.getAuthorizationDetails(authorizationId)) {
        OAuthAuthorizationRedirectResponse(:final redirectUrl) =>
          AlreadyApproved(Uri.parse(redirectUrl)),
        OAuthAuthorizationDetailsResponse(
          :final client,
          :final user,
          :final scope,
        ) =>
          NeedsConsent(
            clientName: client.clientName ?? client.clientId,
            clientUri: client.clientUri,
            email: user.email,
            scopes: (scope ?? '')
                .split(' ')
                .where((s) => s.isNotEmpty)
                .toList(),
          ),
      };

  @override
  Future<Uri> approve(String authorizationId) async =>
      _redirect(await _oauth.approveAuthorization(authorizationId));

  @override
  Future<Uri> deny(String authorizationId) async =>
      _redirect(await _oauth.denyAuthorization(authorizationId));

  static Uri _redirect(OAuthConsentResponse response) => switch (response) {
    OAuthConsentResponse(:final String redirectUrl) => Uri.parse(redirectUrl),
    _ => throw const AuthException('no redirect_url'),
  };
}

String scopeLabel(AppLocalizations l10n, String scope) => switch (scope) {
  'openid' => l10n.scopeOpenid,
  'email' => l10n.scopeEmail,
  'profile' => l10n.scopeProfile,
  'phone' => l10n.scopePhone,
  'offline_access' => l10n.scopeOfflineAccess,
  _ => scope,
};

/// Supabase Auth sends the browser here (`/oauth/consent?authorization_id=`)
/// when an MCP client asks to connect.
class const ConsentScreen({
  required final String? authorizationId,
  super.key,

  /// Overrides the Supabase API, for tests.
  final ConsentApi? api,

  /// Overrides leaving the app for the client's redirect, for tests.
  final Future<void> Function(Uri url)? navigate,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionCubit>().state;
    if (session is! InHousehold) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ConsentView(
      authorizationId: authorizationId,
      household: session.household,
      api: api ?? SupabaseConsentApi(Supabase.instance.client.auth.oauth),
      navigate: navigate ?? _openHere,
    );
  }

  static Future<void> _openHere(Uri url) =>
      launchUrl(url, webOnlyWindowName: '_self');
}

class const ConsentView({
  required final String? authorizationId,
  required final Household household,
  required final ConsentApi api,
  required final Future<void> Function(Uri url) navigate,
  super.key,
}) extends StatefulWidget {
  @override
  State<ConsentView> createState() => _ConsentViewState();
}

sealed class const _Phase();

final class const _Loading() extends _Phase;

final class const _Failed(final String? detail) extends _Phase;

final class const _Asking(final NeedsConsent request) extends _Phase;

/// Decided; the browser is on its way to the client.
final class const _Leaving(final NeedsConsent? request) extends _Phase;

class _ConsentViewState() extends State<ConsentView> {
  _Phase _phase = const _Loading();

  @override
  void initState() {
    super.initState();
    final id = widget.authorizationId;
    if (id == null || id.isEmpty) {
      _phase = const _Failed(null);
    } else {
      unawaited(
        _guard(() async {
          switch (await widget.api.getDetails(id)) {
            case AlreadyApproved(:final redirect):
              _show(const _Leaving(null));
              await widget.navigate(redirect);
            case final NeedsConsent request:
              _show(_Asking(request));
          }
        }),
      );
    }
  }

  void _show(_Phase phase) {
    if (mounted) {
      setState(() => _phase = phase);
    }
  }

  Future<void> _decide(
    NeedsConsent request,
    Future<Uri> Function(String id) decision,
  ) => _guard(() async {
    _show(_Leaving(request));
    await widget.navigate(await decision(widget.authorizationId!));
  });

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on AuthException catch (e) {
      _show(_Failed(e.message));
    } on Object catch (e) {
      _show(_Failed('$e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final body = switch (_phase) {
      _Loading() || _Leaving(request: null) => const [
        Center(child: CircularProgressIndicator()),
      ],
      _Failed(:final detail) => [
        Text(l10n.consentInvalid, style: theme.textTheme.titleMedium),
        if (detail != null) ...[
          const SizedBox(height: 8),
          Text(detail, style: theme.textTheme.bodySmall),
        ],
      ],
      _Asking(:final request) || _Leaving(:final request?) => _details(
        context,
        request,
        leaving: _phase is _Leaving,
      ),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.consentTitle),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: body,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _details(
    BuildContext context,
    NeedsConsent request, {
    required bool leaving,
  }) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final clientUri = request.clientUri;
    final email = request.email;
    return [
      Text(request.clientName, style: theme.textTheme.headlineSmall),
      if (clientUri != null) Text(clientUri, style: theme.textTheme.bodySmall),
      const SizedBox(height: 16),
      if (email != null) Text(l10n.consentSignedInAs(email)),
      Text(l10n.consentHousehold(widget.household.name)),
      const SizedBox(height: 16),
      Text(
        l10n.consentWants(request.clientName),
        style: theme.textTheme.titleMedium,
      ),
      for (final permission in [
        l10n.consentListAccess,
        for (final scope in request.scopes) scopeLabel(l10n, scope),
      ])
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.check),
          title: Text(permission),
        ),
      const SizedBox(height: 24),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: leaving
                ? null
                : () => unawaited(_decide(request, widget.api.deny)),
            child: Text(l10n.consentDeny),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: leaving
                ? null
                : () => unawaited(_decide(request, widget.api.approve)),
            child: Text(l10n.consentAllow),
          ),
        ],
      ),
      if (leaving) ...[
        const SizedBox(height: 16),
        Text(l10n.redirecting, textAlign: TextAlign.center),
      ],
    ];
  }
}
