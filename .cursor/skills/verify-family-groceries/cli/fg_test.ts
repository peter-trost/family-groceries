import { assert, assertEquals, assertMatch, assertStringIncludes } from '@std/assert';
import type { RunOptions, Shell } from './core.ts';
import { COMMANDS, main } from './fg.ts';
import { loadInstance } from './instance.ts';
import { parseElements, rowKeyFor } from './marionette.ts';
import { rewriteConfig } from './stack.ts';

/** In-memory shell: records every call; files live in a map; scripted command output. */
class FakeShell implements Shell {
  calls: string[][] = [];
  stdins: string[] = [];
  spawned: string[][] = [];
  killed: [number, string][] = [];
  writes: string[] = [];
  removed: string[] = [];
  files = new Map<string, string>();
  alivePids = new Set<number>();
  constructor(private reply: (cmd: string[]) => { code: number; stdout: string; stderr?: string } = () => ({ code: 1, stdout: '' })) {}
  run(cmd: string[], opts?: RunOptions) {
    this.calls.push(cmd);
    if (opts?.stdin) this.stdins.push(opts.stdin);
    const r = this.reply(cmd);
    return Promise.resolve({ code: r.code, stdout: r.stdout, stderr: r.stderr ?? '' });
  }
  spawn(cmd: string[]) {
    this.spawned.push(cmd);
    return Promise.resolve(4242);
  }
  alive(pid: number) {
    return Promise.resolve(this.alivePids.has(pid));
  }
  kill(pid: number, signal: Deno.Signal) {
    this.killed.push([pid, signal]);
    this.alivePids.delete(pid);
    return Promise.resolve();
  }
  exists(path: string) {
    return Promise.resolve(this.files.has(path));
  }
  readText(path: string) {
    const text = this.files.get(path);
    return text === undefined ? Promise.reject(new Deno.errors.NotFound(path)) : Promise.resolve(text);
  }
  writeText(path: string, text: string) {
    this.writes.push(path);
    this.files.set(path, text);
    return Promise.resolve();
  }
  mkdir() {
    return Promise.resolve();
  }
  remove(path: string) {
    this.removed.push(path);
    return Promise.resolve();
  }
  fetch(): Promise<Response> {
    return Promise.reject(new TypeError('network disabled in tests'));
  }
  sleep() {
    return Promise.resolve();
  }
}

const ENV = { HOME: '/home/t', FG_PORT_PREFIX: '548', FG_KVM_MARKER: '/none' };
const REPO = '/repo';

async function fg(argv: string[], sh = new FakeShell(), env: Record<string, string> = ENV) {
  let out = '';
  const code = await main(argv, sh, env, REPO, { out: (t) => (out += t), err: () => {} });
  let json: Record<string, unknown> | null = null;
  try {
    json = JSON.parse(out);
  } catch { /* help text */ }
  return { code, out, json, sh };
}

const error = (json: Record<string, unknown> | null) => json?.error as { code: string; message: string; hint: string };

Deno.test('help lists every command, and each command documents usage and examples', async () => {
  const { code, out } = await fg(['help']);
  assertEquals(code, 0);
  for (const c of COMMANDS) {
    assertStringIncludes(out, `  ${c.name}`);
    const help = await fg([...c.name.split(' '), '--help']);
    assertEquals(help.code, 0, c.name);
    assertStringIncludes(help.out, 'Usage: fg ');
    assertStringIncludes(help.out, 'Examples:');
    if (c.destructive) assertStringIncludes(help.out, '--dry-run');
  }
});

Deno.test('an unknown command fails as usage with a suggestion', async () => {
  const { code, json } = await fg(['record', 'begin']);
  assertEquals(code, 64);
  assertEquals(error(json).code, 'usage');
  assertStringIncludes(error(json).hint, 'record start');
});

Deno.test('an unknown flag fails and lists the flags the command has', async () => {
  const { code, json } = await fg(['tap', '--selector', 'x']);
  assertEquals(code, 64);
  assertStringIncludes(error(json).hint, '--key');
});

Deno.test('--dry-run is refused on read-only commands and choices are checked', async () => {
  assertEquals((await fg(['doctor', '--dry-run'])).code, 64);
  const bad = await fg(['up', '--surface', 'ios']);
  assertEquals(bad.code, 64);
  assertStringIncludes(error(bad.json).message, 'linux, android');
});

Deno.test('driving without a running app says to run fg up', async () => {
  const { code, json } = await fg(['tap', '--text', 'Milch']);
  assertEquals(code, 1);
  assertEquals(error(json).code, 'no_client');
  assertStringIncludes(error(json).hint, 'fg up');
});

Deno.test('up --dry-run changes nothing and lists what it would do', async () => {
  const sh = new FakeShell();
  sh.files.set(`${REPO}/supabase/config.toml`, 'project_id = "family-groceries"\nport = 54321\n');
  const { code, json } = await fg(['up', '--clients', 'peter,lea', '--dry-run'], sh);
  assertEquals(code, 0);
  assertEquals(json?.dryRun, true);
  const plan = (json?.wouldDo as string[]).join('\n');
  assertStringIncludes(plan, 'supabase start');
  assertStringIncludes(plan, 'db reset');
  assertStringIncludes(plan, 'as lea');
  assertEquals(sh.spawned, []);
  assertEquals(sh.writes, []);
  assertEquals(sh.removed, []);
  const mutating = sh.calls.filter((c) => ['start', 'reset', 'stop', 'build', 'install'].some((w) => c.includes(w)));
  assertEquals(mutating, []);
});

Deno.test('down --dry-run kills nothing, and down keeps the evidence directory', async () => {
  const sh = new FakeShell();
  const state = {
    run: 'run-x',
    clients: {
      peter: {
        surface: 'linux',
        pid: 11,
        marker: 'family_groceries',
        vmUri: 'ws://x',
        log: '/l',
        fingerprint: 'f',
        display: 5481,
        xvfbPid: 12,
      },
    },
    recordings: {},
    builds: {},
  };
  sh.files.set('/home/t/.cache/fg/548/state.json', JSON.stringify(state));
  sh.alivePids = new Set([11, 12]);
  const dry = await fg(['down', '--dry-run'], sh);
  assertEquals(dry.code, 0);
  assertEquals(sh.killed, []);
  assertStringIncludes((dry.json?.wouldDo as string[]).join('\n'), 'Xvfb :5481');

  const real = await fg(['down'], sh);
  assertEquals(real.code, 0);
  assertEquals(sh.killed.map(([pid]) => pid).sort(), [11, 12]);
  assert(!sh.removed.some((p) => p.includes('evidence')), 'evidence is never removed');
  assertEquals(real.json?.evidenceDir, '/home/t/fg-evidence/run-x');
});

Deno.test('db query runs read-only unless --write, and --as applies the user through RLS', async () => {
  const sh = new FakeShell((cmd) => {
    if (cmd[0] === 'docker') return { code: 0, stdout: '[{"id":"u1"}]\n' };
    return { code: 1, stdout: '' };
  });
  const read = await fg(['db', 'query', 'select 1 as x'], sh);
  assertEquals(read.code, 0);
  assertStringIncludes(sh.stdins.at(-1)!, 'default_transaction_read_only = on');

  await fg(['db', 'query', "update items set name = 'x'", '--write'], sh);
  assert(!sh.stdins.at(-1)!.includes('read_only'), '--write lifts read-only');

  await fg(['db', 'query', 'select count(*) from items', '--as', 'lea'], sh);
  assertStringIncludes(sh.stdins.at(-1)!, 'set local role authenticated');
  assertStringIncludes(sh.stdins.at(-1)!, '"sub":"u1"');
});

Deno.test('a write in a read-only session fails with a hint to use --write', async () => {
  const sh = new FakeShell(() => ({ code: 1, stdout: '', stderr: 'ERROR:  cannot execute UPDATE in a read-only transaction' }));
  const { code, json } = await fg(['db', 'query', "update items set name = 'x'"], sh);
  assertEquals(code, 1);
  assertEquals(error(json).code, 'read_only');
  assertStringIncludes(error(json).hint, '--write');
});

Deno.test('planned perf commands fail with not_implemented and an alternative', async () => {
  const { code, json } = await fg(['trace', 'start']);
  assertEquals(code, 1);
  assertEquals(error(json).code, 'not_implemented');
  assertMatch(error(json).hint, /DevTools/);
});

Deno.test('record stop signals only the Dart recorder, never ffmpeg or the sh wrapper', async () => {
  const group = '  100   100 sh /h/.pub-cache/bin/marionette --uri ws://x record-video --output /e/a.webm\n' +
    '  101   100 /sdk/dartvm --resolved_executable_name=dart /snap marionette.snapshot --uri ws://x record-video --output /e/a.webm\n' +
    '  102   100 ffmpeg -f rawvideo -i pipe:0 /e/a.webm\n';
  let stopped = false;
  const sh = new FakeShell((cmd) => {
    if (cmd[0] === 'ps') return { code: 0, stdout: stopped ? '' : group };
    if (cmd[0] === 'ffprobe') return { code: 0, stdout: '6.4\n' };
    return { code: 1, stdout: '' };
  });
  const origKill = sh.kill.bind(sh);
  sh.kill = (pid, signal) => {
    stopped = true;
    return origKill(pid, signal);
  };
  sh.files.set('/e/a.webm', 'video');
  sh.files.set(
    '/home/t/.cache/fg/548/state.json',
    JSON.stringify({
      run: 'r',
      clients: {},
      builds: {},
      recordings: { a: { pid: 100, marker: 'marionette', path: '/e/a.webm', kind: 'marionette', client: 'peter', startedAt: '' } },
    }),
  );
  const { code, json } = await fg(['record', 'stop'], sh);
  assertEquals(code, 0, JSON.stringify(json));
  assertEquals(sh.killed, [[101, 'SIGINT']]);
  assertEquals((json?.stopped as { durationSec: number }[])[0].durationSec, 6.4);
});

Deno.test('instance settings derive from FG_PORT_PREFIX; a KVM marker makes linux the default', async () => {
  const sh = new FakeShell();
  sh.files.set('/m', 'kernel BUG in kvm');
  const inst = await loadInstance(sh, { HOME: '/h', FG_PORT_PREFIX: '548', FG_KVM_MARKER: '/m' }, '/r');
  assertEquals(inst.apiUrl, 'http://127.0.0.1:54821');
  assertEquals(inst.dbContainer, 'supabase_db_family-groceries-548');
  assertEquals(inst.serial, 'emulator-5564');
  assertEquals(inst.defaultSurface, 'linux');
  const plain = await loadInstance(sh, { HOME: '/h', FG_KVM_MARKER: '/none' }, '/r');
  assertEquals(plain.projectId, 'family-groceries');
  assertEquals(plain.defaultSurface, 'android');
});

Deno.test('config rewrite moves every 543xx port line and the project id, and leaves URLs alone', () => {
  const toml =
    'project_id = "family-groceries"\nport = 54321\nshadow_port = 54320\nsite_url = "http://127.0.0.1:3000"\nurl = "http://host.docker.internal:54399/realms/test"\n';
  assertEquals(
    rewriteConfig(toml, '548', 'family-groceries-05'),
    'project_id = "family-groceries-05"\nport = 54821\nshadow_port = 54820\nsite_url = "http://127.0.0.1:3000"\nurl = "http://host.docker.internal:54399/realms/test"\n',
  );
});

// Captured from `marionette get-interactive-elements` on the list screen (abridged).
const LIST_SCREEN = `Found 9 interactive element(s):

Type: TextField, autofocus: "true", maxLength: "120", label: "Was fehlt?", Key: "add-item-field", bounds: {"x":16,"y":64,"width":380,"height":48}
Type: Text, Text: "Obst & Gemüse", bounds: {"x":16,"y":136,"width":380,"height":20}
Type: _ItemTile, Key: "addb2484", bounds: {"x":0,"y":160,"width":412,"height":48}
Type: Dismissible, Key: "dismiss-addb2484", bounds: {"x":0,"y":160,"width":412,"height":48}
Type: Checkbox, bounds: {"x":16,"y":164,"width":40,"height":40}
Type: Text, Text: "Äpfel", bounds: {"x":68,"y":172,"width":300,"height":24}
Type: Text, Text: "Brot, hell", bounds: {"x":68,"y":260,"width":300,"height":24}
Type: IconButton, tooltip: "Menü", bounds: {"x":372,"y":8,"width":40,"height":40}
Type: FilledButton, enabled: "true", bounds: {"x":454,"y":364,"width":372,"height":32}
`;

Deno.test('element parsing keeps keys, labels, tooltips, bounds and text with commas', () => {
  const els = parseElements(LIST_SCREEN);
  assertEquals(els.length, 9);
  assertEquals(els[0], { type: 'TextField', key: 'add-item-field', label: 'Was fehlt?', bounds: { x: 16, y: 64, width: 380, height: 48 } });
  assertEquals(els[6].text, 'Brot, hell');
  assertEquals(els[7].tooltip, 'Menü');
  assertEquals(els[8].enabled, true);
});

Deno.test('a row is the smallest keyed element around the text', () => {
  const els = parseElements(LIST_SCREEN);
  assertEquals(rowKeyFor(els, 'Äpfel'), 'addb2484');
});

Deno.test('Marionette failures surface the app-side exception, and lost focus gets its own code', async () => {
  const { firstLine } = await import('./marionette.ts');
  const output =
    'Error: Extension marionette.tap failed\nError: {"exception":"Exception: Element matching {text: Brot} not found","stack":"#0"}';
  assertEquals(firstLine(output), 'Element matching {text: Brot} not found');
  const state = {
    run: 'r',
    clients: { peter: { surface: 'linux', pid: 1, marker: 'f', vmUri: 'ws://x', log: '/l', fingerprint: 'f' } },
    recordings: {},
    builds: {},
  };
  const sh = new FakeShell((cmd) =>
    cmd.includes('enter-text')
      ? {
        code: 1,
        stdout: '',
        stderr: 'Error: Extension marionette.enterText failed\nError: {"exception":"Exception: No element is currently focused"}',
      }
      : { code: 0, stdout: '' }
  );
  sh.files.set('/home/t/.cache/fg/548/state.json', JSON.stringify(state));
  const { code, json } = await fg(['type', '--input', 'Milch'], sh);
  assertEquals(code, 1);
  assertEquals(error(json).code, 'no_focus');
  assertStringIncludes(error(json).hint, '--key add-item-field');
});

Deno.test('up restarts a running stack whose config or functions changed since it started', async () => {
  const status = JSON.stringify({ API_URL: 'http://127.0.0.1:54821', PUBLISHABLE_KEY: 'pk', SECRET_KEY: 'sk' });
  const sh = new FakeShell((cmd) => (cmd[0] === 'supabase' && cmd[1] === 'status' ? { code: 0, stdout: status } : { code: 0, stdout: '' }));
  sh.files.set(`${REPO}/supabase/config.toml`, 'project_id = "family-groceries"\nport = 54321\n');
  sh.files.set('/home/t/.cache/fg/548/state.json', JSON.stringify({ run: 'r', clients: {}, recordings: {}, builds: {}, stack: 'stale' }));
  const { code, json } = await fg(['up', '--only', 'stack', '--dry-run'], sh);
  assertEquals(code, 0, JSON.stringify(json));
  const plan = (json?.wouldDo as string[]).join('\n');
  assertStringIncludes(plan, 'config.toml or the function set changed');
  assertStringIncludes(plan, 'supabase start');
});
