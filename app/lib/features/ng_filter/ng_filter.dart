/// Offline NG-word filter for character names (SPEC §2-3). Dart port of
/// `firebase/functions/src/ngwords/ngFilter.ts`; the dictionary is the
/// byte-identical asset copy of `shared/ng_words/ng_words.json`.
///
/// This is only the cheap first layer: the server re-checks names (dictionary
/// + AI) before anything is shown online.
library;

import 'dart:convert';

import 'package:flutter/services.dart';

import 'normalize.dart';

export 'normalize.dart';

/// Asset key of the bundled copy of `shared/ng_words/ng_words.json`.
const ngWordsAssetKey = 'assets/ng_words/ng_words.json';

enum NgCategory { slur, sexual, violence, insult, personalInfo }

NgCategory _category(String name) => switch (name) {
  'slur' => NgCategory.slur,
  'sexual' => NgCategory.sexual,
  'violence' => NgCategory.violence,
  'insult' => NgCategory.insult,
  'personal_info' => NgCategory.personalInfo,
  _ => throw FormatException('unknown NG category $name'),
};

enum NgHitKind { substring, exact, pattern }

/// First NG hit. Never show [term] or [category] to children.
class NgHit {
  const NgHit(this.category, this.kind, this.term);
  final NgCategory category;
  final NgHitKind kind;
  final String term;
}

class NgFilter {
  NgFilter._({
    required this.version,
    required List<(String, NgCategory)> substring,
    required Map<String, NgCategory> exact,
    required List<(String, NgCategory, RegExp)> patterns,
    required Set<String> allowExact,
  }) : _substring = substring, // ignore: prefer_initializing_formals
       _exact = exact, // ignore: prefer_initializing_formals
       _patterns = patterns, // ignore: prefer_initializing_formals
       _allowExact = allowExact; // ignore: prefer_initializing_formals

  /// Compiles a parsed `ng_words.json`.
  factory NgFilter.fromJson(Map<String, Object?> json) {
    final fileNormalizer = json['normalizerVersion'];
    if (fileNormalizer != normalizerVersion) {
      throw FormatException(
        'ng_words.json normalizerVersion $fileNormalizer != $normalizerVersion',
      );
    }
    final substring = <(String, NgCategory)>[];
    final exact = <String, NgCategory>{};
    final categories = (json['categories']! as Map).cast<String, Object?>();
    for (final cat in categories.entries) {
      final category = _category(cat.key);
      for (final lists in (cat.value! as Map).values) {
        final l = (lists as Map).cast<String, Object?>();
        for (final w in (l['substring']! as List).cast<String>()) {
          final term = normalizeForMatch(w);
          if (term.isNotEmpty) substring.add((term, category));
        }
        for (final w in (l['exact']! as List).cast<String>()) {
          final term = normalizeForMatch(w);
          if (term.isNotEmpty) exact[term] = category;
        }
      }
    }
    return NgFilter._(
      version: json['version']! as int,
      substring: substring,
      exact: exact,
      patterns: [
        for (final p in (json['patterns']! as List).cast<Map>())
          (
            p['id']! as String,
            _category(p['category']! as String),
            RegExp(p['regex']! as String, unicode: true),
          ),
      ],
      allowExact: {
        for (final w in (json['allowExact']! as List).cast<String>())
          normalizeForMatch(w),
      },
    );
  }

  factory NgFilter.fromJsonString(String source) =>
      NgFilter.fromJson((jsonDecode(source) as Map).cast<String, Object?>());

  /// Loads the bundled dictionary.
  static Future<NgFilter> load([AssetBundle? bundle]) async =>
      NgFilter.fromJsonString(
        await (bundle ?? rootBundle).loadString(ngWordsAssetKey),
      );

  /// `version` of the dictionary.
  final int version;
  final List<(String, NgCategory)> _substring;
  final Map<String, NgCategory> _exact;
  final List<(String, NgCategory, RegExp)> _patterns;
  final Set<String> _allowExact;

  /// Returns the first NG hit for [text], or null when it is clean. Same
  /// evaluation order as the server.
  NgHit? findNgWord(String text) {
    final patternForm = normalizeForPatterns(text);
    for (final (id, category, re) in _patterns) {
      if (re.hasMatch(patternForm)) {
        return NgHit(category, NgHitKind.pattern, id);
      }
    }
    final m = normalizeForMatch(text);
    if (m.isEmpty || _allowExact.contains(m)) return null;
    final exactCat = _exact[m];
    if (exactCat != null) return NgHit(exactCat, NgHitKind.exact, m);
    for (final (term, category) in _substring) {
      if (m.contains(term)) return NgHit(category, NgHitKind.substring, term);
    }
    return null;
  }

  bool isClean(String text) => findNgWord(text) == null;
}
