/// Validator for AI-proposed moves (Claude via `judgeDrawing`) — the same
/// deterministic rules as `shared/battle_engine_v3_ts/src/validator.ts`.
/// docs/GAME_DESIGN_V2.md §5.6.
library;

import 'moves.dart';
import 'spec.dart';

/// Outcome of validating one AI-proposed move.
class MoveValidation {
  MoveValidation(
    this.move,
    this.warnings, {
    this.rejected = false,
    this.reason,
  });
  final Move? move;
  final List<String> warnings;
  final bool rejected;
  final String? reason;
}

/// Integer value of a JSON number (floor of a finite double, saturated at
/// ±1e9 so every port agrees), or [def] for anything else.
int _intOr(Object? v, int def) {
  if (v is int) return v;
  if (v is double && v.isFinite) {
    if (v >= 1e9) return 1000000000;
    if (v <= -1e9) return -1000000000;
    return v.floor();
  }
  return def;
}

final RegExp _kanaName = RegExp(r'^[ぁ-ゖァ-ヺー]{1,10}$');
final RegExp _kanaFlavor = RegExp(r'^[ぁ-ゖァ-ヺー、。！？ 　]{0,30}$');

/// Validates and normalises one move proposed by the AI for [slot] of a
/// character with attribute [own]. Deterministic; see docs §5.6.
/// [ngCheck] returns true when a string contains an NG word.
MoveValidation validateAiMove(
  V3Spec s,
  Map<String, Object?> json, {
  required int slot,
  required Attr own,
  required int moveFactorPct,
  bool Function(String)? ngCheck,
}) {
  final w = <String>[];
  MoveValidation reject(String r) =>
      MoveValidation(null, w, rejected: true, reason: r);

  final tplId = json['template'];
  if (tplId is! String || !kTemplates.containsKey(tplId)) {
    return reject('unknown template');
  }
  final tpl = kTemplates[tplId]!;
  int numParam(String k, int def) {
    final v = json[k];
    final r = tpl.ranges[k];
    var i = _intOr(v, def);
    if (v != null && v is! int && v is! double) w.add('$k not a number');
    if (r != null && (i < r.min || i > r.max)) {
      w.add('$k clamped');
      i = r.clamp(i);
    }
    return i;
  }

  // Slot rules.
  if (slot == 0 && !tpl.isDamage) return reject('slot 1 must be a damage move');
  if (slot == 3 && !tpl.isDamage) return reject('slot 4 must be a damage move');

  var attr = Attr.values.firstWhere(
    (a) => a.name == json['attribute'],
    orElse: () => Attr.none,
  );
  final supportKind =
      tpl.kind == MoveKind.heal ||
      tpl.kind == MoveKind.buff ||
      tpl.kind == MoveKind.shield;
  if (supportKind && attr != Attr.none) {
    w.add('support moves have no attribute');
    attr = Attr.none;
  }
  if (slot == 0 && attr != own) {
    w.add('slot 1 attribute forced to own');
    attr = own;
  }
  if (slot == 3 && attr != Attr.none) {
    w.add('slot 4 (ひっさつ) is always neutral');
    attr = Attr.none;
  }
  if (slot == 1 && attr == own) {
    w.add('slot 2 attribute must differ from slot 1');
    attr = Attr.none;
  }

  // Strings.
  var name = json['name'] is String ? json['name']! as String : '';
  var flavor = json['flavor'] is String ? json['flavor']! as String : '';
  if (!_kanaName.hasMatch(name) || (ngCheck?.call(name) ?? false)) {
    return reject('name');
  }
  if (!_kanaFlavor.hasMatch(flavor) || (ngCheck?.call(flavor) ?? false)) {
    w.add('flavor dropped');
    flavor = '';
  }
  var vfx = json['vfx'] is String ? json['vfx']! as String : '';
  if (!kVfx.contains(vfx)) {
    w.add('vfx defaulted');
    vfx = tpl.isDamage ? 'punch' : 'glow';
  }
  var colour = json['colour'] is String ? json['colour']! as String : '';
  if (!kColours.contains(colour)) {
    w.add('colour defaulted');
    colour = 'white';
  }

  final fc = json['atkFormula'];
  var formula = fc is String ? AtkFormula.fromCode(fc) : null;
  final physical = tpl.kind == MoveKind.physical;
  if (tpl.isDamage && (formula == null || formula.physical != physical)) {
    w.add('atkFormula defaulted');
    formula = physical ? AtkFormula.strAgi : AtkFormula.intDex;
  }
  var statKind = Stat.str;
  if (tpl.kind == MoveKind.buff || tpl.kind == MoveKind.debuff) {
    final c = json['stat'];
    final found = kStageStats.where((st) => st.code == c);
    if (found.isEmpty) return reject('stat');
    statKind = found.first;
  }

  var secondary = SecondaryType.none;
  var secChance = 0;
  var secStat = Stat.def;
  var drain = 0;
  if (tpl.isDamage && json['secondary'] is Map) {
    final sec = (json['secondary']! as Map).cast<String, Object?>();
    secondary = SecondaryType.values.firstWhere(
      (t) => t.name == sec['type'],
      orElse: () => SecondaryType.none,
    );
    int sn(String k) {
      final v = sec[k];
      final i = _intOr(v, kSecondaryRanges[k]!.min);
      final c = kSecondaryRanges[k]!.clamp(i);
      if (c != i) w.add('secondary.$k clamped');
      return c;
    }

    if (secondary == SecondaryType.poison ||
        secondary == SecondaryType.paralyze ||
        secondary == SecondaryType.debuff) {
      secChance = sn('chance');
    }
    if (secondary == SecondaryType.debuff) {
      final found = kStageStats.where((st) => st.code == sec['stat']);
      if (found.isEmpty) {
        w.add('secondary dropped');
        secondary = SecondaryType.none;
      } else {
        secStat = found.first;
      }
    }
    if (secondary == SecondaryType.drain) drain = sn('drainPct');
  }

  var m = Move(
    template: tplId,
    attr: attr,
    name: name,
    flavor: flavor,
    vfx: vfx,
    colour: colour,
    atkFormula: formula ?? AtkFormula.strAgi,
    power: tpl.isDamage ? numParam('power', 100) : 0,
    hits: tpl.isDamage ? numParam('hits', tpl.ranges['hits']!.min) : 1,
    accuracy: tpl.ranges.containsKey('accuracy')
        ? numParam('accuracy', 100)
        : 100,
    critBonus: tpl.isDamage ? numParam('critBonus', 0) : 0,
    spCost: numParam('spCost', 0),
    castTicks: numParam('castTicks', 0),
    cooldownTicks: numParam('cooldownTicks', tpl.ranges['cooldownTicks']!.min),
    secondary: secondary,
    secondaryChance: secChance,
    secondaryStat: secStat,
    drainPct: drain,
    healPct: tpl.kind == MoveKind.heal ? numParam('healPct', 10) : 0,
    stat: statKind,
    stages: tpl.ranges.containsKey('stages') ? numParam('stages', 1) : 0,
    durationTicks: tpl.ranges.containsKey('durationTicks')
        ? numParam('durationTicks', tpl.ranges['durationTicks']!.min)
        : 0,
    chance: tpl.ranges.containsKey('chance') ? numParam('chance', 30) : 0,
    shieldPct: tpl.ranges.containsKey('shieldPct')
        ? numParam('shieldPct', 20)
        : 0,
  );

  // Slot-1 "いつもの わざ" must be always usable.
  if (slot == 0 && (m.spCost != 0 || m.cooldownTicks != 0 || m.castTicks > 5)) {
    w.add('slot 1 made free (sp 0, cooldown 0, cast <= 5)');
    m = m.copyWith(
      spCost: 0,
      cooldownTicks: 0,
      castTicks: m.castTicks > 5 ? 5 : m.castTicks,
    );
  }
  // Buffs/debuffs can not be re-applied while active.
  if ((m.kind == MoveKind.buff || m.kind == MoveKind.debuff) &&
      m.cooldownTicks < m.durationTicks) {
    m = m.copyWith(cooldownTicks: m.durationTicks);
  }

  final fitted = fitToBudget(s, m, slotBudget(s, slot, moveFactorPct));
  if (fitted == null) return reject('over budget');
  if (!identical(fitted, m)) w.add('scaled to budget');
  return MoveValidation(fitted, w);
}

/// Outcome of one slot of [validateAiMoveSet].
class SlotValidation {
  SlotValidation(this.slot, this.result);
  final int slot;
  final MoveValidation result;

  bool get accepted => !result.rejected;

  /// The normalised proposal to persist (`Move.toJson()` of the accepted
  /// move), or null when the slot falls back to the offline move.
  Map<String, Object?>? get proposal => result.move?.toJson();
}

/// Validates a whole AI answer `{"moves": [m0, m1, m2, m3]}` (index = slot).
/// Missing / malformed entries and a name already used by an earlier
/// accepted slot are rejected; rejected slots fall back to the offline move
/// ([resolveWithOffline]). Always returns 4 results.
List<SlotValidation> validateAiMoveSet(
  V3Spec s,
  Object? json, {
  required Attr own,
  required int moveFactorPct,
  bool Function(String)? ngCheck,
}) {
  final raw = json is Map ? json['moves'] : null;
  final list = raw is List ? raw : const <Object?>[];
  final names = <String>{};
  return [
    for (var slot = 0; slot < 4; slot++)
      SlotValidation(slot, () {
        final m = slot < list.length ? list[slot] : null;
        if (m is! Map) {
          return MoveValidation(
            null,
            const [],
            rejected: true,
            reason: 'missing',
          );
        }
        final v = validateAiMove(
          s,
          m.cast<String, Object?>(),
          slot: slot,
          own: own,
          moveFactorPct: moveFactorPct,
          ngCheck: ngCheck,
        );
        if (v.rejected) return v;
        if (!names.add(v.move!.name)) {
          return MoveValidation(
            null,
            v.warnings,
            rejected: true,
            reason: 'duplicate name',
          );
        }
        return v;
      }()),
  ];
}

/// The moves a character fights with: per slot the accepted AI move, else
/// the offline move ([offline] = `generateOfflineMoves`, 4 entries).
List<Move> resolveWithOffline(List<Move> offline, List<SlotValidation> v) => [
  for (var i = 0; i < offline.length; i++)
    i < v.length && v[i].accepted ? v[i].result.move! : offline[i],
];
