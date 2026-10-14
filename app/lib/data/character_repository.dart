import 'dart:typed_data';

import '../domain/character_v2.dart';
import 'before_photo.dart';

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
  Future<List<CharacterV2>> loadAll();

  /// Where the cut-out PNG of character [id] is (or will be) stored. Use it
  /// as `CharacterV2.imagePath` when creating a character.
  String imagePathFor(String id);

  /// Stores a new character and its cut-out. Throws
  /// [CollectionFullException] when [limit] characters already exist.
  Future<void> add(
    CharacterV2 character,
    Uint8List cutoutPng, {
    required int limit,
  });

  /// Replaces an existing character (level, xp, seeds, name, onlineId...).
  Future<void> update(CharacterV2 character);

  Future<void> delete(String id);

  /// Removes every character and image.
  Future<void> deleteAll();

  /// Cut-out PNG bytes, or null if missing.
  Future<Uint8List?> readImage(String id);

  /// Stores the "Before" paper photo of an existing character (video
  /// export, docs/VIDEO.md). Removed by [delete] and [deleteAll].
  Future<void> saveBeforePhoto(String id, BeforePhoto photo);

  /// The "Before" photo, or null (older characters, or nothing kept).
  Future<BeforePhoto?> readBeforePhoto(String id);
}
