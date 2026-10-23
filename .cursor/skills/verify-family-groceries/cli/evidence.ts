/** Evidence: screenshots, screen recordings and logs, saved outside the repo so cleanup never eats them. */

import { type Command, type Ctx, FgError, int, type JsonObject, str } from './core.ts';
import { clientName, type RecordingState, runDir } from './instance.ts';
import { client, clientFlag } from './drive.ts';
import { mustRun } from './stack.ts';
import { SCREEN } from './surfaces.ts';

const nativeFlag = {
  name: 'native',
  type: 'boolean' as const,
  help: 'Capture with the OS instead of Marionette (ffmpeg x11grab on Linux, adb on Android).',
};

async function evidencePath(ctx: Ctx, name: string | undefined, fallback: string, ext: string): Promise<string> {
  const dir = runDir(ctx.inst, ctx.state);
  await ctx.sh.mkdir(dir);
  const base = (name ?? fallback).replace(/[^\w.-]+/g, '-');
  return `${dir}/${base.endsWith(ext) ? base : `${base}${ext}`}`;
}

const stamp = () => new Date().toISOString().slice(11, 19).replaceAll(':', '');

async function durationSeconds(ctx: Ctx, path: string): Promise<number | null> {
  const res = await ctx.sh.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', path]);
  const value = Number(res.stdout.trim());
  return res.code === 0 && Number.isFinite(value) ? Math.round(value * 10) / 10 : null;
}

async function processGroup(ctx: Ctx, pgid: number): Promise<{ pid: number; args: string }[]> {
  const res = await ctx.sh.run(['ps', '-eo', 'pid=,pgid=,args=']);
  return res.stdout.split('\n').flatMap((line) => {
    const m = line.trim().match(/^(\d+)\s+(\d+)\s+(.*)$/);
    return m && Number(m[2]) === pgid ? [{ pid: Number(m[1]), args: m[3] }] : [];
  });
}

/**
 * Ends a recording so the file is complete. A Marionette recording runs as
 * sh wrapper -> dart -> ffmpeg in one process group; only the dart process may
 * get SIGINT: it stops the screencast and closes ffmpeg's input. An ffmpeg that
 * gets SIGINT exits 255, and Marionette then deletes the file.
 */
export async function stopRecording(ctx: Ctx, id: string, rec: RecordingState): Promise<JsonObject> {
  if (rec.kind === 'screenrecord') {
    await ctx.sh.run(['adb', '-s', ctx.inst.serial, 'shell', 'pkill', '-INT', 'screenrecord']);
    await ctx.sh.sleep(1500);
    await mustRun(ctx.sh, ['adb', '-s', ctx.inst.serial, 'pull', `/sdcard/fg-${id}.mp4`, rec.path]);
  } else {
    const group = await processGroup(ctx, rec.pid);
    const targets = rec.kind === 'marionette'
      ? group.filter((p) => p.args.includes('record-video') && !p.args.startsWith('sh ') && !p.args.startsWith('ffmpeg'))
      : group.filter((p) => p.args.startsWith('ffmpeg'));
    for (const p of targets) await ctx.sh.kill(p.pid, 'SIGINT');
    for (let i = 0; i < 120 && (await processGroup(ctx, rec.pid)).length > 0; i++) await ctx.sh.sleep(250);
  }
  delete ctx.state.recordings[id];
  const exists = await ctx.sh.exists(rec.path);
  return { name: id, path: rec.path, exists, durationSec: exists ? await durationSeconds(ctx, rec.path) : null };
}

export const evidenceCommands: Command[] = [
  {
    name: 'screenshot',
    summary: "Save a PNG of a client to the run's evidence directory.",
    usage: 'fg screenshot [--name NAME] [--client peter|lea] [--native]',
    description:
      "Marionette renders the app's own frame (no window chrome). --native grabs the X display or the emulator screen instead (shows the soft keyboard on Android). Files go to $FG_EVIDENCE_DIR/<run>/ and survive `fg down`.",
    flags: [{ name: 'name', help: 'File name without extension (default <client>-<time>).' }, clientFlag, nativeFlag],
    examples: ['fg screenshot --name 01-list-after-add', 'fg screenshot --client lea --name 02-lea-sees-milch'],
    async run(ctx, args) {
      const { name, state, m } = client(ctx, args);
      const path = await evidencePath(ctx, str(args, 'name'), `${name}-${stamp()}`, '.png');
      if (!args.flags.native) {
        await m.call(['take-screenshots', '--output', path]);
      } else if (state.surface === 'linux') {
        await mustRun(ctx.sh, [
          'ffmpeg',
          '-loglevel',
          'error',
          '-y',
          '-f',
          'x11grab',
          '-video_size',
          `${SCREEN.width}x${SCREEN.height}`,
          '-i',
          `:${state.display}`,
          '-frames:v',
          '1',
          path,
        ]);
      } else {
        await mustRun(ctx.sh, ['sh', '-c', `adb -s "$0" exec-out screencap -p > "$1"`, ctx.inst.serial, path]);
      }
      if (!(await ctx.sh.exists(path))) {
        throw new FgError('screenshot_failed', `No file at ${path}.`, 'Retry with --native, and check `fg doctor`.');
      }
      return { client: name, path };
    },
  },
  {
    name: 'record start',
    summary: 'Start a screen recording of a client (WebM via Marionette, or --native).',
    usage: 'fg record start [--name NAME] [--client peter|lea] [--native]',
    description:
      "Runs in the background until `fg record stop`. Marionette streams the app's frames to ffmpeg (WebM). --native records the X display with ffmpeg (MP4) or the emulator with adb screenrecord (MP4, max 3 min). One recording per name.",
    flags: [{ name: 'name', help: 'Recording name and file name (default <client>-<time>).' }, clientFlag, nativeFlag],
    examples: ['fg record start --name quick-add', 'fg record start --name lea-view --client lea'],
    destructive: true,
    async run(ctx, args) {
      const { name, state, m } = client(ctx, args);
      const id = str(args, 'name') ?? `${name}-${stamp()}`;
      if (ctx.state.recordings[id]) {
        throw new FgError(
          'recording_exists',
          `Recording "${id}" is already running.`,
          `Stop it with \`fg record stop --name ${id}\` or pick another --name.`,
        );
      }
      const native = Boolean(args.flags.native);
      const kind = !native ? 'marionette' : state.surface === 'linux' ? 'x11grab' : 'screenrecord';
      const path = await evidencePath(ctx, id, id, kind === 'marionette' ? '.webm' : '.mp4');
      const log = `${ctx.inst.stateDir}/record-${id}.log`;
      const cmd = kind === 'marionette' ? ['marionette', '--uri', state.vmUri, 'record-video', '--output', path] : kind === 'x11grab'
        ? [
          'ffmpeg',
          '-loglevel',
          'error',
          '-y',
          '-f',
          'x11grab',
          '-framerate',
          '15',
          '-video_size',
          `${SCREEN.width}x${SCREEN.height}`,
          '-i',
          `:${state.display}`,
          '-c:v',
          'libx264',
          '-preset',
          'ultrafast',
          '-pix_fmt',
          'yuv420p',
          path,
        ]
        : ['adb', '-s', ctx.inst.serial, 'shell', 'screenrecord', `/sdcard/fg-${id}.mp4`];
      await ctx.act(`start recording "${id}" (${kind}) to ${path}`, async () => {
        const pid = await ctx.sh.spawn(cmd, { log });
        ctx.state.recordings[id] = { pid, marker: cmd[0], path, kind, client: name, startedAt: new Date().toISOString() };
        await ctx.save();
        if (kind === 'marionette') {
          // The recording starts once Marionette reports its frame size.
          await m.elements();
          for (let i = 0; i < 40 && !(await ctx.sh.readText(log).catch(() => '')).includes('Recording'); i++) await ctx.sh.sleep(250);
        }
      });
      return { client: name, name: id, kind, path, log };
    },
  },
  {
    name: 'record stop',
    summary: 'Stop a recording (or all) and report the file and its duration.',
    usage: 'fg record stop [--name NAME]',
    description:
      'Sends SIGINT so ffmpeg finalizes the file, waits for it to exit, then checks the file with ffprobe. Without --name it stops every running recording.',
    flags: [{ name: 'name', help: 'Recording to stop (default: all).' }],
    examples: ['fg record stop --name quick-add', 'fg record stop'],
    destructive: true,
    async run(ctx, args) {
      const wanted = str(args, 'name');
      const ids = wanted ? [wanted] : Object.keys(ctx.state.recordings);
      if (wanted && !ctx.state.recordings[wanted]) {
        throw new FgError(
          'no_recording',
          `No recording named "${wanted}".`,
          `Running: ${Object.keys(ctx.state.recordings).join(', ') || 'none'}.`,
        );
      }
      const stopped: JsonObject[] = [];
      for (const id of ids) {
        const rec = ctx.state.recordings[id];
        const result = await ctx.act(`stop recording "${id}" (pid ${rec.pid})`, () => stopRecording(ctx, id, rec));
        if (result) stopped.push(result);
      }
      await ctx.save();
      const missing = stopped.filter((s) => !s.exists || !s.durationSec);
      if (missing.length) {
        throw new FgError(
          'recording_failed',
          `No playable video for ${missing.map((s) => s.name).join(', ')}.`,
          `Read ${ctx.inst.stateDir}/record-<name>.log; retry with --native.`,
          1,
          { stopped },
        );
      }
      return { stopped };
    },
  },
  {
    name: 'logs',
    summary: "Tail app output (default) or a Supabase service's container log.",
    usage: 'fg logs [--client peter|lea] [--service auth|rest|realtime|edge_runtime|db|kong|inbucket] [--lines N] [--grep REGEX]',
    description:
      "App logs are the client's stdout/stderr (print, debugPrint, Flutter errors, the VM service line). --service reads `docker logs` of this instance's container.",
    flags: [clientFlag, { name: 'service', help: 'Supabase container: auth, rest, realtime, edge_runtime, db, kong, inbucket.' }, {
      name: 'lines',
      help: 'How many lines (default 80).',
    }, { name: 'grep', help: 'Only lines matching this regex.' }],
    examples: ['fg logs', 'fg logs --client lea --grep -i error', 'fg logs --service edge_runtime --lines 200'],
    async run(ctx, args) {
      const lines = int(args, 'lines', 80);
      const service = str(args, 'service');
      let text: string;
      let source: string;
      if (service) {
        source = `supabase_${service}_${ctx.inst.projectId}`;
        const res = await ctx.sh.run(['docker', 'logs', '--tail', String(lines * 5), source]);
        if (res.code !== 0) {
          throw new FgError(
            'no_service',
            `No container ${source}.`,
            'Services: auth, rest, realtime, edge_runtime, db, kong, inbucket. Is the stack up (`fg doctor`)?',
          );
        }
        text = res.stdout + res.stderr;
      } else {
        const name = clientName(str(args, 'client'));
        const c = ctx.state.clients[name];
        if (!c) throw new FgError('no_client', `No ${name} app is running.`, 'Run `fg up`.');
        source = c.log;
        if (c.surface === 'android') {
          await ctx.sh.writeText(c.log, (await ctx.sh.run(['adb', '-s', ctx.inst.serial, 'logcat', '-d', '-s', 'flutter'])).stdout);
        }
        text = await ctx.sh.readText(c.log);
      }
      const pattern = str(args, 'grep');
      const re = pattern ? new RegExp(pattern) : null;
      const all = text.split('\n').filter((l) => l.trim() && (!re || re.test(l)));
      return { source, lines: all.slice(-lines) };
    },
  },
  {
    name: 'trace',
    summary: '(planned) Record a performance timeline of an interaction.',
    usage: 'fg trace start|stop [--client peter|lea]',
    description:
      'Placeholder for the profiling job: will capture a Dart/Flutter timeline over the VM service (profile build) and save it next to the other evidence.',
    examples: ['fg trace start', 'fg trace stop'],
    planned: true,
    run: () =>
      Promise.reject(
        new FgError(
          'not_implemented',
          '`fg trace` is not built yet.',
          'Until it is: `fg marionette -- get-logs`, or run the app with `flutter run --profile -t test_driver/main_marionette.dart` and open DevTools.',
        ),
      ),
  },
  {
    name: 'memory',
    summary: "(planned) Report the app's memory use.",
    usage: 'fg memory [--client peter|lea]',
    description: 'Placeholder for the profiling job: will read heap usage over the VM service (getMemoryUsage) and process RSS.',
    examples: ['fg memory'],
    planned: true,
    run: () =>
      Promise.reject(
        new FgError('not_implemented', '`fg memory` is not built yet.', 'Until it is: `ps -o rss= -p <pid>` with the pid from `fg env`.'),
      ),
  },
];
