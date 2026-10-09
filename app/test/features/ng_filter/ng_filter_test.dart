import 'dart:convert';
import 'dart:io';

import 'package:doodle_battle/features/ng_filter/ng_filter.dart';
import 'package:flutter_test/flutter_test.dart';

const _shared = '../shared/ng_words';

Map<String, Object?> _json(String name) =>
    (jsonDecode(File('$_shared/$name').readAsStringSync()) as Map)
        .cast<String, Object?>();

String _categoryName(NgCategory c) =>
    c == NgCategory.personalInfo ? 'personal_info' : c.name;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled asset is byte-identical to shared/ng_words/ng_words.json', () {
    expect(
      File('assets/ng_words/ng_words.json').readAsBytesSync(),
      File('$_shared/ng_words.json').readAsBytesSync(),
      reason: 'run `dart run tool/sync_ng_words.dart`',
    );
  });

  group('normalize_vectors.json', () {
    final file = _json('normalize_vectors.json');
    test('normalizer version matches', () {
      expect(file['normalizerVersion'], normalizerVersion);
    });
    final vectors = (file['vectors']! as List).cast<Map>();
    test('has vectors', () => expect(vectors, isNotEmpty));
    for (final v in vectors) {
      final input = v['input']! as String;
      test('${v['note']}: "$input"', () {
        expect(normalizeForMatch(input), v['match'], reason: 'match form');
        expect(normalizeForPatterns(input), v['pattern'],
            reason: 'pattern form');
      });
    }
  });

  group('ng_check_vectors.json', () {
    final file = _json('ng_check_vectors.json');
    final filter = NgFilter.fromJson(_json('ng_words.json'));
    test('dictionary version matches vectors', () {
      expect(filter.version, file['ngWordsVersion']);
    });
    final vectors = (file['vectors']! as List).cast<Map>();
    test('has vectors', () => expect(vectors, isNotEmpty));
    for (final v in vectors) {
      final input = v['input']! as String;
      test('"$input" blocked=${v['blocked']}', () {
        final hit = filter.findNgWord(input);
        expect(hit != null, v['blocked']);
        expect(hit == null ? null : _categoryName(hit.category), v['category']);
      });
    }
  });

  test('loads from the asset bundle', () async {
    final filter = await NgFilter.load();
    expect(filter.isClean('ねこまる'), isTrue);
    expect(filter.isClean('090-1234-5678'), isFalse);
  });
}
