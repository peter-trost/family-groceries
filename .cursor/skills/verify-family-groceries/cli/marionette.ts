/** Thin layer over the Marionette CLI (pub: marionette_cli): stateless calls by VM service URI. */

import { FgError, type Shell } from './core.ts';

export interface Bounds {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface Element {
  type: string;
  key?: string;
  text?: string;
  label?: string;
  tooltip?: string;
  identifier?: string;
  enabled?: boolean;
  bounds?: Bounds;
}

/** A matcher in Marionette's terms; exactly one of key/identifier/text/type, or x+y. */
export type Matcher =
  | { key: string }
  | { identifier: string }
  | { text: string }
  | { type: string }
  | { x: number; y: number };

export function matcherArgs(m: Matcher): string[] {
  if ('x' in m) return ['--x', String(m.x), '--y', String(m.y)];
  const [name, value] = Object.entries(m)[0];
  return [`--${name}`, String(value)];
}

/**
 * Parses `get-interactive-elements` output. Each element is one line of
 * `Name: value` pairs; values are quoted strings (may contain commas),
 * JSON objects (bounds) or bare words.
 */
export function parseElements(output: string): Element[] {
  const elements: Element[] = [];
  for (const line of output.split('\n')) {
    if (!line.startsWith('Type: ')) continue;
    const fields: Record<string, string> = {};
    const pair = /(\w+): ("(?:[^"\\]|\\.)*"|\{[^}]*\}|[^,]+)(?:, |$)/g;
    for (const m of line.matchAll(pair)) {
      const raw = m[2];
      fields[m[1]] = raw.startsWith('"') ? JSON.parse(raw) : raw.trim();
    }
    const el: Element = { type: fields.Type };
    if (fields.Key !== undefined) el.key = fields.Key;
    if (fields.Text !== undefined) el.text = fields.Text;
    if (fields.label !== undefined) el.label = fields.label;
    if (fields.tooltip !== undefined) el.tooltip = fields.tooltip;
    if (fields.identifier !== undefined) el.identifier = fields.identifier;
    if (fields.enabled !== undefined) el.enabled = fields.enabled === 'true';
    if (fields.bounds !== undefined) el.bounds = JSON.parse(fields.bounds);
    elements.push(el);
  }
  return elements;
}

const contains = (outer: Bounds, inner: Bounds) =>
  inner.x >= outer.x && inner.y >= outer.y &&
  inner.x + inner.width <= outer.x + outer.width && inner.y + inner.height <= outer.y + outer.height;

/**
 * The key of the smallest keyed element whose bounds contain the element
 * showing exactly `text`: the list row for an item name, so an agent can
 * act on "the checkbox in the Milch row" without knowing its id.
 */
export function rowKeyFor(elements: Element[], text: string): string {
  const label = elements.find((e) => e.text === text && e.bounds);
  if (!label?.bounds) {
    throw new FgError(
      'not_found',
      `No element shows the text "${text}".`,
      'Run `fg find` to list what is on screen; text must match exactly (case, umlauts).',
    );
  }
  const rows = elements
    .filter((e) => e.key !== undefined && e.bounds && contains(e.bounds, label.bounds!))
    .sort((a, b) => a.bounds!.width * a.bounds!.height - b.bounds!.width * b.bounds!.height);
  if (rows.length === 0) {
    throw new FgError(
      'not_found',
      `"${text}" is not inside a keyed row.`,
      'Match it directly with --text, or tap by coordinates from `fg find`.',
    );
  }
  return rows[0].key!;
}

/** Which top-level screen shows, told apart by the key of its main field. */
export const SCREEN_KEYS = { list: 'add-item-field', welcome: 'household-name', login: 'login-email' } as const;
export type Screen = keyof typeof SCREEN_KEYS | 'other';

export function screenOf(elements: Element[]): Screen {
  const found = (Object.keys(SCREEN_KEYS) as (keyof typeof SCREEN_KEYS)[]).find((s) => elements.some((e) => e.key === SCREEN_KEYS[s]));
  return found ?? 'other';
}

export class Marionette {
  constructor(private sh: Shell, private uri: string) {}

  async call(args: string[], timeoutMs = 30_000): Promise<string> {
    const res = await this.sh.run(['marionette', '--uri', this.uri, '--timeout', '10', ...args], { timeoutMs });
    if (res.code !== 0) {
      const message = (res.stderr || res.stdout).trim();
      if (/No element is currently focused/.test(message)) {
        throw new FgError(
          'no_focus',
          'No text field has focus.',
          'Focus is only automatic when the list screen opens. Name the field: `fg type --key add-item-field --input ...`.',
        );
      }
      if (/not found/i.test(message)) {
        throw new FgError('not_found', firstLine(message), 'Run `fg find` to see what is on screen, or `fg wait` until it appears.');
      }
      if (/connect|WebSocket|SocketException|refused|timed out/i.test(message)) {
        throw new FgError(
          'app_unreachable',
          `Marionette cannot reach the app at ${this.uri}: ${firstLine(message)}`,
          'The app stopped or restarted. Run `fg doctor`, then `fg up` to relaunch it.',
        );
      }
      throw new FgError('marionette_failed', firstLine(message), 'Run `fg doctor`; `fg logs` shows the app output.', 1, {
        output: message.slice(0, 2000),
      });
    }
    return res.stdout;
  }

  async elements(ancestorKeys: string[] = []): Promise<Element[]> {
    const args = ['get-interactive-elements'];
    for (const k of ancestorKeys) args.push('--ancestor-keys', k);
    return parseElements(await this.call(args));
  }
}

/** Marionette nests the app-side exception as JSON on a later line; that is the useful part. */
export function firstLine(message: string): string {
  const nested = message.match(/"exception":"((?:[^"\\]|\\.)*)"/);
  if (nested) return nested[1].replace(/^Exception: /, '').slice(0, 400);
  return message.split('\n')[0].slice(0, 400);
}
