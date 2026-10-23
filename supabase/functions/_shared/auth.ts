// Bearer authentication shared by the edge functions (MCP, Siri).
// Accepts three credentials, all scoped to the caller's household:
//   oauth   - an access token Supabase's OAuth 2.1 server issued to a client (has client_id);
//   session - the app's own Supabase session token;
//   pat     - a personal access token (fgp_...), checked by hash against the database.
import { createRemoteJWKSet, type JWTPayload, jwtVerify } from 'jose';
import { householdOf, resolvePersonalAccessToken } from './db.ts';

export type Auth =
  & { userId: string; householdId: string }
  & ({ via: 'oauth'; clientId: string } | { via: 'pat' } | { via: 'session' });

export type Via = Auth['via'];

export type AuthFailure = 'missing_token' | 'invalid_token' | 'no_household';

export class AuthError extends Error {
  constructor(readonly reason: AuthFailure, message: string) {
    super(message);
  }

  /** 401 for a missing or bad credential, 403 for a valid user without a household. */
  get status(): 401 | 403 {
    return this.reason === 'no_household' ? 403 : 401;
  }
}

/** Where the token's issuer lives, as browsers and the tokens' `iss` see it. */
export type Issuer = { issuer: string; jwksUri: URL };

export type AuthDeps = {
  issuer: () => Promise<Issuer>;
  jwks: (issuer: Issuer) => Parameters<typeof jwtVerify>[1];
  householdOf: (userId: string) => Promise<string | null>;
  resolvePat: (tokenHash: string) => Promise<{ userId: string; householdId: string } | null>;
};

export const PAT_PREFIX = 'fgp_';

export async function authenticate(req: Request, deps: AuthDeps = defaultDeps): Promise<Auth> {
  const header = req.headers.get('authorization') ?? '';
  const match = /^Bearer\s+(\S+)\s*$/i.exec(header);
  if (!match) throw new AuthError('missing_token', 'Authorization: Bearer <token> fehlt.');
  const token = match[1];

  if (token.startsWith(PAT_PREFIX)) {
    const owner = await deps.resolvePat(await sha256Hex(token));
    if (!owner) throw new AuthError('invalid_token', 'Token unbekannt oder widerrufen.');
    return { ...owner, via: 'pat' };
  }

  const claims = await verifyJwt(token, deps);
  const householdId = await deps.householdOf(claims.sub);
  if (!householdId) throw new AuthError('no_household', 'Dieses Konto gehört zu keinem Haushalt.');
  return typeof claims.client_id === 'string'
    ? { userId: claims.sub, householdId, via: 'oauth', clientId: claims.client_id }
    : { userId: claims.sub, householdId, via: 'session' };
}

async function verifyJwt(
  token: string,
  deps: AuthDeps,
): Promise<JWTPayload & { sub: string }> {
  const issuer = await deps.issuer();
  try {
    const { payload } = await jwtVerify(token, deps.jwks(issuer), {
      issuer: issuer.issuer,
      // Supabase issues user and OAuth access tokens for this audience; it ignores RFC 8707.
      audience: 'authenticated',
      algorithms: ['ES256', 'RS256'],
      requiredClaims: ['sub', 'exp'],
    });
    const { sub, role } = payload;
    if (typeof sub !== 'string' || role !== 'authenticated') throw new Error('not a user token');
    return { ...payload, sub };
  } catch (e) {
    throw new AuthError('invalid_token', `Token ungültig: ${(e as Error).message}`);
  }
}

export async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * The public issuer, read from Supabase Auth's discovery document through the internal URL.
 * Inside the local stack SUPABASE_URL is http://kong:8000 while tokens carry the public URL.
 */
let issuerCache: Promise<Issuer> | undefined;
export function discoverIssuer(): Promise<Issuer> {
  issuerCache ??= (async () => {
    const internal = Deno.env.get('SUPABASE_URL')!;
    const res = await fetch(`${internal}/auth/v1/.well-known/openid-configuration`);
    if (!res.ok) throw new Error(`auth discovery failed: ${res.status}`);
    const { issuer } = await res.json() as { issuer: string };
    return { issuer, jwksUri: new URL(`${internal}/auth/v1/.well-known/jwks.json`) };
  })().catch((e) => {
    issuerCache = undefined;
    throw e;
  });
  return issuerCache;
}

let jwksCache: ReturnType<typeof createRemoteJWKSet> | undefined;

const defaultDeps: AuthDeps = {
  issuer: discoverIssuer,
  jwks: (issuer) => (jwksCache ??= createRemoteJWKSet(issuer.jwksUri)),
  householdOf,
  resolvePat: resolvePersonalAccessToken,
};
