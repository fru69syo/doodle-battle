import 'dart:io';
import 'dart:typed_data';

import '../domain/character_v2.dart';
import 'before_photo.dart';
import 'character_repository.dart';
import 'json_file.dart';

/// Stores each character as `<root>/characters/<id>.json` + `<id>.png`
/// (root = app documents directory in the app). The optional "Before" paper
/// photo lives in `<root>/characters/before/<id>.jpg` + `<id>.json`.
class FileCharacterRepository implements CharacterRepository {
  FileCharacterRepository(Directory root)
    : _dir = Directory('${root.path}/characters');

  final Directory _dir;

  static final _validId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  File _json(String id) => File('${_dir.path}/$id.json');
  File _png(String id) => File('${_dir.path}/$id.png');
  Directory get _beforeDir => Directory('${_dir.path}/before');
  File _beforeJpg(String id) => File('${_beforeDir.path}/$id.jpg');
  File _beforeMeta(String id) => File('${_beforeDir.path}/$id.json');

  void _checkId(String id) {
    if (!_validId.hasMatch(id)) throw ArgumentError.value(id, 'id');
  }

  @override
  String imagePathFor(String id) => _png(id).path;

  @override
  Future<List<CharacterV2>> loadAll() async {
    if (!await _dir.exists()) return [];
    final out = <CharacterV2>[];
    await for (final entity in _dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final json = await readJsonFile(entity);
      if (json == null) continue;
      try {
        final c = CharacterV2.fromJson(json);
        // v1 file (no `schema`): store the migrated v2 record once.
        if (json['schema'] != CharacterV2.schema) {
          await writeJsonFile(entity, c.toJson());
        }
        out.add(c);
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
    CharacterV2 character,
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
  Future<void> update(CharacterV2 character) async {
    _checkId(character.id);
    if (!await _json(character.id).exists()) {
      throw StateError('unknown character ${character.id}');
    }
    await writeJsonFile(_json(character.id), character.toJson());
  }

  @override
  Future<void> delete(String id) async {
    _checkId(id);
    for (final f in [_json(id), _png(id), _beforeJpg(id), _beforeMeta(id)]) {
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

  @override
  Future<void> saveBeforePhoto(String id, BeforePhoto photo) async {
    _checkId(id);
    if (!await _json(id).exists()) {
      throw StateError('unknown character $id');
    }
    await _beforeDir.create(recursive: true);
    await _beforeJpg(id).writeAsBytes(photo.jpeg, flush: true);
    await writeJsonFile(_beforeMeta(id), photo.metaJson());
  }

  @override
  Future<BeforePhoto?> readBeforePhoto(String id) async {
    _checkId(id);
    final jpg = _beforeJpg(id);
    if (!await jpg.exists()) return null;
    final meta = await readJsonFile(_beforeMeta(id));
    return BeforePhoto(
      jpeg: await jpg.readAsBytes(),
      inkRect: BeforePhoto.inkRectFromMeta(meta),
    );
  }
}
