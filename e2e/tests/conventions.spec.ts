import { readdirSync, readFileSync } from 'node:fs';
import { expect, test } from './fixtures';

test('every spec takes test from ./fixtures, which closes the contexts it opens', () => {
  const dir = new URL('.', import.meta.url);
  const offenders = readdirSync(dir)
    .filter((f) => f.endsWith('.spec.ts'))
    .filter((f) => /from '@playwright\/test'/.test(readFileSync(new URL(f, dir), 'utf8')));
  expect(offenders, "import from './fixtures' instead of '@playwright/test'").toEqual([]);
});
