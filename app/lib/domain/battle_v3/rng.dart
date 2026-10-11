/// Portable 32-bit PRNG for battle spec v3 (bit-exact with
/// `shared/battle_engine_v3_ts/src/rng.ts`). Same algorithm as the v1 engine
/// (docs/BATTLE.md §2); kept as its own copy so v3 does not depend on v1.
///
/// Algorithm: mulberry32 (public domain). All arithmetic is done on unsigned
/// 32-bit values with explicit masking, and multiplication is split into
/// 16-bit halves so the result never depends on 64-bit overflow behaviour
/// (works identically on the Dart VM, dart2js and JavaScript).
///
/// Streams (docs/GAME_DESIGN_V2.md §9): 0 battle, 1/2 AI a/b, 10 stat
/// jitter, 11 growth, 12 moves, 13 rebirth stats, 14 rebirth moves.
library;

import 'dart:convert' show utf8;

/// 0xFFFFFFFF.
const int mask32 = 0xFFFFFFFF;

/// `Math.imul` semantics, returned as an unsigned 32-bit value.
int imul32(int a, int b) {
  a &= mask32;
  b &= mask32;
  final ah = a >> 16;
  final al = a & 0xFFFF;
  final bh = b >> 16;
  final bl = b & 0xFFFF;
  final high = ((ah * bl + al * bh) & 0xFFFF) << 16;
  return (al * bl + high) & mask32;
}

/// mulberry32 generator. Its whole state is a single uint32 ([state]), so a
/// battle in progress can be persisted (e.g. in Firestore) and resumed with
/// `Mulberry32(savedState)`.
class Mulberry32 {
  Mulberry32(int seed) : _state = seed & mask32;

  int _state;

  /// Current internal state (uint32). `Mulberry32(rng.state)` continues the
  /// exact same sequence.
  int get state => _state;

  /// Next uniformly distributed uint32.
  int nextUint32() {
    _state = (_state + 0x6D2B79F5) & mask32;
    var t = _state;
    t = imul32(t ^ (t >> 15), t | 1);
    t ^= (t + imul32(t ^ (t >> 7), t | 61)) & mask32;
    return (t ^ (t >> 14)) & mask32;
  }

  /// Integer in `[0, n)`, computed as `nextUint32() % n` (1 <= n < 2^31).
  int nextInt(int n) {
    if (n < 1) throw ArgumentError.value(n, 'n', 'must be >= 1');
    return nextUint32() % n;
  }
}

/// FNV-1a 32-bit hash over the UTF-8 bytes of [input]. Handy to derive a
/// match seed from a string id (e.g. a Firestore match id).
int fnv1a32(String input) {
  var h = 0x811C9DC5;
  for (final b in utf8.encode(input)) {
    h ^= b;
    h = imul32(h, 0x01000193);
  }
  return h & mask32;
}

/// Derives an independent uint32 seed for stream [stream] from [seed].
///
/// `deriveSeed(seed, s) = mulberry32(seed XOR imul(s + 1, 0x9E3779B1)).next()`.
int deriveSeed(int seed, int stream) =>
    Mulberry32((seed ^ imul32(stream + 1, 0x9E3779B1)) & mask32).nextUint32();
