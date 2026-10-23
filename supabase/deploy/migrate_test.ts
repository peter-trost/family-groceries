import { assertEquals, assertStringIncludes, assertThrows } from '@std/assert';
import { applyQuery, type Migration, parseMigration, pending, readMigrations } from './migrate.ts';

const m = (version: string, name = 'x'): Migration => ({
  version,
  name,
  sql: `select ${version};`,
});

Deno.test('everything is pending on an empty remote, oldest first', () => {
  const todo = pending([m('20261023000002'), m('20261023000001')], []);
  assertEquals(todo.map((x) => x.version), ['20261023000001', '20261023000002']);
});

Deno.test('an up-to-date remote has nothing pending', () => {
  assertEquals(pending([m('20261023000001')], ['20261023000001']), []);
});

Deno.test('only migrations newer than the remote ones are pending', () => {
  const todo = pending([m('20261023000001'), m('20261023000002')], ['20261023000001']);
  assertEquals(todo.map((x) => x.version), ['20261023000002']);
});

Deno.test('a remote migration missing locally stops the deploy', () => {
  assertThrows(
    () => pending([m('20261023000001')], ['20261023000001', '20261023000009']),
    Error,
    '20261023000009',
  );
});

Deno.test('a local migration older than the latest remote one stops the deploy', () => {
  assertThrows(
    () => pending([m('20261023000001'), m('20261023000005')], ['20261023000005']),
    Error,
    'newer timestamp',
  );
});

Deno.test('the apply query wraps the migration and its history row in one transaction', () => {
  const q = applyQuery({ version: '20261023000001', name: 'demo', sql: "select 'it''s';" });
  assertEquals(q.split('\n')[0], 'begin;');
  assertEquals(q.trimEnd().split('\n').at(-1), 'commit;');
  assertStringIncludes(q, 'insert into supabase_migrations.schema_migrations');
  assertStringIncludes(q, "array[$fg_20261023000001$select 'it''s';$fg_20261023000001$]");
});

Deno.test('a migration containing the quote tag is refused', () => {
  assertThrows(() => applyQuery({ version: '1', name: 'x', sql: 'select $fg_1$;' }), Error, 'tag');
});

Deno.test('file names that are not <version>_<name>.sql are refused', () => {
  assertThrows(() => parseMigration('foundation.sql', ''), Error, 'named');
  assertEquals(parseMigration('20261022150000_foundation.sql', 's').name, 'foundation');
});

Deno.test('every file in supabase/migrations parses', async () => {
  const all = await readMigrations(new URL('../migrations/', import.meta.url));
  assertEquals(all.length > 0, true);
});
