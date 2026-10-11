import 'dart:ui' show FrameTiming;

import '../puppet/puppet_builder.dart';

/// Rendering tier of the stage.
enum StageQuality {
  /// Mesh grid 64, all props, clouds, vignette, full particles.
  high(particles: 1, puppet: PuppetQuality.high),

  /// Old / slow phones: mesh grid 40, half the props, no clouds or
  /// vignette, 40 % particles.
  low(particles: 0.4, puppet: PuppetQuality.low);

  const StageQuality({required this.particles, required this.puppet});
  final double particles;
  final PuppetQuality puppet;
}

/// A simple adaptive quality switch: watches real frame timings and drops
/// to [StageQuality.low] once frames are clearly over budget for a while.
/// It never switches back up during a battle (no flicker between tiers);
/// the choice is remembered for the next battle by the caller
/// ([downgraded]).
///
/// Feed it from `SchedulerBinding.instance.addTimingsCallback`.
class AdaptiveQuality {
  AdaptiveQuality({
    StageQuality initial = StageQuality.high,
    this.budgetMs = 20,
    this.window = 90,
    this.slowShare = 0.25,
    this.onChange,
  }) : _quality = initial;

  /// A frame slower than this (build + raster, ms) counts as slow. 20 ms
  /// leaves headroom on 60 Hz; on low tier the stage is fine at 30 fps.
  final double budgetMs;

  /// Frames per decision window (~1.5 s at 60 fps).
  final int window;

  /// Share of slow frames in a window that triggers the downgrade.
  final double slowShare;
  final void Function(StageQuality q)? onChange;

  StageQuality _quality;
  int _frames = 0, _slow = 0, _badWindows = 0;

  StageQuality get quality => _quality;
  bool get downgraded => _quality == StageQuality.low;

  void onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      addFrame(
        (t.buildDuration.inMicroseconds + t.rasterDuration.inMicroseconds) /
            1000,
      );
    }
  }

  /// Records one frame's cost (ms). Exposed for tests.
  void addFrame(double ms) {
    if (_quality == StageQuality.low) return;
    _frames++;
    if (ms > budgetMs) _slow++;
    if (_frames < window) return;
    final bad = _slow / _frames >= slowShare;
    _badWindows = bad ? _badWindows + 1 : 0;
    _frames = 0;
    _slow = 0;
    // Two bad windows in a row (≈ 3 s): not a one-off hitch (GC, the first
    // shader compile...).
    if (_badWindows >= 2) {
      _quality = StageQuality.low;
      onChange?.call(_quality);
    }
  }
}
