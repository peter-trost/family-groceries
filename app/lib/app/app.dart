import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/session/social_sign_in.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class const App({
  required final SessionCubit session,
  required final SocialSignIn social,
  required final DeviceCache cache,
  super.key,
}) extends StatefulWidget {
  @override
  State<App> createState() => _AppState();
}

class _AppState() extends State<App> {
  late final GoRouter _router = buildRouter(widget.session);

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E7D32);
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: widget.social),
        RepositoryProvider.value(value: widget.cache),
      ],
      child: BlocProvider.value(
        value: widget.session,
        child: MaterialApp.router(
          onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
          theme: ThemeData(colorSchemeSeed: seed),
          darkTheme: ThemeData(
            colorSchemeSeed: seed,
            brightness: Brightness.dark,
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          routerConfig: _router,
          builder: (context, child) => BlocBuilder<SessionCubit, Session>(
            builder: (context, session) => session is SessionLoading
                ? const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  )
                : child!,
          ),
        ),
      ),
    );
  }
}
