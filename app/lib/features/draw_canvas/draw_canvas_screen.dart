import 'package:flutter/material.dart';

import 'draw_canvas_controller.dart';
import 'stroke_drawing.dart';
import 'stroke_painter.dart';

/// 「アプリで かく」(SPEC §12.2 input ②): draw with a finger on a paper-like
/// canvas — crayon / marker / brush, 12 colours, eraser, undo / redo,
/// clear (asks first). There is no way to bring a picture in: no album,
/// no paste, no text field. Pops with the [StrokeDrawing] on できた！.
class DrawCanvasScreen extends StatefulWidget {
  const DrawCanvasScreen({super.key, this.initial});

  final StrokeDrawing? initial;

  @override
  State<DrawCanvasScreen> createState() => DrawCanvasScreenState();
}

class DrawCanvasScreenState extends State<DrawCanvasScreen> {
  late final controller = DrawCanvasController(initial: widget.initial);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('canvas-clear-dialog'),
        title: const Text(
          'ぜんぶ けす？',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 26),
        ),
        content: const Icon(
          Icons.delete_sweep,
          size: 72,
          color: Color(0xFFE5533D),
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          FilledButton.tonalIcon(
            key: const Key('canvas-clear-cancel'),
            onPressed: () => Navigator.pop(context, false),
            icon: const Icon(Icons.close),
            label: const Text('やめる', style: TextStyle(fontSize: 20)),
          ),
          FilledButton.icon(
            key: const Key('canvas-clear-ok'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE5533D),
            ),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete),
            label: const Text('けす', style: TextStyle(fontSize: 20)),
          ),
        ],
      ),
    );
    if (ok == true) controller.clear();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFFF1D6),
    appBar: AppBar(
      backgroundColor: const Color(0xFFFFF1D6),
      title: const Text(
        'アプリで かこう',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
    ),
    body: SafeArea(
      top: false,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Column(
          children: [
            Expanded(child: _canvas()),
            _tools(),
            _palette(),
            _done(),
          ],
        ),
      ),
    ),
  );

  Widget _canvas() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
    child: Center(
      child: AspectRatio(
        aspectRatio: 1 / StrokeDrawing.aspect,
        child: LayoutBuilder(
          builder: (context, box) {
            final k = box.maxWidth / StrokeDrawing.size;
            (double, double) unit(Offset p) => (p.dx / k, p.dy / k);
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0x33000000)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: GestureDetector(
                  key: const Key('canvas-surface'),
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) {
                    final (x, y) = unit(d.localPosition);
                    controller.begin(x, y);
                  },
                  onPanUpdate: (d) {
                    final (x, y) = unit(d.localPosition);
                    controller.extend(x, y);
                  },
                  onPanEnd: (_) => controller.end(),
                  onTapUp: (d) {
                    // A tap leaves a dot.
                    final (x, y) = unit(d.localPosition);
                    controller
                      ..begin(x, y)
                      ..end();
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const RepaintBoundary(
                        child: CustomPaint(painter: PaperPainter()),
                      ),
                      CustomPaint(painter: _StrokesPainter(controller, k)),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );

  Widget _tools() {
    Widget tool(DrawTool t, IconData icon, String label) => _RoundButton(
      key: Key('tool-${t.name}'),
      icon: icon,
      label: label,
      color: t == DrawTool.eraser
          ? const Color(0xFF8E8E8E)
          : Color(controller.color),
      selected: controller.tool == t,
      onTap: () => controller.setTool(t),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          tool(DrawTool.crayon, Icons.edit, 'クレヨン'),
          tool(DrawTool.marker, Icons.draw, 'ペン'),
          tool(DrawTool.brush, Icons.brush, 'ふで'),
          tool(DrawTool.eraser, Icons.cleaning_services, 'けしごむ'),
          const SizedBox(width: 4),
          _RoundButton(
            key: const Key('canvas-undo'),
            icon: Icons.undo,
            label: 'もどす',
            color: const Color(0xFF4A7DFF),
            onTap: controller.canUndo ? controller.undo : null,
          ),
          _RoundButton(
            key: const Key('canvas-redo'),
            icon: Icons.redo,
            label: 'やりなおす',
            color: const Color(0xFF4A7DFF),
            onTap: controller.canRedo ? controller.redo : null,
          ),
          _RoundButton(
            key: const Key('canvas-clear'),
            icon: Icons.delete_sweep,
            label: 'ぜんぶけす',
            color: const Color(0xFFE5533D),
            onTap: controller.isEmpty ? null : _confirmClear,
          ),
        ],
      ),
    );
  }

  Widget _palette() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
    child: Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (i, c) in kCanvasColors.indexed)
          GestureDetector(
            key: Key('color-$i'),
            onTap: () => controller.setColor(c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      controller.color == c &&
                          controller.tool != DrawTool.eraser
                      ? const Color(0xFF1F1A3D)
                      : Colors.white,
                  width: controller.color == c ? 5 : 3,
                ),
                boxShadow: const [
                  BoxShadow(color: Color(0x33000000), blurRadius: 3),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  Widget _done() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
    child: SizedBox(
      width: double.infinity,
      height: 60,
      child: FilledButton.icon(
        key: const Key('canvas-done'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF2EAE5B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        onPressed: controller.isEmpty
            ? null
            : () => Navigator.of(context).pop(controller.drawing),
        icon: const Icon(Icons.check_circle, size: 30),
        label: const Text(
          'できた！',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
        ),
      ),
    ),
  );
}

class _StrokesPainter extends CustomPainter {
  _StrokesPainter(this.c, this.k) : super(repaint: c);
  final DrawCanvasController c;
  final double k;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(k);
    const StrokeRenderer().paint(canvas, c.strokes, live: c.live);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StrokesPainter old) => true;
}

/// 48 dp round button with an icon and a tiny label.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 30,
        child: Opacity(
          opacity: on ? 1 : 0.35,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: selected ? color : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 3),
            ),
            child: Icon(icon, color: selected ? Colors.white : color, size: 26),
          ),
        ),
      ),
    );
  }
}
