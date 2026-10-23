/** Commands that act on a running app client through Marionette. */

import { type Args, type Command, type Ctx, FgError, type FlagSpec, int, type JsonObject, str, usage } from './core.ts';
import { type ClientName, clientName, type ClientState, USERS } from './instance.ts';
import { type Element, Marionette, type Matcher, matcherArgs, rowKeyFor, SCREEN_KEYS, screenOf } from './marionette.ts';
import { waitFor } from './surfaces.ts';

export const clientFlag: FlagSpec = {
  name: 'client',
  help: 'Which running app to drive: peter (default) or lea.',
  choices: ['peter', 'lea'],
};

const matcherFlags: FlagSpec[] = [
  { name: 'key', help: 'ValueKey<String> of the widget (most stable). Keys: see features/README.md.' },
  { name: 'text', help: 'Exact visible text, e.g. "Haushalt anlegen" or an item name.' },
  { name: 'type', help: 'Widget type name, e.g. Checkbox, FilledButton.' },
  { name: 'identifier', help: 'Semantics identifier.' },
  { name: 'tooltip', help: 'Tooltip of an icon button, e.g. "Menü" (tapped at its center).' },
  { name: 'label', help: 'Label/hint of a text field, e.g. "Was fehlt?" (tapped at its center).' },
  { name: 'x', help: 'X coordinate in logical pixels (with --y).' },
  { name: 'y', help: 'Y coordinate in logical pixels (with --x).' },
  { name: 'row', help: 'Scope the match to the list row that shows this exact text, e.g. --row Milch --type Checkbox.' },
];

export function client(ctx: Ctx, args: Args): { name: ClientName; state: ClientState; m: Marionette } {
  const name = clientName(str(args, 'client'));
  const state = ctx.state.clients[name];
  if (!state) {
    throw new FgError(
      'no_client',
      `No ${name} app is running in this instance (FG_PORT_PREFIX=${ctx.inst.prefix}).`,
      name === 'peter' ? 'Run `fg up`.' : 'Run `fg up --clients peter,lea` to start the second app.',
    );
  }
  return { name, state, m: new Marionette(ctx.sh, state.vmUri) };
}

type Resolved = { matcher: Matcher; ancestors: string[] };

/** Turns matcher flags into a Marionette matcher; tooltip/label become coordinates from the element list. */
async function resolve(m: Marionette, args: Args, required = true): Promise<Resolved | null> {
  const ancestors: string[] = [];
  const row = str(args, 'row');
  let elements: Element[] | null = null;
  const all = async () => (elements ??= await m.elements());
  if (row !== undefined) ancestors.push(rowKeyFor(await all(), row));
  const given = ['key', 'text', 'type', 'identifier', 'tooltip', 'label'].filter((f) => str(args, f) !== undefined);
  const hasXY = str(args, 'x') !== undefined || str(args, 'y') !== undefined;
  if (given.length + (hasXY ? 1 : 0) > 1) {
    throw usage(
      `Give one matcher, got ${[...given, ...(hasXY ? ['x/y'] : [])].join(', ')}.`,
      'Combine a matcher only with --row, e.g. --row Milch --type Checkbox.',
    );
  }
  if (hasXY) {
    if (str(args, 'x') === undefined || str(args, 'y') === undefined) throw usage('--x and --y go together.', 'e.g. --x 200 --y 88');
    return { matcher: { x: int(args, 'x', 0), y: int(args, 'y', 0) }, ancestors };
  }
  const flag = given[0];
  if (flag === undefined) {
    if (!required) return null;
    throw usage(
      'No matcher given.',
      'Pass one of --key, --text, --type, --identifier, --tooltip, --label or --x/--y. `fg find` lists candidates.',
    );
  }
  const value = str(args, flag)!;
  if (flag === 'tooltip' || flag === 'label') {
    const el = (await all()).find((e) => e[flag] === value && e.bounds);
    if (!el?.bounds) {
      throw new FgError('not_found', `No element with ${flag} "${value}".`, 'Run `fg find` to list tooltips and labels on screen.');
    }
    return { matcher: { x: el.bounds.x + el.bounds.width / 2, y: el.bounds.y + el.bounds.height / 2 }, ancestors: [] };
  }
  return { matcher: { [flag]: value } as Matcher, ancestors };
}

const withAncestors = (r: Resolved) => [...matcherArgs(r.matcher), ...r.ancestors.flatMap((k) => ['--ancestor-keys', k])];

export function filterElements(elements: Element[], args: Args): Element[] {
  const eq = (field: keyof Element, flag: string) => {
    const want = str(args, flag);
    return (e: Element) => want === undefined || e[field] === want;
  };
  const contains = str(args, 'contains');
  return elements
    .filter(eq('key', 'key'))
    .filter(eq('text', 'text'))
    .filter(eq('type', 'type'))
    .filter(eq('identifier', 'identifier'))
    .filter(eq('tooltip', 'tooltip'))
    .filter(eq('label', 'label'))
    .filter((e) => contains === undefined || [e.text, e.label, e.tooltip, e.key].some((v) => v?.includes(contains)));
}

/** Waits until one of the keys is on screen; returns which. */
async function waitForAnyKey(ctx: Ctx, m: Marionette, keys: string[], timeoutMs: number): Promise<string> {
  let seen: string | undefined;
  await waitFor(
    ctx.sh,
    async () => {
      const elements = await m.elements().catch(() => []);
      seen = keys.find((k) => elements.some((e) => e.key === k));
      return seen !== undefined;
    },
    timeoutMs,
    () =>
      new FgError(
        'timeout',
        `None of ${keys.join(', ')} appeared within ${timeoutMs / 1000} s.`,
        'Take `fg screenshot` to see the screen; `fg logs` shows app errors.',
      ),
  );
  return seen!;
}

export const driveCommands: Command[] = [
  {
    name: 'find',
    summary: 'List widgets on screen (type, key, text, label, tooltip, bounds) as JSON.',
    usage: 'fg find [--key K] [--text T] [--type W] [--label L] [--tooltip T] [--contains S] [--row TEXT] [--client peter|lea]',
    description:
      "Reads Marionette's interactive-element tree. Filters are exact matches and combine with AND; --contains matches a substring of text, label, tooltip or key. --row limits the tree to the list row showing that text. An empty result is not an error: check `count`.",
    flags: [...matcherFlags.filter((f) => !['x', 'y'].includes(f.name)), {
      name: 'contains',
      help: 'Substring of text, label, tooltip or key.',
    }, clientFlag],
    examples: ['fg find', 'fg find --text Milch', 'fg find --row Milch --type Checkbox', 'fg find --key add-item-field --client lea'],
    async run(ctx, args) {
      const { name, m } = client(ctx, args);
      const row = str(args, 'row');
      const ancestors = row === undefined ? [] : [rowKeyFor(await m.elements(), row)];
      const elements = filterElements(await m.elements(ancestors), args);
      return { client: name, count: elements.length, elements: elements as unknown as JsonObject[] };
    },
  },
  {
    name: 'tap',
    summary: 'Tap a widget by key, text, type, tooltip, label, row, or coordinates.',
    usage:
      'fg tap (--key K | --text T | --type W | --identifier I | --tooltip T | --label L | --x X --y Y) [--row TEXT] [--client peter|lea]',
    description:
      "Taps through Marionette's gesture dispatcher, the same path as a finger. Text must match exactly. To tick an item, tap the checkbox in its row: `fg tap --row Milch --type Checkbox`. Tapping an item's name opens its edit sheet instead.",
    flags: [...matcherFlags, clientFlag],
    examples: ['fg tap --text "Haushalt anlegen"', 'fg tap --row Milch --type Checkbox', 'fg tap --tooltip Menü', 'fg tap --text Abmelden'],
    async run(ctx, args) {
      const { name, m } = client(ctx, args);
      const r = (await resolve(m, args))!;
      await m.call(['tap', ...withAncestors(r)]);
      return { client: name, tapped: r as unknown as JsonObject };
    },
  },
  {
    name: 'type',
    summary: 'Enter text into a field (default: the focused one), optionally pressing Enter.',
    usage: 'fg type --input TEXT [--key K | --label L | --identifier I] [--submit] [--client peter|lea]',
    description:
      'Without a matcher it types into the focused field, which proves focus: on the list screen the add field has focus on launch. With --key or --label it taps the field first, so --submit reaches it; --label finds keyless fields by their label (e.g. "Einladungscode"). The text replaces the field\'s content. --submit sends a real Enter key event (onSubmitted runs). Umlauts and ß are safe.',
    flags: [
      { name: 'input', help: 'Text to enter (required).' },
      ...matcherFlags.filter((f) => ['key', 'label', 'identifier'].includes(f.name)),
      { name: 'submit', type: 'boolean', help: 'Press Enter afterwards.' },
      clientFlag,
    ],
    examples: [
      'fg type --input Milch --submit',
      'fg type --key login-email --input peter@fg.test',
      'fg type --input "2 Äpfel" --submit --client lea',
      'fg type --label Einladungscode --input ABCD2345 --submit',
    ],
    async run(ctx, args) {
      const { name, m } = client(ctx, args);
      const input = str(args, 'input');
      if (input === undefined) throw usage('--input is required.', 'e.g. fg type --input Milch --submit');
      const r = await resolve(m, args, false);
      if (r) await m.call(['tap', ...withAncestors(r)]);
      // A label resolves to coordinates; once tapped, the field is the focused one.
      const target = !r || 'x' in r.matcher ? ['--focused'] : withAncestors(r);
      await m.call(['enter-text', ...target, '--input', input]);
      if (args.flags.submit) await m.call(['press-key', '--key', 'enter']);
      return {
        client: name,
        typed: input,
        into: r ? (r.matcher as unknown as JsonObject) : 'focused',
        submitted: Boolean(args.flags.submit),
      };
    },
  },
  {
    name: 'press',
    summary: 'Press a key on the focused widget (enter, tab, escape, backspace, arrows, a-z, 0-9).',
    usage: 'fg press <key> [--modifiers control,shift,alt,meta] [--client peter|lea]',
    description: "Sends a real key event through Flutter's focus system.",
    flags: [{ name: 'modifiers', help: 'Comma-separated: control, shift, alt, meta.' }, clientFlag],
    examples: ['fg press enter', 'fg press escape', 'fg press a --modifiers control'],
    async run(ctx, args) {
      const { name, m } = client(ctx, args);
      const key = args.positional[0];
      if (!key) throw usage('Which key?', 'e.g. fg press enter');
      const mods = str(args, 'modifiers');
      await m.call(['press-key', '--key', key, ...(mods ? ['--modifiers', mods] : [])]);
      return { client: name, pressed: key, modifiers: mods ?? null };
    },
  },
  {
    name: 'back',
    summary: 'Press the system back button (closes sheets and dialogs, pops routes).',
    usage: 'fg back [--client peter|lea]',
    description: 'Android back / route pop. On the root route it does nothing useful on Linux.',
    flags: [clientFlag],
    examples: ['fg back'],
    async run(ctx, args) {
      const { name, m } = client(ctx, args);
      return { client: name, output: (await m.call(['press-back-button'])).trim() };
    },
  },
  {
    name: 'swipe',
    summary: 'Swipe a widget or row in a direction (e.g. swipe an item left to delete it).',
    usage: 'fg swipe (--key K | --text T | --row TEXT) --direction left|right|up|down [--distance PX] [--client peter|lea]',
    description:
      'List rows are Dismissible: swiping left far enough deletes the item (with an undo snackbar). --row swipes the whole row that shows the text.',
    flags: [
      ...matcherFlags.filter((f) => ['key', 'text', 'type', 'row'].includes(f.name)),
      { name: 'direction', help: 'left, right, up or down.', choices: ['left', 'right', 'up', 'down'] },
      { name: 'distance', help: 'Pixels (default 300).' },
      clientFlag,
    ],
    examples: ['fg swipe --row Milch --direction left'],
    async run(ctx, args) {
      const { name, m } = client(ctx, args);
      const direction = str(args, 'direction');
      if (!direction) throw usage('--direction is required.', 'e.g. --direction left');
      const row = str(args, 'row');
      const target = row !== undefined && !['key', 'text', 'type'].some((f) => str(args, f))
        ? ['--key', rowKeyFor(await m.elements(), row)]
        : withAncestors((await resolve(m, args))!);
      await m.call(['swipe', ...target, '--direction', direction, '--distance', String(int(args, 'distance', 300))]);
      return { client: name, swiped: direction, target: target.join(' ') };
    },
  },
  {
    name: 'wait',
    summary: 'Wait until a widget appears (or with --gone, disappears). Use instead of sleep.',
    usage:
      'fg wait (--key K | --text T | --type W | --label L | --tooltip T | --contains S) [--gone] [--timeout SECONDS] [--client peter|lea]',
    description:
      'Polls the element tree every 0.5 s. Exits 0 with the matches once the condition holds, or fails with code "timeout" (default 15 s). Live-sync checks use this on the other client: `fg wait --text Milch --gone --client lea`.',
    flags: [
      ...matcherFlags.filter((f) => !['x', 'y', 'row'].includes(f.name)),
      { name: 'contains', help: 'Substring of text, label, tooltip or key.' },
      { name: 'gone', type: 'boolean', help: 'Wait until nothing matches.' },
      { name: 'timeout', help: 'Seconds (default 15).' },
      clientFlag,
    ],
    examples: ['fg wait --key add-item-field', 'fg wait --text Milch --client lea --timeout 5', 'fg wait --text Milch --gone --client lea'],
    async run(ctx, args) {
      const { name, m } = client(ctx, args);
      if (!['key', 'text', 'type', 'identifier', 'label', 'tooltip', 'contains'].some((f) => str(args, f) !== undefined)) {
        throw usage('No condition given.', 'Pass --key, --text, --type, --label, --tooltip or --contains.');
      }
      const gone = Boolean(args.flags.gone);
      const timeout = int(args, 'timeout', 15);
      const started = Date.now();
      let matches: Element[] = [];
      await waitFor(
        ctx.sh,
        async () => {
          matches = filterElements(await m.elements(), args);
          return gone ? matches.length === 0 : matches.length > 0;
        },
        timeout * 1000,
        () =>
          new FgError(
            'timeout',
            `After ${timeout} s the element is ${gone ? 'still there' : 'not there'}.`,
            'Take `fg screenshot` to see the screen; raise --timeout if the backend is slow.',
            1,
            { matches: matches as unknown as JsonObject[] },
          ),
      );
      return { client: name, gone, elapsedMs: Date.now() - started, matches: matches as unknown as JsonObject[] };
    },
  },
  {
    name: 'login',
    summary: 'Sign a client in through the real login screen (email + password), or print an API token.',
    usage: 'fg login <peter|lea> [--client peter|lea] [--api]',
    description:
      "Types the seeded credentials into login-email and login-password and presses Enter, then waits for the list (or welcome) screen. The client defaults to the user's own app. Fails with not_on_login if the app is already signed in: `fg logout` first. With --api it drives nothing and prints an access token for curl and `fg fn call`.",
    flags: [clientFlag, { name: 'api', type: 'boolean', help: 'Return {accessToken, userId} instead of driving the UI.' }],
    examples: ['fg login peter', 'fg login lea', 'fg login peter --api'],
    async run(ctx, args) {
      const user = clientName(args.positional[0]);
      if (args.flags.api) {
        const { stackEnv, signIn } = await import('./stack.ts');
        const session = await signIn(ctx.sh, await stackEnv(ctx.sh, ctx.inst), user);
        return { user, email: USERS[user].email, accessToken: session.accessToken, userId: session.userId };
      }
      const { name, m } = client(ctx, { ...args, flags: { ...args.flags, client: str(args, 'client') ?? user } });
      const elements = await m.elements();
      if (!elements.some((e) => e.key === 'login-email')) {
        const screen = screenOf(elements);
        throw new FgError(
          'not_on_login',
          `The ${name} app shows the ${screen} screen, not the login screen.`,
          `Already signed in? Run \`fg logout --client ${name}\` first.`,
          1,
          { screen },
        );
      }
      const { email, password } = USERS[user];
      await m.call(['enter-text', '--key', 'login-email', '--input', email]);
      await m.call(['tap', '--key', 'login-password']);
      await m.call(['enter-text', '--key', 'login-password', '--input', password]);
      await m.call(['press-key', '--key', 'enter']);
      const key = await waitForAnyKey(ctx, m, [SCREEN_KEYS.list, SCREEN_KEYS.welcome], 20_000);
      return { client: name, user, email, screen: key === SCREEN_KEYS.list ? 'list' : 'welcome' };
    },
  },
  {
    name: 'logout',
    summary: 'Sign a client out through its menu (Menü, then Abmelden).',
    usage: 'fg logout [--client peter|lea]',
    description:
      "Opens the list screen's menu and chooses Abmelden, or the welcome screen's Abmelden button, then waits for the login screen.",
    flags: [clientFlag],
    examples: ['fg logout', 'fg logout --client lea'],
    async run(ctx, args) {
      const { name, m } = client(ctx, args);
      const elements = await m.elements();
      if (elements.some((e) => e.key === 'login-email')) return { client: name, screen: 'login', alreadySignedOut: true };
      const tapTooltip = async (tooltip: string) => {
        const el = (await m.elements()).find((e) => e.tooltip === tooltip && e.bounds);
        if (!el?.bounds) {
          throw new FgError('not_found', `No "${tooltip}" button on screen.`, 'Take `fg screenshot`; close dialogs with `fg back`.');
        }
        await m.call(['tap', '--x', String(el.bounds.x + el.bounds.width / 2), '--y', String(el.bounds.y + el.bounds.height / 2)]);
      };
      if (elements.some((e) => e.tooltip === 'Menü')) {
        await tapTooltip('Menü');
        await waitFor(
          ctx.sh,
          async () => (await m.elements()).some((e) => e.text === 'Abmelden'),
          5000,
          () => new FgError('timeout', 'The menu did not open.', 'Take `fg screenshot`.'),
        );
        await m.call(['tap', '--text', 'Abmelden']);
      } else {
        await tapTooltip('Abmelden');
      }
      await waitForAnyKey(ctx, m, ['login-email'], 15_000);
      return { client: name, screen: 'login' };
    },
  },
  {
    name: 'marionette',
    summary: 'Run any Marionette CLI command against a client (escape hatch).',
    usage: 'fg marionette [--client peter|lea] -- <marionette args...>',
    description:
      "Passes the client's VM service URI for you. See `marionette help-ai` for the full reference (scroll-to, long-press, double-tap, set-device-config, get-logs, hot-reload).",
    flags: [clientFlag],
    examples: [
      'fg marionette -- scroll-to --text "Kürzlich gekauft"',
      'fg marionette -- long-press --text Milch',
      'fg marionette -- set-device-config --text-scale 2.0',
    ],
    async run(ctx, args) {
      const { name, m } = client(ctx, args);
      if (args.rest.length === 0) throw usage('Nothing to pass to marionette.', 'e.g. fg marionette -- scroll-to --text Milch');
      return { client: name, output: (await m.call(args.rest, 120_000)).trim() };
    },
  },
];
