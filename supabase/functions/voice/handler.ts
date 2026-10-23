// POST /functions/v1/voice {"text": "Milch, zwei Gurken und Klopapier"}
// Splits the sentence, adds the items to the caller's list and answers with a German
// sentence for Siri to speak. `?format=text` answers with that sentence as plain text.
// {"text": ..., "mode": "parse"} only splits; the app adds the items itself.
import { AuthError } from '../_shared/auth.ts';
import { corsHeaders, json, preflight } from '../_shared/http.ts';
import { type ParsedItem, parseSentence, spoken } from './parse.ts';

export interface Caller {
  userId: string;
  householdId: string;
}

export interface Added extends ParsedItem {
  /** The category the classifier picked, by name. */
  category: string;
  /** True when the item was active already and nothing was added. */
  alreadyOnList: boolean;
}

export interface Deps<C extends Caller = Caller> {
  /** Resolves the bearer token; throws an AuthError when it can't. */
  authenticate(req: Request): Promise<C>;
  addItems(caller: C, items: ParsedItem[]): Promise<Added[]>;
}

export const maxTextLength = 1000;

const example = 'Sag zum Beispiel: Milch, zwei Gurken und Klopapier.';

const failures = {
  method: [405, 'Bitte schick den Text per POST.'],
  unauthorized: [
    401,
    'Der Zugriffstoken fehlt oder ist ungültig. Erstelle in der Einkauf-App unter Menü, Zugänge einen neuen.',
  ],
  no_household: [
    403,
    'Du bist noch in keinem Haushalt. Leg in der Einkauf-App einen an oder tritt einem bei.',
  ],
  no_text: [400, `Ich habe keinen Text bekommen. ${example}`],
  too_long: [413, 'Das war zu lang. Sag höchstens dreißig Dinge auf einmal.'],
  nothing_understood: [422, `Ich habe nichts verstanden, was auf die Liste soll. ${example}`],
  server: [500, 'Das hat leider nicht geklappt. Versuch es gleich noch einmal.'],
} as const satisfies Record<string, readonly [number, string]>;

type Failure = keyof typeof failures;

/** The confirmation Siri speaks. */
export function confirmation(results: Added[]): string {
  const list = (items: Added[]) => items.map(spoken).join(', ');
  const added = results.filter((r) => !r.alreadyOnList);
  const existing = results.filter((r) => r.alreadyOnList);
  return [
    added.length ? `Hinzugefügt: ${list(added)}.` : '',
    existing.length ? `Schon auf der Liste: ${list(existing)}.` : '',
  ].filter(Boolean).join(' ');
}

interface Body {
  text: string | null;
  mode: 'add' | 'parse';
}

/** Accepts JSON {"text", "mode"}, a JSON string, or a plain-text body. */
async function readBody(req: Request): Promise<Body> {
  const raw = await req.text();
  if (!(req.headers.get('content-type') ?? '').includes('json')) return { text: raw, mode: 'add' };
  try {
    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed === 'string') return { text: parsed, mode: 'add' };
    const { text, mode } = (parsed ?? {}) as { text?: unknown; mode?: unknown };
    return {
      text: typeof text === 'string' ? text : null,
      mode: mode === 'parse' ? 'parse' : 'add',
    };
  } catch {
    return { text: null, mode: 'add' };
  }
}

export function createHandler<C extends Caller>(deps: Deps<C>) {
  return async (req: Request): Promise<Response> => {
    const early = preflight(req);
    if (early) return early;
    const asText = new URL(req.url).searchParams.get('format') === 'text';

    const reply = (status: number, body: { speech: string } & Record<string, unknown>) => {
      if (!asText) return json(body, { status, headers: authHeader(status) });
      return new Response(body.speech, {
        status,
        headers: {
          ...corsHeaders,
          ...authHeader(status),
          'content-type': 'text/plain; charset=utf-8',
        },
      });
    };
    const fail = (error: Failure) => {
      const [status, speech] = failures[error];
      return reply(status, { error, speech });
    };

    if (req.method !== 'POST') return fail('method');

    let caller: C;
    try {
      caller = await deps.authenticate(req);
    } catch (e) {
      if (e instanceof AuthError) return fail(e.status === 403 ? 'no_household' : 'unauthorized');
      console.error('voice: authenticate failed', e);
      return fail('server');
    }

    const body = await readBody(req);
    const text = body.text?.trim();
    if (!text) return fail('no_text');
    if (text.length > maxTextLength) return fail('too_long');
    const items = parseSentence(text);
    if (!items.length) return fail('nothing_understood');

    if (body.mode === 'parse') {
      return reply(200, { speech: `Verstanden: ${items.map(spoken).join(', ')}.`, items });
    }

    try {
      const added = await deps.addItems(caller, items);
      return reply(200, { speech: confirmation(added), items: added });
    } catch (e) {
      console.error('voice: adding items failed', e);
      return fail('server');
    }
  };
}

const authHeader = (status: number): Record<string, string> =>
  status === 401 ? { 'www-authenticate': 'Bearer' } : {};
