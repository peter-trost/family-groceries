import 'package:family_groceries/main.dart' as app;
import 'package:flutter/foundation.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

/// Debug entrypoint for agents: the real app plus the Marionette binding,
/// which `.cursor/skills/verify-family-groceries` drives over the VM
/// service. Release builds use `lib/main.dart` and never reach this file;
/// marionette_flutter is a dev dependency, so `lib/` cannot import it.
Future<void> main() async {
  if (kReleaseMode) {
    throw StateError('main_marionette.dart is for debug and profile builds.');
  }
  MarionetteBinding.ensureInitialized();
  await app.main();
}
