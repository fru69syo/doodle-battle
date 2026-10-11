// Engine v3 — levels, XP, ads, rated sync, family battles, stages.
import 'package:doodle_battle/domain/battle_v3/battle_v3.dart';
import 'package:doodle_battle/domain/battle_v3/sim.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const s = V3Spec();

  test('XP curve and rewards', () {
    expect(xpToNext(s, 1), 80);
    expect(xpToNext(s, 10), 335);
    expect(xpToNext(s, 50), 2935);
    expect(xpToNext(s, 99), 9390);
    expect(totalXpTo(s, 100), 351165);
    expect(xpSinglePlayer(win: true, stage: 1, level: 1), 100);
    expect(xpSinglePlayer(win: false, stage: 1, level: 1), 40);
    expect(xpSinglePlayer(win: true, stage: 10, level: 35), 27); // replay 20 %
    expect(
      xpSinglePlayer(win: true, stage: 10, level: 35, hiddenBloomer: true),
      272,
    );
    expect(
      xpSinglePlayer(win: true, stage: 5, level: 5, firstClear: true),
      232,
    );
    expect(xpSinglePlayer(win: true, stage: 5, level: 5, adBoost: true), 232);
    expect(xpOnline(win: true, level: 1, eligible: true), 150);
    expect(xpOnline(win: true, level: 1, eligible: false), 0);
    expect(kFamilyBattleXp, 0);
  });

  test('rewarded ad: Android only, parent-approved, 3 a day', () {
    bool ok(AppPlatform p, int used, {bool parent = true}) =>
        adBoostAvailable(platform: p, parentAllowsAds: parent, usedToday: used);
    expect(ok(AppPlatform.android, 0), isTrue);
    expect(ok(AppPlatform.android, 2), isTrue);
    expect(ok(AppPlatform.android, 3), isFalse);
    expect(ok(AppPlatform.ios, 0), isFalse);
    expect(ok(AppPlatform.android, 0, parent: false), isFalse);
  });

  test('applyXp levels up, unlocks slots at Lv10 / Lv50, stops at 100', () {
    var p = applyXp(s, level: 1, xp: 0, gained: 79);
    expect((p.level, p.xp, p.levelledUp), (1, 79, false));
    p = applyXp(s, level: 9, xp: 0, gained: xpToNext(s, 9));
    expect(p.level, 10);
    expect(p.newSlots, [2]);
    expect(p.evolutions, ['kagayaki']);
    p = applyXp(s, level: 49, xp: 0, gained: xpToNext(s, 49), isBloomer: true);
    expect(p.newSlots, [3]);
    expect(p.evolutions, ['densetsu']);
    expect(p.rebirth, isTrue);
    p = applyXp(s, level: 49, xp: 0, gained: xpToNext(s, 49));
    expect(p.rebirth, isFalse);
    p = applyXp(s, level: 99, xp: 0, gained: 1 << 30);
    expect((p.level, p.xp), (100, 0));
    expect(unlockedSlots(s, 1), 2);
    expect(unlockedSlots(s, 10), 3);
    expect(unlockedSlots(s, 50), 4);
  });

  test('rated sync: Lv50 stats, actual unlocked slots, bloomer pre-form', () {
    final r = Mulberry32(31);
    final kid = randomKid(s, r);
    final low = ratedSetup(s, kid, actualLevel: 7);
    final high = ratedSetup(s, kid, actualLevel: 90);
    expect(low.stats, kid.statsAt(50));
    expect(high.stats, kid.statsAt(50));
    expect(low.moves, hasLength(2));
    expect(ratedSetup(s, kid, actualLevel: 10).moves, hasLength(3));
    expect(high.moves, hasLength(4));
    final b = randomBloomer(s, r);
    final pre = ratedSetup(s, b, actualLevel: 30);
    expect(pre.stats, b.statsAt(50, preForm: true));
    final post = ratedSetup(s, b, actualLevel: 60);
    expect(post.stats, b.statsAt(50));
    final sum = (List<int> x) => x.fold<int>(0, (a, v) => a + v);
    expect(sum(pre.stats), lessThan(sum(post.stats)));
  });

  test('family battle level and the hidden form', () {
    expect(
      familyBattleLevel(s, ownLevel: 5, otherLevel: 30, sameLevel: true),
      30,
    );
    expect(
      familyBattleLevel(
        s,
        ownLevel: 5,
        otherLevel: 30,
        sameLevel: false,
        boost: 3,
      ),
      8,
    );
    expect(
      familyBattleLevel(
        s,
        ownLevel: 99,
        otherLevel: 1,
        sameLevel: false,
        boost: 10,
      ),
      100,
    );
    final b = randomBloomer(s, Mulberry32(4));
    final f = familySetup(s, b, actualLevel: 30, battleLevel: 60);
    expect(f.stats, b.statsAt(60, preForm: true));
  });

  test('stage table: 10 worlds × 10, tiers, bosses, CPU power', () {
    final t = stageTable();
    expect(t, hasLength(100));
    expect(t.where((st) => st.boss), hasLength(10));
    expect(t.first.tier, AiTier.weak);
    expect(t[20].tier, AiTier.normal);
    expect(t[60].tier, AiTier.strong);
    for (final st in t) {
      expect(st.recommendedLevel, st.stage);
      expect(st.cpuLevel, st.stage);
      expect(kWorldRosters[st.world - 1], contains(st.cpuId));
      if (st.boss) expect(st.cpuId, kWorldRosters[st.world - 1].last);
    }
    for (final roster in kWorldRosters) {
      expect(roster.length, inInclusiveRange(3, 5));
    }
  });

  test('Elo and badges', () {
    expect(eloDelta(1000, 1000, true, 48), 24);
    expect(eloDelta(610, 900, false, 48), -8);
    expect(eloDelta(605, 900, false, 48), -5); // rating floor 600
    expect(eloK(0), 48);
    expect(eloK(20), 24);
    expect(eloK(20, ghost: true), 12);
    expect(badgeFor(1000), 'たまご');
    expect(badgeFor(1460), 'ライオン');
    expect(matchBand(0), 100);
    expect(matchBand(60), 400);
  });
}
