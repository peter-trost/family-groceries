import 'dart:async';

import 'package:family_groceries/app/environment.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/oauth/consent_screen.dart';
import 'package:family_groceries/settings/access_cubit.dart';
import 'package:family_groceries/settings/access_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ways in from outside the app: the MCP endpoint, personal access tokens
/// and OAuth-connected apps.
class const SettingsScreen({
  super.key,

  /// Overrides the Supabase repository, for tests.
  final AccessRepository? repository,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) {
      final cubit = AccessCubit(
        repository ?? SupabaseAccessRepository(Supabase.instance.client),
      );
      unawaited(cubit.load());
      return cubit;
    },
    child: const _Settings(),
  );
}

class const _Settings() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<AccessCubit>().state;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.accessTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _Header(l10n.mcpServer),
              ListTile(
                title: const SelectionArea(child: Text(Environment.mcpUrl)),
                subtitle: Text(l10n.mcpServerBody),
                trailing: IconButton(
                  tooltip: l10n.copy,
                  icon: const Icon(Icons.copy),
                  onPressed: () => _copy(context, Environment.mcpUrl),
                ),
              ),
              _Header(l10n.accessTokens),
              ..._section(
                context,
                state.tokens,
                empty: l10n.noTokens,
                tile: (token) => _TokenTile(token: token),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.add),
                    label: Text(l10n.createToken),
                    onPressed: () => unawaited(_createToken(context)),
                  ),
                ),
              ),
              _Header(l10n.connectedApps),
              ..._section(
                context,
                state.apps,
                empty: l10n.noConnectedApps,
                tile: (app) => _AppTile(app: app),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static List<Widget> _section<T>(
    BuildContext context,
    Section<List<T>> section, {
    required String empty,
    required Widget Function(T value) tile,
  }) => switch (section) {
    SectionLoading() => const [
      Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
    ],
    SectionFailed(:final message) => [
      ListTile(title: Text(AppLocalizations.of(context).genericError(message))),
    ],
    SectionLoaded(value: []) => [ListTile(title: Text(empty))],
    SectionLoaded(:final value) => [for (final v in value) tile(v)],
  };
}

void _copy(BuildContext context, String text) {
  unawaited(Clipboard.setData(ClipboardData(text: text)));
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).copied)));
}

String _errorText(AppLocalizations l10n, Object error) => switch (error) {
  AccessError(code: 'too_many_tokens') => l10n.tooManyTokens,
  AccessError(:final code) => l10n.genericError(code),
  _ => l10n.genericError('$error'),
};

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialog).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Runs [action], showing a failure as a snack bar.
Future<void> _attempt(
  BuildContext context,
  Future<void> Function() action,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(_errorText(l10n, e))));
  }
}

Future<void> _createToken(BuildContext context) async {
  final cubit = context.read<AccessCubit>();
  final name = await showDialog<String>(
    context: context,
    builder: (_) => const _NameDialog(),
  );
  if (name == null || !context.mounted) {
    return;
  }
  await _attempt(context, () async {
    final token = await cubit.create(name);
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _NewTokenDialog(token: token),
      );
    }
  });
}

class const _Header(final String text) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    ),
  );
}

class const _TokenTile({required final AccessToken token})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lastUsed = token.lastUsedAt;
    return ListTile(
      leading: const Icon(Icons.key),
      title: Text(token.name),
      subtitle: Text(
        [
          l10n.tokenHint(token.hint),
          l10n.createdOn(token.createdAt),
          if (lastUsed == null) l10n.neverUsed else l10n.lastUsedOn(lastUsed),
        ].join(' · '),
      ),
      trailing: IconButton(
        tooltip: l10n.revokeToken(token.name),
        icon: const Icon(Icons.delete_outline),
        onPressed: () => unawaited(_revoke(context)),
      ),
    );
  }

  Future<void> _revoke(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<AccessCubit>();
    final confirmed = await _confirm(
      context,
      title: l10n.revokeTokenTitle,
      body: l10n.revokeTokenBody,
      action: l10n.revoke,
    );
    if (confirmed && context.mounted) {
      await _attempt(context, () => cubit.revoke(token.id));
    }
  }
}

class const _AppTile({required final ConnectedApp app})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      leading: const Icon(Icons.smart_toy_outlined),
      title: Text(app.name),
      subtitle: Text(
        [
          l10n.connectedOn(app.grantedAt),
          for (final scope in app.scopes) scopeLabel(l10n, scope),
        ].join(' · '),
      ),
      trailing: IconButton(
        tooltip: l10n.disconnectApp(app.name),
        icon: const Icon(Icons.link_off),
        onPressed: () => unawaited(_disconnect(context)),
      ),
    );
  }

  Future<void> _disconnect(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<AccessCubit>();
    final confirmed = await _confirm(
      context,
      title: l10n.disconnectTitle(app.name),
      body: l10n.disconnectBody,
      action: l10n.disconnect,
    );
    if (confirmed && context.mounted) {
      await _attempt(context, () => cubit.disconnect(app.clientId));
    }
  }
}

class const _NameDialog() extends StatefulWidget {
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState() extends State<_NameDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_name.text.trim());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.createToken),
      content: TextField(
        controller: _name,
        autofocus: true,
        maxLength: 60,
        decoration: InputDecoration(
          labelText: l10n.tokenName,
          hintText: l10n.tokenNameHint,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.create)),
      ],
    );
  }
}

/// The only time the secret is shown.
class const _NewTokenDialog({required final NewToken token})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.tokenCreated),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.tokenShownOnce),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SelectionArea(
                  child: Text(
                    token.token,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.copy,
                icon: const Icon(Icons.copy),
                onPressed: () => _copy(context, token.token),
              ),
            ],
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.done),
        ),
      ],
    );
  }
}
