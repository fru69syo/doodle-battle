/// The 2.5D rig stored with a character (docs/V2_25D_TECH.md §3), kept here
/// as an opaque JSON blob: the Puppet team owns its meaning
/// (`CharacterRig.toJson()`); this layer only checks its size and shape so a
/// broken or hostile blob never reaches an opponent's device. The same rules
/// run on the server (`shared/battle_engine_v3_ts/src/rig.ts`).
///
/// Unknown versions and invalid blobs are dropped (the app then falls back
/// to the automatic rig), never "repaired".
library;

import 'dart:convert';

/// Rig JSON format version this build understands.
const int kRigVersion = 1;

/// Max UTF-8 size of the encoded blob (a rig is 0.5–1 KB).
const int kRigMaxBytes = 4096;

/// Max limbs (head, arms, legs, tail, extras).
const int kRigMaxLimbs = 12;

/// Max cut-out side in pixels (the analyser caps it at 512).
const int kRigMaxSide = 4096;

const Set<String> kRigLimbKinds = {'head', 'arm', 'leg', 'tail', 'extra'};
const Set<String> kRigSources = {'auto', 'edited'};

/// Returns [json] (as a JSON-safe map) when it is a valid rig blob, else
/// null. See [rigProblem] for the reason.
Map<String, Object?>? validateRigJson(Object? json) => rigProblem(json) == null
    ? (jsonDecode(jsonEncode(json)) as Map).cast<String, Object?>()
    : null;

/// Why [json] is not a valid rig blob, or null when it is.
String? rigProblem(Object? json) {
  if (json is! Map) return 'not an object';
  final String enc;
  try {
    enc = jsonEncode(json);
  } on Object {
    return 'not JSON';
  }
  if (utf8.encode(enc).length > kRigMaxBytes) return 'too large';
  if (json['v'] != kRigVersion) return 'version';
  final w = json['width'];
  final h = json['height'];
  if (w is! num || h is! num) return 'size';
  if (!(w > 0 && w <= kRigMaxSide && h > 0 && h <= kRigMaxSide)) {
    return 'size';
  }
  bool point(Object? p) {
    if (p is! List || p.length != 2) return false;
    final x = p[0];
    final y = p[1];
    if (x is! num || y is! num || !x.isFinite || !y.isFinite) return false;
    return x >= -w && x <= 2 * w && y >= -h && y <= 2 * h;
  }

  if (!point(json['root']) || !point(json['chest'])) return 'body';
  final ground = json['ground'];
  if (ground != null &&
      (ground is! num || !ground.isFinite || ground < -h || ground > 2 * h)) {
    return 'ground';
  }
  final source = json['source'];
  if (source != null && !kRigSources.contains(source)) return 'source';
  final limbs = json['limbs'];
  if (limbs is! List) return 'limbs';
  if (limbs.length > kRigMaxLimbs) return 'too many limbs';
  for (final l in limbs) {
    if (l is! Map) return 'limb';
    if (!kRigLimbKinds.contains(l['kind'])) return 'limb kind';
    if (!point(l['base']) || !point(l['mid']) || !point(l['tip'])) {
      return 'limb point';
    }
    final e = l['edited'];
    if (e != null && e is! bool) return 'limb edited';
  }
  return null;
}
