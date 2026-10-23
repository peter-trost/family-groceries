import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;
import 'package:supabase_flutter/supabase_flutter.dart'
    as auth_types
    show Session;

import 'fake_auth.dart';

void main() {
  late FakeAuth auth;
  late MemorySessionCache cache;
  late SessionCubit cubit;

  const user = User(
    id: 'peter',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-10-22T12:00:00Z',
  );
  const household = Household(id: 'home', name: 'Zuhause');

  setUp(() {
    auth = FakeAuth()..user = user;
    cache = MemorySessionCache();
    cubit = SessionCubit(FakeClient(auth), cache);
  });

  tearDown(() async {
    await cubit.close();
    await auth.close();
  });

  Session signIn() {
    auth.states.add(
      AuthState(
        AuthChangeEvent.initialSession,
        auth_types.Session(accessToken: 'jwt', tokenType: 'bearer', user: user),
      ),
    );
    return cubit.state;
  }

  test('offline with a cached household opens it', () async {
    cache.households['peter'] = household;
    signIn();
    await pumpEventQueue();
    expect(
      cubit.state,
      isA<InHousehold>()
          .having((s) => s.userId, 'user', 'peter')
          .having((s) => s.household.id, 'household', 'home'),
    );
  });

  test('a cached household opens before the server is asked', () async {
    final whileAsking = <Session>[];
    await cubit.close();
    cubit = SessionCubit(
      FakeClient(auth, onQuery: () => whileAsking.add(cubit.state)),
      cache,
    );
    cache.households['peter'] = household;
    signIn();
    await pumpEventQueue();
    expect(whileAsking.first, isA<InHousehold>());
  });

  test('offline without a cached household keeps loading', () async {
    signIn();
    await pumpEventQueue();
    expect(cubit.state, isA<SessionLoading>());
  });

  test('a token refresh that fails offline does not sign out', () async {
    cache.households['peter'] = household;
    auth.states.addError(AuthRetryableFetchException(message: 'offline'));
    await pumpEventQueue();
    expect(cubit.state, isA<InHousehold>());
  });

  test('signing out forgets the cache', () async {
    cache.households['peter'] = household;
    signIn();
    await pumpEventQueue();
    auth.states.add(const AuthState(AuthChangeEvent.signedOut, null));
    await pumpEventQueue();
    expect(cubit.state, isA<SignedOut>());
    expect(cache.households, isEmpty);
  });
}
