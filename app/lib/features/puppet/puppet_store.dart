import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'rig/character_rig.dart';

/// Where a character's rig and (for the in-app drawing tool) its stroke list
/// live. Local only: the strokes never leave the phone. The rig is meant to
/// travel with the character record (Character v2 `rig`, sent with
/// `registerCharacter` so online opponents see the same joints); until the
/// v3 model lands it is kept next to the character's other files, and the
/// integration copies [loadRigJson] into the record (docs/PUPPET.md §6).
abstract interface class PuppetStore {
  /// Validated rig JSON, or null (→ auto-rig).
  Future<String?> loadRigJson(String characterId);
  Future<void> saveRig(String characterId, CharacterRig rig);
  Future<void> deleteRig(String characterId);

  /// The drawing tool's stroke list (`StrokeDrawing.toJson`), or null for a
  /// photographed paper drawing.
  Future<String?> loadStrokesJson(String characterId);
  Future<void> saveStrokesJson(String characterId, String json);

  Future<void> deleteCharacter(String characterId);
  Future<void> deleteAll();
}

final _validId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

void _check(String id) {
  if (!_validId.hasMatch(id)) throw ArgumentError.value(id, 'characterId');
}

/// `<root>/puppet/<characterId>/rig.json` and `strokes.json`.
class FilePuppetStore implements PuppetStore {
  FilePuppetStore(Directory root) : _dir = Directory('${root.path}/puppet');
  final Directory _dir;

  File _f(String id, String name) => File('${_dir.path}/$id/$name.json');

  Future<String?> _read(String id, String name) async {
    _check(id);
    final f = _f(id, name);
    try {
      return await f.exists() ? await f.readAsString() : null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _write(String id, String name, String s) async {
    _check(id);
    final f = _f(id, name);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(s, flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<String?> loadRigJson(String characterId) async {
    final s = await _read(characterId, 'rig');
    return CharacterRig.tryDecode(s) == null ? null : s;
  }

  @override
  Future<void> saveRig(String characterId, CharacterRig rig) {
    final problem = rig.validate();
    if (problem != null) throw ArgumentError('invalid rig: $problem');
    return _write(characterId, 'rig', rig.encode());
  }

  @override
  Future<void> deleteRig(String characterId) async {
    _check(characterId);
    final f = _f(characterId, 'rig');
    if (await f.exists()) await f.delete();
  }

  @override
  Future<String?> loadStrokesJson(String characterId) =>
      _read(characterId, 'strokes');

  @override
  Future<void> saveStrokesJson(String characterId, String json) =>
      _write(characterId, 'strokes', json);

  @override
  Future<void> deleteCharacter(String characterId) async {
    _check(characterId);
    final d = Directory('${_dir.path}/$characterId');
    if (await d.exists()) await d.delete(recursive: true);
  }

  @override
  Future<void> deleteAll() async {
    if (await _dir.exists()) await _dir.delete(recursive: true);
  }
}

/// In-memory store (tests; default when not overridden).
class InMemoryPuppetStore implements PuppetStore {
  final rigs = <String, String>{};
  final strokes = <String, String>{};

  @override
  Future<String?> loadRigJson(String characterId) async {
    final s = rigs[characterId];
    return CharacterRig.tryDecode(s) == null ? null : s;
  }

  @override
  Future<void> saveRig(String characterId, CharacterRig rig) async {
    _check(characterId);
    final problem = rig.validate();
    if (problem != null) throw ArgumentError('invalid rig: $problem');
    rigs[characterId] = rig.encode();
  }

  @override
  Future<void> deleteRig(String characterId) async => rigs.remove(characterId);

  @override
  Future<String?> loadStrokesJson(String characterId) async =>
      strokes[characterId];

  @override
  Future<void> saveStrokesJson(String characterId, String json) async {
    _check(characterId);
    jsonDecode(json); // must be JSON
    strokes[characterId] = json;
  }

  @override
  Future<void> deleteCharacter(String characterId) async {
    rigs.remove(characterId);
    strokes.remove(characterId);
  }

  @override
  Future<void> deleteAll() async {
    rigs.clear();
    strokes.clear();
  }
}

/// Overridden with [FilePuppetStore] in `main.dart`.
final puppetStoreProvider = Provider<PuppetStore>((ref) => InMemoryPuppetStore());
