import 'package:doodle_battle/core/config/app_config.dart';
import 'package:doodle_battle/features/video_export/video_composer.dart';
import 'package:doodle_battle/features/video_export/video_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoTimeline', () {
    for (final hits in [1, 2]) {
      test('$hits hit(s): 10–15 s at 30 fps, scenes in order', () {
        final tl = VideoTimeline.forHits(hits);
        expect(
          tl.duration,
          inInclusiveRange(kMinVideoSeconds, kMaxVideoSeconds),
        );
        expect(tl.fps, 30);
        expect(tl.frameCount, (tl.duration * 30).round());
        final starts = tl.starts;
        expect(starts[VideoScene.before], 0);
        expect(starts[VideoScene.birth], tl.before);
        expect(starts[VideoScene.battle], tl.before + tl.birth);
        expect(
          starts[VideoScene.endCard],
          closeTo(tl.duration - tl.endCard, 1e-9),
        );
        // Every frame maps to a scene, in non-decreasing scene order.
        var last = 0;
        for (var i = 0; i < tl.frameCount; i++) {
          final s = tl.sceneAt(tl.timeOfFrame(i));
          expect(s.scene.index, greaterThanOrEqualTo(last));
          expect(s.local, inInclusiveRange(0, s.length));
          last = s.scene.index;
        }
        expect(last, VideoScene.endCard.index);
      });
    }

    test('scene boundaries', () {
      final tl = VideoTimeline.forHits(2);
      expect(tl.sceneAt(0).scene, VideoScene.before);
      expect(tl.sceneAt(tl.before - 0.001).scene, VideoScene.before);
      expect(tl.sceneAt(tl.before).scene, VideoScene.birth);
      expect(tl.sceneAt(tl.before).local, 0);
      final battle = tl.sceneAt(tl.before + tl.birth + 1);
      expect(battle.scene, VideoScene.battle);
      expect(battle.local, closeTo(1, 1e-9));
      expect(battle.progress, closeTo(1 / tl.battle, 1e-9));
      // Past the end clamps to the last moment of the end card.
      final end = tl.sceneAt(tl.duration + 5);
      expect(end.scene, VideoScene.endCard);
      expect(end.progress, 1);
    });

    test('battle beats: intro, each hit, outro', () {
      final tl = VideoTimeline.forHits(2);
      expect(tl.battleBeatAt(0), isA<IntroBeat>());
      final h0 = tl.battleBeatAt(BattleBeats.intro + 0.5);
      expect(h0, isA<HitBeat>().having((b) => b.index, 'index', 0));
      expect(h0.local, closeTo(0.5, 1e-9));
      final h1 = tl.battleBeatAt(BattleBeats.intro + BattleBeats.hit + 0.1);
      expect(h1, isA<HitBeat>().having((b) => b.index, 'index', 1));
      expect(tl.battleBeatAt(tl.battle - 0.01), isA<OutroBeat>());

      final single = VideoTimeline.forHits(1);
      expect(
        single.battleBeatAt(BattleBeats.intro + BattleBeats.hit + 0.2),
        isA<OutroBeat>(),
      );
      expect(single.battle, lessThan(tl.battle));
    });

    test('captions never mention skill or scores', () {
      const all = [
        VideoTexts.before,
        VideoTexts.birth,
        VideoTexts.battleStart,
        VideoTexts.win,
        VideoTexts.logo,
        VideoTexts.tagline,
        VideoTexts.store,
      ];
      for (final t in all) {
        for (final banned in ['しょぼ', 'じょうず', 'のびのび', 'げいじゅつ']) {
          expect(t.contains(banned), isFalse, reason: t);
        }
      }
      expect(VideoTexts.before, 'かみに かいた え が…');
    });
  });

  test('the end-card logo is the app name and shrinks to fit the frame', () {
    expect(VideoTexts.logo, appDisplayName);
    expect(VideoTexts.store, contains(appDisplayName));
    expect(videoLogoFontSize(400), kVideoLogoMaxFontSize);
    expect(videoLogoFontSize(kVideoLogoMaxWidth), kVideoLogoMaxFontSize);
    final size = videoLogoFontSize(920); // 10 glyphs at 92
    expect(size, lessThan(kVideoLogoMaxFontSize));
    expect(920 * size / kVideoLogoMaxFontSize, lessThanOrEqualTo(620));
  });
}
