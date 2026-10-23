/** Which local instance this CLI drives, derived from the environment, plus its saved state. */

import { FgError, type Shell } from './core.ts';

export type ClientName = 'peter' | 'lea';
export type SurfaceKind = 'linux' | 'android';

export const USERS: Record<ClientName, { email: string; password: string; name: string }> = {
  peter: { email: 'peter@fg.test', password: 'test-password-123', name: 'Peter' },
  lea: { email: 'lea@fg.test', password: 'test-password-123', name: 'Lea' },
};
export const HOUSEHOLD = 'Familie Test';
export const APP_ID = 'com.petertrost.familygroceries';
export const ENTRYPOINT = 'test_driver/main_marionette.dart';

/** Emulator image and APK target matching the host CPU (x86_64 boxes, Apple silicon). */
export const ANDROID_ABI = Deno.build.arch === 'aarch64'
  ? { image: 'arm64-v8a', target: 'android-arm64' }
  : { image: 'x86_64', target: 'android-x64' };

export function clientName(raw: string | undefined): ClientName {
  const name = raw ?? 'peter';
  if (name === 'peter' || name === 'lea') return name;
  throw new FgError(
    'unknown_user',
    `Unknown user "${name}".`,
    'The seeded users are "peter" and "lea" (one household).',
    64,
  );
}

export interface Instance {
  repo: string;
  /** Port block: 543 gives API 54321, DB 54322, Mailpit 54324. */
  prefix: string;
  projectId: string;
  stateDir: string;
  /** Generated Supabase workdir: config.toml with this port block, symlinks to the repo's sql/functions. */
  workdir: string;
  apiUrl: string;
  dbPort: number;
  mailUrl: string;
  dbContainer: string;
  avd: string;
  emuPort: number;
  serial: string;
  evidenceRoot: string;
  /** Present when this box cannot run the Android emulator; its text says why. */
  kvmBroken: string | null;
  kvmMarker: string;
  defaultSurface: SurfaceKind;
}

export async function loadInstance(sh: Shell, env: Record<string, string | undefined>, repo: string): Promise<Instance> {
  const prefix = env.FG_PORT_PREFIX ?? '543';
  if (!/^5\d\d$/.test(prefix)) {
    throw new FgError(
      'bad_env',
      `FG_PORT_PREFIX="${prefix}" is not a 3-digit port block.`,
      'Use e.g. FG_PORT_PREFIX=548 for ports 54820-54829.',
      64,
    );
  }
  const home = env.HOME ?? '/tmp';
  const stateDir = env.FG_STATE_DIR ?? `${home}/.cache/fg/${prefix}`;
  const offset = Number(prefix) - 543;
  const emuPort = Number(env.FG_EMU_PORT ?? 5554 + 2 * offset);
  const kvmMarker = env.FG_KVM_MARKER ?? `${home}/.config/fg/kvm-broken`;
  const kvmBroken = (await sh.exists(kvmMarker)) ? (await sh.readText(kvmMarker)).trim() : null;
  const surface = env.FG_SURFACE;
  if (surface !== undefined && surface !== 'linux' && surface !== 'android') {
    throw new FgError('bad_env', `FG_SURFACE="${surface}" is not a surface.`, 'Use FG_SURFACE=linux or FG_SURFACE=android.', 64);
  }
  const projectId = env.FG_PROJECT_ID ?? (prefix === '543' ? 'family-groceries' : `family-groceries-${prefix}`);
  return {
    repo,
    prefix,
    projectId,
    stateDir,
    workdir: `${stateDir}/stack`,
    apiUrl: `http://127.0.0.1:${prefix}21`,
    dbPort: Number(`${prefix}22`),
    mailUrl: `http://127.0.0.1:${prefix}24`,
    dbContainer: `supabase_db_${projectId}`,
    avd: env.FG_AVD ?? `fg-${prefix}`,
    emuPort,
    serial: `emulator-${emuPort}`,
    evidenceRoot: env.FG_EVIDENCE_DIR ?? `${home}/fg-evidence`,
    kvmBroken,
    kvmMarker,
    defaultSurface: surface ?? (kvmBroken ? 'linux' : 'android'),
  };
}

export interface ClientState {
  surface: SurfaceKind;
  pid: number;
  /** Substring of the process command line, so a recycled pid is never mistaken for ours. */
  marker: string;
  vmUri: string;
  log: string;
  fingerprint: string;
  display?: number;
  xvfbPid?: number;
  hostPort?: number;
  /** ISO time the app process started; a client older than the last seed holds a stale session. */
  startedAt?: string;
}

export interface RecordingState {
  pid: number;
  marker: string;
  path: string;
  kind: 'marionette' | 'x11grab' | 'screenrecord';
  client: ClientName;
  startedAt: string;
}

export interface State {
  run: string;
  clients: Partial<Record<ClientName, ClientState>>;
  emulator?: { pid: number; marker: string };
  recordings: Record<string, RecordingState>;
  builds: Partial<Record<SurfaceKind, string>>;
  /** Config and function set the running stack was started with (see stackSignature). */
  stack?: string;
  /** ISO time of the last database reset and seed. */
  seededAt?: string;
}

const emptyState = (): State => ({ run: newRunId(), clients: {}, recordings: {}, builds: {} });

export function newRunId(now = new Date()): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `run-${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}-${pad(now.getHours())}${pad(now.getMinutes())}${
    pad(now.getSeconds())
  }`;
}

export async function readState(sh: Shell, inst: Instance): Promise<State> {
  const path = `${inst.stateDir}/state.json`;
  if (!(await sh.exists(path))) return emptyState();
  return { ...emptyState(), ...JSON.parse(await sh.readText(path)) };
}

export async function writeState(sh: Shell, inst: Instance, state: State): Promise<void> {
  await sh.mkdir(inst.stateDir);
  await sh.writeText(`${inst.stateDir}/state.json`, JSON.stringify(state, null, 2));
}

export const runDir = (inst: Instance, state: State) => `${inst.evidenceRoot}/${state.run}`;
