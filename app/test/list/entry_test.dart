import 'package:family_groceries/list/entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cases = {
    'Milch': Entry('Milch', null),
    '  Milch  ': Entry('Milch', null),
    '2 Gurken': Entry('Gurken', '2'),
    '2x Milch': Entry('Milch', '2'),
    '2 x Milch': Entry('Milch', '2'),
    '500g Hackfleisch': Entry('Hackfleisch', '500 g'),
    '1,5 l Apfelsaft': Entry('Apfelsaft', '1,5 l'),
    '3 Dosen Tomaten': Entry('Tomaten', '3 Dosen'),
    'Hack 500 g': Entry('Hack', '500 g'),
    'Milch 2x': Entry('Milch', '2'),
    'Windeln Größe 4': Entry('Windeln Größe 4', null),
    '7up': Entry('7up', null),
    'Vitamin D3': Entry('Vitamin D3', null),
    'Eier   10': Entry('Eier 10', null),
  };
  for (final MapEntry(:key, :value) in cases.entries) {
    test('"$key" parses to $value', () => expect(parseEntry(key), value));
  }
}
