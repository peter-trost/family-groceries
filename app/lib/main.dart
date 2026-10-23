import 'package:family_groceries/app/app.dart';
import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/app/environment.dart';
import 'package:family_groceries/session/plugin_sign_in.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/session/social_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  // Path URLs (/join/CODE, later /oauth/consent) instead of #-fragments.
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    // Exposes the widget tree to the DOM for screen readers and Playwright.
    SemanticsBinding.instance.ensureSemantics();
  }
  await Supabase.initialize(
    url: Environment.supabaseUrl,
    publishableKey: Environment.supabasePublishableKey,
    // The list and session retry on their own (every 3 s, ops until acked);
    // postgrest's GET retries (1 + 2 + 4 s) only hid an offline start.
    // `client.from` ignores this option, so reads go through `client.rest`.
    postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
  );
  final client = Supabase.instance.client;
  final social = SocialSignIn(
    client.auth,
    flows: socialFlows(
      (
        googleWebClientId: Environment.googleWebClientId,
        googleIosClientId: Environment.googleIosClientId,
        apple: Environment.signInWithApple,
      ),
      web: kIsWeb,
      platform: defaultTargetPlatform,
    ),
    native: PluginSignIn(
      googleWebClientId: Environment.googleWebClientId,
      googleIosClientId: defaultTargetPlatform == TargetPlatform.iOS
          ? Environment.googleIosClientId
          : null,
    ),
  );
  final cache = DeviceCache.onDevice();
  runApp(
    App(session: SessionCubit(client, cache), social: social, cache: cache),
  );
}
