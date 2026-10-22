// A stand-in identity provider for the local Supabase stack. Supabase Auth
// can't fake Google or Apple (their issuers are hard-coded), but its Keycloak
// provider accepts any issuer and runs the same ID token, nonce, audience and
// account-linking code. supabase/config.toml points [auth.external.keycloak]
// here through host.docker.internal.
//
// The signing key is derived from a fixed seed, so any copy of this server
// (another worktree, a rerun) issues tokens every copy verifies.
//
// Usage: node fake-oidc.mjs [port]   (default 54399)
import { createECDH, createHash, createPrivateKey, sign } from 'node:crypto';
import { createServer } from 'node:http';

const port = Number(process.argv[2] ?? process.env.FAKE_OIDC_PORT ?? 54399);
const issuer = `http://host.docker.internal:${port}/realms/test`;
const clientId = 'family-groceries-e2e';

const b64url = (buf) => Buffer.from(buf).toString('base64url');
const sha256 = (s) => createHash('sha256').update(s).digest();

const ecdh = createECDH('prime256v1');
ecdh.setPrivateKey(sha256('family-groceries fake oidc'));
const point = ecdh.getPublicKey();
const jwk = { kty: 'EC', crv: 'P-256', x: b64url(point.subarray(1, 33)), y: b64url(point.subarray(33)) };
const key = createPrivateKey({ key: { ...jwk, d: b64url(ecdh.getPrivateKey()) }, format: 'jwk' });
const kid = 'fake-1';

/** An ES256 ID token for `email`; `nonce` is embedded as given (already hashed). */
function idToken({ email, name, nonce, aud = clientId, emailVerified = true }) {
  const now = Math.floor(Date.now() / 1000);
  const claims = {
    iss: issuer, aud, sub: b64url(sha256(email)).slice(0, 22), email, email_verified: emailVerified,
    iat: now, exp: now + 600, ...(name ? { name } : {}), ...(nonce ? { nonce } : {}),
  };
  const head = b64url(JSON.stringify({ alg: 'ES256', typ: 'JWT', kid }));
  const body = b64url(JSON.stringify(claims));
  const sig = sign('sha256', Buffer.from(`${head}.${body}`), { key, dsaEncoding: 'ieee-p1363' });
  return `${head}.${body}.${b64url(sig)}`;
}

/** The authorization code carries the user, so the server keeps no state. */
const encodeUser = (user) => b64url(JSON.stringify(user));
const decodeUser = (code) => JSON.parse(Buffer.from(code, 'base64url').toString());

async function readBody(req) {
  let raw = '';
  for await (const chunk of req) raw += chunk;
  return req.headers['content-type']?.includes('json') ? JSON.parse(raw || '{}') : Object.fromEntries(new URLSearchParams(raw));
}

function json(res, status, body) {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(body));
}

const realm = '/realms/test';
const server = createServer(async (req, res) => {
  const url = new URL(req.url, issuer);
  const path = url.pathname.startsWith(realm) ? url.pathname.slice(realm.length) : url.pathname;
  switch (`${req.method} ${path}`) {
    case 'GET /.well-known/openid-configuration':
      return json(res, 200, {
        issuer,
        authorization_endpoint: `${issuer}/protocol/openid-connect/auth`,
        token_endpoint: `${issuer}/protocol/openid-connect/token`,
        userinfo_endpoint: `${issuer}/protocol/openid-connect/userinfo`,
        jwks_uri: `${issuer}/protocol/openid-connect/certs`,
        id_token_signing_alg_values_supported: ['ES256'],
        response_types_supported: ['code'],
        subject_types_supported: ['public'],
      });
    case 'GET /protocol/openid-connect/certs':
      return json(res, 200, { keys: [{ ...jwk, kid, use: 'sig', alg: 'ES256' }] });
    case 'GET /protocol/openid-connect/auth': {
      // The browser test picks the account with login_hint, or refuses with deny=1.
      const back = new URL(url.searchParams.get('redirect_uri'));
      back.searchParams.set('state', url.searchParams.get('state') ?? '');
      const email = url.searchParams.get('login_hint');
      if (url.searchParams.get('deny') || !email) {
        back.searchParams.set('error', 'access_denied');
        back.searchParams.set('error_description', 'The user denied the request');
      } else {
        back.searchParams.set('code', encodeUser({ email, name: url.searchParams.get('name') ?? undefined }));
      }
      res.writeHead(302, { location: back.toString() });
      return res.end();
    }
    case 'POST /protocol/openid-connect/token': {
      const { code } = await readBody(req);
      return json(res, 200, { access_token: code, token_type: 'Bearer', expires_in: 600, id_token: idToken(decodeUser(code)) });
    }
    case 'GET /protocol/openid-connect/userinfo': {
      const { email, name } = decodeUser(req.headers.authorization?.replace(/^Bearer /, '') ?? '');
      return json(res, 200, { sub: b64url(sha256(email)).slice(0, 22), email, email_verified: true, name });
    }
    case 'POST /mint':
      return json(res, 200, { id_token: idToken(await readBody(req)) });
    default:
      return json(res, 404, { error: 'not_found', path });
  }
});

server.listen(port, '0.0.0.0', () => console.log(`fake OIDC issuer ${issuer}`));
