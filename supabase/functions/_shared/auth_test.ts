import { assertEquals, assertRejects } from '@std/assert';
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT } from 'jose';
import { type AuthDeps, authenticate, AuthError, type AuthFailure, sha256Hex } from './auth.ts';

const ISSUER = 'http://127.0.0.1:54621/auth/v1';
const USER = '11111111-1111-1111-1111-111111111111';
const HOUSEHOLD = '22222222-2222-2222-2222-222222222222';
const PAT = 'fgp_valid-token';

const { publicKey, privateKey } = await generateKeyPair('ES256');
const jwks = createLocalJWKSet({
  keys: [{ ...(await exportJWK(publicKey)), kid: 'k1', alg: 'ES256' }],
});
const other = await generateKeyPair('ES256');

const deps: AuthDeps = {
  issuer: () => Promise.resolve({ issuer: ISSUER, jwksUri: new URL('http://unused') }),
  jwks: () => jwks,
  householdOf: (userId) => Promise.resolve(userId === USER ? HOUSEHOLD : null),
  resolvePat: async (hash) =>
    hash === await sha256Hex(PAT) ? { userId: USER, householdId: HOUSEHOLD } : null,
};

function token(
  claims: Record<string, unknown> = {},
  opts: { key?: CryptoKey; exp?: string; aud?: string; iss?: string } = {},
) {
  return new SignJWT({ role: 'authenticated', ...claims })
    .setProtectedHeader({ alg: 'ES256', kid: 'k1' })
    .setSubject(USER)
    .setIssuer(opts.iss ?? ISSUER)
    .setAudience(opts.aud ?? 'authenticated')
    .setIssuedAt()
    .setExpirationTime(opts.exp ?? '1h')
    .sign(opts.key ?? privateKey);
}

const bearer = (value: string) =>
  new Request('http://local/mcp', { headers: { authorization: `Bearer ${value}` } });

async function failsWith(req: Request, reason: AuthFailure) {
  const error = await assertRejects(() => authenticate(req, deps), AuthError);
  assertEquals(error.reason, reason);
}

Deno.test('an OAuth access token authenticates as its user, household and client', async () => {
  const auth = await authenticate(bearer(await token({ client_id: 'c-1', scope: 'openid' })), deps);
  assertEquals(auth, { userId: USER, householdId: HOUSEHOLD, via: 'oauth', clientId: 'c-1' });
});

Deno.test('an app session token authenticates as a session', async () => {
  assertEquals(await authenticate(bearer(await token()), deps), {
    userId: USER,
    householdId: HOUSEHOLD,
    via: 'session',
  });
});

Deno.test('a personal access token authenticates by its hash', async () => {
  assertEquals(await authenticate(bearer(PAT), deps), {
    userId: USER,
    householdId: HOUSEHOLD,
    via: 'pat',
  });
});

Deno.test('missing or malformed Authorization headers are missing tokens', async () => {
  await failsWith(new Request('http://local/mcp'), 'missing_token');
  await failsWith(
    new Request('http://local/mcp', { headers: { authorization: 'Basic abc' } }),
    'missing_token',
  );
});

Deno.test('unknown or revoked personal access tokens are invalid', async () => {
  await failsWith(bearer('fgp_revoked'), 'invalid_token');
});

Deno.test('tokens that fail signature, expiry, audience, issuer or role checks are invalid', async () => {
  await failsWith(bearer(await token({}, { key: other.privateKey })), 'invalid_token');
  await failsWith(bearer(await token({}, { exp: '-1m' })), 'invalid_token');
  await failsWith(bearer(await token({}, { aud: 'someone-else' })), 'invalid_token');
  await failsWith(
    bearer(await token({}, { iss: 'https://evil.example/auth/v1' })),
    'invalid_token',
  );
  await failsWith(bearer(await token({ role: 'anon' })), 'invalid_token');
  await failsWith(bearer('not-a-jwt'), 'invalid_token');
});

Deno.test('a valid user without a household is refused with 403', async () => {
  const req = bearer(
    await new SignJWT({ role: 'authenticated' })
      .setProtectedHeader({ alg: 'ES256', kid: 'k1' })
      .setSubject('33333333-3333-3333-3333-333333333333')
      .setIssuer(ISSUER)
      .setAudience('authenticated')
      .setExpirationTime('1h')
      .sign(privateKey),
  );
  const error = await assertRejects(() => authenticate(req, deps), AuthError);
  assertEquals([error.reason, error.status], ['no_household', 403]);
});
