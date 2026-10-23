// Splits one dictated German sentence into list items:
// "Wir brauchen Milch, zwei Gurken und eine Packung Eier"
//   -> Milch | 2 Gurken | 1 Packung Eier.

export interface ParsedItem {
  name: string;
  /** Spoken amount ("2", "1 kg", "3 Packungen"); null when none was said. */
  quantity: string | null;
}

export const maxItems = 30;
const maxNameLength = 120;

/** Words that separate items. */
const separators = new Set([
  ',',
  ';',
  ':',
  '&',
  '+',
  'und',
  'u',
  'sowie',
  'noch',
  'auch',
  'außerdem',
  'ausserdem',
  'plus',
]);

const words = (phrases: string) => phrases.split('|').map((p) => p.split(' '));
const cross = (...parts: string[][]) =>
  parts.reduce<string[][]>(
    (acc, options) => acc.flatMap((head) => options.map((o) => o ? [...head, o] : head)),
    [[]],
  );

/** "auf die Liste", "zu meiner Einkaufsliste", "in den Einkaufszettel", ... */
const onTheList = cross(
  ['auf', 'in', 'zu', 'zur'],
  ['', 'die', 'den', 'der', 'meine', 'meinen', 'meiner', 'unsere', 'unseren', 'unserer'],
  ['liste', 'einkaufsliste', 'einkaufszettel', 'zettel'],
);

/**
 * Filler before an item ("bitte", "wir brauchen", "kannst du"). Stripped
 * repeatedly, so "Kannst du bitte noch" peels off piece by piece.
 */
const leadingFiller = [
  ...words(
    'hey siri|siri|okay|ok|also|ach ja|ach so|achso|ach|äh|ähm|ehm|hm|hmm|so|ja|dann|' +
      'bitte|mal|danke|doch|eben|halt|unbedingt|dringend|mehr|mal sehen|' +
      'wir brauchen|wir bräuchten|ich brauche|ich bräuchte|brauchen|brauche|' +
      'wir haben|wir haben kein|wir haben keine|wir haben keinen|' +
      'es gibt kein|es gibt keine|es gibt keinen|' +
      'es fehlt|es fehlen|uns fehlt|uns fehlen|uns geht|uns gehen|' +
      'kannst du|könntest du|kannst du mir|könntest du mir|' +
      'wir müssen|ich muss|wir sollten|ich möchte|wir möchten|ich hätte gern|' +
      'ich hätte gerne|ich will|wir wollen|vergiss nicht|vergiss|denk an|denke an|' +
      'schreib|schreibe|notier|notiere|setz|setze|füg|füge|' +
      'pack|packe|kauf|kaufe|kauft|hol|hole|bring|bringe|' +
      'etwas|ein bisschen|einige|viel|viele|kein|keine|keinen|der|die|das|den|dem',
  ),
  ...onTheList,
];

/** Filler after an item ("auf die Liste setzen", "bitte", "mehr"). */
const trailingFiller = [
  ...words(
    'bitte|danke|mehr|mal|da|mehr da|auf|hinzu|hinzufügen|dazu|mit|setzen|schreiben|' +
      'aufschreiben|notieren|kaufen|holen|mitbringen|besorgen|brauchen|nötig|' +
      'nicht vergessen|vergessen|nicht|ist alle|sind alle|ist leer|sind leer|ist aus|aus',
  ),
  ...onTheList.flatMap((place) =>
    ['', 'setzen', 'schreiben', 'hinzu', 'hinzufügen', 'packen'].map((verb) =>
      verb ? [...place, verb] : place
    )
  ),
];

const ones: Record<string, number> = {
  ein: 1,
  eins: 1,
  zwei: 2,
  drei: 3,
  vier: 4,
  fünf: 5,
  sechs: 6,
  sieben: 7,
  acht: 8,
  neun: 9,
};

const tens: Record<string, number> = {
  zwanzig: 20,
  dreißig: 30,
  dreissig: 30,
  vierzig: 40,
  fünfzig: 50,
  sechzig: 60,
  siebzig: 70,
  achtzig: 80,
  neunzig: 90,
};

const numberWords: Record<string, number> = {
  ...ones,
  ...tens,
  eine: 1,
  einen: 1,
  einer: 1,
  eines: 1,
  einem: 1,
  zehn: 10,
  elf: 11,
  zwölf: 12,
  dreizehn: 13,
  vierzehn: 14,
  fünfzehn: 15,
  sechzehn: 16,
  siebzehn: 17,
  achtzehn: 18,
  neunzehn: 19,
  hundert: 100,
  einhundert: 100,
  zweihundert: 200,
  dreihundert: 300,
  fünfhundert: 500,
  tausend: 1000,
  eintausend: 1000,
  anderthalb: 1.5,
  eineinhalb: 1.5,
  zweieinhalb: 2.5,
};

/** Spoken unit -> how it is written, singular and plural. */
interface Unit {
  one: string;
  many: string;
}

const abbreviation = (short: string): Unit => ({ one: short, many: short });
const noun = (one: string, many = one): Unit => ({ one, many });

const units: Record<string, Unit> = {
  kg: abbreviation('kg'),
  kilo: abbreviation('kg'),
  kilos: abbreviation('kg'),
  kilogramm: abbreviation('kg'),
  g: abbreviation('g'),
  gr: abbreviation('g'),
  gramm: abbreviation('g'),
  pfund: noun('Pfund'),
  l: abbreviation('l'),
  liter: abbreviation('l'),
  ml: abbreviation('ml'),
  milliliter: abbreviation('ml'),
  packung: noun('Packung', 'Packungen'),
  packungen: noun('Packung', 'Packungen'),
  pck: noun('Packung', 'Packungen'),
  pkg: noun('Packung', 'Packungen'),
  pack: noun('Pack', 'Packs'),
  packs: noun('Pack', 'Packs'),
  päckchen: noun('Päckchen'),
  paket: noun('Paket', 'Pakete'),
  pakete: noun('Paket', 'Pakete'),
  sixpack: noun('Sixpack', 'Sixpacks'),
  dose: noun('Dose', 'Dosen'),
  dosen: noun('Dose', 'Dosen'),
  büchse: noun('Büchse', 'Büchsen'),
  büchsen: noun('Büchse', 'Büchsen'),
  flasche: noun('Flasche', 'Flaschen'),
  flaschen: noun('Flasche', 'Flaschen'),
  glas: noun('Glas', 'Gläser'),
  gläser: noun('Glas', 'Gläser'),
  becher: noun('Becher'),
  tüte: noun('Tüte', 'Tüten'),
  tüten: noun('Tüte', 'Tüten'),
  beutel: noun('Beutel'),
  sack: noun('Sack', 'Säcke'),
  säcke: noun('Sack', 'Säcke'),
  netz: noun('Netz', 'Netze'),
  netze: noun('Netz', 'Netze'),
  bund: noun('Bund'),
  stück: noun('Stück'),
  stk: noun('Stück'),
  st: noun('Stück'),
  kiste: noun('Kiste', 'Kisten'),
  kisten: noun('Kiste', 'Kisten'),
  kasten: noun('Kasten', 'Kästen'),
  kästen: noun('Kasten', 'Kästen'),
  karton: noun('Karton', 'Kartons'),
  kartons: noun('Karton', 'Kartons'),
  rolle: noun('Rolle', 'Rollen'),
  rollen: noun('Rolle', 'Rollen'),
  tafel: noun('Tafel', 'Tafeln'),
  tafeln: noun('Tafel', 'Tafeln'),
  schale: noun('Schale', 'Schalen'),
  schalen: noun('Schale', 'Schalen'),
  laib: noun('Laib', 'Laibe'),
  laibe: noun('Laib', 'Laibe'),
  scheibe: noun('Scheibe', 'Scheiben'),
  scheiben: noun('Scheibe', 'Scheiben'),
  riegel: noun('Riegel'),
  tube: noun('Tube', 'Tuben'),
  tuben: noun('Tube', 'Tuben'),
  stange: noun('Stange', 'Stangen'),
  stangen: noun('Stange', 'Stangen'),
  kopf: noun('Kopf', 'Köpfe'),
  köpfe: noun('Kopf', 'Köpfe'),
  paar: noun('Paar'),
  dutzend: noun('Dutzend'),
};

/** "3x Joghurt", "3 mal Joghurt": a count, not a unit. */
const multipliers = new Set(['x', '×', 'mal']);

/** Words that link a unit to its item ("eine Packung von den Eiern"). */
const linkWords = new Set(['von', 'vom', 'mit']);

/** A number after these is part of the name: "Windeln Größe 4", "Mehl Typ 405". */
const sizeWords = new Set([
  'größe',
  'grösse',
  'gr',
  'typ',
  'type',
  'nr',
  'stufe',
  'klasse',
  'size',
]);

/** Abbreviations whose dot does not end a sentence ("2 Stk. Butter"). */
const abbreviationDot = /\b(stk|st|pck|pkg|gr|nr|ca|bzw|etc|usw|u)\.(?=\s|$)/gi;

/** Numbers stay whole ("1,5", "1.000", "1,5-Liter-Flasche"); punctuation is its own token. */
const tokenPattern = /\d+(?:[.,]\d+)+[^\s,;:&]*|[,;:&]|[^\s,;:&]+/g;

/** Reads one number token: digits ("2", "1,5", "500g", "3x") or a German number word. */
function readNumber(token: string): { value: number; glued: string } | null {
  const digits = /^(\d{1,3}(?:\.\d{3})+|0|[1-9]\d*|(?:0|[1-9]\d*)[.,]\d+)(\p{L}*|×)$/u.exec(token);
  if (digits) {
    const [, number, glued] = digits;
    const value =
      /\.\d{3}/.test(number) && !number.includes(',') && number.split('.')[1].length === 3
        ? Number(number.replaceAll('.', ''))
        : Number(number.replace(',', '.'));
    return { value, glued };
  }
  const word = token.toLowerCase();
  const times = word.endsWith('mal') && word !== 'mal' ? word.slice(0, -3) : null;
  const spoken = numberWords[times ?? word] ??
    (() => {
      const compound = /^(ein|zwei|drei|vier|fünf|sechs|sieben|acht|neun)und(\p{L}+)$/u.exec(
        times ?? word,
      );
      return compound && compound[2] in tens ? ones[compound[1]] + tens[compound[2]] : undefined;
    })();
  return spoken === undefined ? null : { value: spoken, glued: '' };
}

const formatNumber = (n: number) => String(n).replace('.', ',');
const amountOf = (n: number, unit: Unit | null) =>
  unit ? `${formatNumber(n)} ${n > 1 ? unit.many : unit.one}` : formatNumber(n);

/** True for "eine Gurke": an indefinite article, not a count the user means to record. */
const isArticle = (token: string) => /^ein(e|en|er|es|em)?$/i.test(token);
const isHalf = (token: string) => /^halb(e|en|er|es)?$/i.test(token);

const lower = (tokens: string[]) => tokens.map((t) => t.toLowerCase());

function startsWith(tokens: string[], phrase: string[]): boolean {
  const head = lower(tokens.slice(0, phrase.length));
  return phrase.every((word, i) => head[i] === word);
}

function endsWith(tokens: string[], phrase: string[]): boolean {
  const tail = lower(tokens.slice(tokens.length - phrase.length));
  return tokens.length >= phrase.length && phrase.every((word, i) => tail[i] === word);
}

/** Phrases keyed by the word they start (or end) with, longest first. */
function indexBy(phrases: string[][], key: (phrase: string[]) => string) {
  const index = new Map<string, string[][]>();
  for (const phrase of [...phrases].sort((a, b) => b.length - a.length)) {
    index.set(key(phrase), [...(index.get(key(phrase)) ?? []), phrase]);
  }
  return index;
}

const leadingIndex = indexBy(leadingFiller, (p) => p[0]);
const trailingIndex = indexBy(trailingFiller, (p) => p[p.length - 1]);

function stripFiller(tokens: string[]): string[] {
  let rest = tokens;
  for (let changed = true; changed && rest.length;) {
    changed = false;
    const lead = leadingIndex.get(rest[0].toLowerCase())?.find((p) => startsWith(rest, p));
    if (lead) {
      rest = rest.slice(lead.length);
      changed = true;
    }
    if (!rest.length) break;
    const trail = trailingIndex.get(rest[rest.length - 1].toLowerCase())
      ?.find((p) => endsWith(rest, p));
    if (trail) {
      rest = rest.slice(0, rest.length - trail.length);
      changed = true;
    }
  }
  return rest;
}

/** One segment: an item, or only an amount for the item before it ("Äpfel, ein Kilo"). */
type Piece = { name: string; quantity: string | null } | { name: null; quantity: string };

/** Reads one segment, with its amount at the start ("2 kg Mehl") or the end ("Mehl 2 kg"). */
function readPiece(segment: string[]): Piece | null {
  let tokens = stripFiller(segment);
  if (startsWith(tokens, ['ein', 'paar']) && tokens[1] === 'paar') {
    return piece(tokens.slice(2), 'ein paar');
  }
  if (tokens[0] === 'paar' && tokens.length > 1) return piece(tokens.slice(1), 'ein paar');

  let amount: number | null = null;
  let unit: Unit | null = null;
  let article = false;
  if (tokens.length > 1 && isHalf(tokens[0])) tokens = ['0,5', ...tokens.slice(1)];
  const first = tokens.length ? readNumber(tokens[0]) : null;
  const gluedUnit = first?.glued ? units[first.glued.toLowerCase()] : undefined;
  if (first && (!first.glued || gluedUnit || multipliers.has(first.glued.toLowerCase()))) {
    article = isArticle(tokens[0]);
    amount = first.value;
    unit = gluedUnit ?? null;
    tokens = tokens.slice(1);
    if (article && tokens.length > 1 && isHalf(tokens[0])) {
      amount = 0.5;
      article = false;
      tokens = tokens.slice(1);
    }
    if (!unit && tokens.length && multipliers.has(tokens[0].toLowerCase())) {
      tokens = tokens.slice(1);
    }
  }
  const next = tokens[0]?.toLowerCase();
  if (!unit && next in units && (amount !== null || tokens.length > 1)) {
    unit = units[next];
    tokens = tokens.slice(1);
    while (tokens.length > 1 && linkWords.has(tokens[0].toLowerCase())) tokens = tokens.slice(1);
    tokens = stripFiller(tokens);
  }

  if (amount === null && !unit) {
    const trailing = trailingAmount(tokens);
    if (trailing) return piece(trailing.rest, trailing.quantity);
    return piece(tokens, null);
  }
  if (unit) return piece(tokens, amountOf(amount ?? 1, unit));
  return piece(tokens, article && amount === 1 ? null : amountOf(amount!, null));
}

/** "Eier zehn Stück", "Milch 2 Liter", "Joghurt 3x": an amount said after the item. */
function trailingAmount(tokens: string[]): { rest: string[]; quantity: string } | null {
  const at = (i: number) => tokens[tokens.length - i];
  const allowed = (before: string | undefined) =>
    before !== undefined && !sizeWords.has(before.toLowerCase()) && !readNumber(before);

  const last = readNumber(at(1) ?? '');
  if (last && !isArticle(at(1)) && allowed(at(2))) {
    const unit = last.glued ? units[last.glued.toLowerCase()] : null;
    if (last.glued && !unit && !multipliers.has(last.glued.toLowerCase())) return null;
    return { rest: tokens.slice(0, -1), quantity: amountOf(last.value, unit) };
  }
  const unit = units[at(1)?.toLowerCase() ?? ''];
  const number = readNumber(at(2) ?? '');
  if (unit && number && !number.glued && !isArticle(at(2)) && allowed(at(3))) {
    return { rest: tokens.slice(0, -2), quantity: amountOf(number.value, unit) };
  }
  return null;
}

function piece(tokens: string[], quantity: string | null): Piece | null {
  const text = stripFiller(tokens).join(' ').replace(/^[\s.!?:-]+|[\s.!?:-]+$/g, '');
  if (!/\p{L}/u.test(text) || readNumber(text)?.glued === '') {
    return quantity ? { name: null, quantity } : null;
  }
  const name = (text[0].toUpperCase() + text.slice(1)).slice(0, maxNameLength).trim();
  return { name, quantity };
}

function segmentsOf(text: string): string[][] {
  const cleaned = text
    .normalize('NFC')
    .replace(abbreviationDot, '$1')
    .replace(/[.!?]+(\s|$)/g, ',$1');
  const segments: string[][] = [[]];
  for (const token of cleaned.match(tokenPattern) ?? []) {
    const current = segments[segments.length - 1];
    // "Salz- und Pfeffermühle" is one item.
    const joined = token === 'und' && current.at(-1)?.endsWith('-');
    if (separators.has(token.toLowerCase()) && !joined) segments.push([]);
    else current.push(token);
  }
  return segments.filter((s) => s.length);
}

/** Splits a dictated sentence into items, in the order spoken, without duplicates. */
export function parseSentence(text: string): ParsedItem[] {
  const items: ParsedItem[] = [];
  for (const segment of segmentsOf(text)) {
    const read = readPiece(segment);
    if (!read) continue;
    const previous = items.at(-1);
    if (read.name === null) {
      if (previous && previous.quantity === null) previous.quantity = read.quantity;
      continue;
    }
    if (items.some((item) => item.name.toLowerCase() === read.name.toLowerCase())) continue;
    if (items.length === maxItems) break;
    items.push({ name: read.name, quantity: read.quantity });
  }
  return items;
}

/** How an item is read back: "2 Gurken", "1 kg Mehl", "Milch". */
export const spoken = (item: ParsedItem) =>
  item.quantity ? `${item.quantity} ${item.name}` : item.name;
