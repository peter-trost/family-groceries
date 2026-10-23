/** fg: drive the real Family Groceries app and its backend, and prove behavior. Entry point. */

import { type Args, type Command, type Ctx, EXIT_USAGE, FgError, type RunOptions, type Shell, type SpawnOptions, usage } from './core.ts';
import { loadInstance, readState, writeState } from './instance.ts';
import { lifecycleCommands } from './lifecycle.ts';
import { driveCommands } from './drive.ts';
import { evidenceCommands } from './evidence.ts';
import { backendCommands } from './backend.ts';

export const COMMANDS: Command[] = [...lifecycleCommands, ...driveCommands, ...evidenceCommands, ...backendCommands];

const GROUPS: [string, string[]][] = [
  ['Lifecycle', ['setup', 'up', 'restart', 'down', 'doctor', 'env', 'seed']],
  ['Drive the app (Marionette)', ['login', 'logout', 'find', 'tap', 'type', 'press', 'back', 'swipe', 'wait', 'marionette']],
  ['Evidence', ['screenshot', 'record start', 'record stop', 'logs']],
  ['Backend', ['db query', 'fn call', 'peer', 'mail']],
  ['Performance (planned)', ['trace', 'memory']],
];

const GLOBAL_FLAGS = ['help', 'dry-run'];

export function overview(): string {
  const lines = [
    'fg: drive the real Family Groceries app (Flutter debug build + Marionette) and its local Supabase backend.',
    '',
    'Usage: fg <command> [args] [--flags]      Output: one JSON object on stdout; progress on stderr.',
    '       fg help <command>                  Full help with flags and examples (or <command> --help).',
    '',
  ];
  for (const [group, names] of GROUPS) {
    lines.push(`${group}:`);
    for (const name of names) {
      const c = COMMANDS.find((x) => x.name === name)!;
      lines.push(`  ${name.padEnd(14)}${c.summary}${c.destructive ? ' [--dry-run]' : ''}`);
    }
    lines.push('');
  }
  lines.push(
    'Start: fg up --clients peter,lea && fg doctor && fg login peter && fg login lea --client lea',
    'Errors: {"ok":false,"error":{"code","message","hint"}}; exit 1 failed, 64 bad usage. Follow the hint.',
    'Instance: FG_PORT_PREFIX (default 543 -> ports 54321..), FG_PROJECT_ID, FG_SURFACE (linux|android),',
    '          FG_AVD, FG_EMU_PORT, FG_EVIDENCE_DIR (default ~/fg-evidence), FG_STATE_DIR.',
    'Skill: .cursor/skills/verify-family-groceries/SKILL.md; feature recipes in features/.',
  );
  return lines.join('\n');
}

export function commandHelp(c: Command): string {
  const lines = [`fg ${c.name}: ${c.summary}`, '', `Usage: ${c.usage}`, '', c.description, ''];
  const flags = [...(c.flags ?? [])];
  if (c.destructive) flags.push({ name: 'dry-run', type: 'boolean', help: 'Print the actions this would take, change nothing.' });
  if (flags.length) {
    lines.push('Flags:');
    for (const f of flags) {
      const arg = f.type === 'boolean' ? '' : f.choices ? ` <${f.choices.join('|')}>` : ' <value>';
      lines.push(`  --${f.name}${arg}`.padEnd(34) + f.help);
    }
    lines.push('');
  }
  lines.push('Examples:', ...c.examples.map((e) => `  ${e}`));
  if (c.planned) lines.push('', 'Status: planned (fails with code not_implemented).');
  return lines.join('\n');
}

const BOOLEAN = (c: Command, name: string) => GLOBAL_FLAGS.includes(name) || c.flags?.some((f) => f.name === name && f.type === 'boolean');

/** Splits argv into the command (one or two words) and its args; validates flags against the command's spec. */
export function parse(argv: string[]): { command: Command | null; args: Args; help: boolean } {
  const dash = argv.indexOf('--');
  const head = dash < 0 ? argv : argv.slice(0, dash);
  const rest = dash < 0 ? [] : argv.slice(dash + 1);
  const words = head.filter((a) => !a.startsWith('--'));
  if (head.length === 0 || words[0] === 'help' || (words.length === 0 && head.includes('--help'))) {
    const target = words[0] === 'help' ? words.slice(1).join(' ') : '';
    const c = target ? find(target) : null;
    if (target && !c) throw unknown(target);
    return { command: c, args: { positional: [], flags: {}, rest: [] }, help: true };
  }
  const two = words.slice(0, 2).join(' ');
  const command = COMMANDS.find((c) => c.name === two) ?? COMMANDS.find((c) => c.name === words[0]);
  if (!command) throw unknown(words.slice(0, 2).join(' '));
  const nameWords = command.name.split(' ').length;
  const args: Args = { positional: [], flags: {}, rest };
  let consumed = 0;
  for (let i = 0; i < head.length; i++) {
    const a = head[i];
    if (!a.startsWith('--')) {
      if (consumed < nameWords) consumed++;
      else args.positional.push(a);
      continue;
    }
    const [rawName, inline] = a.slice(2).split(/=(.*)/s, 2);
    const known = GLOBAL_FLAGS.includes(rawName) || command.flags?.some((f) => f.name === rawName);
    if (!known) {
      throw usage(
        `fg ${command.name} has no flag --${rawName}.`,
        `Flags: ${
          [...(command.flags ?? []).map((f) => `--${f.name}`), ...(command.destructive ? ['--dry-run'] : [])].join(' ') || 'none'
        }. See \`fg help ${command.name}\`.`,
      );
    }
    if (rawName === 'dry-run' && !command.destructive) {
      throw usage(`fg ${command.name} changes nothing, so it has no --dry-run.`, `Run it directly.`);
    }
    if (BOOLEAN(command, rawName)) {
      args.flags[rawName] = inline === undefined ? true : inline !== 'false';
      continue;
    }
    const value = inline ?? head[++i];
    if (value === undefined) throw usage(`--${rawName} needs a value.`, `See \`fg help ${command.name}\`.`);
    const spec = command.flags?.find((f) => f.name === rawName);
    if (spec?.choices && !spec.choices.includes(value)) {
      throw usage(`--${rawName} must be one of ${spec.choices.join(', ')}; got "${value}".`, `e.g. --${rawName} ${spec.choices[0]}`);
    }
    args.flags[rawName] = value;
  }
  return { command, args, help: Boolean(args.flags.help) };
}

function find(name: string): Command | null {
  return COMMANDS.find((c) => c.name === name) ?? null;
}

function unknown(name: string): FgError {
  const close = COMMANDS.filter((c) => c.name.startsWith(name.split(' ')[0]) || name.startsWith(c.name.split(' ')[0])).map((c) => c.name);
  return usage(
    `Unknown command "${name}".`,
    close.length ? `Did you mean: ${close.join(', ')}? Run \`fg help\` for all commands.` : 'Run `fg help` for all commands.',
  );
}

export const realShell: Shell = {
  async run(cmd: string[], opts: RunOptions = {}) {
    try {
      const child = new Deno.Command(cmd[0], {
        args: cmd.slice(1),
        cwd: opts.cwd,
        env: opts.env,
        stdin: opts.stdin === undefined ? 'null' : 'piped',
        stdout: 'piped',
        stderr: 'piped',
        signal: opts.timeoutMs ? AbortSignal.timeout(opts.timeoutMs) : undefined,
      }).spawn();
      if (opts.stdin !== undefined) {
        const w = child.stdin.getWriter();
        await w.write(new TextEncoder().encode(opts.stdin));
        await w.close();
      }
      const out = await child.output();
      const dec = new TextDecoder();
      return { code: out.code, stdout: dec.decode(out.stdout), stderr: dec.decode(out.stderr) };
    } catch (e) {
      if (e instanceof Deno.errors.NotFound) {
        throw new FgError('missing_tool', `\`${cmd[0]}\` is not installed or not on PATH.`, 'Run `fg setup` (see --dry-run first).');
      }
      throw e;
    }
  },
  async spawn(cmd: string[], opts: SpawnOptions) {
    // setsid detaches the process from the CLI's session; it outlives this command.
    const child = new Deno.Command('setsid', {
      args: ['sh', '-c', 'exec "$@" >>"$FG_LOG" 2>&1 </dev/null', 'sh', ...cmd],
      cwd: opts.cwd,
      env: { ...opts.env, FG_LOG: opts.log },
      stdin: 'null',
      stdout: 'null',
      stderr: 'null',
    }).spawn();
    child.unref();
    return await Promise.resolve(child.pid);
  },
  async alive(pid: number, marker: string) {
    try {
      const cmdline = await Deno.readTextFile(`/proc/${pid}/cmdline`);
      const stat = await Deno.readTextFile(`/proc/${pid}/stat`);
      return cmdline.includes(marker) && !/\) Z /.test(stat);
    } catch {
      return false;
    }
  },
  kill(pid: number, signal: Deno.Signal) {
    try {
      Deno.kill(pid, signal);
    } catch { /* already gone */ }
    return Promise.resolve();
  },
  async exists(path: string) {
    try {
      await Deno.stat(path);
      return true;
    } catch {
      return false;
    }
  },
  readText: (path) => Deno.readTextFile(path),
  writeText: (path, text) => Deno.writeTextFile(path, text),
  mkdir: (path) => Deno.mkdir(path, { recursive: true }),
  remove: (path) => Deno.remove(path, { recursive: true }).catch(() => {}),
  fetch: (url, init) => fetch(url, init),
  sleep: (ms) => new Promise((r) => setTimeout(r, ms)),
};

export interface Io {
  out(text: string): void;
  err(text: string): void;
}

/** Runs one invocation; returns the exit code. */
export async function main(argv: string[], sh: Shell, env: Record<string, string | undefined>, repo: string, io: Io): Promise<number> {
  let name = argv.filter((a) => !a.startsWith('--')).slice(0, 2).join(' ') || 'help';
  try {
    const { command, args, help } = parse(argv);
    if (help) {
      io.out(command ? commandHelp(command) : overview());
      return 0;
    }
    name = command!.name;
    const inst = await loadInstance(sh, env, repo);
    const state = await readState(sh, inst);
    const dryRun = Boolean(args.flags['dry-run']);
    const ctx: Ctx = {
      sh,
      dryRun,
      inst,
      state,
      actions: [],
      log: (m) => io.err(`[fg] ${m}`),
      async act(description, step) {
        ctx.actions.push(description);
        if (dryRun) return undefined;
        ctx.log(description);
        return await step();
      },
      save: () => (dryRun ? Promise.resolve() : writeState(sh, inst, state)),
    };
    const result = await command!.run(ctx, args);
    const doc: Record<string, unknown> = { ok: true, command: name, ...(dryRun ? { dryRun: true } : {}), ...result };
    if (ctx.actions.length) doc[dryRun ? 'wouldDo' : 'did'] = ctx.actions;
    io.out(JSON.stringify(doc, null, 2));
    return 0;
  } catch (e) {
    const err = e instanceof FgError ? e : new FgError(
      'internal',
      String(e instanceof Error ? e.stack ?? e.message : e),
      'This is a bug in fg; report it with the command you ran.',
    );
    io.out(
      JSON.stringify(
        { ok: false, command: name, error: { code: err.code, message: err.message, hint: err.hint, ...err.details } },
        null,
        2,
      ),
    );
    return err.exitCode ?? (err.code === 'usage' ? EXIT_USAGE : 1);
  }
}

if (import.meta.main) {
  const repo = new URL('../../../../', import.meta.url).pathname.replace(/\/$/, '');
  const code = await main(Deno.args, realShell, Deno.env.toObject(), repo, {
    out: (t) => console.log(t),
    err: (t) => console.error(t),
  });
  Deno.exit(code);
}
