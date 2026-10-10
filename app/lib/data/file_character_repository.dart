import 'dart:io';
import 'dart:typed_data';

import '../domain/character.dart';
import 'character_repository.dart';
import 'json_file.dart';

/// Stores each character as `<root>/characters/<id>.json` + `<id>.png`
/// (root = app documents directory in the app).
class FileCharacterRepository implements CharacterRepository {
  FileCharacterRepository(Directory root)
    : _dir = Directory('${root.path}/characters');

  final Directory _dir;

  static final _validId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  File _json(String id) => File('${_dir.path}/$id.json');
  File _png(String id) => File('${_dir.path}/$id.png');

  void _checkId(String id) {
    if (!_validId.hasMatch(id)) throw ArgumentError.value(id, 'id');
  }

  @override
  String imagePathFor(String id) => _png(id).path;

  @override
  Future<List<Character>> loadAll() async {
    if (!await _dir.exists()) return [];
    final out = <Character>[];
    await for (final entity in _dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final json = await readJsonFile(entity);
      if (json == null) continue;
      try {
        out.add(Character.fromJson(json));
      } on Object {
        // Skip unreadable entries rather than losing the whole collection.
      }
    }
    // Tie-break on id: directory listing order is filesystem-dependent.
    out.sort((a, b) {
      final byDate = a.createdAt.compareTo(b.createdAt);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    return out;
  }

  @override
  Future<void> add(
    Character character,
    Uint8List cutoutPng, {
    required int limit,
  }) async {
    _checkId(character.id);
    final existing = await loadAll();
    if (existing.length >= limit) throw CollectionFullException(limit);
    await _dir.create(recursive: true);
    await _png(character.id).writeAsBytes(cutoutPng, flush: true);
    await writeJsonFile(_json(character.id), character.toJson());
  }

  @override
  Future<void> update(Character character) async {
    _checkId(character.id);
    if (!await _json(character.id).exists()) {
      throw StateError('unknown character ${character.id}');
    }
    await writeJsonFile(_json(character.id), character.toJson());
  }

  @override
  Future<void> delete(String id) async {
    _checkId(id);
    for (final f in [_json(id), _png(id)]) {
      if (await f.exists()) await f.delete();
    }
  }

  @override
  Future<void> deleteAll() async {
    if (await _dir.exists()) await _dir.delete(recursive: true);
  }

  @override
  Future<Uint8List?> readImage(String id) async {
    _checkId(id);
    final f = _png(id);
    return await f.exists() ? f.readAsBytes() : null;
  }
}
