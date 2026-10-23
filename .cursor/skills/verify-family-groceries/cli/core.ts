/** Shared types for the fg CLI: errors, the process runner, and the command shape. */

import type { Instance, State } from './instance.ts';

export type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
export type JsonObject = { [key: string]: Json };
/** What a command returns; serialized as the JSON document on stdout. */
export type Result = Record<string, unknown>;

/** Exit codes: 0 ok, 1 failed (see error.code and error.hint), 64 bad usage. */
export const EXIT_FAILED = 1;
export const EXIT_USAGE = 64;

/** A failure the agent can act on: what broke, and what to run instead. */
export class FgError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly hint: string,
    readonly exitCode = EXIT_FAILED,
    readonly details: JsonObject = {},
  ) {
    super(message);
  }
}

export const usage = (message: string, hint: string) => new FgError('usage', message, hint, EXIT_USAGE);

export interface RunResult {
  code: number;
  stdout: string;
  stderr: string;
}

export interface RunOptions {
  env?: Record<string, string>;
  cwd?: string;
  stdin?: string;
  timeoutMs?: number;
}

export interface SpawnOptions {
  env?: Record<string, string>;
  cwd?: string;
  log: string;
}

/** Every side effect on processes goes through this, so tests can fake it. */
export interface Shell {
  run(cmd: string[], opts?: RunOptions): Promise<RunResult>;
  /** Starts a detached process that outlives the CLI; returns its pid. */
  spawn(cmd: string[], opts: SpawnOptions): Promise<number>;
  /** True when pid runs and its command line contains marker. */
  alive(pid: number, marker: string): Promise<boolean>;
  kill(pid: number, signal: Deno.Signal): Promise<void>;
  exists(path: string): Promise<boolean>;
  readText(path: string): Promise<string>;
  writeText(path: string, text: string): Promise<void>;
  mkdir(path: string): Promise<void>;
  remove(path: string): Promise<void>;
  fetch(url: string, init?: RequestInit): Promise<Response>;
  sleep(ms: number): Promise<void>;
}

export type FlagSpec = {
  name: string;
  help: string;
  type?: 'string' | 'boolean';
  default?: string;
  /** Allowed values, checked before the command runs. */
  choices?: string[];
};

export type Args = {
  positional: string[];
  flags: Record<string, string | boolean | undefined>;
  /** Everything after a literal `--`. */
  rest: string[];
};

export interface Ctx {
  sh: Shell;
  dryRun: boolean;
  /** Progress for humans; goes to stderr so stdout stays one JSON document. */
  log(message: string): void;
  /**
   * Runs a state-changing step, or only records it under --dry-run. Every
   * mutation in a destructive command goes through here.
   */
  act<T>(description: string, step: () => Promise<T>): Promise<T | undefined>;
  actions: string[];
  inst: Instance;
  state: State;
  /** Persists `state`; skipped under --dry-run. */
  save(): Promise<void>;
}

export interface Command {
  /** One or two words: `up`, `db query`, `record start`. */
  name: string;
  summary: string;
  usage: string;
  description: string;
  flags?: FlagSpec[];
  examples: string[];
  /** Mutates state outside the CLI: gets --dry-run, which reports instead of acting. */
  destructive?: boolean;
  /** Placeholder for a later job; listed in help, fails with not_implemented. */
  planned?: boolean;
  run(ctx: Ctx, args: Args): Promise<Result>;
}

export function str(args: Args, name: string): string | undefined {
  const value = args.flags[name];
  return typeof value === 'string' ? value : undefined;
}

export function int(args: Args, name: string, fallback: number): number {
  const raw = str(args, name);
  if (raw === undefined) return fallback;
  const value = Number(raw);
  if (!Number.isFinite(value)) throw usage(`--${name} must be a number, got "${raw}".`, `Pass e.g. --${name} ${fallback}.`);
  return value;
}
