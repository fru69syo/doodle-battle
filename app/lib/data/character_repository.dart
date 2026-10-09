import 'dart:typed_data';

import '../domain/character.dart';

/// Free collection size (SPEC §2-4). Purchases add [extraSlotsPerPack].
const int freeCollectionLimit = 12;
const int extraSlotsPerPack = 24;

/// Thrown by [CharacterRepository.add] when the collection is full.
class CollectionFullException implements Exception {
  const CollectionFullException(this.limit);
  final int limit;
  @override
  String toString() => 'CollectionFullException(limit: $limit)';
}

/// Local store of the child's characters (JSON + cut-out PNG).
abstract interface class CharacterRepository {
  /// All characters, oldest first.
  Future<List<Character>> loadAll();

  /// Where the cut-out PNG of character [id] is (or will be) stored. Use it
  /// as `Character.imagePath` when creating a character.
  String imagePathFor(String id);

  /// Stores a new character and its cut-out. Throws
  /// [CollectionFullException] when [limit] characters already exist.
  Future<void> add(
    Character character,
    Uint8List cutoutPng, {
    required int limit,
  });

  /// Replaces an existing character (level, xp, seeds, name, onlineId...).
  Future<void> update(Character character);

  Future<void> delete(String id);

  /// Removes every character and image.
  Future<void> deleteAll();

  /// Cut-out PNG bytes, or null if missing.
  Future<Uint8List?> readImage(String id);
}
