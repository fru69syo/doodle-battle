import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Shared helpers for the headless 2.5D renders (docs/v2_25d/).
/// Software Skia in `flutter test` exercises the same
/// `drawVertices` + `ImageShader` path as GLES2 phones, so no GPU is needed.
Future<void> loadAppFonts() async {
  for (final f in ['Regular', 'Bold']) {
    final bytes = File('assets/fonts/ZenMaruGothic-$f.ttf').readAsBytesSync();
    await ui.loadFontFromList(bytes, fontFamily: 'ZenMaruGothic');
  }
}

/// Output directory for PNGs: PUPPET_RENDER_DIR, else docs/v2_25d when
/// PUPPET_WRITE_DOCS=1, else null (render but do not write).
String? renderDir() {
  final env = Platform.environment;
  if (env['PUPPET_RENDER_DIR'] case final d?) return d;
  if (env['PUPPET_WRITE_DOCS'] == '1') return '../docs/v2_25d';
  return null;
}

Future<void> savePicture(ui.Picture pic, int w, int h, String? path) async {
  final image = await pic.toImage(w, h);
  if (path == null) {
    image.dispose();
    return;
  }
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(data!.buffer.asUint8List());
  image.dispose();
}

void label(
  Canvas c,
  String text,
  Offset at, {
  double size = 16,
  Color color = const Color(0xFF1F1A3D),
}) {
  final pb =
      ui.ParagraphBuilder(
          ui.ParagraphStyle(
            fontFamily: 'ZenMaruGothic',
            fontSize: size,
            fontWeight: FontWeight.w700,
          ),
        )
        ..pushStyle(ui.TextStyle(color: color))
        ..addText(text);
  final p = pb.build()..layout(const ui.ParagraphConstraints(width: 600));
  c.drawParagraph(p, at);
}
