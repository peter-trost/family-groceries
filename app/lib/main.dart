import 'package:family_groceries/app/app.dart';
import 'package:family_groceries/app/environment.dart';
import 'package:family_groceries/session/session_cubit.dart';
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
  );
  runApp(App(session: SessionCubit(Supabase.instance.client)));
}
