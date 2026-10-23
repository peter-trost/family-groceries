import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const household = InHousehold('u', Household(id: 'h', name: 'H'));
  const consent = '/oauth/consent?authorization_id=abc';
  const next = 'next=%2Foauth%2Fconsent%3Fauthorization_id%3Dabc';
  const cases = <(Session, String, String?)>[
    (SessionLoading(), '/', null),
    (SignedOut(), '/', '/login'),
    (SignedOut(), '/login', null),
    (SignedOut(), '/join/ABCD2345', '/login?invite=ABCD2345'),
    (NeedsHousehold('u'), '/login?invite=ABCD2345', '/welcome?invite=ABCD2345'),
    (NeedsHousehold('u'), '/', '/welcome'),
    (NeedsHousehold('u'), '/join/ABCD2345', '/welcome?invite=ABCD2345'),
    (household, '/login', '/'),
    (household, '/welcome', '/'),
    (household, '/welcome?invite=ABCD2345', '/'),
    (household, '/login?invite=ABCD2345', '/join/ABCD2345'),
    (household, '/join/ABCD2345', null),
    (household, '/?code=pkce', '/'),
    (household, '/', null),
    (household, '/settings', null),
    (SignedOut(), '/settings', '/login'),
    (SignedOut(), consent, '/login?$next'),
    (SignedOut(), '/login?$next', null),
    (NeedsHousehold('u'), '/login?$next', '/welcome?$next'),
    (NeedsHousehold('u'), consent, '/welcome?$next'),
    (NeedsHousehold('u'), '/welcome?$next', null),
    (household, '/login?$next', consent),
    (household, '/welcome?$next', consent),
    (household, consent, null),
    (household, '/oauth/consent', null),
    (household, '$consent&code=pkce', null),
    (SignedOut(), '/login?next=https%3A%2F%2Fevil.example', '/login'),
    (SignedOut(), '/login?next=%2F%2Fevil.example%2Foauth%2Fconsent', '/login'),
    (household, '/login?next=https%3A%2F%2Fevil.example', '/'),
    (household, '/welcome?next=%2Fsettings', '/'),
    (NeedsHousehold('u'), '/welcome?next=%2Fsettings', '/welcome'),
  ];
  for (final (session, from, to) in cases) {
    test('${session.runtimeType} at $from goes to ${to ?? 'stays'}', () {
      expect(authRedirect(session, Uri.parse(from)), to);
    });
  }
}
