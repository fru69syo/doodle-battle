import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'json_file.dart';

/// Local files of the drawing loop (docs/LOOP.md): per-character PNG assets
/// (drawn parts, drawn move effects, the cached composite picture) and the
/// stamp card of the daily theme. Nothing here is ever uploaded.
abstract interface class DrawingLoopStorage {
  Future<Uint8List?> readAsset(String characterId, String name);
  Future<void> writeAsset(String characterId, String name, Uint8List bytes);
  Future<void> deleteAsset(String characterId, String name);

  /// Names of the assets stored for [characterId].
  Future<List<String>> listAssets(String characterId);

  /// Removes every asset of [characterId] (character released).
  Future<void> deleteCharacter(String characterId);

  /// Stamp card JSON (`OdaiStampCard`), null when none yet.
  Future<Map<String, Object?>?> loadStampCard();
  Future<void> saveStampCard(Map<String, Object?> json);

  /// 「すべてのデータを削除」.
  Future<void> deleteAll();
}

final _validName = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

void _check(String characterId, String? name) {
  if (!_validName.hasMatch(characterId)) {
    throw ArgumentError.value(characterId, 'characterId');
  }
  if (name != null && !_validName.hasMatch(name)) {
    throw ArgumentError.value(name, 'name');
  }
}

/// `<root>/drawing_loop/<characterId>/<name>.png` and
/// `<root>/drawing_loop/stamps.json` (root = app documents directory).
class FileDrawingLoopStorage implements DrawingLoopStorage {
  FileDrawingLoopStorage(Directory root)
    : _dir = Directory('${root.path}/drawing_loop');

  final Directory _dir;

  Directory _charDir(String id) => Directory('${_dir.path}/$id');
  File _asset(String id, String name) => File('${_dir.path}/$id/$name.png');
  File get _stamps => File('${_dir.path}/stamps.json');

  @override
  Future<Uint8List?> readAsset(String characterId, String name) async {
    _check(characterId, name);
    final f = _asset(characterId, name);
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> writeAsset(
    String characterId,
    String name,
    Uint8List bytes,
  ) async {
    _check(characterId, name);
    final f = _asset(characterId, name);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> deleteAsset(String characterId, String name) async {
    _check(characterId, name);
    final f = _asset(characterId, name);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<List<String>> listAssets(String characterId) async {
    _check(characterId, null);
    final d = _charDir(characterId);
    if (!await d.exists()) return const [];
    return [
      await for (final e in d.list())
        if (e is File && e.path.endsWith('.png'))
          e.uri.pathSegments.last.replaceFirst(RegExp(r'\.png$'), ''),
    ]..sort();
  }

  @override
  Future<void> deleteCharacter(String characterId) async {
    _check(characterId, null);
    final d = _charDir(characterId);
    if (await d.exists()) await d.delete(recursive: true);
  }

  @override
  Future<Map<String, Object?>?> loadStampCard() => readJsonFile(_stamps);

  @override
  Future<void> saveStampCard(Map<String, Object?> json) =>
      writeJsonFile(_stamps, json);

  @override
  Future<void> deleteAll() async {
    if (await _dir.exists()) await _dir.delete(recursive: true);
  }
}

/// In-memory [DrawingLoopStorage] (tests; default when not overridden).
class InMemoryDrawingLoopStorage implements DrawingLoopStorage {
  final Map<String, Map<String, Uint8List>> assets = {};
  Map<String, Object?>? stampCard;

  @override
  Future<Uint8List?> readAsset(String characterId, String name) async =>
      assets[characterId]?[name];

  @override
  Future<void> writeAsset(
    String characterId,
    String name,
    Uint8List bytes,
  ) async {
    _check(characterId, name);
    (assets[characterId] ??= {})[name] = bytes;
  }

  @override
  Future<void> deleteAsset(String characterId, String name) async =>
      assets[characterId]?.remove(name);

  @override
  Future<List<String>> listAssets(String characterId) async =>
      (assets[characterId]?.keys.toList() ?? <String>[])..sort();

  @override
  Future<void> deleteCharacter(String characterId) async =>
      assets.remove(characterId);

  @override
  Future<Map<String, Object?>?> loadStampCard() async => stampCard;

  @override
  Future<void> saveStampCard(Map<String, Object?> json) async =>
      stampCard = json;

  @override
  Future<void> deleteAll() async {
    assets.clear();
    stampCard = null;
  }
}

/// Overridden with [FileDrawingLoopStorage] in `main.dart`.
final drawingLoopStorageProvider = Provider<DrawingLoopStorage>(
  (ref) => InMemoryDrawingLoopStorage(),
);
