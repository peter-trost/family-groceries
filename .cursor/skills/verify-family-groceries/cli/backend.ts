/** Secondary surfaces: Postgres state, Edge Functions over HTTP, a REST/realtime peer client, and Mailpit. */

import { type Command, FgError, int, type JsonObject, str, usage } from './core.ts';
import { clientName, USERS } from './instance.ts';
import { householdOf, restAs, signIn, sql, sqlRows, stackEnv } from './stack.ts';

const asFlag = { name: 'as', help: 'Run as this seeded user (peter or lea) instead of the superuser.', choices: ['peter', 'lea'] };

export const backendCommands: Command[] = [
  {
    name: 'db query',
    summary: 'Run SQL against the local database; read-only JSON rows unless --write.',
    usage: 'fg db query "<sql>" [--as peter|lea] [--write] [--dry-run]',
    description:
      "A single SELECT/WITH returns {rows: [...]}. The session is read-only unless --write, so a stray UPDATE fails with code read_only instead of changing data. --as runs the statement as role authenticated with that user's id, so RLS applies exactly as in the app (use it to prove cross-household isolation).",
    flags: [asFlag, { name: 'write', type: 'boolean', help: "Allow writes; output is psql's status text instead of rows." }],
    examples: [
      'fg db query "select name, status, category_id from items order by created_at desc limit 5"',
      'fg db query "select count(*) from items" --as lea',
      'fg db query "delete from items where name = \'Milch\'" --write --dry-run',
    ],
    destructive: true,
    async run(ctx, args) {
      const text = args.positional[0];
      if (!text) throw usage('No SQL given.', 'Quote it: fg db query "select * from items"');
      const as = str(args, 'as');
      const asUser = as ? await userId(ctx, clientName(as)) : undefined;
      if (args.flags.write) {
        const out = await ctx.act(`run as ${as ?? 'postgres'}: ${text}`, () => sql(ctx.sh, ctx.inst, text, { write: true, asUser }));
        return { as: as ?? 'postgres', write: true, output: out?.trim() ?? null };
      }
      if (ctx.dryRun) {
        ctx.actions.push(`read as ${as ?? 'postgres'}: ${text}`);
        return { as: as ?? 'postgres' };
      }
      const rows = await sqlRows(ctx.sh, ctx.inst, text, asUser);
      return { as: as ?? 'postgres', count: rows.length, rows };
    },
  },
  {
    name: 'fn call',
    summary: 'Call an Edge Function over HTTP as a seeded user (or anonymously).',
    usage: 'fg fn call <function> [--as peter|lea|anon] [--method POST] [--path /sub/path] [--body JSON] [--bearer TOKEN] [--dry-run]',
    description:
      "Hits http://127.0.0.1:<prefix>21/functions/v1/<function><path> with the publishable key and the user's session JWT (or --bearer, e.g. a personal access token). Returns status, content type and the parsed body. Some functions write data (voice, mcp tools/call), hence --dry-run.",
    flags: [
      { name: 'as', help: 'peter, lea or anon (default peter).', choices: ['peter', 'lea', 'anon'] },
      { name: 'method', help: 'HTTP method (default GET, or POST with --body).' },
      { name: 'path', help: 'Suffix after the function name, e.g. /.well-known/oauth-protected-resource.' },
      { name: 'body', help: 'JSON request body.' },
      { name: 'bearer', help: 'Use this token instead of a session (PAT: fgp_...).' },
    ],
    examples: [
      'fg fn call health --as anon',
      'fg fn call mcp --method POST --body \'{"jsonrpc":"2.0","id":1,"method":"tools/list"}\'',
      'fg fn call mcp --as anon --path /.well-known/oauth-protected-resource',
    ],
    destructive: true,
    async run(ctx, args) {
      const name = args.positional[0];
      if (!name) throw usage('Which function?', 'e.g. fg fn call health; functions live in supabase/functions/.');
      const env = await stackEnv(ctx.sh, ctx.inst);
      const as = str(args, 'as') ?? 'peter';
      const body = str(args, 'body');
      if (body !== undefined) {
        try {
          JSON.parse(body);
        } catch {
          throw usage('--body is not valid JSON.', 'Quote it in single quotes: --body \'{"text":"Milch"}\'');
        }
      }
      const method = str(args, 'method') ?? (body ? 'POST' : 'GET');
      const url = `${env.apiUrl}/functions/v1/${name}${str(args, 'path') ?? ''}`;
      const token = str(args, 'bearer') ?? (as === 'anon' ? undefined : (await signIn(ctx.sh, env, clientName(as))).accessToken);
      const headers: Record<string, string> = { apikey: env.publishableKey, accept: 'application/json, text/event-stream' };
      if (token) headers.authorization = `Bearer ${token}`;
      if (body) headers['content-type'] = 'application/json';
      const res = await ctx.act(
        `${method} ${url} as ${str(args, 'bearer') ? 'bearer token' : as}`,
        () => ctx.sh.fetch(url, { method, headers, body }),
      );
      if (!res) return { method, url };
      const text = await res.text();
      let parsed: JsonObject | string = text;
      try {
        parsed = JSON.parse(text);
      } catch { /* not JSON: keep the text */ }
      return {
        method,
        url,
        status: res.status,
        contentType: res.headers.get('content-type'),
        wwwAuthenticate: res.headers.get('www-authenticate'),
        body: parsed,
      };
    },
  },
  {
    name: 'peer',
    summary: 'A second client over REST/realtime: add, tick or list items, or watch live changes.',
    usage: 'fg peer <peter|lea> add <name> | tick <name> | list | watch [--timeout S] [--until TEXT] [--dry-run]',
    description:
      'Acts as the given user through the same PostgREST and Realtime endpoints the app uses, without a UI. Use it as the second client when only one app runs (Android), and as an independent observer: `watch` prints realtime events for the household until --until appears in an item name or --timeout passes.',
    flags: [{ name: 'timeout', help: 'Seconds for watch (default 15).' }, {
      name: 'until',
      help: 'Stop watch at the first event for an item with this name.',
    }],
    examples: ['fg peer lea add Butter', 'fg peer lea tick Milch', 'fg peer lea list', 'fg peer lea watch --until Brot --timeout 20'],
    destructive: true,
    async run(ctx, args) {
      const [rawUser, action, ...words] = args.positional;
      const user = clientName(rawUser);
      const env = await stackEnv(ctx.sh, ctx.inst);
      const session = await signIn(ctx.sh, env, user);
      const household = await householdOf(ctx.sh, ctx.inst, user);
      if (!household) throw new FgError('no_household', `${USERS[user].email} is in no household.`, 'Run `fg seed`.');
      const itemName = words.join(' ');
      const active = async () =>
        (await restAs(
          ctx.sh,
          env,
          session,
          `items?select=id,name,quantity,status,category_id&household_id=eq.${household}&status=eq.active&order=created_at`,
        )) as JsonObject[];
      switch (action) {
        case 'list':
          return { user, items: await active() };
        case 'add': {
          if (!itemName) throw usage('What to add?', 'e.g. fg peer lea add Butter');
          const row = await ctx.act(
            `${user} adds "${itemName}"`,
            () =>
              restAs(ctx.sh, env, session, 'items', {
                method: 'POST',
                body: JSON.stringify({ id: crypto.randomUUID(), household_id: household, name: itemName, status: 'active' }),
              }),
          );
          return { user, added: ((row as JsonObject[] | undefined)?.[0] ?? null) as JsonObject | null };
        }
        case 'tick': {
          const match = (await active()).find((i) => i.name === itemName);
          if (!match) {
            throw new FgError(
              'not_found',
              `"${itemName}" is not on ${user}'s active list.`,
              '`fg peer <user> list` shows the exact names.',
            );
          }
          await ctx.act(
            `${user} ticks "${itemName}"`,
            () => restAs(ctx.sh, env, session, `items?id=eq.${match.id}`, { method: 'PATCH', body: JSON.stringify({ status: 'bought' }) }),
          );
          return { user, ticked: match };
        }
        case 'watch':
          return {
            user,
            ...(await watch(env.apiUrl, env.publishableKey, session.accessToken, household, int(args, 'timeout', 15), str(args, 'until'))),
          };
        default:
          throw usage(`Unknown peer action "${action ?? ''}".`, 'Use add, tick, list or watch.');
      }
    },
  },
  {
    name: 'mail',
    summary: 'Read the local inbox (Mailpit) and extract sign-in links.',
    usage: 'fg mail [--to peter|lea|EMAIL] [--limit N]',
    description:
      'Lists the newest messages for the address with subject, time and any auth links (magic link, confirmation). Nothing leaves the box: the local stack sends all mail to Mailpit.',
    flags: [{ name: 'to', help: 'Seeded user or an email address (default: all).' }, {
      name: 'limit',
      help: 'Messages to return (default 5).',
    }],
    examples: ['fg mail --to peter', 'fg mail --limit 1'],
    async run(ctx, args) {
      const to = str(args, 'to');
      const address = to === 'peter' || to === 'lea' ? USERS[to].email : to;
      const res = await ctx.sh.fetch(`${ctx.inst.mailUrl}/api/v1/messages?limit=50`).catch(() => null);
      if (!res?.ok) {
        throw new FgError(
          'mail_down',
          `Mailpit at ${ctx.inst.mailUrl} does not answer.`,
          'Run `fg doctor`; start the stack with `fg up --only stack`.',
        );
      }
      const list = (await res.json()).messages as JsonObject[];
      const mine = list.filter((m) => !address || (m.To as JsonObject[]).some((t) => t.Address === address)).slice(
        0,
        int(args, 'limit', 5),
      );
      const messages: JsonObject[] = [];
      for (const m of mine) {
        const full = await (await ctx.sh.fetch(`${ctx.inst.mailUrl}/api/v1/message/${m.ID}`)).json();
        const links = [...new Set(String(full.Text ?? full.HTML ?? '').match(/https?:\/\/[^\s"'<>)]+/g) ?? [])].filter((l) =>
          l.includes('/auth/v1/')
        );
        messages.push({ id: m.ID, to: (m.To as JsonObject[]).map((t) => t.Address), subject: m.Subject, created: m.Created, links });
      }
      return { to: address ?? null, count: messages.length, messages };
    },
  },
];

async function userId(ctx: Parameters<Command['run']>[0], user: 'peter' | 'lea'): Promise<string> {
  const rows = await sqlRows(ctx.sh, ctx.inst, `select id from auth.users where email = '${USERS[user].email}'`);
  if (!rows[0]) throw new FgError('no_user', `${USERS[user].email} does not exist.`, 'Run `fg seed`.');
  return rows[0].id as string;
}

async function watch(url: string, key: string, token: string, household: string, timeoutS: number, until?: string): Promise<JsonObject> {
  const { createClient } = await import('@supabase/supabase-js');
  const client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  client.realtime.setAuth(token);
  const events: JsonObject[] = [];
  const started = Date.now();
  let subscribed = false;
  const done = await new Promise<string>((resolve) => {
    const timer = setTimeout(() => resolve('timeout'), timeoutS * 1000);
    client
      .channel(`fg-peer-${household}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'items', filter: `household_id=eq.${household}` }, (p) => {
        const row = (Object.keys(p.new ?? {}).length ? p.new : p.old) as JsonObject;
        events.push({
          atMs: Date.now() - started,
          event: p.eventType,
          name: row.name ?? null,
          status: row.status ?? null,
          id: row.id ?? null,
        });
        if (until && row.name === until) {
          clearTimeout(timer);
          resolve('matched');
        }
      })
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') subscribed = true;
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          clearTimeout(timer);
          resolve(status);
        }
      });
  });
  await client.removeAllChannels();
  if (!subscribed) {
    throw new FgError('realtime_failed', `Realtime subscription failed (${done}).`, 'Check `fg logs --service realtime` and `fg doctor`.');
  }
  if (until && done !== 'matched') {
    throw new FgError(
      'timeout',
      `No realtime event for "${until}" within ${timeoutS} s.`,
      'Did the other client actually write? Check `fg db query`.',
      1,
      { events },
    );
  }
  return { result: done, events };
}
