import 'dart:convert';
import 'dart:io';

import '../rig/rig.dart';

/// Pure edits used by the joint editor (unit-tested without widgets).
/// Kids drag the *tips* (head, hands, feet, tail) and the body; the limb's
/// base stays where it leaves the body and the elbow / knee is re-placed
/// halfway, which is enough for the procedural clips.
class RigEdits {
  RigEdits._();

  static CharacterRig moveTip(CharacterRig r, int limb, V2 tip) {
    final out = r.copy()..source = 'edited';
    final l = out.limbs[limb];
    l
      ..tip = _clamp(out, tip)
      ..mid = l.base.lerp(tip, 0.5)
      ..edited = true;
    return out;
  }

  /// Moves the body pivot; the chest follows so the spine keeps its length.
  static CharacterRig moveRoot(CharacterRig r, V2 p) {
    final out = r.copy()..source = 'edited';
    final d = _clamp(out, p) - out.root;
    out
      ..root = out.root + d
      ..chest = out.chest + d;
    return out;
  }

  /// Adds a limb of [kind] sticking out from the body; the child then drags
  /// its tip onto the drawing.
  static CharacterRig addLimb(CharacterRig r, LimbKind kind) {
    final out = r.copy()..source = 'edited';
    final w = r.width, h = r.height;
    final side = out.of(kind).length.isEven ? -1.0 : 1.0;
    final (V2 base, V2 tip) = switch (kind) {
      LimbKind.head => (out.chest, V2(out.chest.x, out.chest.y - 0.25 * h)),
      LimbKind.arm => (out.chest, out.chest + V2(side * 0.35 * w, 0.05 * h)),
      LimbKind.leg => (
        out.root + V2(side * 0.1 * w, 0),
        V2(out.root.x + side * 0.15 * w, out.groundY - 0.03 * h),
      ),
      LimbKind.tail => (out.root, out.root + V2(-side * 0.4 * w, -0.1 * h)),
      LimbKind.extra => (out.chest, out.chest + V2(0, -0.3 * h)),
    };
    out.limbs.add(
      RigLimb(kind, base, base.lerp(tip, 0.5), _clamp(out, tip))..edited = true,
    );
    return out;
  }

  static CharacterRig removeLimb(CharacterRig r, int limb) {
    final out = r.copy()..source = 'edited';
    out.limbs.removeAt(limb);
    return out;
  }

  static V2 _clamp(CharacterRig r, V2 p) =>
      V2(p.x.clamp(0, r.width), p.y.clamp(0, r.height));
}

/// Where rigs live. The spike stores one JSON file per drawing, keyed by
/// the image hash, next to the app's other files; production keeps it in
/// the `Character` record (and sends it with `registerCharacter`, so an
/// online opponent animates your drawing the way you set it up).
abstract class RigStore {
  Future<CharacterRig?> load(String imageHash);
  Future<void> save(String imageHash, CharacterRig rig);
}

class MemoryRigStore implements RigStore {
  final Map<String, String> _m = {};
  @override
  Future<CharacterRig?> load(String imageHash) async {
    final s = _m[imageHash];
    return s == null
        ? null
        : CharacterRig.fromJson((jsonDecode(s) as Map).cast<String, Object?>());
  }

  @override
  Future<void> save(String imageHash, CharacterRig rig) async =>
      _m[imageHash] = jsonEncode(rig.toJson());
}

class FileRigStore implements RigStore {
  FileRigStore(this.dir);
  final Directory dir;

  File _f(String hash) => File(
    '${dir.path}/rigs/${hash.replaceAll(RegExp('[^0-9a-zA-Z]'), '')}.json',
  );

  @override
  Future<CharacterRig?> load(String imageHash) async {
    final f = _f(imageHash);
    if (!f.existsSync()) return null;
    try {
      return CharacterRig.fromJson(
        (jsonDecode(await f.readAsString()) as Map).cast<String, Object?>(),
      );
    } on FormatException {
      return null; // unknown version: auto-rig again
    }
  }

  @override
  Future<void> save(String imageHash, CharacterRig rig) async {
    final f = _f(imageHash);
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(rig.toJson()));
  }
}
