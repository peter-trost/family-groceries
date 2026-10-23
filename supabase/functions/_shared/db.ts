// Direct Postgres access for edge functions. Requests run as the signed-in user (role
// authenticated, auth.uid() = the user), so RLS, triggers and classify_item behave exactly as
// they do for the app. Only credential lookups run with the connection's own privileges.
import postgres from 'postgres';

export type Sql = postgres.Sql;
export type Tx = postgres.TransactionSql;

let pool: Sql | undefined;

function db(): Sql {
  pool ??= (() => {
    const url = new URL(Deno.env.get('SUPABASE_DB_URL')!);
    // The local stack names the database container supabase_db_<project>; Deno's resolvers
    // refuse underscores in hostnames. The container's network alias "db" points at the same
    // host. Hosted database URLs have no underscores.
    if (url.hostname.includes('_')) url.hostname = 'db';
    // prepare: false keeps it working behind Supavisor's transaction pooler.
    return postgres(url.toString(), { max: 3, prepare: false, idle_timeout: 30 });
  })();
  return pool;
}

/** Runs `work` in one transaction as `userId`, under RLS. */
export async function asUser<T>(userId: string, work: (tx: Tx) => Promise<T>): Promise<T> {
  const claims = JSON.stringify({ sub: userId, role: 'authenticated' });
  const result = await db().begin(async (tx) => {
    await tx`select set_config('role', 'authenticated', true),
                    set_config('request.jwt.claims', ${claims}, true)`;
    return await work(tx);
  });
  return result as T;
}

export async function householdOf(userId: string): Promise<string | null> {
  const sql = db();
  const [row] = await sql<{ household_id: string }[]>`
    select household_id from public.household_members where user_id = ${userId}`;
  return row?.household_id ?? null;
}

export async function resolvePersonalAccessToken(
  tokenHash: string,
): Promise<{ userId: string; householdId: string } | null> {
  const sql = db();
  const [row] = await sql<{ user_id: string; household_id: string }[]>`
    select user_id, household_id from public.authenticate_personal_access_token(${tokenHash})`;
  return row ? { userId: row.user_id, householdId: row.household_id } : null;
}
