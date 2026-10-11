import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../domain/battle_v3/battle_v3.dart';
import '../render/character_sprite.dart';
import 'battle_session25.dart';
import 'stage_painter.dart';

/// Prototype 2.5D battle (debug route `/debug/25d`): two auto-rigged
/// drawings on a perspective stage, the real v3 ATB engine at 10 Hz, move
/// buttons with さきどり and おまかせ. Pure Flutter canvas, so it runs on
/// every phone the app supports (Android 7+, iOS).
class Battle25dScreen extends StatefulWidget {
  const Battle25dScreen({
    super.key,
    required this.player,
    required this.cpu,
    this.seed = 7,
    this.lowQuality = false,
    this.autoStart = true,
  });

  final Side25 player;
  final Side25 cpu;
  final int seed;
  final bool lowQuality;

  /// Tests drive time with [Battle25dScreenState.advance] instead.
  final bool autoStart;

  @override
  State<Battle25dScreen> createState() => Battle25dScreenState();
}

class Battle25dScreenState extends State<Battle25dScreen>
    with SingleTickerProviderStateMixin {
  BattleSession25? session;
  List<CharacterSprite>? _sprites;
  final _repaint = ValueNotifier<int>(0);
  Ticker? _ticker;
  Duration _last = Duration.zero;
  String? _error;

  /// Average CPU time of advance + paint recording (µs), for the debug
  /// label.
  double frameUs = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final chars = [
        buildSideCharacter(widget.player),
        buildSideCharacter(widget.cpu),
      ];
      final sprites = [for (final c in chars) await CharacterSprite.create(c)];
      if (!mounted) return;
      setState(() {
        _sprites = sprites;
        session = BattleSession25(
          sides: [widget.player, widget.cpu],
          characters: chars,
          seed: widget.seed,
        );
      });
      if (widget.autoStart) {
        _ticker = createTicker(_onTick)..start();
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _onTick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = now;
    advance(dt);
  }

  /// Advances the battle by [dt] seconds and repaints.
  void advance(double dt) {
    final s = session;
    if (s == null) return;
    final sw = Stopwatch()..start();
    s.advance(dt);
    frameUs = frameUs * 0.9 + sw.elapsedMicroseconds * 0.1;
    _repaint.value++;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _repaint.dispose();
    for (final s in _sprites ?? const <CharacterSprite>[]) {
      s.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = session;
    final sprites = _sprites;
    if (_error != null) {
      return Scaffold(body: Center(child: Text(_error!)));
    }
    if (s == null || sprites == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: const Color(0xFF8ED36B),
      body: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: StagePainter(
              director: s.director,
              sprites: sprites,
              repaintSignal: _repaint,
              legend: [widget.player.level >= 50, widget.cpu.level >= 50],
              lowQuality: widget.lowQuality,
            ),
          ),
          ListenableBuilder(
            listenable: _repaint,
            builder: (context, _) => SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                    child: Row(
                      children: [
                        Expanded(child: _panel(s, 0)),
                        const SizedBox(width: 8),
                        Expanded(child: _panel(s, 1)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    child: s.over ? _result(s) : _controls(s),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _ink = Color(0xFF1F1A3D);

  Widget _panel(BattleSession25 s, int side) {
    final f = s.fighter(side);
    final v = s.director.fighters[side];
    final hp = (v.shownHp / f.maxHp).clamp(0.0, 1.0);
    final gauge = f.gauge / s.engine.spec.gaugeMax;
    final ready = f.phase != Phase.charging;
    final hpColor = hp > 0.5
        ? const Color(0xFF43C443)
        : hp > 0.25
        ? const Color(0xFFFFC107)
        : const Color(0xFFE53935);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: side == 0 ? const Color(0xFFFF6B35) : const Color(0xFF1E88E5),
          width: 3,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  side == 0 ? '${s.sides[0].name}（きみ）' : s.sides[1].name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: _ink,
                  ),
                ),
              ),
              Text(
                'Lv${s.sides[side].level}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _bar(hp, hpColor, 12, label: '${v.shownHp.round()}'),
          const SizedBox(height: 5),
          _bar(
            gauge,
            ready ? const Color(0xFFFF9A2E) : const Color(0xFF8E44FF),
            9,
            glow: ready,
          ),
          if (v.poisoned || v.paralyzed || v.shield > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 4,
                children: [
                  if (v.poisoned) _chip('ねばねば', const Color(0xFFB45CFF)),
                  if (v.paralyzed) _chip('ビリビリ', const Color(0xFFE6B800)),
                  if (v.shield > 0) _chip('まもり', const Color(0xFF3AA0E0)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8)),
    child: Text(
      t,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _bar(
    double v,
    Color c,
    double h, {
    String? label,
    bool glow = false,
  }) => Container(
    height: h,
    decoration: BoxDecoration(
      color: const Color(0x22000000),
      borderRadius: BorderRadius.circular(h),
      boxShadow: glow
          ? [BoxShadow(color: c.withValues(alpha: 0.7), blurRadius: 8)]
          : null,
    ),
    child: FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: v.clamp(0.0, 1.0),
      child: Container(
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(h),
        ),
      ),
    ),
  );

  static Color attrColor(Attr a) => switch (a) {
    Attr.gu => const Color(0xFFE5533D),
    Attr.choki => const Color(0xFF2F8FE0),
    Attr.pa => const Color(0xFF2EAE5B),
    Attr.none => const Color(0xFF8E5BE8),
  };

  Widget _controls(BattleSession25 s) {
    final f = s.fighter(0);
    final left = s.choiceLeft;
    final String prompt;
    if (s.alwaysAuto) {
      prompt = 'おまかせで たたかうよ';
    } else if (left != null) {
      prompt = 'わざを えらんでね！';
    } else if (s.pending != null) {
      prompt = 'たまったら すぐ だすよ';
    } else if (f.phase == Phase.casting) {
      prompt = 'ためているよ…';
    } else {
      prompt = 'つぎの わざを えらんでおけるよ';
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (left != null) ...[
                _countdown(
                  left / (s.engine.spec.decisionTicks / s.engine.spec.tickHz),
                  left,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  prompt,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: _ink,
                  ),
                ),
              ),
              const Text(
                'おまかせ',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
              Switch(
                value: s.alwaysAuto,
                onChanged: (v) => setState(() {
                  s.alwaysAuto = v;
                  s.pending = null;
                }),
              ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.55,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (var i = 0; i < 4; i++)
                i < f.moves.length ? _moveButton(s, i, f.moves[i]) : _locked(i),
            ],
          ),
        ],
      ),
    );
  }

  Widget _countdown(double frac, double left) => SizedBox(
    width: 34,
    height: 34,
    child: Stack(
      alignment: Alignment.center,
      children: [
        CircularProgressIndicator(
          value: frac.clamp(0.0, 1.0),
          strokeWidth: 5,
          color: const Color(0xFFFF6B35),
          backgroundColor: const Color(0x22000000),
        ),
        Text(
          '${left.ceil()}',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 15,
            color: _ink,
          ),
        ),
      ],
    ),
  );

  Widget _moveButton(BattleSession25 s, int i, Move m) {
    final usable = s.usable(i);
    final selected = s.pending == i;
    final ready = s.choiceLeft != null;
    final col = attrColor(m.attr);
    final enabled =
        usable && !s.alwaysAuto && s.fighter(0).phase != Phase.casting;
    final cd = s.fighter(0).cooldowns[i];
    return GestureDetector(
      onTap: enabled ? () => setState(() => s.tap(i)) : null,
      child: AnimatedScale(
        scale: selected ? 1.04 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          decoration: BoxDecoration(
            color: enabled ? col : const Color(0xFFBDBDBD),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? const Color(0xFFFFD83A) : Colors.white,
              width: selected ? 5 : 2,
            ),
            boxShadow: [
              if (ready && enabled)
                BoxShadow(color: col.withValues(alpha: 0.6), blurRadius: 10),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    m.name.isEmpty ? m.template : m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      shadows: [
                        Shadow(blurRadius: 2, color: Color(0x88000000)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      _tag(
                        m.attr == Attr.none
                            ? (i == 3 ? 'ひっさつ' : 'むぞくせい')
                            : m.attr.label,
                      ),
                      const SizedBox(width: 4),
                      if (m.spCost > 0) _tag('SP${m.spCost}'),
                    ],
                  ),
                ],
              ),
              if (selected)
                Positioned(
                  right: 0,
                  top: 0,
                  child: _tag(
                    ready ? 'これ！' : 'つぎ！',
                    bg: const Color(0xFFFFD83A),
                    fg: _ink,
                  ),
                ),
              if (cd > 0)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Text(
                    '${(cd / 10).ceil()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _locked(int i) => Container(
    decoration: BoxDecoration(
      color: const Color(0x22000000),
      borderRadius: BorderRadius.circular(16),
    ),
    alignment: Alignment.center,
    child: Text(
      i == 2 ? 'Lv10 で おぼえるよ' : 'Lv50 で おぼえるよ',
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        color: Color(0x991F1A3D),
      ),
    ),
  );

  Widget _tag(
    String t, {
    Color bg = const Color(0x33FFFFFF),
    Color fg = Colors.white,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      t,
      style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w900),
    ),
  );

  Widget _result(BattleSession25 s) {
    final win = s.director.winner == 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            win ? 'かち！' : 'まけちゃった…',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: win ? const Color(0xFFFF6B35) : _ink,
            ),
          ),
          Text(
            '${(s.engine.tick / 10).toStringAsFixed(0)} びょう',
            style: const TextStyle(color: _ink),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('もどる'),
          ),
        ],
      ),
    );
  }

  /// Exposed for tests.
  double get battleSeconds => (session?.engine.tick ?? 0) / 10;
}
