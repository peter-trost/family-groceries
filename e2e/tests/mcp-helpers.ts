import {
  Client,
  type OAuthClientProvider,
  StreamableHTTPClientTransport,
} from '@modelcontextprotocol/client';
import { expect, type Page } from '@playwright/test';
import { supabaseUrl } from './helpers';

export const mcpUrl = new URL('/functions/v1/mcp', supabaseUrl);

/** Loopback redirect like a desktop MCP client's; the browser never really reaches it. */
export const callbackUrl = 'http://127.0.0.1:8976/callback';

export type Era = 'legacy' | 'modern';

/** fetch for SDK transports that reports slow round trips, to tell server stalls from client ones. */
export const timedFetch: typeof fetch = async (input, init) => {
  const started = Date.now();
  const res = await fetch(input, init);
  const ms = Date.now() - started;
  if (ms > 2_000) console.warn(`slow MCP round trip: ${init?.method ?? 'GET'} ${String(input)} -> ${res.status} in ${ms} ms`);
  return res;
};

/** An MCP SDK client that already has a bearer token (a PAT or an OAuth access token). */
export async function connectWithToken(token: string, era: Era = 'legacy'): Promise<Client> {
  const client = new Client(
    { name: 'family-groceries-e2e', version: '1.0.0' },
    era === 'modern' ? { versionNegotiation: { mode: { pin: '2026-07-28' } } } : {},
  );
  await client.connect(
    new StreamableHTTPClientTransport(mcpUrl, {
      requestInit: { headers: { authorization: `Bearer ${token}` } },
    }),
  );
  return client;
}

/** Parses a tool result's JSON text; fails the test on tool errors. */
export async function call<T = unknown>(
  client: Client,
  name: string,
  args: Record<string, unknown> = {},
): Promise<T> {
  const result = await client.callTool({ name, arguments: args });
  const [first] = result.content as { type: string; text: string }[];
  expect(result.isError, `${name} failed: ${first?.text}`).toBeFalsy();
  return JSON.parse(first.text) as T;
}

export async function callExpectingError(
  client: Client,
  name: string,
  args: Record<string, unknown>,
): Promise<string> {
  const result = await client.callTool({ name, arguments: args });
  expect(result.isError, `${name} should fail`).toBe(true);
  return (result.content as { text: string }[])[0].text;
}

/**
 * The client side of the OAuth flow, as an MCP host implements it: the SDK does discovery,
 * dynamic client registration, PKCE and the token exchange; we only keep its state in memory
 * and capture the authorization URL it wants to open in a browser.
 */
export class TestOAuthProvider implements OAuthClientProvider {
  authorizationUrl?: URL;
  client?: Awaited<ReturnType<OAuthClientProvider['clientInformation']>>;
  saved?: Awaited<ReturnType<OAuthClientProvider['tokens']>>;
  private verifier = '';
  private discovery?: Awaited<ReturnType<NonNullable<OAuthClientProvider['discoveryState']>>>;

  constructor(readonly clientName: string) {}

  get redirectUrl() {
    return callbackUrl;
  }

  get clientMetadata() {
    return {
      client_name: this.clientName,
      redirect_uris: [callbackUrl],
      grant_types: ['authorization_code', 'refresh_token'],
      response_types: ['code'],
      token_endpoint_auth_method: 'none',
    };
  }

  clientInformation() {
    return this.client;
  }

  saveClientInformation(info: NonNullable<TestOAuthProvider['client']>) {
    this.client = info;
  }

  tokens() {
    return this.saved;
  }

  saveTokens(tokens: NonNullable<TestOAuthProvider['saved']>) {
    this.saved = tokens;
  }

  redirectToAuthorization(url: URL) {
    this.authorizationUrl = url;
  }

  saveCodeVerifier(verifier: string) {
    this.verifier = verifier;
  }

  codeVerifier() {
    return this.verifier;
  }

  saveDiscoveryState(state: NonNullable<TestOAuthProvider['discovery']>) {
    this.discovery = state;
  }

  discoveryState() {
    return this.discovery;
  }
}

/**
 * Opens the authorization URL in a signed-in browser page. Supabase sends the browser to
 * <site_url>/oauth/consent; the tests serve the app on another port than the configured site
 * URL, so that one hop is mapped onto `appBaseUrl`.
 */
export async function openAuthorization(
  page: Page,
  authorizationUrl: URL,
  appBaseUrl: string,
): Promise<void> {
  const app = new URL(appBaseUrl);
  // Route handlers do not see redirect hops, so rewrite the authorize response's Location.
  await page.route(`${authorizationUrl.origin}${authorizationUrl.pathname}**`, async (route) => {
    const response = await route.fetch({ maxRedirects: 0 });
    const location = new URL(response.headers()['location'] ?? '', authorizationUrl);
    if (location.pathname === '/oauth/consent') {
      location.protocol = app.protocol;
      location.host = app.host;
    }
    await route.fulfill({ response, headers: { ...response.headers(), location: location.toString() } });
  });
  await page.route(`${callbackUrl}**`, (route) =>
    route.fulfill({ contentType: 'text/html', body: '<h1>MCP-Client: Anmeldung abgeschlossen</h1>' }));
  await page.goto(authorizationUrl.toString());
}

/** Waits for the redirect to the client's callback and returns its query parameters. */
export async function callbackParams(page: Page): Promise<URLSearchParams> {
  await page.waitForURL(`${callbackUrl}**`);
  return new URL(page.url()).searchParams;
}
