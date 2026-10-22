import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const household = InHousehold('u', Household(id: 'h', name: 'H'));
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
  ];
  for (final (session, from, to) in cases) {
    test('${session.runtimeType} at $from goes to ${to ?? 'stays'}', () {
      expect(authRedirect(session, Uri.parse(from)), to);
    });
  }
}
