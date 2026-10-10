import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/cosmetics.dart';
import 'part_geometry.dart';

/// A part being placed in the editor.
class PlacedPart {
  PlacedPart({
    required this.id,
    required this.type,
    required this.png,
    required this.width,
    required this.height,
    required this.transform,
    this.isNew = false,
  });

  final String id;
  PartType type;
  final Uint8List png;
  final int width;
  final int height;
  PartTransform transform;

  /// Drawn in this session (its PNG is not stored yet).
  final bool isNew;
}

/// Paper canvas where the child drags (1 finger), pinches and twists
/// (2 fingers) the selected part. Tapping a part selects it.
class PartPlacementCanvas extends StatefulWidget {
  const PartPlacementCanvas({
    super.key,
    required this.basePng,
    required this.baseWidth,
    required this.baseHeight,
    required this.parts,
    required this.selected,
    required this.onSelect,
    required this.onChanged,
    this.maxSide = 360,
  });

  final Uint8List basePng;
  final int baseWidth;
  final int baseHeight;
  final List<PlacedPart> parts;
  final int? selected;
  final ValueChanged<int?> onSelect;
  final void Function(int index, PartTransform t) onChanged;
  final double maxSide;

  @override
  State<PartPlacementCanvas> createState() => _PartPlacementCanvasState();
}

class _PartPlacementCanvasState extends State<PartPlacementCanvas> {
  Offset _lastFocal = Offset.zero;
  double _lastScale = 1;
  double _lastRotation = 0;

  List<(PartTransform, int, int)> get _hitList => [
    for (final p in widget.parts) (p.transform, p.width, p.height),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final side = math.min(box.maxWidth, widget.maxSide);
      final g = EditorGeometry(
        canvas: Size(side, side),
        baseW: widget.baseWidth,
        baseH: widget.baseHeight,
      );

      Widget placed(int i, {bool outline = false}) {
        final p = widget.parts[i];
        final size = g.partSize(p.transform, p.width, p.height);
        final c = g.partCenter(p.transform);
        return Positioned(
          key: outline ? Key('part-outline-$i') : Key('part-on-canvas-$i'),
          left: c.dx - size.width / 2,
          top: c.dy - size.height / 2,
          width: size.width,
          height: size.height,
          child: Transform.rotate(
            angle: p.transform.rotation,
            child: outline
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.primary, width: 3),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  )
                : Image.memory(p.png, fit: BoxFit.fill, gaplessPlayback: true),
          ),
        );
      }

      final n = widget.parts.length;
      return Center(
        child: GestureDetector(
          key: const Key('part-canvas'),
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => widget.onSelect(g.hitTest(d.localPosition, _hitList)),
          onScaleStart: (d) {
            final hit = g.hitTest(d.localFocalPoint, _hitList);
            if (hit != null && hit != widget.selected) widget.onSelect(hit);
            _lastFocal = d.localFocalPoint;
            _lastScale = 1;
            _lastRotation = 0;
          },
          onScaleUpdate: (d) {
            final i = widget.selected;
            if (i == null || i >= widget.parts.length) return;
            final next = g.applyGesture(
              widget.parts[i].transform,
              pan: d.localFocalPoint - _lastFocal,
              scaleFactor: d.pointerCount > 1 ? d.scale / _lastScale : 1,
              rotationDelta: d.pointerCount > 1
                  ? d.rotation - _lastRotation
                  : 0,
            );
            _lastFocal = d.localFocalPoint;
            _lastScale = d.scale;
            _lastRotation = d.rotation;
            widget.onChanged(i, next);
          },
          child: Container(
            width: side,
            height: side,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE6E0D4), width: 2),
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < n; i++)
                  if (widget.parts[i].transform.behind) placed(i),
                Positioned.fromRect(
                  rect: g.baseRect,
                  child: Image.memory(
                    widget.basePng,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                  ),
                ),
                for (var i = 0; i < n; i++)
                  if (!widget.parts[i].transform.behind) placed(i),
                if (widget.selected != null && widget.selected! < n)
                  placed(widget.selected!, outline: true),
              ],
            ),
          ),
        ),
      );
    },
  );
}
