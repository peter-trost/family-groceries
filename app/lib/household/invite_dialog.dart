import 'dart:async';

import 'package:family_groceries/app/environment.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Creates an invite code and shows it with a link. Nothing is sent.
Future<void> showInviteDialog(BuildContext context, Household household) =>
    showDialog<void>(
      context: context,
      builder: (_) => _InviteDialog(household: household),
    );

/// Asks for a code, then hands over to the join route which confirms.
Future<void> showJoinCodeDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final router = GoRouter.of(context);
  final controller = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(l10n.joinOtherHousehold),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(labelText: l10n.inviteCode),
        onSubmitted: (value) => Navigator.of(dialog).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialog).pop(controller.text),
          child: Text(l10n.joinHousehold),
        ),
      ],
    ),
  );
  controller.dispose();
  final cleaned = code?.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
  if (cleaned != null && cleaned.isNotEmpty) {
    router.go(joinPath(cleaned));
  }
}

class const _InviteDialog({required final Household household})
    extends StatefulWidget {
  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState() extends State<_InviteDialog> {
  late final Future<String> _code = _create();

  Future<String> _create() async {
    final row = await Supabase.instance.client.rpc<Map<String, dynamic>>(
      'create_invite',
      params: {'p_household': widget.household.id},
    );
    return row['code']! as String;
  }

  String? _link(String code) {
    final base = kIsWeb ? Uri.base.origin : Environment.appUrl;
    return base.isEmpty ? null : '$base${joinPath(code)}';
  }

  void _copy(String text) {
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).copied)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.inviteTitle),
      content: FutureBuilder(
        future: _code,
        builder: (context, snapshot) => switch (snapshot) {
          AsyncSnapshot(:final String data) => _InviteBody(
            code: data,
            link: _link(data),
            onCopy: _copy,
          ),
          AsyncSnapshot(:final Object error) => Text(
            l10n.genericError('$error'),
          ),
          _ => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator()),
          ),
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}

class const _InviteBody({
  required final String code,
  required final String? link,
  required final ValueChanged<String> onCopy,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final link = this.link;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.inviteBody),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.inviteCodeLabel),
          subtitle: Text(
            code,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          trailing: IconButton(
            tooltip: l10n.copy,
            icon: const Icon(Icons.copy),
            onPressed: () => onCopy(code),
          ),
        ),
        if (link != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.inviteLinkLabel),
            subtitle: Text(link),
            trailing: IconButton(
              tooltip: l10n.copy,
              icon: const Icon(Icons.copy),
              onPressed: () => onCopy(link),
            ),
          ),
      ],
    );
  }
}
