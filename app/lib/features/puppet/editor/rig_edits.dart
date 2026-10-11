import '../rig/character_rig.dart';

/// Pure edits used by the joint editor (unit-tested without widgets).
/// Children drag the *tips* (head, hands, feet, tail) and the body; the
/// limb's base stays where it leaves the body and the elbow / knee is
/// re-placed halfway, which is enough for the procedural clips. A selected
/// limb also shows its base so it can be moved.
class RigEdits {
  RigEdits._();

  /// How many of each kind a child may have (the JSON holds 12 limbs).
  static const maxOf = {
    LimbKind.head: 2,
    LimbKind.arm: 4,
    LimbKind.leg: 6,
    LimbKind.tail: 2,
  };

  static CharacterRig moveTip(CharacterRig r, int limb, P2 tip) {
    final out = r.copy(source: RigSource.edited);
    final l = out.limbs[limb];
    l
      ..tip = _clamp(out, tip)
      ..mid = l.base.lerp(l.tip, 0.5)
      ..edited = true;
    return out;
  }

  static CharacterRig moveBase(CharacterRig r, int limb, P2 base) {
    final out = r.copy(source: RigSource.edited);
    final l = out.limbs[limb];
    l
      ..base = _clamp(out, base)
      ..mid = l.base.lerp(l.tip, 0.5)
      ..edited = true;
    return out;
  }

  /// Moves the body pivot; the chest follows so the spine keeps its
  /// length.
  static CharacterRig moveRoot(CharacterRig r, P2 p) {
    final out = r.copy(source: RigSource.edited);
    final d = _clamp(out, p) - out.root;
    out
      ..root = out.root + d
      ..chest = out.chest + d;
    return out;
  }

  static bool canAdd(CharacterRig r, LimbKind kind) =>
      r.limbs.length < CharacterRig.maxLimbs &&
      r.of(kind).length < (maxOf[kind] ?? 0);

  /// Adds a limb of [kind] sticking out from the body (alternating sides);
  /// the child then drags its tip onto the drawing. Returns [r] unchanged
  /// when the limit is reached.
  static CharacterRig addLimb(CharacterRig r, LimbKind kind) {
    if (!canAdd(r, kind)) return r;
    final out = r.copy(source: RigSource.edited);
    final w = r.width, h = r.height;
    final side = out.of(kind).length.isEven ? -1.0 : 1.0;
    final (P2 base, P2 tip) = switch (kind) {
      LimbKind.head => (out.chest, P2(out.chest.x, out.chest.y - 0.25 * h)),
      LimbKind.arm => (out.chest, out.chest + P2(side * 0.35 * w, 0.05 * h)),
      LimbKind.leg => (
        out.root + P2(side * 0.1 * w, 0),
        P2(out.root.x + side * 0.15 * w, out.groundY - 0.03 * h),
      ),
      LimbKind.tail => (out.root, out.root + P2(-side * 0.4 * w, -0.1 * h)),
      LimbKind.extra ||
      LimbKind.wing ||
      LimbKind.item => (out.chest, out.chest + P2(0, -0.3 * h)),
    };
    out.limbs.add(
      RigLimb(kind, _clamp(out, base), base.lerp(tip, 0.5), _clamp(out, tip))
        ..edited = true,
    );
    return out;
  }

  /// Removes limb [limb]; limbs attached to it move to the body.
  static CharacterRig removeLimb(CharacterRig r, int limb) {
    final out = r.copy(source: RigSource.edited);
    out.limbs.removeAt(limb);
    for (final l in out.limbs) {
      final a = l.attach;
      if (a == null) continue;
      l.attach = a == limb ? null : (a > limb ? a - 1 : a);
    }
    return out;
  }

  static P2 _clamp(CharacterRig r, P2 p) => P2(
    p.x.clamp(-0.1 * r.width, 1.1 * r.width),
    p.y.clamp(-0.1 * r.height, 1.1 * r.height),
  );
}

/// Undo history of the editor (bounded).
class RigHistory {
  RigHistory(CharacterRig initial) : _stack = [initial];

  static const maxSteps = 40;
  final List<CharacterRig> _stack;

  CharacterRig get current => _stack.last;
  bool get canUndo => _stack.length > 1;

  void push(CharacterRig r) {
    _stack.add(r);
    if (_stack.length > maxSteps) _stack.removeAt(0);
  }

  /// Replaces the current state (a drag in progress) without a new step.
  void replace(CharacterRig r) => _stack[_stack.length - 1] = r;

  CharacterRig undo() {
    if (canUndo) _stack.removeLast();
    return current;
  }
}
