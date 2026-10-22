import 'package:flutter/foundation.dart';

@immutable
class const Entry(final String name, final String? quantity) {
  @override
  bool operator ==(Object other) =>
      other is Entry && other.name == name && other.quantity == quantity;

  @override
  int get hashCode => Object.hash(name, quantity);

  @override
  String toString() => 'Entry($name, $quantity)';
}

const _units =
    'x|kg|g|gr|l|ml|stk|stück|pck|packung|packungen|dose|dosen|flasche|'
    'flaschen|bund|becher|glas|gläser|tüte|tüten|beutel|netz|kiste';

final _leading = RegExp(
  '^(\\d+(?:[.,]\\d+)?)(?:\\s*($_units)\\.?)?\\s+(.+)\$',
  caseSensitive: false,
);
final _trailing = RegExp(
  // A unit is required at the end: "Windeln Größe 4" is a name, not 4 Windeln.
  '^(.+?)\\s+(\\d+(?:[.,]\\d+)?)\\s*($_units)\\.?\$',
  caseSensitive: false,
);

/// Splits a typed line like "2 Gurken" or "Hack 500 g" into name and quantity.
/// The full German sentence splitter is a server concern (voice endpoint).
Entry parseEntry(String input) {
  final text = input.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (_leading.firstMatch(text) case final m?) {
    return Entry(m[3]!, _quantity(m[1]!, m[2]));
  }
  if (_trailing.firstMatch(text) case final m?) {
    return Entry(m[1]!, _quantity(m[2]!, m[3]));
  }
  return Entry(text, null);
}

String _quantity(String amount, String? unit) => switch (unit) {
  null => amount,
  final u when u.toLowerCase() == 'x' => amount,
  final u => '$amount $u',
};
