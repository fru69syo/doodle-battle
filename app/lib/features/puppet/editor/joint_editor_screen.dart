import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../anim/clips.dart';
import '../puppet_builder.dart';
import '../puppet_look.dart';
import '../puppet_store.dart';
import '../render/puppet_view.dart';
import '../rig/character_rig.dart';
import '../rig/limb_hints.dart';
import 'rig_edits.dart';

/// Colour and icon per handle kind (no reading needed: a face is the head,
/// a hand is a hand...). Labels are short hiragana for the screen reader
/// and the little tag under the button.
class LimbStyle {
  const LimbStyle(this.color, this.icon, this.label);
  final Color color;
  final IconData icon;
  final String label;
}

const kBodyStyle = LimbStyle(Color(0xFFD7263D), Icons.favorite, 'からだ');
const kLimbStyles = {
  LimbKind.head: LimbStyle(Color(0xFFE84393), Icons.face, 'あたま'),
  LimbKind.arm: LimbStyle(Color(0xFFFF8A00), Icons.back_hand, 'て'),
  LimbKind.leg: LimbStyle(Color(0xFF2E9E44), Icons.directions_walk, 'あし'),
  LimbKind.tail: LimbStyle(Color(0xFF00A0A0), Icons.pets, 'しっぽ'),
  LimbKind.extra: LimbStyle(Color(0xFF9C8A00), Icons.auto_awesome, 'つの'),
  LimbKind.wing: LimbStyle(Color(0xFF6C7BFF), Icons.air, 'はね'),
  LimbKind.item: LimbStyle(Color(0xFF6D6D6D), Icons.star, 'もちもの'),
};

/// Kinds that get a draggable handle (hair, drawn parts just jiggle along).
bool _handled(LimbKind k) =>
    k == LimbKind.head ||
    k == LimbKind.arm ||
    k == LimbKind.leg ||
    k == LimbKind.tail;

/// Handle size (dp): big enough for a 4-year-old's finger.
const double kHandleRadius = 26;
const double kHitRadius = 44;

/// 「うごく ところを なおそう」: the child drags big round handles (head, hands,
/// feet, tail, body) onto the right places of their drawing while a small
/// preview keeps moving with the current joints. Undo, start over, add or
/// remove a hand / foot / tail, done. Skippable ([firstTime]: shown right
/// after birth, with an animated "drag me" hint).
///
/// Saves the rig to [PuppetStore] under [characterId] and pops with it
/// (null when skipped).
class JointEditorScreen extends ConsumerStatefulWidget {
  const JointEditorScreen({
    super.key,
    required this.characterId,
    required this.png,
    this.strokes,
    this.initialRigJson,
    this.firstTime = false,
    this.onFinished,
  });

  final String characterId;

  /// The character's cut-out PNG.
  final Uint8List png;

  /// Drawing-tool strokes (for もどす: the same auto-rig as at birth).
  final List<HintStroke>? strokes;
  final String? initialRigJson;
  final bool firstTime;

  /// Called after saving (rig) or skipping (null) instead of popping.
  final ValueChanged<CharacterRig?>? onFinished;

  @override
  ConsumerState<JointEditorScreen> createState() => JointEditorScreenState();
}

class JointEditorScreenState extends ConsumerState<JointEditorScreen>
    with SingleTickerProviderStateMixin {
  RigHistory? _history;
  CharacterRig? _auto;
  ui.Image? _image;

  /// Rig shown by the preview (updated when a drag ends).
  CharacterRig? previewRig;

  /// Limb index being dragged, -1 = body; [_dragBase]: the base handle.
  int? _drag;
  bool _dragBase = false;
  int? selected;
  bool _touched = false;
  bool _saving = false;
  late final AnimationController _hint;

  CharacterRig? get rig => _history?.current;
  bool get canUndo => _history?.canUndo ?? false;

  @override
  void initState() {
    super.initState();
    _hint = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (widget.firstTime) _hint.repeat();
    _load();
  }

  Future<void> _load() async {
    final codec = await ui.instantiateImageCodec(widget.png);
    final frame = await codec.getNextFrame();
    final builder = ref.read(puppetBuilderProvider);
    final auto = await builder.autoRig(widget.png, strokes: widget.strokes);
    final stored =
        CharacterRig.tryDecode(widget.initialRigJson) ??
        CharacterRig.tryDecode(
          await ref.read(puppetStoreProvider).loadRigJson(widget.characterId),
        );
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    setState(() {
      _image = frame.image;
      _auto = auto;
      _history = RigHistory(stored ?? auto);
      previewRig = rig;
    });
  }

  /// Applies an edit as one undo step (also used by tests).
  void apply(CharacterRig r) {
    setState(() {
      _history!.push(r);
      previewRig = r;
    });
  }

  void undo() {
    if (!canUndo) return;
    setState(() {
      _history!.undo();
      previewRig = rig;
      selected = null;
    });
  }

  void reset() {
    final a = _auto;
    if (a == null) return;
    selected = null;
    apply(a.copy());
  }

  Future<void> done() async {
    final r = rig;
    if (r == null || _saving) return;
    setState(() => _saving = true);
    await ref.read(puppetStoreProvider).saveRig(widget.characterId, r);
    if (!mounted) return;
    _finish(r);
  }

  void skip() => _finish(null);

  void _finish(CharacterRig? r) {
    final f = widget.onFinished;
    if (f != null) {
      f(r);
    } else {
      Navigator.of(context).maybePop(r);
    }
  }

  @override
  void dispose() {
    _hint.dispose();
    _image?.dispose();
    super.dispose();
  }

  // Drawing ↔ screen mapping (fit with a margin for the handles).
  (double, Offset) _fit(Size box, CharacterRig r) {
    const m = kHandleRadius + 10;
    final s = math.min(
      (box.width - 2 * m) / r.width,
      (box.height - 2 * m) / r.height,
    );
    return (
      s,
      Offset((box.width - r.width * s) / 2, (box.height - r.height * s) / 2),
    );
  }

  /// Handle under [p] (screen): (limb, isBase) with limb −1 = body.
  (int, bool)? hitTest(Offset p, double s, Offset o) {
    final r = rig!;
    Offset m(P2 q) => o + Offset(q.x * s, q.y * s);
    var best = kHitRadius;
    (int, bool)? hit;
    final sel = selected;
    if (sel != null && sel >= 0 && sel < r.limbs.length) {
      final d = (m(r.limbs[sel].base) - p).distance;
      if (d < best * 0.8) {
        best = d;
        hit = (sel, true);
      }
    }
    for (final (i, l) in r.limbs.indexed) {
      if (!_handled(l.kind)) continue;
      final d = (m(l.tip) - p).distance;
      if (d < best) {
        best = d;
        hit = (i, false);
      }
    }
    if ((m(r.root) - p).distance < best) hit = (-1, false);
    return hit;
  }

  @override
  Widget build(BuildContext context) {
    final r = rig;
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF8E7),
        automaticallyImplyLeading: !widget.firstTime,
        title: const Text(
          'うごく ところを なおそう',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          TextButton.icon(
            key: const Key('joint-skip'),
            onPressed: skip,
            icon: const Icon(Icons.skip_next),
            label: const Text('あとで'),
          ),
        ],
      ),
      body: r == null || _image == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: Column(
                children: [
                  Expanded(child: _canvas(r)),
                  _toolbar(r),
                ],
              ),
            ),
    );
  }

  Widget _canvas(CharacterRig r) => LayoutBuilder(
    builder: (context, box) {
      final (s, o) = _fit(box.biggest, r);
      P2 toDrawing(Offset q) => P2((q.dx - o.dx) / s, (q.dy - o.dy) / s);
      final preview = previewRig;
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: const Key('joint-canvas'),
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) {
                final hit = hitTest(d.localPosition, s, o);
                setState(() {
                  selected = hit?.$1;
                  _touched = true;
                });
              },
              onPanStart: (d) {
                final hit = hitTest(d.localPosition, s, o);
                setState(() {
                  _drag = hit?.$1;
                  _dragBase = hit?.$2 ?? false;
                  if (hit != null) selected = hit.$1;
                  _touched = true;
                });
                if (hit != null) _history!.push(rig!);
              },
              onPanUpdate: (d) {
                final i = _drag;
                if (i == null) return;
                final p = toDrawing(d.localPosition);
                setState(() {
                  _history!.replace(
                    i < 0
                        ? RigEdits.moveRoot(rig!, p)
                        : _dragBase
                        ? RigEdits.moveBase(rig!, i, p)
                        : RigEdits.moveTip(rig!, i, p),
                  );
                });
              },
              onPanEnd: (_) => setState(() {
                _drag = null;
                previewRig = rig;
              }),
              child: CustomPaint(
                painter: _EditorPainter(
                  rig: r,
                  image: _image!,
                  scale: s,
                  origin: o,
                  selected: selected,
                  hint: widget.firstTime && !_touched ? _hint : null,
                ),
                size: box.biggest,
              ),
            ),
          ),
          if (preview != null)
            Positioned(
              right: 8,
              top: 8,
              width: math.min(140, box.maxWidth * 0.34),
              height: math.min(170, box.maxHeight * 0.36),
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFFFC94D),
                      width: 3,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(17),
                    child: PuppetView(
                      key: const Key('joint-preview'),
                      spec: PuppetSpec(
                        png: widget.png,
                        rig: preview,
                        look: const PuppetLook(),
                        quality: PuppetQuality.low,
                      ),
                      clips: const [Anim.walk, Anim.swing, Anim.hop, Anim.kick],
                      clipSeconds: 1.6,
                      placeholder: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _toolbar(CharacterRig r) {
    final sel = selected;
    final canRemove = sel != null && sel >= 0 && sel < r.limbs.length;
    Widget add(LimbKind k) => _ToolButton(
      key: Key('joint-add-${k.name}'),
      icon: kLimbStyles[k]!.icon,
      color: kLimbStyles[k]!.color,
      label: '＋${kLimbStyles[k]!.label}',
      plus: true,
      onTap: RigEdits.canAdd(r, k) ? () => apply(RigEdits.addLimb(r, k)) : null,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 8)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              add(LimbKind.arm),
              add(LimbKind.leg),
              add(LimbKind.tail),
              _ToolButton(
                key: const Key('joint-remove'),
                icon: Icons.delete_outline,
                color: const Color(0xFF8E8E8E),
                label: 'けす',
                onTap: canRemove
                    ? () {
                        selected = null;
                        apply(RigEdits.removeLimb(r, sel));
                      }
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _ToolButton(
                key: const Key('joint-undo'),
                icon: Icons.undo,
                color: const Color(0xFF4A7DFF),
                label: 'もどす',
                onTap: canUndo ? undo : null,
              ),
              const SizedBox(width: 8),
              _ToolButton(
                key: const Key('joint-reset'),
                icon: Icons.refresh,
                color: const Color(0xFF8E5BE8),
                label: 'さいしょ',
                onTap: reset,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 64,
                  child: FilledButton.icon(
                    key: const Key('joint-done'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2EAE5B),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(32),
                      ),
                    ),
                    onPressed: _saving ? null : done,
                    icon: const Icon(Icons.check_circle, size: 32),
                    label: const Text(
                      'できた！',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Big round icon button with a tiny hiragana tag (64 dp target).
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.plus = false,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;
  final bool plus;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        child: Opacity(
          opacity: enabled ? 1 : 0.35,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 60,
                height: 60,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                        border: Border.all(color: color, width: 3),
                      ),
                      alignment: Alignment.center,
                      child: Icon(icon, color: color, size: 32),
                    ),
                    if (plus)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.add,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              ExcludeSemantics(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorPainter extends CustomPainter {
  _EditorPainter({
    required this.rig,
    required this.image,
    required this.scale,
    required this.origin,
    required this.selected,
    this.hint,
  }) : super(repaint: hint);

  final CharacterRig rig;
  final ui.Image image;
  final double scale;
  final Offset origin;
  final int? selected;

  /// First-time "drag me" animation (0..1, repeating), or null.
  final Animation<double>? hint;

  Offset m(P2 p) => origin + Offset(p.x * scale, p.y * scale);

  @override
  void paint(Canvas c, Size size) {
    final r = rig;
    c.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(origin.dx, origin.dy, r.width * scale, r.height * scale),
      Paint()..filterQuality = FilterQuality.medium,
    );
    // Bones: thick, soft lines from the body to each handle.
    final bone = Paint()
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    c.drawLine(
      m(r.root),
      m(r.chest),
      bone..color = kBodyStyle.color.withValues(alpha: 0.7),
    );
    for (final (i, l) in r.limbs.indexed) {
      if (!_handled(l.kind)) continue;
      bone.color = kLimbStyles[l.kind]!.color.withValues(
        alpha: selected == i ? 0.95 : 0.6,
      );
      c.drawLine(m(l.base), m(l.mid), bone);
      c.drawLine(m(l.mid), m(l.tip), bone);
    }
    for (final (i, l) in r.limbs.indexed) {
      if (!_handled(l.kind)) continue;
      final st = kLimbStyles[l.kind]!;
      if (selected == i) {
        // The joint where it leaves the body can be moved too.
        _handle(c, m(l.base), st.color, Icons.open_with, 0.7, false);
      }
      _handle(c, m(l.tip), st.color, st.icon, 1, selected == i);
    }
    _handle(c, m(r.root), kBodyStyle.color, kBodyStyle.icon, 1, selected == -1);
    final h = hint;
    if (h != null) {
      // A pointing hand nudges the first hand / head handle.
      final target = r.limbs.where((l) => _handled(l.kind)).firstOrNull;
      final at = m(target?.tip ?? r.root);
      final t = h.value;
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const Color(0xFFFFB800).withValues(alpha: 1 - t);
      c.drawCircle(at, kHandleRadius + 6 + 26 * t, ring);
      final dx = 28 * math.sin(t * 2 * math.pi);
      _icon(
        c,
        Icons.touch_app,
        at.translate(14 + dx, 22),
        40,
        const Color(0xFF1F1A3D),
      );
    }
  }

  void _handle(
    Canvas c,
    Offset p,
    Color col,
    IconData icon,
    double k,
    bool sel,
  ) {
    final r = kHandleRadius * k * (sel ? 1.15 : 1);
    c.drawCircle(
      p.translate(0, 2),
      r + 3,
      Paint()..color = const Color(0x33000000),
    );
    c.drawCircle(p, r + 3, Paint()..color = Colors.white);
    c.drawCircle(p, r, Paint()..color = col);
    if (sel) {
      c.drawCircle(
        p,
        r + 7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xFFFFD83A),
      );
    }
    _icon(c, icon, p, r * 1.15, Colors.white);
  }

  void _icon(Canvas c, IconData icon, Offset center, double size, Color col) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: size,
          color: col,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_EditorPainter old) =>
      old.rig != rig ||
      old.selected != selected ||
      old.scale != scale ||
      old.origin != origin ||
      old.image != image;
}
