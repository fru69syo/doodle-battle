import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../anim/clips.dart';
import '../render/character_sprite.dart';
import '../rig/auto_rig.dart';
import '../rig/bin_mask.dart';
import '../rig/rig.dart';
import '../rig/rigged_character.dart';
import 'rig_edit.dart';

/// Kid-friendly joint editor: big coloured handles on the head, hands,
/// feet, tail and body that can be dragged when the automatic rig guessed
/// wrong; a live "うごかしてみる" preview; add / remove limbs; reset.
/// Returns the edited [CharacterRig] (also saved to [store]).
class JointEditorScreen extends StatefulWidget {
  const JointEditorScreen({
    super.key,
    required this.png,
    required this.imageHash,
    required this.store,
    this.initial,
  });

  final Uint8List png;
  final String imageHash;
  final RigStore store;
  final CharacterRig? initial;

  @override
  State<JointEditorScreen> createState() => JointEditorScreenState();
}

const kLimbColors = {
  LimbKind.head: Color(0xFFE84393),
  LimbKind.arm: Color(0xFFFF6B35),
  LimbKind.leg: Color(0xFF2E9E44),
  LimbKind.tail: Color(0xFF00A0A0),
  LimbKind.extra: Color(0xFF9C8A00),
};

const kLimbLabels = {
  LimbKind.head: 'あたま',
  LimbKind.arm: 'て',
  LimbKind.leg: 'あし',
  LimbKind.tail: 'しっぽ',
  LimbKind.extra: 'つの',
};

class JointEditorScreenState extends State<JointEditorScreen>
    with SingleTickerProviderStateMixin {
  CharacterRig? rig;
  CharacterRig? _auto;
  ui.Image? _image;
  CharacterSprite? _sprite;
  bool preview = false;
  int? _drag; // limb index, or -1 = body
  int? selected;
  late final Ticker _ticker;
  double _t = 0;
  final _repaint = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) {
      _t = d.inMicroseconds / 1e6;
      if (preview) _repaint.value++;
    })..start();
    _load();
  }

  Future<void> _load() async {
    final codec = await ui.instantiateImageCodec(widget.png);
    final frame = await codec.getNextFrame();
    final bytes = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    final w = frame.image.width, h = frame.image.height;
    final auto = autoRig(BinMask.fromRgba(bytes!.buffer.asUint8List(), w, h))
        .rig;
    final stored = widget.initial ?? await widget.store.load(widget.imageHash);
    if (!mounted) return;
    setState(() {
      _image = frame.image;
      _auto = auto;
      rig = stored ?? auto;
    });
    await _rebuild();
  }

  Future<void> _rebuild() async {
    final r = rig;
    if (r == null) return;
    final data = buildRiggedCharacterFromPng(widget.png, rig: r);
    final s = await CharacterSprite.create(data);
    if (!mounted) return;
    setState(() {
      _sprite?.dispose();
      _sprite = s;
    });
  }

  /// Applies an edit (also used by tests).
  void apply(CharacterRig r) {
    setState(() => rig = r);
    _rebuild();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    _sprite?.dispose();
    _image?.dispose();
    super.dispose();
  }

  // Drawing ↔ screen mapping (fit with margin).
  (double, Offset) _fit(Size box, CharacterRig r) {
    final s = (box.width - 48) / r.width < (box.height - 48) / r.height
        ? (box.width - 48) / r.width
        : (box.height - 48) / r.height;
    return (
      s,
      Offset((box.width - r.width * s) / 2, (box.height - r.height * s) / 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = rig;
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E7),
      appBar: AppBar(
        title: const Text('うごく ところを なおそう'),
        backgroundColor: const Color(0xFFFFF8E7),
      ),
      body: r == null || _image == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    'まるを ゆびで うごかして、あたま・て・あし の ばしょに おいてね',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final (s, o) = _fit(box.biggest, r);
                      Offset toScreen(V2 p) => o + Offset(p.x * s, p.y * s);
                      V2 toDrawing(Offset q) =>
                          V2((q.dx - o.dx) / s, (q.dy - o.dy) / s);
                      return GestureDetector(
                        onPanStart: (d) {
                          var best = 36.0; // finger-sized hit area
                          int? hit;
                          for (final (i, l) in r.limbs.indexed) {
                            final dd =
                                (toScreen(l.tip) - d.localPosition).distance;
                            if (dd < best) {
                              best = dd;
                              hit = i;
                            }
                          }
                          if ((toScreen(r.root) - d.localPosition).distance <
                              best) {
                            hit = -1;
                          }
                          setState(() {
                            _drag = hit;
                            selected = hit;
                          });
                        },
                        onPanUpdate: (d) {
                          final i = _drag;
                          if (i == null) return;
                          final p = toDrawing(d.localPosition);
                          setState(() {
                            rig = i < 0
                                ? RigEdits.moveRoot(rig!, p)
                                : RigEdits.moveTip(rig!, i, p);
                          });
                        },
                        onPanEnd: (_) {
                          _drag = null;
                          _rebuild();
                        },
                        child: CustomPaint(
                          size: box.biggest,
                          painter: _EditorPainter(this, s, o),
                        ),
                      );
                    },
                  ),
                ),
                _toolbar(r),
              ],
            ),
    );
  }

  Widget _toolbar(CharacterRig r) {
    final sel = selected;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (final k in [
                  LimbKind.arm,
                  LimbKind.leg,
                  LimbKind.tail,
                  LimbKind.head,
                ])
                  ActionChip(
                    label: Text('＋${kLimbLabels[k]}'),
                    backgroundColor: kLimbColors[k]!.withValues(alpha: 0.18),
                    onPressed: () => apply(RigEdits.addLimb(r, k)),
                  ),
                if (sel != null && sel >= 0 && sel < r.limbs.length)
                  ActionChip(
                    label: Text('${kLimbLabels[r.limbs[sel].kind]}を けす'),
                    onPressed: () {
                      selected = null;
                      apply(RigEdits.removeLimb(r, sel));
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => apply(_auto!.copy()),
                    child: const Text('もとに もどす'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () => setState(() => preview = !preview),
                    child: Text(preview ? 'とめる' : 'うごかしてみる'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      await widget.store.save(widget.imageHash, r);
                      nav.maybePop(r);
                    },
                    child: const Text('できた！'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorPainter extends CustomPainter {
  _EditorPainter(this.st, this.s, this.o) : super(repaint: st._repaint);
  final JointEditorScreenState st;
  final double s;
  final Offset o;

  @override
  void paint(Canvas c, Size size) {
    final r = st.rig!;
    Offset m(V2 p) => o + Offset(p.x * s, p.y * s);
    final sprite = st._sprite;
    if (st.preview && sprite != null) {
      final feet = m(V2(r.root.x, r.groundY));
      final anim = (st._t % 4) < 2 ? Anim.idle : Anim.walk;
      sprite.draw(c, anim, st._t % 2, feet: feet, scale: s, screenDir: 1);
      return;
    }
    final img = st._image!;
    c.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(o.dx, o.dy, r.width * s, r.height * s),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final bone = Paint()
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    c.drawLine(m(r.root), m(r.chest), bone..color = const Color(0xCCD7263D));
    for (final l in r.limbs) {
      bone.color = kLimbColors[l.kind]!.withValues(alpha: 0.8);
      c.drawLine(m(l.base), m(l.mid), bone);
      c.drawLine(m(l.mid), m(l.tip), bone);
    }
    void handle(Offset p, Color col, String label, bool sel) {
      c.drawCircle(p, sel ? 24 : 20, Paint()..color = Colors.white);
      c.drawCircle(p, sel ? 20 : 16, Paint()..color = col);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final box = Rect.fromCenter(
        center: p.translate(0, -34),
        width: tp.width + 12,
        height: tp.height + 4,
      );
      c.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(8)),
        Paint()..color = col,
      );
      tp.paint(c, box.topLeft + const Offset(6, 2));
    }

    for (final (i, l) in r.limbs.indexed) {
      handle(
        m(l.tip),
        kLimbColors[l.kind]!,
        kLimbLabels[l.kind]!,
        st.selected == i,
      );
    }
    handle(m(r.root), const Color(0xFFD7263D), 'からだ', st.selected == -1);
  }

  @override
  bool shouldRepaint(covariant _EditorPainter old) => true;
}
