/** Bring-up, teardown, health: setup, up, down, doctor, env, seed. */

import { type Command, type Ctx, FgError, type JsonObject, str, usage } from './core.ts';
import {
  ANDROID_ABI,
  type ClientName,
  clientName,
  type ClientState,
  HOUSEHOLD,
  newRunId,
  runDir,
  type SurfaceKind,
  USERS,
} from './instance.ts';
import { Marionette, screenOf } from './marionette.ts';
import { stopRecording } from './evidence.ts';
import {
  functionNames,
  householdOf,
  mustRun,
  seed,
  signIn,
  sqlRows,
  type StackEnv,
  stackEnv,
  stackSignature,
  writeWorkdir,
} from './stack.ts';
import {
  build,
  clientAlive,
  defines,
  ensureEmulator,
  fingerprint,
  restartClient,
  startAndroid,
  startLinux,
  stopClient,
  waitFor,
  waitForMarionette,
} from './surfaces.ts';

const surfaceFlag = {
  name: 'surface',
  help: 'linux (Xvfb desktop app) or android (emulator). Default: $FG_SURFACE, else android unless KVM is marked broken.',
  choices: ['linux', 'android'],
};

function surfaceOf(ctx: Ctx, raw: string | undefined): SurfaceKind {
  return (raw as SurfaceKind | undefined) ?? ctx.inst.defaultSurface;
}

async function stackRunning(ctx: Ctx): Promise<StackEnv | null> {
  return await stackEnv(ctx.sh, ctx.inst).catch(() => null);
}

async function usersReady(ctx: Ctx, env: StackEnv): Promise<boolean> {
  try {
    await signIn(ctx.sh, env, 'peter');
    await signIn(ctx.sh, env, 'lea');
    const [a, b] = [await householdOf(ctx.sh, ctx.inst, 'peter'), await householdOf(ctx.sh, ctx.inst, 'lea')];
    return a !== null && a === b;
  } catch {
    return false;
  }
}

/** Surface per client: the emulator hosts one app, so on android lea runs on linux. */
const surfaceFor = (primary: SurfaceKind, name: ClientName): SurfaceKind => (name === 'peter' ? primary : 'linux');

function parseClients(raw: string | undefined): ClientName[] {
  const names = (raw ?? 'peter').split(',').map((s) => s.trim()).filter(Boolean);
  for (const n of names) {
    if (n !== 'peter' && n !== 'lea') throw usage(`Unknown client "${n}".`, 'Use --clients peter or --clients peter,lea.');
  }
  return names as ClientName[];
}

type Check = { name: string; ok: boolean; detail: string; fix?: string };

async function httpOk(ctx: Ctx, url: string, headers: Record<string, string> = {}): Promise<{ ok: boolean; detail: string }> {
  try {
    const res = await ctx.sh.fetch(url, { headers, signal: AbortSignal.timeout(10_000) });
    const text = (await res.text()).slice(0, 120);
    return { ok: res.ok, detail: `${res.status} ${text}` };
  } catch (e) {
    return { ok: false, detail: String(e).slice(0, 200) };
  }
}

async function doctorChecks(ctx: Ctx): Promise<Check[]> {
  const { sh, inst, state } = ctx;
  const checks: Check[] = [];
  const add = (name: string, ok: boolean, detail: string, fix?: string) => checks.push({ name, ok, detail, ...(ok ? {} : { fix }) });

  const docker = await sh.run(['docker', 'info', '--format', '{{.ServerVersion}}']);
  add(
    'docker',
    docker.code === 0,
    docker.code === 0 ? `server ${docker.stdout.trim()}` : docker.stderr.trim().slice(0, 200),
    'Start dockerd: `sudo dockerd >/tmp/dockerd.log 2>&1 &` then `sudo chmod 666 /var/run/docker.sock`.',
  );

  const env = await stackRunning(ctx);
  add('stack', env !== null, env ? `${inst.projectId} at ${env.apiUrl}` : `${inst.projectId} is not running`, 'Run `fg up --only stack`.');
  if (env) {
    const key = { apikey: env.publishableKey };
    const auth = await httpOk(ctx, `${env.apiUrl}/auth/v1/health`, key);
    add('auth', auth.ok, auth.detail, '`fg logs --service auth`');
    const rest = await httpOk(ctx, `${env.apiUrl}/rest/v1/`, key);
    add('rest', rest.ok, rest.detail, '`fg logs --service rest`');
    const rt = await sh.run(['docker', 'inspect', '-f', '{{.State.Health.Status}}', `supabase_realtime_${inst.projectId}`]);
    add(
      'realtime',
      rt.stdout.trim() === 'healthy',
      `container ${rt.stdout.trim() || 'missing'}`,
      '`fg logs --service realtime`; then `fg down && fg up`.',
    );
    const fn = await httpOk(ctx, `${env.apiUrl}/functions/v1/health`, key);
    add('functions', fn.ok, fn.detail, '`fg logs --service edge_runtime`');
    const unserved: string[] = [];
    for (const name of await functionNames(sh, inst)) {
      const res = await sh.fetch(`${env.apiUrl}/functions/v1/${name}`, { headers: key, signal: AbortSignal.timeout(15_000) }).catch(() =>
        null
      );
      const text = res ? await res.text() : '';
      if (res?.status === 404 && text.includes('Function not found')) unserved.push(name);
    }
    add(
      'functions.served',
      unserved.length === 0,
      unserved.length
        ? `not served: ${unserved.join(', ')} (the stack started before they existed)`
        : 'every function in the checkout answers',
      'Run `fg up` (it restarts a stack whose config or functions changed).',
    );
    if (state.stack) {
      const current = await stackSignature(sh, inst);
      add(
        'stack.config',
        current === state.stack,
        current === state.stack
          ? 'started with the current config.toml and functions'
          : 'config.toml or the function set changed since the stack started',
        'Run `fg up` (restarts the stack).',
      );
    }
    const mail = await httpOk(ctx, `${inst.mailUrl}/api/v1/messages?limit=1`);
    add('mailpit', mail.ok, mail.ok ? inst.mailUrl : mail.detail, '`fg logs --service inbucket`');

    const files = (await sh.run(['ls', `${inst.repo}/supabase/migrations`])).stdout.split('\n').filter((f) => f.endsWith('.sql')).map((f) =>
      f.split('_')[0]
    );
    const applied = await sqlRows(sh, inst, 'select version from supabase_migrations.schema_migrations').then(
      (r) => r.map((x) => String(x.version)),
      () => [] as string[],
    );
    const missing = files.filter((v) => !applied.includes(v));
    add(
      'migrations',
      missing.length === 0,
      missing.length ? `not applied: ${missing.join(', ')}` : `${applied.length} applied`,
      "Run `fg seed` (resets the database to the checkout's migrations).",
    );

    const ready = await usersReady(ctx, env);
    add(
      'users',
      ready,
      ready
        ? `${USERS.peter.email} and ${USERS.lea.email} sign in, one household`
        : 'test users missing, cannot sign in, or not in one household',
      'Run `fg seed`.',
    );
  }

  if (inst.kvmBroken) add('surface', true, `linux only on this box (${inst.kvmBroken.slice(0, 120)})`);
  for (const [name, client] of Object.entries(state.clients) as [ClientName, ClientState][]) {
    const alive = await clientAlive(sh, inst, client);
    add(
      `${name}.process`,
      alive,
      alive ? `${client.surface} app pid ${client.pid}${client.display ? ` on :${client.display}` : ''}` : 'not running',
      'Run `fg up` to relaunch it.',
    );
    if (client.surface === 'android') {
      const boot = await sh.run(['adb', '-s', inst.serial, 'shell', 'getprop', 'sys.boot_completed']);
      add(
        'emulator',
        boot.stdout.trim() === '1',
        boot.stdout.trim() === '1' ? `${inst.serial} booted` : `${inst.serial} not booted or not connected`,
        'Run `fg up`.',
      );
    }
    if (env) {
      const current = await fingerprint(sh, inst, client.surface, defines(inst, env, client.surface));
      add(
        `${name}.build`,
        current === client.fingerprint,
        current === client.fingerprint ? `current (${current})` : `running ${client.fingerprint}, checkout is ${current}`,
        'Run `fg up` (rebuilds and relaunches changed clients).',
      );
    }
    if (alive) {
      const elements = await new Marionette(sh, client.vmUri).elements().then((e) => e, (e: FgError) => e);
      const ok = Array.isArray(elements);
      const screen = ok ? screenOf(elements) : '';
      add(
        `${name}.marionette`,
        ok,
        ok ? `connected, ${elements.length} elements, screen ${screen}` : (elements as FgError).message,
        'Run `fg up --rebuild`.',
      );
    }
  }
  if (Object.keys(state.clients).length === 0) add('clients', false, 'no app is running', 'Run `fg up` (add --clients peter,lea for two).');
  return checks;
}

export const lifecycleCommands: Command[] = [
  {
    name: 'setup',
    summary: 'One-time machine setup: packages, Marionette CLI, KVM access, emulator image and AVD.',
    usage: 'fg setup [--surface linux|android] [--dry-run]',
    description:
      'Idempotent; installs only what is missing (apt via sudo, `dart pub global activate marionette_cli`, sdkmanager, avdmanager). Run with --dry-run first to see the plan. On this box /etc and /dev are reset by restarts, so rerun it after a reboot.',
    flags: [surfaceFlag],
    examples: ['fg setup --dry-run', 'fg setup', 'fg setup --surface android'],
    destructive: true,
    async run(ctx, args) {
      const surface = surfaceOf(ctx, str(args, 'surface'));
      const has = async (bin: string) => (await ctx.sh.run(['sh', '-c', `command -v ${bin}`])).code === 0;
      const apt: string[] = [];
      for (
        const [bin, pkg] of [['Xvfb', 'xvfb'], ['ffmpeg', 'ffmpeg'], ['clang++', 'clang'], ['cmake', 'cmake'], ['ninja', 'ninja-build'], [
          'pkg-config',
          'pkg-config',
        ]]
      ) {
        if (!(await has(bin))) apt.push(pkg);
      }
      if ((await ctx.sh.run(['pkg-config', '--exists', 'gtk+-3.0'])).code !== 0) {
        apt.push('libgtk-3-dev', 'liblzma-dev', 'libstdc++-14-dev');
      }
      if (surface === 'android' && !(await has('java'))) apt.push('openjdk-21-jdk-headless');
      if (apt.length) {
        await ctx.act(
          `sudo apt-get install -y ${apt.join(' ')}`,
          () => mustRun(ctx.sh, ['sudo', 'apt-get', 'install', '-y', '-qq', ...apt], { timeoutMs: 900_000 }),
        );
      }
      if (!(await has('marionette'))) {
        await ctx.act(
          'dart pub global activate marionette_cli',
          () => mustRun(ctx.sh, ['dart', 'pub', 'global', 'activate', 'marionette_cli'], { timeoutMs: 300_000 }),
        );
      }
      if (!/enable-linux-desktop: true/.test((await ctx.sh.run(['flutter', 'config', '--list'])).stdout)) {
        await ctx.act('flutter config --enable-linux-desktop', () => mustRun(ctx.sh, ['flutter', 'config', '--enable-linux-desktop']));
      }
      if (surface === 'android') {
        if (ctx.inst.kvmBroken) {
          throw new FgError('kvm_broken', `Refusing Android setup: ${ctx.inst.kvmBroken}`, 'Use the linux surface on this box.');
        }
        const gid = (await ctx.sh.run(['stat', '-c', '%g', '/dev/kvm'])).stdout.trim();
        if ((await ctx.sh.run(['test', '-r', '/dev/kvm', '-a', '-w', '/dev/kvm'])).code !== 0) {
          await ctx.act(`create group kvm (gid ${gid}), add $USER, chmod o+rw /dev/kvm`, async () => {
            await mustRun(ctx.sh, ['sudo', 'groupadd', '-f', '-g', gid, 'kvm']);
            await mustRun(ctx.sh, ['sh', '-c', 'sudo usermod -aG kvm "$USER"']);
            await mustRun(ctx.sh, ['sudo', 'chmod', 'o+rw', '/dev/kvm']);
          });
        }
        const image = `system-images;android-35;google_apis;${ANDROID_ABI.image}`;
        if (
          !(await has('emulator')) ||
          !(await ctx.sh.exists(
            `${
              Deno.env.get('ANDROID_HOME') ?? `${Deno.env.get('HOME')}/android-sdk`
            }/system-images/android-35/google_apis/${ANDROID_ABI.image}`,
          ))
        ) {
          await ctx.act(
            `sdkmanager emulator "${image}"`,
            () => mustRun(ctx.sh, ['sdkmanager', 'emulator', image], { timeoutMs: 1_800_000 }),
          );
        }
        if (!(await ctx.sh.run(['emulator', '-list-avds'])).stdout.split('\n').includes(ctx.inst.avd)) {
          await ctx.act(
            `avdmanager create avd -n ${ctx.inst.avd} (pixel_6, 2 GB RAM)`,
            () => mustRun(ctx.sh, ['sh', '-c', `echo no | avdmanager create avd -n "$0" -k "$1" -d pixel_6`, ctx.inst.avd, image]),
          );
        }
      }
      return { surface, upToDate: ctx.actions.length === 0 };
    },
  },
  {
    name: 'up',
    summary: 'Bring the instance to a usable state: stack, seed, build, app clients, Marionette.',
    usage: 'fg up [--clients peter|peter,lea] [--surface linux|android] [--only stack] [--rebuild] [--fresh] [--run NAME] [--dry-run]',
    description:
      "Idempotent: reuses what already runs and is current. Starts this instance's Supabase stack (ports from FG_PORT_PREFIX), seeds peter@fg.test and lea@fg.test in one household when they are missing (--fresh always reseeds), builds the debug app from test_driver/main_marionette.dart when the source changed, launches each client and waits until Marionette answers. A new evidence run directory starts when no client was running (or with --run). Ready = this command exits 0; its JSON names every URL and path.",
    flags: [
      { name: 'clients', help: 'Apps to run: peter (default) or peter,lea. Each logs in as itself with `fg login`.' },
      surfaceFlag,
      { name: 'only', help: 'stack: start Supabase (and seed) only.', choices: ['stack'] },
      { name: 'rebuild', type: 'boolean', help: 'Rebuild and relaunch the app even if nothing changed.' },
      { name: 'fresh', type: 'boolean', help: 'Reset the database and reseed (signs every client out).' },
      { name: 'run', help: 'Evidence run name (default run-<date>-<time>).' },
    ],
    examples: ['fg up', 'fg up --clients peter,lea', 'fg up --only stack', 'fg up --fresh --dry-run'],
    destructive: true,
    async run(ctx, args) {
      const { inst, state } = ctx;
      const surface = surfaceOf(ctx, str(args, 'surface'));
      const names = parseClients(str(args, 'clients'));
      await writeWorkdir(ctx, inst);
      let env = await stackRunning(ctx);
      const signature = await stackSignature(ctx.sh, inst);
      if (env && state.stack && state.stack !== signature) {
        await ctx.act(
          `restart ${inst.projectId}: config.toml or the function set changed since it started`,
          () => mustRun(ctx.sh, ['supabase', 'stop', '--workdir', inst.workdir, '--no-backup'], { timeoutMs: 300_000 }),
        );
        env = null;
      }
      if (!env) {
        await ctx.act(
          `supabase start --workdir ${inst.workdir} (${inst.projectId}, ports ${inst.prefix}xx)`,
          () => mustRun(ctx.sh, ['supabase', 'start', '--workdir', inst.workdir], { timeoutMs: 900_000 }),
        );
        if (!ctx.dryRun) env = await stackEnv(ctx.sh, inst);
        state.stack = signature;
      }
      let seeded: JsonObject | null = null;
      if (args.flags.fresh || !env || !(await usersReady(ctx, env))) {
        seeded = await seed(ctx, inst);
        state.seededAt = new Date().toISOString();
      }
      if (!ctx.dryRun) {
        // A reset restarts the containers; realtime answers last.
        await waitFor(
          ctx.sh,
          async () =>
            (await ctx.sh.run(['docker', 'inspect', '-f', '{{.State.Health.Status}}', `supabase_realtime_${inst.projectId}`])).stdout
              .trim() === 'healthy',
          180_000,
          () =>
            new FgError(
              'realtime_unhealthy',
              'Realtime did not become healthy within 3 minutes.',
              'Run `fg logs --service realtime`, then `fg down && fg up`.',
            ),
        );
      }
      if (!ctx.dryRun) env = await stackEnv(ctx.sh, inst);
      const anyAlive = (await Promise.all(Object.values(state.clients).map((c) => clientAlive(ctx.sh, inst, c!)))).some(Boolean);
      const run = str(args, 'run');
      if (run || !anyAlive) state.run = run ?? newRunId();
      const clients: JsonObject = {};
      if (str(args, 'only') !== 'stack') {
        if (!env) {
          for (const name of names) ctx.actions.push(`build and launch the ${surfaceFor(surface, name)} app as ${name}`);
        } else {
          for (const name of names) {
            const kind = surfaceFor(surface, name);
            const fp = await build(ctx, inst, state, kind, env, Boolean(args.flags.rebuild));
            const existing = state.clients[name];
            if (
              // An app started before the last seed holds a session for a deleted user, so it restarts signed out.
              existing && existing.surface === kind && existing.fingerprint === fp && !args.flags.rebuild &&
              (existing.startedAt ?? '') > (state.seededAt ?? '') &&
              (await clientAlive(ctx.sh, inst, existing))
            ) {
              clients[name] = { surface: kind, reused: true, vmUri: existing.vmUri };
              continue;
            }
            if (existing) {
              await stopClient(ctx, inst, name, existing);
              delete state.clients[name];
            }
            if (kind === 'android') await ensureEmulator(ctx, inst, state);
            const started = kind === 'android' ? await startAndroid(ctx, inst, fp) : await startLinux(ctx, inst, name, fp);
            if (started) {
              state.clients[name] = started;
              await ctx.save();
              await waitForMarionette(ctx.sh, started.vmUri);
              clients[name] = {
                surface: kind,
                reused: false,
                vmUri: started.vmUri,
                pid: started.pid,
                ...(started.display ? { display: started.display } : {}),
              };
            }
          }
        }
      }
      await ctx.save();
      return {
        surface,
        run: state.run,
        evidenceDir: runDir(inst, state),
        stack: { projectId: inst.projectId, apiUrl: env?.apiUrl ?? inst.apiUrl, mailUrl: inst.mailUrl, dbPort: inst.dbPort },
        household: HOUSEHOLD,
        users: Object.fromEntries(Object.entries(USERS).map(([k, u]) => [k, { email: u.email, password: u.password }])),
        seeded: seeded !== null,
        clients,
        next: names.map((n) => `fg login ${n}${n === 'peter' ? '' : ` --client ${n}`}`).join(' && '),
      };
    },
  },
  {
    name: 'restart',
    summary: 'Quit and reopen an app client like a user would, keeping its login.',
    usage: 'fg restart [--client peter|lea] [--dry-run]',
    description:
      'Ends the app process and launches the same build again with the same stored session, then waits for Marionette. Use it to prove launch behavior: what shows and what has focus right after opening the app. `fg up --rebuild` instead starts signed out.',
    flags: [{ name: 'client', help: 'peter (default) or lea.', choices: ['peter', 'lea'] }],
    examples: ['fg restart', 'fg restart --client lea'],
    destructive: true,
    async run(ctx, args) {
      const name = clientName(str(args, 'client'));
      const client = ctx.state.clients[name];
      if (!client) throw new FgError('no_client', `No ${name} app is running.`, 'Run `fg up` first.');
      const started = await restartClient(ctx, ctx.inst, name, client);
      if (!started) return { client: name };
      ctx.state.clients[name] = started;
      await ctx.save();
      await waitForMarionette(ctx.sh, started.vmUri);
      return { client: name, pid: started.pid, vmUri: started.vmUri };
    },
  },
  {
    name: 'down',
    summary: 'Tear down what this instance started: recordings, apps, Xvfb, emulator, Supabase. Keeps evidence.',
    usage: 'fg down [--keep-stack] [--dry-run]',
    description:
      "Stops only processes and containers this instance tracks (by pid and its own project id), never by name. Finalizes running recordings first so they are not lost. Removes the clients' scratch session data. The evidence directory is never touched; its path is in the output.",
    flags: [{ name: 'keep-stack', type: 'boolean', help: 'Leave Supabase running (faster next `fg up`).' }],
    examples: ['fg down --dry-run', 'fg down', 'fg down --keep-stack'],
    destructive: true,
    async run(ctx, args) {
      const { inst, state, sh } = ctx;
      const evidence = runDir(inst, state);
      for (const [id, rec] of Object.entries(state.recordings)) {
        await ctx.act(`finalize recording "${id}" (pid ${rec.pid})`, async () => {
          await stopRecording(ctx, id, rec);
        });
      }
      for (const [name, client] of Object.entries(state.clients) as [ClientName, ClientState][]) {
        await stopClient(ctx, inst, name, client);
        await ctx.act(`remove ${inst.stateDir}/clients/${name} (session data)`, () => sh.remove(`${inst.stateDir}/clients/${name}`));
        delete state.clients[name];
      }
      if (state.emulator) {
        const emu = state.emulator;
        await ctx.act(`kill emulator ${inst.serial}`, async () => {
          await sh.run(['adb', '-s', inst.serial, 'emu', 'kill']);
          await waitFor(
            sh,
            async () => !(await sh.alive(emu.pid, emu.marker)),
            30_000,
            () => new FgError('emulator_stuck', `Emulator pid ${emu.pid} did not exit.`, `kill ${emu.pid}`),
          ).catch(() => sh.kill(emu.pid, 'SIGKILL'));
          delete state.emulator;
        });
      }
      if (!args.flags['keep-stack'] && (await stackRunning(ctx))) {
        await ctx.act(
          `supabase stop --workdir ${inst.workdir} --no-backup (${inst.projectId} only)`,
          () => mustRun(ctx.sh, ['supabase', 'stop', '--workdir', inst.workdir, '--no-backup'], { timeoutMs: 300_000 }),
        );
        delete state.stack;
      }
      await ctx.act(
        `remove recording logs in ${inst.stateDir}`,
        () => sh.run(['find', inst.stateDir, '-maxdepth', '1', '-name', 'record-*.log', '-delete']),
      );
      await ctx.save();
      // A run that captured nothing has no directory; naming it would point at nothing.
      return (await sh.exists(evidence)) ? { evidenceDir: evidence, evidenceKept: true } : { evidenceDir: null, evidenceKept: false };
    },
  },
  {
    name: 'doctor',
    summary: 'Read-only health check: is this instance worth driving? Names a fix for each failure.',
    usage: 'fg doctor',
    description:
      'Checks Docker; the stack (auth, rest, realtime, functions, Mailpit); migrations applied vs the checkout; the two test users signing in and sharing a household; and per client: process alive, build current with the checkout, Marionette connected and which screen shows. Exit 1 when any check fails. Run it first whenever something looks off.',
    examples: ['fg doctor'],
    async run(ctx) {
      const checks = await doctorChecks(ctx);
      const failed = checks.filter((c) => !c.ok);
      if (failed.length) {
        throw new FgError(
          'unhealthy',
          `${failed.length} check(s) failed: ${failed.map((c) => c.name).join(', ')}.`,
          failed.map((c) => `${c.name}: ${c.fix}`).join(' | '),
          1,
          { checks: checks as unknown as JsonObject[] },
        );
      }
      return { checks: checks as unknown as JsonObject[] };
    },
  },
  {
    name: 'env',
    summary: "Print this instance's settings and state: ports, URLs, users, clients, evidence dir.",
    usage: 'fg env',
    description:
      'Derived from FG_PORT_PREFIX, FG_PROJECT_ID, FG_SURFACE, FG_AVD, FG_EMU_PORT, FG_EVIDENCE_DIR and FG_STATE_DIR. Never prints secrets.',
    examples: ['fg env'],
    run(ctx) {
      const { inst, state } = ctx;
      return Promise.resolve({
        prefix: inst.prefix,
        projectId: inst.projectId,
        apiUrl: inst.apiUrl,
        dbPort: inst.dbPort,
        mailUrl: inst.mailUrl,
        defaultSurface: inst.defaultSurface,
        kvmBroken: inst.kvmBroken,
        avd: inst.avd,
        serial: inst.serial,
        stateDir: inst.stateDir,
        run: state.run,
        evidenceDir: runDir(inst, state),
        users: Object.fromEntries(Object.entries(USERS).map(([k, u]) => [k, { email: u.email, password: u.password }])),
        clients: state.clients as unknown as JsonObject,
        recordings: state.recordings as unknown as JsonObject,
      });
    },
  },
  {
    name: 'seed',
    summary: 'Reset the database and create peter@fg.test + lea@fg.test in one household.',
    usage: 'fg seed [--dry-run]',
    description:
      "Runs `supabase db reset` on this instance (all data is lost), then creates both users through the auth admin API and the household through the app's own RPCs: create_household as peter, create_invite, join_household as lea. Running apps keep stale sessions: `fg logout` and `fg login` them afterwards.",
    examples: ['fg seed --dry-run', 'fg seed'],
    destructive: true,
    async run(ctx) {
      if (!(await stackRunning(ctx))) {
        throw new FgError('stack_down', 'The stack is not running.', 'Run `fg up --only stack` (it seeds too).');
      }
      const result = await seed(ctx, ctx.inst);
      ctx.state.seededAt = new Date().toISOString();
      await ctx.save();
      return { ...result, next: 'Running apps hold stale sessions now: `fg up` relaunches them signed out.' };
    },
  },
];
