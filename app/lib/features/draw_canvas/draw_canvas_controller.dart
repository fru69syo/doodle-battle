import 'package:flutter/foundation.dart';

import 'stroke_drawing.dart';

/// State of the drawing tool: strokes, the live stroke, undo / redo,
/// current brush and colour. Pure (no widgets) so it is unit-tested.
class DrawCanvasController extends ChangeNotifier {
  DrawCanvasController({StrokeDrawing? initial})
    : _strokes = [...?initial?.strokes];

  final List<Stroke> _strokes;

  /// Undone strokes, or the cleared page (one redo step brings it back).
  final List<List<Stroke>> _redo = [];

  /// A clear is one undo step: the strokes before it.
  final List<(int, List<Stroke>)> _cleared = [];

  Stroke? _live;
  DrawTool tool = DrawTool.crayon;
  int color = kCanvasColors[2];

  List<Stroke> get strokes => List.unmodifiable(_strokes);
  Stroke? get live => _live;
  bool get isEmpty => StrokeDrawing(strokes: _strokes).isEmpty;
  bool get canUndo => _strokes.isNotEmpty || _cleared.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  StrokeDrawing get drawing => StrokeDrawing(strokes: [..._strokes]);

  void setTool(DrawTool t) {
    tool = t;
    notifyListeners();
  }

  void setColor(int c) {
    color = c;
    if (tool == DrawTool.eraser) tool = DrawTool.crayon;
    notifyListeners();
  }

  bool get _full =>
      _strokes.length >= StrokeDrawing.maxStrokes ||
      drawing.pointCount >= StrokeDrawing.maxPoints;

  /// Starts a stroke at ([x], [y]) in canvas units.
  void begin(double x, double y) {
    if (_full) return;
    _live = Stroke(tool, color, null)..add(x, y);
    notifyListeners();
  }

  void extend(double x, double y) {
    final s = _live;
    if (s == null) return;
    if (s.length >= 1500) return;
    if (s.add(
      x.clamp(0, StrokeDrawing.size),
      y.clamp(0, StrokeDrawing.height),
    )) {
      notifyListeners();
    }
  }

  void end() {
    final s = _live;
    _live = null;
    if (s != null && s.length > 0) {
      _strokes.add(s);
      _redo.clear();
    }
    notifyListeners();
  }

  void undo() {
    if (_cleared.isNotEmpty && _strokes.length == _cleared.last.$1) {
      // Undo the clear: the page comes back.
      final (_, before) = _cleared.removeLast();
      _redo.add([]); // marker: redo = clear again
      _strokes
        ..clear()
        ..addAll(before);
    } else if (_strokes.isNotEmpty) {
      _redo.add([_strokes.removeLast()]);
    }
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    final r = _redo.removeLast();
    if (r.isEmpty) {
      _cleared.add((0, [..._strokes]));
      _strokes.clear();
    } else {
      _strokes.addAll(r);
    }
    notifyListeners();
  }

  /// Clears the page (the UI asks first); undo brings it back.
  void clear() {
    if (_strokes.isEmpty) return;
    _cleared.add((0, [..._strokes]));
    _strokes.clear();
    _redo.clear();
    notifyListeners();
  }
}
