import { assertEquals, assertMatch } from '@std/assert';
import { AuthError } from '../_shared/auth.ts';
import { type Added, type Caller, confirmation, createHandler, type Deps } from './handler.ts';
import type { ParsedItem } from './parse.ts';

const caller: Caller = { userId: 'u1', householdId: 'h1' };
const fail = (status: 401 | 403) =>
  new AuthError(status === 403 ? 'no_household' : 'invalid_token', 'test');

/** A fake list: "Milch" is already on it, everything else lands in "Sonstiges". */
function fakeDeps(overrides: Partial<Deps> = {}) {
  const calls: ParsedItem[][] = [];
  const deps: Deps = {
    authenticate: (req) =>
      req.headers.get('authorization') === 'Bearer fgp_good'
        ? Promise.resolve(caller)
        : Promise.reject(fail(401)),
    addItems: (_caller, items) => {
      calls.push(items);
      return Promise.resolve(items.map((item) => ({
        ...item,
        category: 'Sonstiges',
        alreadyOnList: item.name === 'Milch',
      })));
    },
    ...overrides,
  };
  return { handle: createHandler(deps), calls };
}

const post = (body: unknown, init: { token?: string; query?: string; type?: string } = {}) =>
  new Request(`http://local/voice${init.query ?? ''}`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${init.token ?? 'fgp_good'}`,
      'content-type': init.type ?? 'application/json',
    },
    body: typeof body === 'string' && init.type ? body : JSON.stringify(body),
  });

Deno.test('adds the split items and confirms them in German', async () => {
  const { handle, calls } = fakeDeps();
  const res = await handle(post({ text: 'Zwei Gurken und Klopapier' }));
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.speech, 'Hinzugefügt: 2 Gurken, Klopapier.');
  assertEquals(calls, [[{ name: 'Gurken', quantity: '2' }, { name: 'Klopapier', quantity: null }]]);
  assertEquals(body.items[0], {
    name: 'Gurken',
    quantity: '2',
    category: 'Sonstiges',
    alreadyOnList: false,
  });
});

Deno.test('names items that were already on the list', async () => {
  const { handle } = fakeDeps();
  const res = await handle(post({ text: 'Milch, zwei Gurken und Klopapier' }));
  assertEquals(
    (await res.json()).speech,
    'Hinzugefügt: 2 Gurken, Klopapier. Schon auf der Liste: Milch.',
  );
});

Deno.test('answers in plain text with ?format=text', async () => {
  const { handle } = fakeDeps();
  const res = await handle(post({ text: 'Klopapier' }, { query: '?format=text' }));
  assertEquals(res.headers.get('content-type'), 'text/plain; charset=utf-8');
  assertEquals(await res.text(), 'Hinzugefügt: Klopapier.');
});

Deno.test('accepts a plain-text body', async () => {
  const { handle } = fakeDeps();
  const res = await handle(post('Klopapier', { type: 'text/plain' }));
  assertEquals((await res.json()).speech, 'Hinzugefügt: Klopapier.');
});

Deno.test('parse mode splits without adding', async () => {
  const { handle, calls } = fakeDeps();
  const res = await handle(post({ text: 'Milch und 1 kg Mehl', mode: 'parse' }));
  assertEquals(res.status, 200);
  assertEquals((await res.json()).items, [
    { name: 'Milch', quantity: null },
    { name: 'Mehl', quantity: '1 kg' },
  ]);
  assertEquals(calls, []);
});

const errors: [string, () => Request, Partial<Deps>, number, string, RegExp][] = [
  [
    'wrong token',
    () => post({ text: 'Milch' }, { token: 'nope' }),
    {},
    401,
    'unauthorized',
    /Zugriffstoken/,
  ],
  [
    'no household',
    () => post({ text: 'Milch' }),
    { authenticate: () => Promise.reject(fail(403)) },
    403,
    'no_household',
    /keinem Haushalt/,
  ],
  ['GET', () => new Request('http://local/voice'), {}, 405, 'method', /POST/],
  ['empty text', () => post({ text: '  ' }), {}, 400, 'no_text', /keinen Text/],
  ['no text field', () => post({ words: 'Milch' }), {}, 400, 'no_text', /keinen Text/],
  [
    'broken JSON',
    () => post('{"text": ', { type: 'application/json' }),
    {},
    400,
    'no_text',
    /keinen Text/,
  ],
  [
    'only filler',
    () => post({ text: 'Bitte, danke' }),
    {},
    422,
    'nothing_understood',
    /nichts verstanden/,
  ],
  ['too long', () => post({ text: 'Milch '.repeat(300) }), {}, 413, 'too_long', /zu lang/],
  [
    'database down',
    () => post({ text: 'Milch' }),
    { addItems: () => Promise.reject(new Error('boom')) },
    500,
    'server',
    /nicht geklappt/,
  ],
  [
    'auth backend down',
    () => post({ text: 'Milch' }),
    { authenticate: () => Promise.reject(new Error('jwks down')) },
    500,
    'server',
    /nicht geklappt/,
  ],
];

for (const [label, request, overrides, status, error, speech] of errors) {
  Deno.test(`answers ${status} ${error} for ${label}`, async () => {
    const { handle, calls } = fakeDeps(overrides);
    const res = await handle(request());
    assertEquals(res.status, status);
    const body = await res.json();
    assertEquals(body.error, error);
    assertMatch(body.speech, speech);
    assertEquals(calls, []);
  });
}

Deno.test('a 401 tells the client to send a bearer token', async () => {
  const { handle } = fakeDeps();
  const res = await handle(post({ text: 'Milch' }, { token: 'nope' }));
  assertEquals(res.headers.get('www-authenticate'), 'Bearer');
  await res.body?.cancel();
});

Deno.test('answers CORS preflight', async () => {
  const { handle } = fakeDeps();
  const res = await handle(new Request('http://local/voice', { method: 'OPTIONS' }));
  assertEquals(res.status, 204);
  assertEquals(res.headers.get('access-control-allow-origin'), '*');
});

Deno.test('confirmation lists only what was said back', () => {
  const item = (name: string, alreadyOnList: boolean, quantity: string | null = null): Added => ({
    name,
    quantity,
    category: 'Kühlregal',
    alreadyOnList,
  });
  assertEquals(confirmation([item('Milch', true)]), 'Schon auf der Liste: Milch.');
  assertEquals(
    confirmation([item('Mehl', false, '1 kg'), item('Eier', false)]),
    'Hinzugefügt: 1 kg Mehl, Eier.',
  );
});

Deno.test('more than thirty items: the first thirty are added and Siri says so', async () => {
  const { handle, calls } = fakeDeps();
  const sentence = Array.from({ length: 40 }, (_, i) => `Ding${i}`).join(', ');
  const res = await handle(post({ text: sentence }));
  const body = await res.json();
  assertEquals(calls[0].length, 30);
  assertEquals(body.truncated, true);
  assertMatch(body.speech, /Mehr als dreißig auf einmal gehen nicht/);
});

Deno.test('thirty items exactly are not reported as cut', async () => {
  const { handle } = fakeDeps();
  const sentence = Array.from({ length: 30 }, (_, i) => `Ding${i}`).join(', ');
  const body = await (await handle(post({ text: sentence }))).json();
  assertEquals(body.truncated, false);
  assertEquals(body.items.length, 30);
});
