/// Paints one moment of the Before/After video onto a canvas in a fixed
/// 720×1280 coordinate space (docs/VIDEO.md §3). Deterministic: the same
/// content and time always give the same picture, so it is used both for
/// the off-screen frames that get encoded and for the live preview.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/before_photo.dart';
import '../../domain/battle/battle.dart' show BattleAction;
import '../../domain/element_type.dart';
import 'battle_highlight.dart';
import 'video_timeline.dart';

const _font = 'ZenMaruGothic';
const _w = kVideoWidth * 1.0;
const _h = kVideoHeight * 1.0;

/// Everything shown in the video, already decoded.
class VideoContent {
  VideoContent({
    required this.before,
    required this.inkRect,
    required this.character,
    required this.name,
    required this.element,
    required this.highlight,
    required this.cpuImage,
    this.original,
    this.moveEffects = const {},
  });

  /// The paper photo (or the generated paper fallback).
  final ui.Image before;

  /// Where the drawing is on [before] (normalised).
  final NormRect inkRect;

  /// The character's display image (cut-out; includes drawn-on parts once
  /// the Loop feature composites them into it).
  final ui.Image character;
  final String name;
  final ElementType element;
  final BattleHighlight highlight;
  final ui.Image cpuImage;

  /// The plain cut-out of the paper drawing (without drawn-on parts), used
  /// where the character still sits on the paper. Null = [character].
  final ui.Image? original;

  /// The child's drawn move effects by move (Loop feature); drawn as the
  /// projectile, otherwise an element-coloured energy ball.
  final Map<BattleAction, ui.Image> moveEffects;

  ui.Image get drawing => original ?? character;
}

/// Paints frames of the video for one [VideoContent].
class VideoComposer {
  VideoComposer(this.content)
    : timeline = VideoTimeline.forHits(content.highlight.hits.length),
      _accent = AppColors.element(content.element) {
    final r = math.Random(20261010);
    _sparkles = [
      for (var i = 0; i < 26; i++)
        _Sparkle(
          angle: r.nextDouble() * math.pi * 2,
          distance: 120 + r.nextDouble() * 260,
          size: 10 + r.nextDouble() * 22,
          delay: r.nextDouble() * 0.35,
          hue: r.nextInt(5),
        ),
    ];
    _burst = [
      for (var i = 0; i < 14; i++)
        _Sparkle(
          angle: i / 14 * math.pi * 2 + r.nextDouble() * 0.3,
          distance: 90 + r.nextDouble() * 90,
          size: 10 + r.nextDouble() * 14,
          delay: r.nextDouble() * 0.08,
          hue: r.nextInt(5),
        ),
    ];
  }

  final VideoContent content;
  final VideoTimeline timeline;
  final Color _accent;
  late final List<_Sparkle> _sparkles;
  late final List<_Sparkle> _burst;
  final _texts = _TextCache();

  static const _palette = [
    AppColors.gold,
    Color(0xFFFFFFFF),
    AppColors.pink,
    Color(0xFF7FDBFF),
    AppColors.primary,
  ];

  /// Paints the frame at [t] seconds into a 720×1280 canvas.
  void paint(Canvas canvas, double t) {
    canvas.save();
    canvas.clipRect(const Rect.fromLTWH(0, 0, _w, _h));
    final s = timeline.sceneAt(t);
    switch (s.scene) {
      case VideoScene.before:
        _paintBefore(canvas, s.local);
      case VideoScene.birth:
        _paintBirth(canvas, s.local);
      case VideoScene.battle:
        _paintBattle(canvas, s.local);
      case VideoScene.endCard:
        _paintEndCard(canvas, s.local);
    }
    if (s.scene != VideoScene.endCard) _paintWatermark(canvas);
    // White flash between scenes.
    final flash = _flashAt(t);
    if (flash > 0) {
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, _w, _h),
        Paint()..color = Color.fromRGBO(255, 255, 255, flash),
      );
    }
    canvas.restore();
  }

  double _flashAt(double t) {
    final starts = timeline.starts;
    var f = 0.0;
    for (final scene in [VideoScene.battle, VideoScene.endCard]) {
      final d = (t - starts[scene]!).abs();
      if (d < 0.15) f = math.max(f, 1 - d / 0.15);
    }
    return f * 0.9;
  }

  // ---------------------------------------------------------------- scenes

  static const _desk = Color(0xFFE9D3B0);
  static const _paperTilt = -0.035;

  /// Where the paper photo sits in scenes 1–2.
  Rect get _paperRect {
    final img = content.before;
    final fit = _fit(
      img.width.toDouble(),
      img.height.toDouble(),
      const Size(620, 860),
    );
    return Rect.fromCenter(
      center: const Offset(_w / 2, 600),
      width: fit.width,
      height: fit.height,
    );
  }

  void _paintDesk(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _w, _h),
      Paint()
        ..shader = ui.Gradient.radial(const Offset(_w / 2, 560), 900, [
          const Color(0xFFF6E7CC),
          _desk,
        ]),
    );
  }

  void _paintPaper(Canvas canvas, double zoom, {double dim = 0}) {
    final rect = _paperRect;
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate(_paperTilt);
    canvas.scale(zoom);
    final r = Rect.fromCenter(
      center: Offset.zero,
      width: rect.width,
      height: rect.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        r.shift(const Offset(10, 16)),
        const Radius.circular(6),
      ),
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    _drawImage(canvas, content.before, r);
    if (dim > 0) {
      canvas.drawRect(r, Paint()..color = Color.fromRGBO(30, 20, 60, dim));
    }
    canvas.restore();
  }

  /// Centre, size and rotation of the drawing on the paper (scene 1 pose).
  ({Offset center, Size size, double angle}) _inkPose(double zoom) {
    final rect = _paperRect;
    final ink = content.inkRect;
    final local = Offset(
      (ink.centerX - 0.5) * rect.width * zoom,
      (ink.centerY - 0.5) * rect.height * zoom,
    );
    final c = math.cos(_paperTilt), s = math.sin(_paperTilt);
    final rotated = Offset(
      local.dx * c - local.dy * s,
      local.dx * s + local.dy * c,
    );
    return (
      center: rect.center + rotated,
      size: Size(
        ink.width * rect.width * zoom,
        ink.height * rect.height * zoom,
      ),
      angle: _paperTilt,
    );
  }

  static const _sceneOneZoomEnd = 1.06;

  void _paintBefore(Canvas canvas, double t) {
    _paintDesk(canvas);
    final zoom = 1 + (_sceneOneZoomEnd - 1) * _ease(t / timeline.before);
    _paintPaper(canvas, zoom);
    // Typewriter caption.
    final text = VideoTexts.before;
    final shown = ((t - 0.4) / 1.4 * text.length).floor().clamp(0, text.length);
    if (shown > 0) {
      _caption(canvas, text.substring(0, shown), y: 1135, full: text);
    }
  }

  void _paintBirth(Canvas canvas, double t) {
    // 0–0.5 glow on the paper; 0.5–1.3 lift-off (the drawing leaves a white
    // silhouette on the paper); 0.9–1.5 the stage replaces the desk; 1.0
    // sparkle burst; then the character bounces.
    final stage = _phase(t, 0.9, 1.5);
    final start = _inkPose(_sceneOneZoomEnd);
    if (stage < 1) {
      _paintDesk(canvas);
      _paintPaper(canvas, _sceneOneZoomEnd, dim: 0.45 * _phase(t, 0.4, 1.2));
      final hole = _phase(t, 0.5, 0.9);
      if (hole > 0) {
        canvas.save();
        canvas.translate(start.center.dx, start.center.dy);
        canvas.rotate(start.angle);
        _drawImage(
          canvas,
          content.drawing,
          Rect.fromCenter(
            center: Offset.zero,
            width: start.size.width,
            height: start.size.height,
          ),
          tint: const Color(0xFFFDFBF6),
          opacity: 0.9 * hole,
        );
        canvas.restore();
      }
    }
    if (stage > 0) {
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, _w, _h),
        Paint()
          ..color = Color.lerp(
            _accent,
            Colors.white,
            0.7,
          )!.withValues(alpha: stage),
      );
      _paintRays(canvas, stage, t, center: const Offset(_w / 2, 560));
    }

    final endBox = _fit(
      content.character.width.toDouble(),
      content.character.height.toDouble(),
      const Size(500, 500),
    );
    final liftRaw = _phase(t, 0.5, 1.3);
    final lift = _easeOutBack(liftRaw);
    // Pops up off the paper (arc) while growing towards the viewer.
    final center =
        Offset.lerp(start.center, const Offset(_w / 2, 560), lift)! -
        Offset(0, math.sin(liftRaw * math.pi) * 150);
    final size = Size.lerp(start.size, endBox, lift)!;
    final angle = ui.lerpDouble(start.angle, 0, lift)!;

    // Glow around the drawing before it lifts.
    final glow = _phase(t, 0.0, 0.4) * (1 - _phase(t, 0.9, 1.3));
    if (glow > 0) {
      canvas.drawOval(
        Rect.fromCenter(
          center: start.center,
          width: start.size.width * 1.25,
          height: start.size.height * 1.25,
        ),
        Paint()
          ..color = AppColors.gold.withValues(alpha: 0.55 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
      );
    }

    // Bounce once it has landed.
    final alive = _phase(t, 1.3, 1.5);
    final hop = alive * math.max(0.0, math.sin((t - 1.3) * 7)).toDouble();
    final squash = 1 + alive * 0.06 * math.sin((t - 1.3) * 14);
    final shadowW = size.width * 0.7 * (1 - hop * 0.25);
    if (lift > 0.05) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(center.dx, center.dy + size.height / 2 + 20),
          width: shadowW,
          height: 34,
        ),
        Paint()..color = Color.fromRGBO(0, 0, 0, 0.25 * _phase(t, 0.5, 1.0)),
      );
    }
    canvas.save();
    canvas.translate(center.dx, center.dy - hop * 60);
    canvas.rotate(angle + alive * 0.05 * math.sin((t - 1.3) * 5));
    canvas.scale(1 / squash, squash);
    final r = Rect.fromCenter(
      center: Offset.zero,
      width: size.width,
      height: size.height,
    );
    // The paper drawing turns into the character (with any drawn-on parts).
    final morph = identical(content.drawing, content.character)
        ? 1.0
        : _phase(t, 0.5, 0.9);
    if (lift > 0.02) {
      // Soft white rim so the cut-out pops off the dark background.
      _drawContain(
        canvas,
        content.character,
        r.inflate(6),
        tint: const Color(0xFFFFFFFF),
        opacity: 0.85 * _phase(t, 0.5, 0.9),
      );
    }
    if (morph < 1) {
      _drawContain(canvas, content.drawing, r, opacity: 1 - morph);
    }
    if (morph > 0) _drawContain(canvas, content.character, r, opacity: morph);
    canvas.restore();

    _paintSparkles(canvas, center, _phase(t, 0.95, 2.2));
    if (t > 1.4) {
      _caption(
        canvas,
        VideoTexts.birth,
        y: 1135,
        scale: _easeOutBack(_phase(t, 1.4, 1.7)),
        color: _accent,
      );
    }
  }

  // Battle layout.
  static const _playerCenter = Offset(220, 900);
  static const _cpuCenter = Offset(515, 450);
  static const _playerBox = Size(330, 330);
  static const _cpuBox = Size(270, 270);
  static const _bannerY = 655.0;

  void _paintBattle(Canvas canvas, double t) {
    final h = content.highlight;
    final beat = timeline.battleBeatAt(t);
    _paintArena(canvas);

    // Defaults: idle positions and HP before the first hit.
    var playerOffset = Offset.zero;
    var cpuOffset = Offset.zero;
    var cpuHp = h.hits.first.targetHpBefore.toDouble();
    var playerHp = h.hits.first.attackerHp.toDouble();
    var cpuFlash = 0.0;
    var cpuFaint = 0.0;
    double? hitLocal;
    HighlightHit? hit;
    final idle = math.sin(t * 6) * 6;

    switch (beat) {
      case IntroBeat(:final local):
        final p = _easeOutCubic(_phase(local, 0, 0.55));
        cpuOffset = Offset(420 * (1 - p), 0);
        playerOffset = Offset(-420 * (1 - p), 0);
      case HitBeat(:final index, :final local):
        hit = h.hits[index];
        hitLocal = local;
        playerHp = hit.attackerHp.toDouble();
        final lunge = local < 0.45
            ? _easeOutCubic(_phase(local, 0.25, 0.45))
            : 1 - _ease(_phase(local, 0.45, 0.75));
        final pullBack =
            _phase(local, 0.0, 0.25) * (1 - _phase(local, 0.25, 0.3));
        playerOffset =
            Offset(80, -60) * lunge - const Offset(24, -12) * pullBack;
        final hpP = _ease(_phase(local, 0.5, 0.9));
        cpuHp = ui.lerpDouble(
          hit.targetHpBefore.toDouble(),
          hit.targetHpAfter.toDouble(),
          hpP,
        )!;
        if (local > 0.45 && local < 0.85) {
          final k = 1 - _phase(local, 0.45, 0.85);
          cpuOffset = Offset(math.sin(local * 90) * 16 * k, 0);
        }
        cpuFlash = local > 0.45 ? 1 - _phase(local, 0.45, 0.6) : 0;
        if (hit.faint) cpuFaint = _phase(local, 1.0, 1.6);
      case OutroBeat():
        final last = h.hits.last;
        hit = last;
        cpuHp = last.targetHpAfter.toDouble();
        playerHp = last.attackerHp.toDouble();
        if (last.faint) cpuFaint = 1;
    }

    // Fighters.
    _paintFighter(
      canvas,
      content.cpuImage,
      _cpuCenter + cpuOffset + Offset(0, cpuFaint > 0 ? 0 : idle * 0.6),
      _cpuBox,
      flash: cpuFlash,
      faint: cpuFaint,
    );
    _paintFighter(
      canvas,
      content.character,
      _playerCenter + playerOffset + Offset(0, -idle),
      _playerBox,
    );

    // Panels.
    _hpPanel(
      canvas,
      name: h.cpu.name,
      level: h.cpuLevel,
      hp: cpuHp,
      maxHp: h.cpuMaxHp.toDouble(),
      topLeft: const Offset(36, 150),
    );
    _hpPanel(
      canvas,
      name: content.name,
      level: null,
      hp: playerHp,
      maxHp: h.playerMaxHp.toDouble(),
      topLeft: const Offset(_w - 36 - 360, 1130),
    );

    if (beat is IntroBeat) {
      final p = _easeOutBack(_phase(beat.local, 0.15, 0.45));
      final fade = 1 - _phase(beat.local, 0.55, 0.7);
      if (p > 0 && fade > 0) {
        _bigText(
          canvas,
          VideoTexts.battleStart,
          const Offset(_w / 2, _bannerY),
          size: 110,
          color: AppColors.primary,
          scale: p,
          opacity: fade,
        );
      }
    }
    if (hit != null && hitLocal != null) {
      _paintHitEffects(canvas, hit, hitLocal, playerOffset);
    }
    final lastHit = h.hits.last;
    if (lastHit.faint) {
      double? winLocal;
      if (beat is HitBeat && beat.index == h.hits.length - 1) {
        winLocal = beat.local - 1.1;
      } else if (beat is OutroBeat) {
        winLocal = BattleBeats.hit - 1.1 + beat.local;
      }
      if (winLocal != null && winLocal > 0) {
        _bigText(
          canvas,
          VideoTexts.win,
          const Offset(_w / 2, _bannerY),
          size: 150,
          color: AppColors.gold,
          scale: _easeOutBack(_phase(winLocal, 0, 0.3)),
        );
      }
    }
  }

  void _paintHitEffects(
    Canvas canvas,
    HighlightHit hit,
    double local,
    Offset playerOffset,
  ) {
    // Move name, then the effectiveness banner in the same spot.
    if (local < 0.6) {
      final p = _easeOutBack(_phase(local, 0, 0.2));
      final fade = 1 - _phase(local, 0.5, 0.6);
      _banner(
        canvas,
        '${hit.moveLabel}！',
        y: _bannerY,
        scale: p,
        opacity: fade,
        background: Colors.white,
        textColor: _accent,
      );
    }
    // Projectile.
    if (local >= 0.25 && local < 0.47) {
      final p = _phase(local, 0.25, 0.45);
      final from = _playerCenter + playerOffset + const Offset(60, -80);
      for (var i = 4; i >= 0; i--) {
        final q = (p - i * 0.06).clamp(0.0, 1.0);
        final pos = Offset.lerp(from, _cpuCenter, _ease(q))!;
        final r = 34.0 - i * 5;
        final drawn = content.moveEffects[hit.action];
        if (drawn != null && i == 0) {
          canvas.save();
          canvas.translate(pos.dx, pos.dy);
          canvas.rotate(p * math.pi);
          _drawContain(
            canvas,
            drawn,
            Rect.fromCenter(center: Offset.zero, width: 150, height: 150),
          );
          canvas.restore();
          continue;
        }
        canvas.drawCircle(
          pos,
          r + 12,
          Paint()
            ..color = _accent.withValues(alpha: 0.35 * (1 - i / 5))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
        );
        canvas.drawCircle(
          pos,
          r,
          Paint()
            ..color = (i == 0 ? Colors.white : _accent).withValues(
              alpha: 1 - i / 6,
            ),
        );
      }
    }
    // Impact.
    if (local >= 0.45 && local < 1.0) {
      final p = _phase(local, 0.45, 1.0);
      if (content.element == ElementType.thunder && p < 0.4) {
        _paintBolt(canvas, _cpuCenter, 1 - p / 0.4);
      }
      canvas.drawCircle(
        _cpuCenter,
        60 + 200 * _easeOutCubic(p),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 18 * (1 - p)
          ..color = _accent.withValues(alpha: 1 - p),
      );
      for (final s in _burst) {
        final q = _phase(p, s.delay, 1);
        if (q <= 0) continue;
        final pos =
            _cpuCenter +
            Offset(math.cos(s.angle), math.sin(s.angle)) *
                (s.distance * _easeOutCubic(q));
        _star(
          canvas,
          pos,
          s.size * (1 - q * 0.6),
          (s.hue.isEven ? _accent : _palette[s.hue]).withValues(alpha: 1 - q),
          q * 3,
        );
      }
    }
    // Damage number.
    if (local >= 0.45 && local < 1.5) {
      final p = _phase(local, 0.45, 1.5);
      _bigText(
        canvas,
        '${hit.damage}',
        _cpuCenter + Offset(90, -150 - 60 * _easeOutCubic(p)),
        size: 72,
        color: AppColors.danger,
        opacity: 1 - _phase(p, 0.7, 1),
        scale: _easeOutBack(_phase(p, 0, 0.2)),
      );
    }
    if (hit.superEffective && local >= 0.6 && local < 1.75) {
      final p = _easeOutBack(_phase(local, 0.6, 0.8));
      final fade = 1 - _phase(local, 1.55, 1.75);
      _banner(
        canvas,
        content.highlight.superText,
        y: _bannerY,
        scale: p,
        opacity: fade,
        background: AppColors.gold,
        textColor: AppColors.ink,
      );
    }
  }

  void _paintEndCard(Canvas canvas, double t) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _w, _h),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, const Offset(0, _h), [
          Color.lerp(_accent, Colors.white, 0.55)!,
          const Color(0xFFFFF8E7),
        ]),
    );
    _paintRays(canvas, 0.35, t, center: const Offset(_w / 2, 470));

    // Before → After.
    final paperIn = _easeOutBack(_phase(t, 0.05, 0.35));
    if (paperIn > 0) {
      final img = content.before;
      final fit = _fit(
        img.width.toDouble(),
        img.height.toDouble(),
        const Size(250, 330),
      );
      canvas.save();
      canvas.translate(178, 470);
      canvas.rotate(-0.1);
      canvas.scale(paperIn);
      final r = Rect.fromCenter(
        center: Offset.zero,
        width: fit.width,
        height: fit.height,
      );
      canvas.drawRect(
        r.inflate(10).shift(const Offset(6, 10)),
        Paint()
          ..color = const Color(0x44000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawRect(r.inflate(10), Paint()..color = Colors.white);
      _drawImage(canvas, img, r);
      canvas.restore();
    }
    final arrowIn = _phase(t, 0.25, 0.45);
    if (arrowIn > 0) _arrow(canvas, const Offset(345, 470), arrowIn);
    final charIn = _easeOutBack(_phase(t, 0.35, 0.65));
    if (charIn > 0) {
      final bob = math.sin(t * 5) * 8;
      final fit = _fit(
        content.character.width.toDouble(),
        content.character.height.toDouble(),
        const Size(330, 370),
      );
      canvas.save();
      canvas.translate(538, 470 + bob);
      canvas.scale(charIn);
      final r = Rect.fromCenter(
        center: Offset.zero,
        width: fit.width,
        height: fit.height,
      );
      _drawImage(
        canvas,
        content.character,
        r.inflate(6),
        tint: Colors.white,
        opacity: 0.9,
      );
      _drawImage(canvas, content.character, r);
      canvas.restore();
    }

    final nameIn = _easeOutBack(_phase(t, 0.55, 0.85));
    if (nameIn > 0) {
      _bigText(
        canvas,
        content.name,
        const Offset(_w / 2, 770),
        size: 76,
        color: AppColors.ink,
        outline: Colors.white,
        scale: nameIn,
        maxWidth: 660,
      );
    }
    _logo(canvas, const Offset(_w / 2, 950), _phase(t, 0.8, 1.4), t);
    final tagIn = _phase(t, 1.3, 1.6);
    if (tagIn > 0) {
      _bigText(
        canvas,
        VideoTexts.tagline,
        const Offset(_w / 2, 1075),
        size: 38,
        color: AppColors.ink,
        outline: Colors.white,
        opacity: tagIn,
        maxWidth: 660,
      );
      _bigText(
        canvas,
        VideoTexts.store,
        const Offset(_w / 2, 1135),
        size: 28,
        color: const Color(0xFF5A5470),
        opacity: tagIn,
        maxWidth: 660,
        bold: false,
      );
    }
  }

  // ------------------------------------------------------------- elements

  void _paintWatermark(Canvas canvas) {
    final p = _texts.get(VideoTexts.logo, size: 26, color: AppColors.ink);
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(24, 28, p.maxIntrinsicWidth + 36, p.height + 14),
      const Radius.circular(40),
    );
    canvas.drawRRect(r, Paint()..color = const Color(0xCCFFFFFF));
    canvas.drawParagraph(p, Offset(42, 35));
  }

  void _paintArena(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _w, 720),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, const Offset(0, 720), [
          const Color(0xFF9ED8FF),
          const Color(0xFFEAF7FF),
        ]),
    );
    canvas.drawRect(
      const Rect.fromLTWH(0, 640, _w, _h - 640),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 640),
          const Offset(0, _h),
          [const Color(0xFFD5F0B5), const Color(0xFF9BD27A)],
        ),
    );
    final pad = Paint()..color = const Color(0x3355882F);
    canvas.drawOval(
      Rect.fromCenter(
        center: _cpuCenter + const Offset(0, 140),
        width: 300,
        height: 70,
      ),
      pad,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: _playerCenter + const Offset(0, 170),
        width: 360,
        height: 80,
      ),
      pad,
    );
  }

  void _paintFighter(
    Canvas canvas,
    ui.Image image,
    Offset center,
    Size box, {
    double flash = 0,
    double faint = 0,
  }) {
    final fit = _fit(image.width.toDouble(), image.height.toDouble(), box);
    canvas.save();
    canvas.translate(center.dx, center.dy + faint * 40);
    canvas.rotate(faint * 0.45);
    final r = Rect.fromCenter(
      center: Offset.zero,
      width: fit.width,
      height: fit.height,
    );
    final opacity = 1 - faint * 0.75;
    _drawImage(
      canvas,
      image,
      r.inflate(5),
      tint: Colors.white,
      opacity: 0.9 * opacity,
    );
    _drawImage(canvas, image, r, opacity: opacity);
    if (flash > 0) {
      _drawImage(canvas, image, r, tint: Colors.white, opacity: flash);
    }
    canvas.restore();
  }

  void _hpPanel(
    Canvas canvas, {
    required String name,
    required int? level,
    required double hp,
    required double maxHp,
    required Offset topLeft,
  }) {
    const width = 360.0;
    final box = RRect.fromRectAndRadius(
      Rect.fromLTWH(topLeft.dx, topLeft.dy, width, 104),
      const Radius.circular(22),
    );
    canvas.drawRRect(
      box.shift(const Offset(0, 5)),
      Paint()..color = const Color(0x33000000),
    );
    canvas.drawRRect(box, Paint()..color = Colors.white);
    canvas.drawRRect(
      box,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = AppColors.ink,
    );
    final label = level == null ? name : '$name  Lv$level';
    final p = _texts.get(
      label,
      size: 32,
      color: AppColors.ink,
      maxWidth: width - 40,
    );
    canvas.drawParagraph(p, topLeft + const Offset(20, 10));
    final ratio = maxHp <= 0 ? 0.0 : (hp / maxHp).clamp(0.0, 1.0);
    final bar = Rect.fromLTWH(topLeft.dx + 20, topLeft.dy + 64, width - 40, 24);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bar, const Radius.circular(12)),
      Paint()..color = const Color(0xFFE3E0EA),
    );
    if (ratio > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(bar.left, bar.top, bar.width * ratio, bar.height),
          const Radius.circular(12),
        ),
        Paint()
          ..color = ratio > 0.5
              ? AppColors.hpHigh
              : ratio > 0.2
              ? AppColors.hpMid
              : AppColors.hpLow,
      );
    }
  }

  void _paintRays(
    Canvas canvas,
    double opacity,
    double t, {
    required Offset center,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(t * 0.25);
    final paint = Paint()
      ..color = Color.lerp(
        _accent,
        Colors.white,
        0.35,
      )!.withValues(alpha: 0.55 * opacity);
    const n = 14;
    for (var i = 0; i < n; i++) {
      final a0 = i / n * math.pi * 2;
      final a1 = a0 + math.pi / n;
      canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(math.cos(a0) * 1500, math.sin(a0) * 1500)
          ..lineTo(math.cos(a1) * 1500, math.sin(a1) * 1500)
          ..close(),
        paint,
      );
    }
    canvas.restore();
    // Soften the centre.
    canvas.drawCircle(
      center,
      420,
      Paint()
        ..shader = ui.Gradient.radial(center, 420, [
          Colors.white.withValues(alpha: 0.5 * opacity),
          Colors.white.withValues(alpha: 0),
        ]),
    );
  }

  void _paintSparkles(Canvas canvas, Offset center, double p) {
    if (p <= 0 || p >= 1) return;
    for (final s in _sparkles) {
      final q = _phase(p, s.delay, s.delay + 0.65);
      if (q <= 0 || q >= 1) continue;
      final pos =
          center +
          Offset(math.cos(s.angle), math.sin(s.angle)) *
              (s.distance * _easeOutCubic(q));
      final a = q < 0.7 ? 1.0 : 1 - (q - 0.7) / 0.3;
      _star(
        canvas,
        pos,
        s.size * (0.6 + 0.4 * math.sin(q * math.pi)),
        _palette[s.hue].withValues(alpha: a),
        q * 4,
      );
    }
  }

  void _paintBolt(Canvas canvas, Offset target, double alpha) {
    final path = Path()
      ..moveTo(target.dx + 40, 0)
      ..lineTo(target.dx - 30, target.dy * 0.45)
      ..lineTo(target.dx + 30, target.dy * 0.5)
      ..lineTo(target.dx - 20, target.dy - 20);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 30
        ..strokeJoin = StrokeJoin.round
        ..color = AppColors.gold.withValues(alpha: 0.5 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withValues(alpha: alpha),
    );
  }

  void _star(Canvas canvas, Offset c, double r, Color color, double rot) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final a = rot + i * math.pi / 4;
      final rr = i.isEven ? r : r * 0.4;
      final p = c + Offset(math.cos(a), math.sin(a)) * rr;
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _arrow(Canvas canvas, Offset c, double p) {
    final paint = Paint()
      ..color = _accent.withValues(alpha: p)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final len = 60 * p;
    canvas.drawLine(c - Offset(len / 2, 0), c + Offset(len / 2, 0), paint);
    canvas.drawPath(
      Path()
        ..moveTo(c.dx + len / 2 - 22, c.dy - 22)
        ..lineTo(c.dx + len / 2, c.dy)
        ..lineTo(c.dx + len / 2 - 22, c.dy + 22),
      paint,
    );
  }

  static const _logoColors = [
    AppColors.primary,
    AppColors.secondary,
    AppColors.success,
    AppColors.gold,
    AppColors.purple,
    AppColors.pink,
    AppColors.danger,
  ];

  void _logo(Canvas canvas, Offset center, double p, double t) {
    if (p <= 0) return;
    const text = VideoTexts.logo;
    const size = 92.0;
    final glyphs = [
      for (var i = 0; i < text.length; i++)
        (
          _texts.get(
            text[i],
            size: size,
            color: _logoColors[i % _logoColors.length],
          ),
          _texts.get(text[i], size: size, stroke: 16, color: AppColors.ink),
        ),
    ];
    final total = glyphs.fold(0.0, (a, g) => a + g.$1.maxIntrinsicWidth);
    var x = center.dx - total / 2;
    for (var i = 0; i < glyphs.length; i++) {
      final (fill, stroke) = glyphs[i];
      final gw = fill.maxIntrinsicWidth;
      final q = _easeOutBack(_phase(p, i * 0.06, i * 0.06 + 0.45));
      if (q > 0) {
        canvas.save();
        final bounce = math.sin(t * 6 + i * 0.9) * 5;
        canvas.translate(x + gw / 2, center.dy + bounce);
        canvas.rotate((i.isEven ? -1 : 1) * 0.06);
        canvas.scale(q);
        final o = Offset(-gw / 2, -fill.height / 2);
        canvas.drawParagraph(stroke, o);
        canvas.drawParagraph(fill, o);
        canvas.restore();
      }
      x += gw;
    }
  }

  void _caption(
    Canvas canvas,
    String text, {
    required double y,
    String? full,
    double scale = 1,
    Color color = AppColors.ink,
  }) {
    if (scale <= 0) return;
    final p = _texts.get(text, size: 54, color: color, maxWidth: 640);
    final pFull = _texts.get(
      full ?? text,
      size: 54,
      color: color,
      maxWidth: 640,
    );
    final box = Rect.fromCenter(
      center: Offset(_w / 2, y),
      width: pFull.maxIntrinsicWidth + 64,
      height: pFull.height + 36,
    );
    canvas.save();
    canvas.translate(box.center.dx, box.center.dy);
    canvas.scale(scale);
    final local = box.shift(-box.center);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        local.shift(const Offset(0, 6)),
        const Radius.circular(40),
      ),
      Paint()..color = const Color(0x33000000),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(local, const Radius.circular(40)),
      Paint()..color = Colors.white,
    );
    canvas.drawParagraph(p, Offset(local.left + 32, local.top + 18));
    canvas.restore();
  }

  void _banner(
    Canvas canvas,
    String text, {
    required double y,
    required double scale,
    required double opacity,
    required Color background,
    required Color textColor,
  }) {
    if (scale <= 0 || opacity <= 0) return;
    final p = _texts.get(text, size: 50, color: textColor, maxWidth: 620);
    final box = Rect.fromCenter(
      center: Offset.zero,
      width: p.maxIntrinsicWidth + 60,
      height: p.height + 30,
    );
    canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
    canvas.translate(_w / 2, y);
    canvas.scale(scale);
    canvas.drawRRect(
      RRect.fromRectAndRadius(box.inflate(5), const Radius.circular(36)),
      Paint()..color = AppColors.ink,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(32)),
      Paint()..color = background,
    );
    canvas.drawParagraph(p, Offset(box.left + 30, box.top + 15));
    canvas.restore();
  }

  void _bigText(
    Canvas canvas,
    String text,
    Offset center, {
    required double size,
    required Color color,
    Color outline = AppColors.ink,
    double scale = 1,
    double opacity = 1,
    double maxWidth = 680,
    bool bold = true,
  }) {
    if (scale <= 0 || opacity <= 0) return;
    final fill = _texts.get(
      text,
      size: size,
      color: color,
      maxWidth: maxWidth,
      bold: bold,
    );
    final stroke = _texts.get(
      text,
      size: size,
      color: outline,
      stroke: size / 7,
      maxWidth: maxWidth,
      bold: bold,
    );
    final layer = opacity < 1;
    if (layer) {
      canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
    } else {
      canvas.save();
    }
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    final w = math.min(fill.maxIntrinsicWidth, maxWidth);
    final o = Offset(-w / 2, -fill.height / 2);
    canvas.drawParagraph(stroke, o);
    canvas.drawParagraph(fill, o);
    canvas.restore();
  }

  /// Draws [image] fitted (contain) and centred in [box].
  void _drawContain(
    Canvas canvas,
    ui.Image image,
    Rect box, {
    Color? tint,
    double opacity = 1,
  }) {
    final fit = _fit(image.width.toDouble(), image.height.toDouble(), box.size);
    _drawImage(
      canvas,
      image,
      Rect.fromCenter(center: box.center, width: fit.width, height: fit.height),
      tint: tint,
      opacity: opacity,
    );
  }

  void _drawImage(
    Canvas canvas,
    ui.Image image,
    Rect dst, {
    Color? tint,
    double opacity = 1,
  }) {
    if (opacity <= 0) return;
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..isAntiAlias = true
      ..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0));
    if (tint != null) {
      paint.colorFilter = ColorFilter.mode(tint, BlendMode.srcIn);
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst,
      paint,
    );
  }
}

// ---------------------------------------------------------------- helpers

/// Size of an [w]×[h] image fitted inside [box] (contain).
Size _fit(double w, double h, Size box) {
  if (w <= 0 || h <= 0) return box;
  final s = math.min(box.width / w, box.height / h);
  return Size(w * s, h * s);
}

double _phase(double t, double a, double b) =>
    b <= a ? (t >= b ? 1 : 0) : ((t - a) / (b - a)).clamp(0.0, 1.0);

double _ease(double t) => Curves.easeInOut.transform(t.clamp(0.0, 1.0));
double _easeOutCubic(double t) =>
    Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));
double _easeOutBack(double t) =>
    Curves.easeOutBack.transform(t.clamp(0.0, 1.0));

class _Sparkle {
  const _Sparkle({
    required this.angle,
    required this.distance,
    required this.size,
    required this.delay,
    required this.hue,
  });
  final double angle;
  final double distance;
  final double size;
  final double delay;
  final int hue;
}

/// Laid-out paragraphs, reused across frames.
class _TextCache {
  final _cache = <String, ui.Paragraph>{};

  ui.Paragraph get(
    String text, {
    required double size,
    required Color color,
    double? stroke,
    double maxWidth = 700,
    bool bold = true,
  }) {
    final key = '$text|$size|${color.toARGB32()}|$stroke|$maxWidth|$bold';
    return _cache.putIfAbsent(key, () {
      final style = ui.TextStyle(
        fontFamily: _font,
        fontSize: size,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        color: stroke == null ? color : null,
        foreground: stroke == null
            ? null
            : (Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = stroke
                ..strokeJoin = StrokeJoin.round
                ..color = color),
      );
      final b =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(
                textAlign: TextAlign.left,
                maxLines: 1,
                ellipsis: '…',
                fontFamily: _font,
              ),
            )
            ..pushStyle(style)
            ..addText(text);
      final p = b.build()..layout(ui.ParagraphConstraints(width: maxWidth));
      // Shrink-wrap so centring works.
      final w = math.min(p.maxIntrinsicWidth.ceilToDouble() + 2, maxWidth);
      return p..layout(ui.ParagraphConstraints(width: w));
    });
  }
}
