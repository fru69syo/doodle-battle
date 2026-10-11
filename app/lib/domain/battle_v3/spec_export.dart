/// Builds `shared/battle_spec_v3/battle_spec_v3.json` (the engine-agnostic,
/// normative copy of every number) from the Dart engine
/// (`dart run tool/v3_sim.dart spec`; a test checks the committed copy).
library;

import '../rig_blob.dart';
import 'ai.dart';
import 'moves.dart';
import 'progression.dart';
import 'spec.dart';
import 'stages.dart';

Map<String, Object?> fullSpecJson(V3Spec s) => {
  ...s.toJson(),
  'featureUnits': kFeatureUnits,
  'moveTemplates': {
    for (final e in kTemplates.entries) e.key: e.value.toJson(),
  },
  'moveRules': {
    'secondaryRanges': {
      for (final e in kSecondaryRanges.entries) e.key: e.value.toJson(),
    },
    'atkFormulas': {
      for (final f in AtkFormula.values)
        f.code: {
          'a': f.a.code,
          'pa': f.pa,
          'b': f.b.code,
          'pb': f.pb,
          'physical': f.physical,
        },
    },
    'stageStats': [for (final st in kStageStats) st.code],
    'vfx': kVfx,
    'colours': kColours,
    'values': {
      'damage':
          'power*accuracy*(200+critBonus)*hitsAdjPct[hits]/(100*200*100) '
          '+ secondary',
      'hitsAdjPct': kHitsAdjPct,
      'secondary': {
        'poison': 'chance*$kPoisonValue/100',
        'paralyze': 'chance*$kParalyzeValue/100',
        'debuff': 'chance*$kDebuffSecondaryValue/100 (1 stage, 60 ticks)',
        'drain': 'drainPct*power/100',
      },
      'heal': 'healPct*$kHealValuePerPct',
      'buff': 'stages*durationTicks*5*(AGI?120:100)/800',
      'debuff': 'stages*durationTicks*5*(AGI?120:100)*accuracy/80000',
      'status':
          'statusValue*chance*accuracy/10000 '
          '(poison $kPoisonValue, paralyze $kParalyzeValue)',
      'shield': 'shieldPct*durationTicks/30',
    },
    'discount':
        'spCost*5/4 + castTicks*2 + max(0, cooldownTicks - freeCooldown)/2, '
        'capped at value*maxDiscountPct/100; freeCooldown: heal 60, '
        'buff/debuff max(20,durationTicks), shield 40, else 20',
    'cost': 'value - discount <= slotBudgets[slot]*moveFactorPct/100',
    'slotRules': [
      'slot1: damage template, attribute = own, spCost 0, cooldown 0, cast <= 5',
      'slot2: attribute != own (support moves: none)',
      'slot3: any template',
      'slot4 (ひっさつ): damage template, attribute none',
      'heal/buff/shield: attribute none',
      'buff/debuff: cooldownTicks >= durationTicks',
    ],
  },
  'ai': {
    'randomPct': {for (final t in AiTier.values) t.name: t.randomPct},
    'thinkTicks': {for (final t in AiTier.values) t.name: t.thinkTicks},
    'note':
        'chooseMove (ai.dart / ai.ts) is normative; the timeout auto-pick, '
        'おまかせ and server ghosts use normal; strong scores with '
        'scoreMoveStrong',
  },
  'progression': {
    'evolutions': {for (final e in kEvolutions.entries) '${e.key}': e.value},
    'xpSinglePlayer': {
      'win': 100,
      'lose': 40,
      'stagePct': '100 + 4*(stage-1)',
      'replayPct': 'level-stage <= 10: 100, <= 20: 50, else 20',
      'firstClearMultiplier': 2,
      'adBoostMultiplier': 2,
      'adBoostPerDay': 3,
      'hiddenBloomerMultiplier': 2,
      'hiddenBloomerReplayExempt': true,
    },
    'xpOnline': {
      'win': 150,
      'lose': 60,
      'levelPct': '100 + 4*(level-1)',
      'battlesPerDay': kOnlineXpBattlesPerDay,
      'sameOpponentCooldownMinutes': 60,
      'adBoost': false,
    },
    'stages': {
      'count': 100,
      'worlds': kWorldNames,
      'powerPctByPosition': kStagePowerPct,
      'aiTier': 'stage 1-20 weak, 21-60 normal, 61-100 strong',
      'powerPctTable': kStagePowerTable,
      'worldRosters': kWorldRosters,
      'table': [for (final st in stageTable()) st.toJson()],
    },
    'rated': {
      'unlockLevel': kRatedUnlockLevel,
      'syncLevel': kRatedSyncLevel,
      'ratingStart': kRatingStart,
      'ratingFloor': kRatingFloor,
      'k': 'first 20 games 48, then 24; ghost matches half',
      'badges': [
        for (final (min, name) in kBadges) {'min': min, 'name': name},
      ],
      'badgeRule': 'shown badge = best ever (never goes down)',
      'matchBand': '100 + 50*(waitSeconds/5), max 400',
      'ghostAfterSeconds': kGhostAfterSeconds,
      'statsAt':
          'statsAt(syncLevel) with preForm for a bloomer below its '
          'rebirth level; slots unlocked at the actual level',
    },
    'family': {
      'xp': kFamilyBattleXp,
      'battleLevel':
          'max(own, other) if sameLevel else own, + boost, '
          'clamped 1..maxLevel; bloomers below Lv50 keep the pre-rebirth form',
    },
    'adBoost': {
      'platforms': ['android'],
      'perDay': kAdBoostsPerDay,
      'singlePlayerOnly': true,
    },
  },
  'rig': {
    'version': kRigVersion,
    'maxBytes': kRigMaxBytes,
    'maxLimbs': kRigMaxLimbs,
    'maxSide': kRigMaxSide,
    'limbKinds': kRigLimbKinds.toList(),
    'sources': kRigSources.toList(),
  },
};
