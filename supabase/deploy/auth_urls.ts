// Points the hosted project's auth at the public web app: Site URL, redirect allow list and the
// OAuth server's consent path. Converges: rerunning with the same arguments changes nothing.
//
// Usage: deno run --allow-env --allow-net supabase/deploy/auth_urls.ts <https://app-url> \
//          [--preview <https://family-groceries-*-team.vercel.app>] [--dry-run]
// Env: SUPABASE_ACCESS_TOKEN, SUPABASE_PROJECT_REF

export const consentPath = '/oauth/consent';
const mobileCallback = 'com.petertrost.familygroceries://login-callback';

export type AuthUrls = {
  site_url: string;
  uri_allow_list: string;
  oauth_server_enabled: boolean;
  oauth_server_authorization_path: string;
};

export function origin(url: string): string {
  const u = new URL(url);
  if (u.protocol !== 'https:' || u.pathname !== '/' || u.search || u.hash) {
    throw new Error(`${url}: expected an https origin like https://family-groceries.vercel.app`);
  }
  return u.origin;
}

/** The target config: the app URL first, then every redirect already allowed, deduplicated. */
export function desired(current: string, appUrl: string, preview?: string): AuthUrls {
  const site = origin(appUrl);
  const keep = current.split(',').map((s) => s.trim()).filter(Boolean);
  const allow = [`${site}/**`, ...(preview ? [`${preview}/**`] : []), mobileCallback];
  return {
    site_url: site,
    uri_allow_list: [...new Set([...allow, ...keep])].join(','),
    // The Management API only accepts the consent path together with the enabled flag.
    oauth_server_enabled: true,
    oauth_server_authorization_path: consentPath,
  };
}

if (import.meta.main) {
  const args = [...Deno.args];
  const dryRun = args.includes('--dry-run');
  const previewAt = args.indexOf('--preview');
  const preview = previewAt >= 0 ? args.splice(previewAt, 2)[1] : undefined;
  const appUrl = args.find((a) => !a.startsWith('--'));
  const token = Deno.env.get('SUPABASE_ACCESS_TOKEN');
  const ref = Deno.env.get('SUPABASE_PROJECT_REF');
  if (!appUrl || !token || !ref) {
    console.error('usage: auth_urls.ts <https://app-url> [--preview <pattern>] [--dry-run]');
    console.error('needs SUPABASE_ACCESS_TOKEN and SUPABASE_PROJECT_REF');
    Deno.exit(1);
  }
  const api = `https://api.supabase.com/v1/projects/${ref}/config/auth`;
  const headers = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
  const res = await fetch(api, { headers });
  if (!res.ok) throw new Error(`GET config/auth ${res.status}: ${await res.text()}`);
  const current = await res.json() as AuthUrls;
  const next = desired(current.uri_allow_list ?? '', appUrl, preview);
  const changed = (Object.keys(next) as (keyof AuthUrls)[]).filter((k) => current[k] !== next[k]);
  for (const k of changed) console.log(`${k}: ${current[k]} -> ${next[k]}`);
  if (!changed.length) console.log('auth URLs already up to date');
  if (dryRun || !changed.length) Deno.exit(0);
  const patch = await fetch(api, { method: 'PATCH', headers, body: JSON.stringify(next) });
  if (!patch.ok) throw new Error(`PATCH config/auth ${patch.status}: ${await patch.text()}`);
  console.log('updated');
}
