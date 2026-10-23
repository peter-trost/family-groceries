import { execSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

/**
 * The local stack this checkout runs, from the environment (scripts/lib.sh, CI) or else from
 * `supabase status`. Never a default port: parallel checkouts run stacks on other port blocks.
 */
function localStack(): { url: string; key: string; mailpit: string } {
  const { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, MAILPIT_URL } = process.env;
  let status: string | undefined;
  const read = (name: string, fromEnv: string | undefined): string => {
    if (fromEnv) return fromEnv;
    status ??= execSync('supabase status -o env', {
      cwd: fileURLToPath(new URL('..', import.meta.url)),
      encoding: 'utf8',
    });
    const value = status.match(new RegExp(`^${name}="(.*)"$`, 'm'))?.[1];
    if (!value) throw new Error(`supabase status reports no ${name}; is the local stack running?`);
    return value;
  };
  return {
    url: read('API_URL', SUPABASE_URL),
    key: read('PUBLISHABLE_KEY', SUPABASE_PUBLISHABLE_KEY),
    mailpit: read('MAILPIT_URL', MAILPIT_URL),
  };
}

export const stack = localStack();

/** The web app's port: WEB_PORT, else <API port's first three digits>80 (54321 -> 54380). */
export const webPort = Number(process.env.WEB_PORT ?? `${new URL(stack.url).port.slice(0, 3)}80`);

/**
 * The fake identity provider's port, from the Keycloak URL the stack's Auth uses
 * (supabase/config.toml), so each checkout runs its own copy instead of borrowing one another
 * job's run may stop midway.
 */
export const fakeOidcPort = (() => {
  const config = readFileSync(new URL('../supabase/config.toml', import.meta.url), 'utf8');
  const port = /^url = "http:\/\/host\.docker\.internal:(\d+)\/realms\/test"$/m.exec(config)?.[1];
  if (!port) throw new Error('supabase/config.toml has no [auth.external.keycloak] url for e2e/fake-oidc.mjs');
  return Number(port);
})();
