import { assertEquals, assertMatch } from '@std/assert';
import { type Auth, AuthError } from '../_shared/auth.ts';
import { type Deps, handle } from './handler.ts';

const RESOURCE = 'https://ref.supabase.co/functions/v1/mcp';
const METADATA = `${RESOURCE}/.well-known/oauth-protected-resource`;
const USER = { userId: 'u', householdId: 'h' };

function deps(auth: Auth | AuthError): Deps {
  return {
    endpoints: () =>
      Promise.resolve({
        resource: RESOURCE,
        metadata: METADATA,
        authorizationServer: 'https://ref.supabase.co/auth/v1',
      }),
    authenticate: () => auth instanceof AuthError ? Promise.reject(auth) : Promise.resolve(auth),
    serve: (_req, a) => Promise.resolve(Response.json({ served: a.via })),
    allowedOriginHosts: () => ['inspector.example'],
  };
}

const post = (headers: Record<string, string> = {}) =>
  new Request('http://edge/mcp', { method: 'POST', headers, body: '{}' });

Deno.test('serves Protected Resource Metadata at the well-known suffix', async () => {
  for (
    const path of ['/mcp/.well-known/oauth-protected-resource', '/mcp/oauth-protected-resource']
  ) {
    const res = await handle(new Request(`http://edge${path}`), deps({ ...USER, via: 'pat' }));
    assertEquals(res.status, 200);
    assertEquals(res.headers.get('access-control-allow-origin'), '*');
    const body = await res.json();
    assertEquals(body.resource, RESOURCE);
    assertEquals(body.authorization_servers, ['https://ref.supabase.co/auth/v1']);
  }
});

Deno.test('a request without a token gets 401 pointing at the metadata', async () => {
  const res = await handle(post(), deps(new AuthError('missing_token', 'fehlt')));
  assertEquals(res.status, 401);
  assertEquals(
    res.headers.get('www-authenticate'),
    `Bearer resource_metadata="${METADATA}", scope="openid email"`,
  );
  assertEquals(
    res.headers.get('access-control-expose-headers'),
    'www-authenticate, mcp-session-id',
  );
});

Deno.test('an invalid token gets 401 with error="invalid_token"', async () => {
  const res = await handle(post(), deps(new AuthError('invalid_token', 'abgelaufen')));
  assertEquals(res.status, 401);
  assertMatch(res.headers.get('www-authenticate')!, /error="invalid_token"/);
});

Deno.test('a user without a household gets 403', async () => {
  const res = await handle(post(), deps(new AuthError('no_household', 'kein Haushalt')));
  assertEquals(res.status, 403);
});

Deno.test('app session tokens are not accepted as MCP credentials', async () => {
  const res = await handle(post(), deps({ ...USER, via: 'session' }));
  assertEquals(res.status, 401);
  assertMatch(res.headers.get('www-authenticate')!, /error="invalid_token"/);
});

Deno.test('OAuth and PAT credentials reach the MCP server', async () => {
  for (const auth of [{ ...USER, via: 'oauth', clientId: 'c' }, { ...USER, via: 'pat' }] as const) {
    const res = await handle(post(), deps(auth));
    assertEquals(await res.json(), { served: auth.via });
  }
});

Deno.test('browser origins outside the allowlist get 403; listed and absent origins pass', async () => {
  const pat = deps({ ...USER, via: 'pat' });
  assertEquals((await handle(post({ origin: 'https://evil.example' }), pat)).status, 403);
  for (
    const origin of [
      'https://inspector.example',
      'http://localhost:6274',
      'https://ref.supabase.co',
    ]
  ) {
    assertEquals((await handle(post({ origin }), pat)).status, 200, origin);
  }
  assertEquals((await handle(post(), pat)).status, 200);
});

Deno.test('CORS preflight answers without auth', async () => {
  const res = await handle(
    new Request('http://edge/mcp', { method: 'OPTIONS' }),
    deps(new AuthError('missing_token', 'x')),
  );
  assertEquals(res.status, 204);
  assertMatch(res.headers.get('access-control-allow-headers')!, /mcp-protocol-version/);
});
