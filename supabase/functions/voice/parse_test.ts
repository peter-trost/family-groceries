import { assertEquals } from '@std/assert';
import { maxItems, parseSentence, spoken } from './parse.ts';

/** Sentence -> items as read back ("2 Gurken"). */
const cases: [string, string[]][] = [
  // The spec's example and plain lists.
  ['Milch, zwei Gurken und Klopapier', ['Milch', '2 Gurken', 'Klopapier']],
  ['Milch', ['Milch']],
  ['milch', ['Milch']],
  ['Milch.', ['Milch']],
  ['Milch und Eier', ['Milch', 'Eier']],
  ['Milch, Eier, Brot', ['Milch', 'Eier', 'Brot']],
  ['Milch Eier', ['Milch Eier']],
  ['Butter sowie Käse', ['Butter', 'Käse']],
  ['Butter; Käse', ['Butter', 'Käse']],
  ['Brot & Butter', ['Brot', 'Butter']],
  ['Salz und Pfeffer und Zucker', ['Salz', 'Pfeffer', 'Zucker']],
  ['Milch, und Eier', ['Milch', 'Eier']],
  ['Milch und noch Eier', ['Milch', 'Eier']],
  ['Milch, außerdem Eier', ['Milch', 'Eier']],
  ['Milch. Eier. Brot.', ['Milch', 'Eier', 'Brot']],
  ['Milch! Und Eier?', ['Milch', 'Eier']],
  ['Milch plus Eier', ['Milch', 'Eier']],
  ['Milch oder Sahne', ['Milch oder Sahne']],

  // Filler around the list.
  ['Bitte Milch', ['Milch']],
  ['Milch bitte', ['Milch']],
  ['Wir brauchen Milch und Brot', ['Milch', 'Brot']],
  ['Wir brauchen noch Milch', ['Milch']],
  ['Ich brauche Eier', ['Eier']],
  ['Schreib auf: Milch und Eier', ['Milch', 'Eier']],
  ['Schreib Milch auf', ['Milch']],
  ['Schreib bitte Milch und Eier auf die Liste', ['Milch', 'Eier']],
  ['Setz Butter auf die Einkaufsliste', ['Butter']],
  ['Setze bitte Butter auf die Liste', ['Butter']],
  ['Füg Joghurt hinzu', ['Joghurt']],
  ['Kauf bitte noch Brot', ['Brot']],
  ['Wir haben keine Milch mehr', ['Milch']],
  ['Es fehlt Zucker', ['Zucker']],
  ['Hey Siri, Milch', ['Milch']],
  ['Äh, Milch und ähm Eier', ['Milch', 'Eier']],
  ['Milch, Eier, danke', ['Milch', 'Eier']],
  ['Ach ja, auch noch Kaffee', ['Kaffee']],
  ['Dann noch Bananen', ['Bananen']],
  ['Milch auch', ['Milch']],
  ['Bitte etwas Ingwer', ['Ingwer']],
  ['Die Milch und das Brot', ['Milch', 'Brot']],

  // Number words and digits.
  ['zwei Gurken', ['2 Gurken']],
  ['Zwei Gurken', ['2 Gurken']],
  ['2 Gurken', ['2 Gurken']],
  ['drei Paprika', ['3 Paprika']],
  ['zehn Eier', ['10 Eier']],
  ['zwölf Eier', ['12 Eier']],
  ['zwanzig Teelichter', ['20 Teelichter']],
  ['fünfundzwanzig Servietten', ['25 Servietten']],
  ['eine Gurke', ['Gurke']],
  ['ein Brot', ['Brot']],
  ['einen Kohlrabi', ['Kohlrabi']],
  ['eins Brot', ['1 Brot']],
  ['ein paar Äpfel', ['ein paar Äpfel']],
  ['ein Dutzend Eier', ['1 Dutzend Eier']],
  ['Eier zehn Stück', ['10 Stück Eier']],
  ['Eier 10', ['10 Eier']],
  ['Gurken zwei', ['2 Gurken']],

  // Units.
  ['1 kg Mehl', ['1 kg Mehl']],
  ['1kg Mehl', ['1 kg Mehl']],
  ['ein Kilo Äpfel', ['1 kg Äpfel']],
  ['zwei Kilo Kartoffeln', ['2 kg Kartoffeln']],
  ['500 g Hackfleisch', ['500 g Hackfleisch']],
  ['500g Hackfleisch', ['500 g Hackfleisch']],
  ['500 Gramm Hackfleisch', ['500 g Hackfleisch']],
  ['ein halbes Kilo Hackfleisch', ['0,5 kg Hackfleisch']],
  ['ein Pfund Kaffee', ['1 Pfund Kaffee']],
  ['1,5 l Milch', ['1,5 l Milch']],
  ['1,5l Milch', ['1,5 l Milch']],
  ['zwei Liter Milch', ['2 l Milch']],
  ['einen Liter Milch', ['1 l Milch']],
  ['Milch 2 Liter', ['2 l Milch']],
  ['eine Packung Eier', ['1 Packung Eier']],
  ['zwei Packungen Eier', ['2 Packungen Eier']],
  ['drei Packung Eier', ['3 Packungen Eier']],
  ['Packung Eier', ['1 Packung Eier']],
  ['eine Packung von den Eiern', ['1 Packung Eiern']],
  ['zwei Dosen Tomaten', ['2 Dosen Tomaten']],
  ['eine Dose Mais', ['1 Dose Mais']],
  ['ein Glas Gurken', ['1 Glas Gurken']],
  ['zwei Gläser Honig', ['2 Gläser Honig']],
  ['einen Kasten Wasser', ['1 Kasten Wasser']],
  ['Kasten Bier', ['1 Kasten Bier']],
  ['zwei Flaschen Wein', ['2 Flaschen Wein']],
  ['ein Bund Petersilie', ['1 Bund Petersilie']],
  ['drei Becher Joghurt', ['3 Becher Joghurt']],
  ['eine Tafel Schokolade', ['1 Tafel Schokolade']],
  ['zwei Tafeln Schokolade', ['2 Tafeln Schokolade']],
  ['eine Tube Zahnpasta', ['1 Tube Zahnpasta']],
  ['ein Netz Zwiebeln', ['1 Netz Zwiebeln']],
  ['vier Rollen Küchenpapier', ['4 Rollen Küchenpapier']],
  ['zwei Paar Socken', ['2 Paar Socken']],
  ['ein Stück Parmesan', ['1 Stück Parmesan']],

  // Mixed sentences as Siri dictates them.
  [
    'Wir brauchen Milch, zwei Gurken, eine Packung Eier und 1 kg Mehl.',
    ['Milch', '2 Gurken', '1 Packung Eier', '1 kg Mehl'],
  ],
  [
    'Schreib bitte Windeln, Feuchttücher sowie zwei Packungen Klopapier auf',
    ['Windeln', 'Feuchttücher', '2 Packungen Klopapier'],
  ],
  ['Milch und noch zwei Gurken und auch Klopapier', ['Milch', '2 Gurken', 'Klopapier']],
  ['Brot, Butter und ein Kasten Wasser bitte', ['Brot', 'Butter', '1 Kasten Wasser']],
  ['Bananen Äpfel und Birnen', ['Bananen Äpfel', 'Birnen']],

  // The examples in docs/SIRI_SHORTCUT.md.
  ['Wir brauchen noch Butter und Eier', ['Butter', 'Eier']],
  ['Schreib bitte Windeln auf die Liste', ['Windeln']],
  ['Ein Kilo Äpfel und 500 Gramm Hackfleisch', ['1 kg Äpfel', '500 g Hackfleisch']],
  ['Eine Packung Eier sowie zwei Flaschen Wein', ['1 Packung Eier', '2 Flaschen Wein']],
  ['Einen Kasten Wasser, auch Kaffee', ['1 Kasten Wasser', 'Kaffee']],

  // Found by an adversarial review: questions, modal verbs, "meine Liste".
  ['Kannst du Milch und Eier aufschreiben?', ['Milch', 'Eier']],
  ['Kannst du noch Brot auf die Liste setzen', ['Brot']],
  ['Könntest du mir bitte Käse aufschreiben', ['Käse']],
  ['Wir müssen noch Milch kaufen', ['Milch']],
  ['Wir haben noch Milch', ['Milch']],
  ['Hey Siri, schreib Milch und Eier auf meine Einkaufsliste', ['Milch', 'Eier']],
  ['Milch auf meine Einkaufsliste', ['Milch']],
  ['Füge Milch zu meiner Einkaufsliste hinzu', ['Milch']],
  ['Schreibe auf die Liste Milch', ['Milch']],
  ['Bring bitte Milch mit', ['Milch']],
  ['Schreib doch noch Käse auf', ['Käse']],
  ['Wir brauchen dringend Windeln', ['Windeln']],
  ['Milch nicht vergessen', ['Milch']],
  ['Vergiss die Milch nicht', ['Milch']],
  ['Die Milch ist alle', ['Milch']],
  ['Eier sind alle', ['Eier']],
  ['Uns geht die Milch aus', ['Milch']],
  ['Kein Brot mehr da', ['Brot']],
  ['Mehr Milch', ['Milch']],
  ['Ausserdem Milch', ['Milch']],
  ['Ach so, Milch', ['Milch']],
  ['Hm, Milch', ['Milch']],

  // Numbers that belong to the name.
  ['Windeln Größe 4', ['Windeln Größe 4']],
  ['Pampers Größe 5', ['Pampers Größe 5']],
  ['Windeln Größe vier', ['Windeln Größe vier']],
  ['Mehl Typ 405', ['Mehl Typ 405']],
  ['Mehl Type 550, 1 kg', ['1 kg Mehl Type 550']],
  ['Spaghetti Nr. 5', ['Spaghetti Nr 5']],
  ['Milch 1,5 %', ['Milch 1,5 %']],
  ['H-Milch 1,5%', ['H-Milch 1,5%']],
  ['1,5-Liter-Flasche Cola', ['1,5-Liter-Flasche Cola']],
  ['Zwei 1,5 Liter Flaschen Cola', ['2 1,5 Liter Flaschen Cola']],
  ['00 Mehl', ['00 Mehl']],
  ['7up', ['7up']],
  ['Salz- und Pfeffermühle', ['Salz- und Pfeffermühle']],
  ['C+A Gutschein', ['C+A Gutschein']],
  ['Milch + Eier', ['Milch', 'Eier']],

  // More amounts.
  ['1.000 g Mehl', ['1000 g Mehl']],
  ['ein halber Liter Sahne', ['0,5 l Sahne']],
  ['halbes Pfund Hack', ['0,5 Pfund Hack']],
  ['Äpfel, ein Kilo', ['1 kg Äpfel']],
  ['Erdbeeren, 500 g', ['500 g Erdbeeren']],
  ['Zucker, 2 Pfund', ['2 Pfund Zucker']],
  ['Gurken, zwei', ['2 Gurken']],
  ['Nassfutter für die Katze, 12 Dosen', ['12 Dosen Nassfutter für die Katze']],
  ['2 Stk. Butter', ['2 Stück Butter']],
  ['1 Pck. Backpulver', ['1 Packung Backpulver']],
  ['Milch u. Eier', ['Milch', 'Eier']],
  ['3x Joghurt', ['3 Joghurt']],
  ['3 x Joghurt', ['3 Joghurt']],
  ['Joghurt 3x', ['3 Joghurt']],
  ['zweimal Joghurt', ['2 Joghurt']],
  ['dreißig Eier', ['30 Eier']],
  ['dreissig Eier', ['30 Eier']],
  ['paar Brötchen', ['ein paar Brötchen']],
  ['ein Paar Socken', ['1 Paar Socken']],
  ['ein Sixpack Bier', ['1 Sixpack Bier']],
  ['Kilo', ['Kilo']],
  ['500 g', []],

  // From review 0.
  ['vierhundert Gramm Hack', ['400 g Hack']],
  ['zweihundertfünfzig Gramm Butter', ['250 g Butter']],
  ['einhundert Gramm Salami', ['100 g Salami']],
  ['Käse, ca. 200 g', ['200 g Käse']],
  ['etwa ein Kilo Kartoffeln', ['1 kg Kartoffeln']],
  ['Hey Siri Einkaufsliste Milch', ['Milch']],
  ['Windeln Größe 4, Windeln Größe 5', ['Windeln Größe 4', 'Windeln Größe 5']],

  // Compound names stay whole.
  ['Vollmilch', ['Vollmilch']],
  ['griechischer Joghurt', ['Griechischer Joghurt']],
  ['Brötchen mit Mohn', ['Brötchen mit Mohn']],
  ['Kunden Karte', ['Kunden Karte']],
  ['Schokoladeneis', ['Schokoladeneis']],

  // Duplicates and nothing.
  ['Milch und Milch', ['Milch']],
  ['Milch, milch', ['Milch']],
  ['', []],
  ['   ', []],
  ['und', []],
  ['bitte', []],
  ['Bitte, danke', []],
  [', , ,', []],
  ['...', []],
  ['2', []],
  ['zwei', []],
];

for (const [sentence, expected] of cases) {
  Deno.test(`parses ${JSON.stringify(sentence)}`, () => {
    assertEquals(parseSentence(sentence).map(spoken), expected);
  });
}

Deno.test('keeps quantity apart from the name', () => {
  assertEquals(parseSentence('zwei Gurken, 1 kg Mehl, Milch'), [
    { name: 'Gurken', quantity: '2' },
    { name: 'Mehl', quantity: '1 kg' },
    { name: 'Milch', quantity: null },
  ]);
});

Deno.test('stops at the item cap', () => {
  const sentence = Array.from({ length: 50 }, (_, i) => `Artikel${i}`).join(', ');
  assertEquals(parseSentence(sentence).length, maxItems);
});

Deno.test('caps a long name at 120 characters', () => {
  const [item] = parseSentence('a'.repeat(300));
  assertEquals(item.name.length, 120);
});

Deno.test('reads decomposed umlauts the same as composed ones', () => {
  assertEquals(parseSentence('Äpfel'), [{ name: 'Äpfel', quantity: null }]);
});
