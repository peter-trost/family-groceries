import { assertEquals, assertThrows } from "@std/assert";
import {
  dictionaryUrl,
  migrationsUrl,
  parseDictionary,
  toMigration,
} from "./generate.ts";

Deno.test("the newest dictionary migration is generated from dictionary.tsv", async () => {
  const names: string[] = [];
  for await (const entry of Deno.readDir(migrationsUrl)) {
    if (entry.name.includes("_classifier_dictionary")) names.push(entry.name);
  }
  const newest = names.sort().at(-1)!;
  const migration = await Deno.readTextFile(new URL(newest, migrationsUrl));
  const expected = toMigration(
    parseDictionary(await Deno.readTextFile(dictionaryUrl)),
  );
  assertEquals(migration, expected, `regenerate ${newest} with generate.ts`);
});

Deno.test("the dictionary covers every category with several hundred terms", async () => {
  const terms = parseDictionary(await Deno.readTextFile(dictionaryUrl));
  const perCategory = Object.groupBy(terms, (t) => t.category);
  assertEquals(Object.keys(perCategory).length, 10);
  for (const [category, list] of Object.entries(perCategory)) {
    if (list!.length < 30) {
      throw new Error(`${category} has only ${list!.length} terms`);
    }
  }
  if (terms.length < 600) throw new Error(`only ${terms.length} terms`);
});

Deno.test("malformed lines are refused with their line number", () => {
  assertThrows(
    () => parseDictionary("milch\tchilled\nmilch\tdrinks"),
    Error,
    "repeats line 1",
  );
  assertThrows(
    () => parseDictionary("# x\nMilch\tchilled"),
    Error,
    "dictionary.tsv:2",
  );
  assertThrows(
    () => parseDictionary("milch\tdairy"),
    Error,
    "unknown category",
  );
  assertThrows(() => parseDictionary("milch chilled"), Error, "expected");
});
