import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'ng_filter.dart';

/// Character-name rules shared with the server
/// (`firebase/functions/src/names/validateName.ts`), so a name accepted
/// offline is not rejected as NAME_INVALID later.
const int nameMaxLength = 10;
const int _maxDigits = 2;
final RegExp _nameChars = RegExp(
  r'^[ぁ-ゖァ-ヺー・々a-zA-Z0-9一-鿿㐀-䶿]+$',
  unicode: true,
);

enum NameProblem {
  empty(''),
  tooLong('なまえは 10もじ までだよ'),
  invalidChars('ひらがな・カタカナ・かんじ・えいご・すうじで かいてね'),
  tooManyDigits('すうじは 2つ までだよ'),
  ng('その なまえは つかえないよ。ほかの なまえに してね');

  const NameProblem(this.message);

  /// Gentle hiragana message for children.
  final String message;
}

/// NFKC + trim (the form the server stores).
String canonicalName(String raw) => unorm.nfkc(raw).trim();

/// Returns the first problem with [raw], or null when it can be used.
NameProblem? checkCharacterName(String raw, NgFilter filter) {
  final name = canonicalName(raw);
  final len = name.runes.length;
  if (len == 0) return NameProblem.empty;
  if (len > nameMaxLength) return NameProblem.tooLong;
  if (!_nameChars.hasMatch(name)) return NameProblem.invalidChars;
  if (RegExp('[0-9]').allMatches(name).length > _maxDigits) {
    return NameProblem.tooManyDigits;
  }
  if (!filter.isClean(name)) return NameProblem.ng;
  return null;
}

/// Safe preset names (same list as the server's presetNames.ts).
const presetCharacterNames = [
  'もこたん', 'ぴかりん', 'ぷにまる', 'ころりん', 'ふわりん', 'ぽよまる', //
  'きらりん', 'どんぐり', 'まめたろう', 'ぽんた', 'にこまる', 'ぷっくん',
  'ちびすけ', 'もちもち', 'ぴょんた', 'ほっぺ', 'くるりん', 'ぱたぱた',
  'ぴよすけ', 'まるたん', 'ゆきんこ', 'ほしまる', 'にじまる', 'かぜのすけ',
];

/// [count] preset names chosen deterministically from [seed] (e.g. the image
/// hash) so the same drawing always gets the same suggestions.
List<String> presetNamesFor(String seed, {int count = 3}) {
  var h = 0;
  for (final c in seed.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  final pool = [...presetCharacterNames];
  final out = <String>[];
  while (out.length < count && pool.isNotEmpty) {
    out.add(pool.removeAt(h % pool.length));
    h = (h * 1103515245 + 12345) & 0x7fffffff;
  }
  return out;
}
