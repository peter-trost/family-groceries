import { assertEquals, assertThrows } from '@std/assert';
import { fold, resolve, ToolError } from './list.ts';

const categories = [
  { id: '00000000-0000-0000-0000-000000000001', name: 'Obst & Gemüse' },
  { id: '00000000-0000-0000-0000-000000000002', name: 'Kühlregal' },
  { id: '00000000-0000-0000-0000-000000000003', name: '👶 Drogerie' },
  { id: '00000000-0000-0000-0000-000000000004', name: 'Süßes & Snacks' },
];
const items = [
  { id: 'a0000000-0000-0000-0000-000000000001', name: 'Milch' },
  { id: 'a0000000-0000-0000-0000-000000000002', name: 'Hafermilch' },
  { id: 'a0000000-0000-0000-0000-000000000003', name: 'Gurken' },
  { id: 'a0000000-0000-0000-0000-000000000004', name: 'Gurkenwasser' },
];

Deno.test('fold ignores case, umlauts, emoji and punctuation', () => {
  assertEquals(fold('👶 Drogerie'), 'drogerie');
  assertEquals(fold('Süßes & Snacks'), 'suessessnacks');
  assertEquals(fold('KÜHLREGAL'), fold('kuehlregal'));
});

Deno.test('resolve finds by id, folded exact name, or unique partial name', () => {
  assertEquals(
    resolve(categories, '00000000-0000-0000-0000-000000000002', 'Kategorie').name,
    'Kühlregal',
  );
  assertEquals(resolve(categories, 'kuehlregal', 'Kategorie').name, 'Kühlregal');
  assertEquals(resolve(categories, 'Drogerie', 'Kategorie').name, '👶 Drogerie');
  assertEquals(resolve(categories, 'obst', 'Kategorie').name, 'Obst & Gemüse');
  assertEquals(resolve(categories, 'Süßes', 'Kategorie').name, 'Süßes & Snacks');
});

Deno.test('an exact name wins over longer names containing it', () => {
  assertEquals(resolve(items, 'milch', 'Eintrag').name, 'Milch');
  assertEquals(resolve(items, 'Gurken', 'Eintrag').name, 'Gurken');
});

Deno.test('ambiguous and unknown names are tool errors that name the options', () => {
  const ambiguous = assertThrows(() => resolve(items, 'gurk', 'Eintrag'), ToolError);
  assertEquals(ambiguous.message, 'Eintrag „gurk“ ist nicht eindeutig: Gurken, Gurkenwasser.');
  const unknown = assertThrows(() => resolve(items, 'Brot', 'Eintrag'), ToolError);
  assertEquals(
    unknown.message,
    'Eintrag „Brot“ nicht gefunden. Vorhanden: Milch, Hafermilch, Gurken, Gurkenwasser.',
  );
  assertThrows(() => resolve(items, '!!!', 'Eintrag'), ToolError);
});
