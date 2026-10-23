// The MCP server: one per request, bound to the authenticated caller.
import { type CallToolResult, McpServer } from '@modelcontextprotocol/server';
import { z } from 'zod';
import type { Auth } from '../_shared/auth.ts';
import { asUser, type Tx } from '../_shared/db.ts';
import { addItems, categories, listItems, moveItem, stores, tickItems, ToolError } from './list.ts';

const INSTRUCTIONS = `Gemeinsame Einkaufsliste eines Haushalts (deutsch).
Einträge haben einen Namen (z. B. "Milch"), optional eine Menge ("2", "500 g"), eine Kategorie
(Gang im Laden, z. B. "Kühlregal") und optional einen Laden (z. B. "dm"). Neue Einträge werden
automatisch einsortiert; gib eine Kategorie nur an, wenn der Nutzer sie ausdrücklich nennt.
Einträge, Kategorien und Läden lassen sich per Name (ungefähr, ohne Umlaute) oder per id angeben.
Abgehakte Einträge verschwinden aus der Liste.`;

/** A tool body: runs as the caller in one transaction; ToolErrors become tool-level errors. */
function run(auth: Auth, body: (tx: Tx) => Promise<unknown>) {
  return async (): Promise<CallToolResult> => {
    try {
      const result = await asUser(auth.userId, body);
      return { content: [{ type: 'text', text: JSON.stringify(result, null, 2) }] };
    } catch (e) {
      if (!(e instanceof ToolError)) throw e;
      return { isError: true, content: [{ type: 'text', text: e.message }] };
    }
  };
}

const itemRef = z.string().min(1).max(120).describe(
  'Name des Eintrags auf der Liste (z. B. "Milch") oder seine id',
);
const storeName = z.string().min(1).max(60).describe('Laden, z. B. "dm", "Lidl", "Edeka"');
const categoryName = z.string().min(1).max(60).describe(
  'Kategorie, z. B. "Obst & Gemüse" oder "Kühlregal"',
);

export function buildServer(auth: Auth): McpServer {
  const server = new McpServer(
    { name: 'family-groceries', title: 'Einkaufsliste', version: '1.0.0' },
    { instructions: INSTRUCTIONS },
  );
  const h = auth.householdId;

  server.registerTool('list_items', {
    title: 'Einkaufsliste anzeigen',
    description:
      'Zeigt die offenen Einträge der Einkaufsliste, in Gang-Reihenfolge sortiert. Mit "store" ' +
      'nur, was in diesem Laden gekauft werden kann (seine Einträge plus alle ohne Laden), in der ' +
      'Reihenfolge dieses Ladens. Mit "category" nur eine Kategorie.',
    inputSchema: z.object({ store: storeName.optional(), category: categoryName.optional() }),
    annotations: { readOnlyHint: true },
  }, (args) => run(auth, (tx) => listItems(tx, h, args))());

  server.registerTool('add_items', {
    title: 'Einträge hinzufügen',
    description:
      'Setzt einen oder mehrere Einträge auf die Liste. Jeder Eintrag wird automatisch einer ' +
      'Kategorie zugeordnet (lernt aus Korrekturen). Was schon auf der Liste steht, wird nicht ' +
      'doppelt angelegt und unter "alreadyOnList" gemeldet. Mengen gehören in "quantity", nicht ' +
      'in den Namen: "2 Gurken" → name "Gurken", quantity "2".',
    inputSchema: z.object({
      items: z.array(z.object({
        name: z.string().min(1).max(120).describe('Was gekauft werden soll, z. B. "Milch"'),
        quantity: z.string().max(40).optional().describe('Menge, z. B. "2" oder "500 g"'),
        category: categoryName.optional().describe(
          'Nur angeben, wenn der Nutzer eine Kategorie ausdrücklich nennt',
        ),
        store: storeName.optional().describe(
          'Nur angeben, wenn es in einem bestimmten Laden sein soll',
        ),
      })).min(1).max(50),
    }),
  }, ({ items }) => run(auth, (tx) => addItems(tx, h, items))());

  server.registerTool('tick_items', {
    title: 'Einträge abhaken',
    description:
      'Hakt einen oder mehrere Einträge als gekauft ab; sie verschwinden von der Liste und ' +
      'landen unter "Zuletzt gekauft". Nicht gefundene Namen werden unter "notFound" gemeldet.',
    inputSchema: z.object({ items: z.array(itemRef).min(1).max(50) }),
    annotations: { destructiveHint: false, idempotentHint: true },
  }, ({ items }) => run(auth, (tx) => tickItems(tx, h, items))());

  server.registerTool('move_item', {
    title: 'Eintrag verschieben',
    description:
      'Ändert die Kategorie und/oder den Laden eines Eintrags. Eine geänderte Kategorie ist eine ' +
      'Korrektur, aus der die automatische Einsortierung lernt. store: null entfernt den Laden ' +
      '(dann in jedem Laden kaufbar).',
    inputSchema: z.object({
      item: itemRef,
      category: categoryName.optional(),
      store: storeName.nullable().optional(),
    }),
    annotations: { idempotentHint: true },
  }, (args) => run(auth, (tx) => moveItem(tx, h, args))());

  server.registerTool('list_categories', {
    title: 'Kategorien anzeigen',
    description: 'Listet die Kategorien des Haushalts in Gang-Reihenfolge.',
    annotations: { readOnlyHint: true },
  }, () => run(auth, (tx) => categories(tx, h))());

  server.registerTool('list_stores', {
    title: 'Läden anzeigen',
    description: 'Listet die Läden des Haushalts.',
    annotations: { readOnlyHint: true },
  }, () => run(auth, (tx) => stores(tx, h))());

  return server;
}
