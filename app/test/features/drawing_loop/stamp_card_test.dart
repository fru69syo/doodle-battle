import 'package:doodle_battle/core/providers.dart';
import 'package:doodle_battle/data/drawing_loop_storage.dart';
import 'package:doodle_battle/domain/cosmetics.dart';
import 'package:doodle_battle/features/drawing_loop/odai/daily_odai.dart';
import 'package:doodle_battle/features/drawing_loop/odai/odai_controller.dart';
import 'package:doodle_battle/features/drawing_loop/odai/stamp_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

OdaiStamp stamp(String date, {StampKind kind = StampKind.character}) =>
    OdaiStamp(date: date, themeId: 'g1', text: 'つばさの ある いきもの', kind: kind);

void main() {
  group('OdaiStampCard', () {
    test('one stamp per day; the first drawing of the day keeps it', () {
      var card = OdaiStampCard.empty.withStamp(stamp('2026-10-10'));
      final again = card.withStamp(stamp('2026-10-10', kind: StampKind.part));
      expect(identical(again, card), isTrue);
      expect(card.total, 1);
      expect(card.byDate['2026-10-10']!.kind, StampKind.character);
      card = card.withStamp(stamp('2026-10-11'));
      expect(card.total, 2);
      expect(card.hasStampOn('2026-10-11'), isTrue);
      expect(card.hasStampOn('2026-10-12'), isFalse);
    });

    test('cumulative only: gaps never reduce anything (no streaks)', () {
      final everyDay = [
        for (var d = 1; d <= 10; d++) '2026-10-${d.toString().padLeft(2, '0')}',
      ];
      final sparse = [
        '2026-01-03',
        '2026-02-14',
        '2026-05-05',
        '2026-07-07',
        '2026-08-30',
        '2026-09-01',
        '2026-10-01',
        '2026-10-20',
        '2026-11-11',
        '2026-12-24',
      ];
      OdaiStampCard build(List<String> dates) =>
          dates.fold(OdaiStampCard.empty, (c, d) => c.withStamp(stamp(d)));
      final a = build(everyDay), b = build(sparse);
      expect(a.total, b.total);
      expect(a.nextDesign, b.nextDesign);
      expect(a.stampsToNextDesign, b.stampsToNextDesign);
      expect(
        a.designOf(everyDay.last),
        b.designOf(sparse.last),
        reason: 'the 10th stamp looks the same however long it took',
      );
    });

    test('designs open every 5 stamps, then stay', () {
      expect(StampDesign.forOrdinal(1), StampDesign.hanamaru);
      expect(StampDesign.forOrdinal(5), StampDesign.hanamaru);
      expect(StampDesign.forOrdinal(6), StampDesign.hoshi);
      expect(StampDesign.forOrdinal(11), StampDesign.niji);
      expect(StampDesign.forOrdinal(21), StampDesign.rocket);
      expect(StampDesign.forOrdinal(500), StampDesign.rocket);

      var card = OdaiStampCard.empty;
      expect(card.stampsToNextDesign, 5);
      expect(card.upcomingDesign, StampDesign.hoshi);
      for (var d = 1; d <= 7; d++) {
        card = card.withStamp(stamp('2026-03-${d.toString().padLeft(2, '0')}'));
      }
      expect(card.stampsToNextDesign, 3);
      expect(card.upcomingDesign, StampDesign.niji);
      expect(card.designOf('2026-03-01'), StampDesign.hanamaru);
      expect(card.designOf('2026-03-06'), StampDesign.hoshi);
      for (var d = 1; d <= 20; d++) {
        card = card.withStamp(stamp('2026-04-${d.toString().padLeft(2, '0')}'));
      }
      expect(card.total, 27);
      expect(card.stampsToNextDesign, isNull);
      expect(card.upcomingDesign, isNull);
    });

    test('inMonth groups by local day', () {
      final card = OdaiStampCard.empty
          .withStamp(stamp('2026-10-01'))
          .withStamp(stamp('2026-10-31'))
          .withStamp(stamp('2026-11-01'));
      expect(card.inMonth(2026, 10).keys, unorderedEquals([1, 31]));
      expect(card.inMonth(2026, 11).keys, [1]);
      expect(card.inMonth(2025, 10), isEmpty);
    });

    test('JSON round-trip, lenient about broken entries', () {
      final card = OdaiStampCard.empty
          .withStamp(stamp('2026-10-01'))
          .withStamp(
            const OdaiStamp(
              date: '2026-10-02',
              themeId: 'e_halloween_0',
              text: 'かぼちゃの おばけ',
              kind: StampKind.effect,
              characterId: 'c_1',
            ),
          );
      final back = OdaiStampCard.fromJson(card.toJson());
      expect(back.toJson(), card.toJson());
      expect(back.byDate['2026-10-02']!.characterId, 'c_1');
      final broken = OdaiStampCard.fromJson({
        'stamps': [
          {'date': 'not-a-date'},
          {'nope': 1},
          'x',
          {'date': '2026-01-01', 'kind': 'future-kind'},
        ],
      });
      expect(broken.total, 1);
      expect(broken.byDate['2026-01-01']!.kind, StampKind.character);
      expect(OdaiStampCard.fromJson(null).total, 0);
      expect(OdaiStampCard.fromJson({'stamps': 3}).total, 0);
    });
  });

  group('controllers', () {
    test('award persists and completes the active theme once', () async {
      final storage = InMemoryDrawingLoopStorage();
      final container = ProviderContainer(
        overrides: [
          drawingLoopStorageProvider.overrideWithValue(storage),
          clockProvider.overrideWithValue(() => DateTime(2026, 10, 10, 18)),
        ],
      );
      addTearDown(container.dispose);
      final theme = container.read(todaysOdaiProvider);
      expect(theme, odaiFor(DateTime(2026, 10, 10)));

      // Nothing active → nothing happens.
      expect(
        await completeActiveOdai(container.read, kind: StampKind.character),
        isNull,
      );

      container.read(activeOdaiProvider.notifier).start(theme);
      final badge = await completeActiveOdai(
        container.read,
        kind: StampKind.character,
        characterId: 'c_1',
      );
      expect(badge, isNotNull);
      expect(badge!.date, '2026-10-10');
      expect(container.read(activeOdaiProvider), isNull);
      final card = await container.read(stampCardProvider.future);
      expect(card.total, 1);
      expect(OdaiStampCard.fromJson(storage.stampCard).total, 1);

      // Same day again: still celebrated by the drawing, no second stamp.
      container.read(activeOdaiProvider.notifier).start(theme);
      expect(
        await completeActiveOdai(container.read, kind: StampKind.part),
        isNull,
      );
      expect((await container.read(stampCardProvider.future)).total, 1);
    });

    test('badge text is frozen at the time of drawing', () {
      const b = OdaiBadge(themeId: 'g3', date: '2026-10-10', text: 'あ');
      expect(OdaiBadge.fromJson(b.toJson()), b);
    });
  });
}
