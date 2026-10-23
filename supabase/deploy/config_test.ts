import { assert, assertEquals } from '@std/assert';
import { parse } from '@std/toml';

// `supabase functions deploy --use-api` uploads only the files a function imports, so bare
// specifiers ('jose', '@modelcontextprotocol/server') resolve only through an import map the
// function's config.toml section names.
Deno.test('every edge function names the shared import map in config.toml', async () => {
  const root = new URL('../', import.meta.url);
  const config = parse(await Deno.readTextFile(new URL('config.toml', root))) as {
    functions?: Record<string, { import_map?: string }>;
  };
  const functions: string[] = [];
  for await (const e of Deno.readDir(new URL('functions/', root))) {
    if (e.isDirectory && !e.name.startsWith('_')) functions.push(e.name);
  }
  assert(functions.length > 0);
  for (const name of functions.sort()) {
    assertEquals(
      config.functions?.[name]?.import_map,
      './functions/deno.json',
      `[functions.${name}] import_map`,
    );
  }
});
