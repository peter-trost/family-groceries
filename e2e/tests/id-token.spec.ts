// signInWithIdToken against the local Supabase Auth: the call the iOS and
// Android apps make after the native Google or Apple dialog. The fake provider
// signs the ID tokens; Supabase Auth verifies issuer, audience and nonce and
// links accounts with the same code it runs for Google and Apple.
import { expect, test } from './fixtures';
import { createHash, randomUUID } from 'node:crypto';
import { anonClient, apiAs, fakeIdToken, latestLinkFor, newEmail, password } from './helpers';

const sha256 = (s: string) => createHash('sha256').update(s).digest('hex');

async function signInWithIdToken(token: string, nonce?: string) {
  const client = anonClient();
  const { data, error } = await client.auth.signInWithIdToken({ provider: 'keycloak', token, nonce });
  return { client, user: data.user, error };
}

test('the raw nonce matching the hashed one in the token signs in', async () => {
  const nonce = randomUUID();
  const { user, error } = await signInWithIdToken(await fakeIdToken({ email: newEmail('nonce'), nonce: sha256(nonce) }), nonce);
  expect(error).toBeNull();
  expect(user?.app_metadata.provider).toBe('keycloak');
});

test('a wrong or missing nonce is refused', async () => {
  const token = await fakeIdToken({ email: newEmail('nonce-bad'), nonce: sha256('the-real-one') });
  expect((await signInWithIdToken(token, 'another-one')).error?.message).toMatch(/nonce/i);
  expect((await signInWithIdToken(token)).error?.message).toMatch(/nonce/i);
});

test('a token issued to another client is refused', async () => {
  const nonce = randomUUID();
  const token = await fakeIdToken({ email: newEmail('aud'), nonce: sha256(nonce), aud: 'someone-elses-app' });
  expect((await signInWithIdToken(token, nonce)).error?.message).toMatch(/audience/i);
});

test('an ID token for an existing email account links to it, household included', async () => {
  const email = newEmail('link-api');
  const signUp = await anonClient().auth.signUp({ email, password });
  expect(signUp.error).toBeNull();
  const owner = await apiAs(email);
  await owner.rpc('create_household', { p_name: 'Trost' });

  const nonce = randomUUID();
  const { client, user, error } = await signInWithIdToken(await fakeIdToken({ email, nonce: sha256(nonce) }), nonce);
  expect(error).toBeNull();
  expect(user?.id).toBe(signUp.data.user?.id);
  const { data: membership } = await client.from('household_members').select('households(name)').single();
  expect(membership).toEqual({ households: { name: 'Trost' } });

  // The password still works after linking.
  await apiAs(email);
});

test('an account created by a provider signs in again by magic link', async () => {
  const email = newEmail('provider-first');
  const nonce = randomUUID();
  const { user } = await signInWithIdToken(await fakeIdToken({ email, nonce: sha256(nonce) }), nonce);
  expect(user).not.toBeNull();

  const { error } = await anonClient().auth.signInWithOtp({ email, options: { shouldCreateUser: false } });
  expect(error).toBeNull();
  const res = await fetch(await latestLinkFor(email), { redirect: 'manual' });
  const fragment = new URLSearchParams(new URL(res.headers.get('location')!).hash.slice(1));
  const claims = JSON.parse(Buffer.from(fragment.get('access_token')!.split('.')[1], 'base64url').toString());
  expect(claims.sub).toBe(user!.id);
});

test('Apple and Google again with the same email reuse the one account', async () => {
  const email = newEmail('twice');
  const first = randomUUID();
  const second = randomUUID();
  const a = await signInWithIdToken(await fakeIdToken({ email, nonce: sha256(first) }), first);
  const b = await signInWithIdToken(await fakeIdToken({ email, nonce: sha256(second) }), second);
  expect(b.user?.id).toBe(a.user?.id);
});
