import 'dart:typed_data';

import '../domain/character.dart';
import 'before_photo.dart';
import 'character_repository.dart';

/// In-memory [CharacterRepository] for tests and previews.
class InMemoryCharacterRepository implements CharacterRepository {
  InMemoryCharacterRepository([
    Iterable<(Character, Uint8List)> initial = const [],
  ]) {
    for (final (c, png) in initial) {
      _chars[c.id] = c;
      _images[c.id] = png;
    }
  }

  final Map<String, Character> _chars = {};
  final Map<String, Uint8List> _images = {};
  final Map<String, BeforePhoto> _before = {};

  @override
  String imagePathFor(String id) => 'memory://characters/$id.png';

  @override
  Future<List<Character>> loadAll() async =>
      _chars.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<void> add(
    Character character,
    Uint8List cutoutPng, {
    required int limit,
  }) async {
    if (_chars.length >= limit) throw CollectionFullException(limit);
    _chars[character.id] = character;
    _images[character.id] = cutoutPng;
  }

  @override
  Future<void> update(Character character) async {
    if (!_chars.containsKey(character.id)) {
      throw StateError('unknown character ${character.id}');
    }
    _chars[character.id] = character;
  }

  @override
  Future<void> delete(String id) async {
    _chars.remove(id);
    _images.remove(id);
    _before.remove(id);
  }

  @override
  Future<void> deleteAll() async {
    _chars.clear();
    _images.clear();
    _before.clear();
  }

  @override
  Future<Uint8List?> readImage(String id) async => _images[id];

  @override
  Future<void> saveBeforePhoto(String id, BeforePhoto photo) async {
    if (!_chars.containsKey(id)) {
      throw StateError('unknown character $id');
    }
    _before[id] = photo;
  }

  @override
  Future<BeforePhoto?> readBeforePhoto(String id) async => _before[id];
}
