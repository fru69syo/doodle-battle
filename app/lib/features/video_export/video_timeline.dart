/// Timeline of the Before/After video (docs/VIDEO.md §3). Pure: no
/// rendering, so the composition logic can be unit-tested.
library;

/// Output size (9:16) and frame rate.
const int kVideoWidth = 720;
const int kVideoHeight = 1280;
const int kVideoFps = 30;

/// Smaller size used when the device's encoder rejects 720×1280 (both
/// multiples of 16).
const int kVideoFallbackWidth = 576;
const int kVideoFallbackHeight = 1024;

/// Allowed total length (SPEC §11.2-1: 10–15 s).
const double kMinVideoSeconds = 10;
const double kMaxVideoSeconds = 15;

/// Captions (hiragana; no skill / score wording anywhere).
abstract final class VideoTexts {
  static const before = 'かみに かいた え が…';
  static const birth = 'うごきだした！';
  static const battleStart = 'バトル！';
  static const win = 'かった！';
  static const logo = 'らくがきバトル';
  static const tagline = 'かみに かいた え が たたかう！';
  static const store = 'Android アプリ「らくがきバトル」';
}

enum VideoScene { before, birth, battle, endCard }

/// Lengths (seconds) of the battle beats.
abstract final class BattleBeats {
  static const intro = 0.7;
  static const hit = 1.8;
  static const outroAfterSingleHit = 0.7;
  static const outroAfterTwoHits = 0.3;
}

/// Which scene a moment belongs to, and how far into it.
class SceneTime {
  const SceneTime(this.scene, this.local, this.length);

  final VideoScene scene;

  /// Seconds since the scene started.
  final double local;

  /// Length of the scene in seconds.
  final double length;

  /// 0..1 through the scene.
  double get progress => length <= 0 ? 1 : (local / length).clamp(0.0, 1.0);

  @override
  String toString() => 'SceneTime($scene, $local / $length)';
}

/// Which beat of the battle scene a moment belongs to.
sealed class BattleBeat {
  const BattleBeat(this.local);

  /// Seconds since the beat started.
  final double local;
}

class IntroBeat extends BattleBeat {
  const IntroBeat(super.local);
}

class HitBeat extends BattleBeat {
  const HitBeat(this.index, super.local);
  final int index;
}

/// After the last hit (holds the final pose).
class OutroBeat extends BattleBeat {
  const OutroBeat(super.local);
}

class VideoTimeline {
  const VideoTimeline({
    this.before = 3.0,
    this.birth = 3.0,
    required this.battle,
    this.endCard = 2.8,
    required this.hits,
    this.fps = kVideoFps,
  });

  /// Timeline for a battle highlight with [hits] (1 or 2) player hits.
  factory VideoTimeline.forHits(int hits) {
    final n = hits.clamp(1, 2);
    return VideoTimeline(
      battle:
          BattleBeats.intro +
          BattleBeats.hit * n +
          (n == 1
              ? BattleBeats.outroAfterSingleHit
              : BattleBeats.outroAfterTwoHits),
      hits: n,
    );
  }

  final double before;
  final double birth;
  final double battle;
  final double endCard;
  final int hits;
  final int fps;

  double get duration => before + birth + battle + endCard;

  int get frameCount => (duration * fps).round();

  /// Presentation time of frame [i] in seconds.
  double timeOfFrame(int i) => i / fps;

  /// Start time of each scene.
  Map<VideoScene, double> get starts => {
    VideoScene.before: 0,
    VideoScene.birth: before,
    VideoScene.battle: before + birth,
    VideoScene.endCard: before + birth + battle,
  };

  SceneTime sceneAt(double t) {
    if (t < before) return SceneTime(VideoScene.before, _pos(t), before);
    t -= before;
    if (t < birth) return SceneTime(VideoScene.birth, t, birth);
    t -= birth;
    if (t < battle) return SceneTime(VideoScene.battle, t, battle);
    t -= battle;
    return SceneTime(VideoScene.endCard, t.clamp(0, endCard), endCard);
  }

  /// Beat of the battle scene at [local] seconds into it.
  BattleBeat battleBeatAt(double local) {
    if (local < BattleBeats.intro) return IntroBeat(_pos(local));
    var t = local - BattleBeats.intro;
    for (var i = 0; i < hits; i++) {
      if (t < BattleBeats.hit) return HitBeat(i, t);
      t -= BattleBeats.hit;
    }
    return OutroBeat(t);
  }

  static double _pos(double t) => t < 0 ? 0 : t;
}
