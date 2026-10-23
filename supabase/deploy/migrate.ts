// Applies supabase/migrations to the hosted project through the Management API
// (HTTPS only, no Postgres connection). Each migration and its row in
// supabase_migrations.schema_migrations commit in one transaction, so `supabase db push`
// and `migration list` see the same history and a rerun picks up where a failed run stopped.
//
// Usage: deno run --allow-read --allow-env --allow-net supabase/deploy/migrate.ts [--dry-run]
// Env: SUPABASE_ACCESS_TOKEN, SUPABASE_PROJECT_REF

export type Migration = { version: string; name: string; sql: string };

const fileName = /^(\d{14})_(.+)\.sql$/;

export function parseMigration(file: string, sql: string): Migration {
  const m = fileName.exec(file);
  if (!m) throw new Error(`${file}: migration files are named <14-digit version>_<name>.sql`);
  return { version: m[1], name: m[2], sql };
}

/** The local migrations still to apply, in order. Throws when the histories disagree. */
export function pending(local: Migration[], applied: string[]): Migration[] {
  const localVersions = new Set(local.map((m) => m.version));
  const unknown = applied.filter((v) => !localVersions.has(v));
  if (unknown.length) {
    throw new Error(
      `the remote database has migrations that are not in supabase/migrations: ${
        unknown.join(', ')
      }`,
    );
  }
  const latest = applied.reduce((a, b) => (a > b ? a : b), '');
  const todo = local.filter((m) => !applied.includes(m.version))
    .sort((a, b) => a.version.localeCompare(b.version));
  const late = todo.filter((m) => m.version < latest);
  if (late.length) {
    throw new Error(
      `${
        late.map((m) => m.version).join(', ')
      } would apply before the latest remote migration ${latest}; give them a newer timestamp`,
    );
  }
  return todo;
}

/** One SQL text that applies the migration and records it, atomically. */
export function applyQuery(m: Migration): string {
  const tag = `$fg_${m.version}$`;
  if (m.sql.includes(tag) || m.name.includes(tag)) {
    throw new Error(`${m.version}: contains its own quote tag ${tag}`);
  }
  return [
    'begin;',
    m.sql,
    ';',
    'insert into supabase_migrations.schema_migrations (version, name, statements)',
    `values (${tag}${m.version}${tag}, ${tag}${m.name}${tag}, array[${tag}${m.sql}${tag}]);`,
    'commit;',
  ].join('\n');
}

type Query = (sql: string) => Promise<unknown[]>;

export function managementApi(ref: string, token: string): Query {
  return async (query) => {
    const res = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query }),
    });
    const body = await res.json().catch(() => null);
    if (!res.ok) throw new Error(`Management API ${res.status}: ${JSON.stringify(body)}`);
    return body as unknown[];
  };
}

export async function appliedVersions(query: Query): Promise<string[]> {
  const rows = await query(
    `select version from supabase_migrations.schema_migrations order by version`,
  ) as { version: string }[];
  return rows.map((r) => r.version);
}

export async function readMigrations(dir: URL): Promise<Migration[]> {
  const out: Migration[] = [];
  for await (const entry of Deno.readDir(dir)) {
    if (!entry.isFile || !entry.name.endsWith('.sql')) continue;
    out.push(parseMigration(entry.name, await Deno.readTextFile(new URL(entry.name, dir))));
  }
  return out;
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

if (import.meta.main) {
  try {
    const dryRun = Deno.args.includes('--dry-run');
    const query = managementApi(
      requireEnv('SUPABASE_PROJECT_REF'),
      requireEnv('SUPABASE_ACCESS_TOKEN'),
    );
    const local = await readMigrations(new URL('../migrations/', import.meta.url));
    const todo = pending(local, await appliedVersions(query));
    if (!todo.length) console.log(`Remote database is up to date (${local.length} migrations).`);
    for (const m of todo) {
      if (dryRun) {
        console.log(`would apply ${m.version}_${m.name}`);
        continue;
      }
      await query(applyQuery(m));
      console.log(`applied ${m.version}_${m.name}`);
    }
  } catch (e) {
    console.error(`migrate: ${e instanceof Error ? e.message : e}`);
    Deno.exit(1);
  }
}
