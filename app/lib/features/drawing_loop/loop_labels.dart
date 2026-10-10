import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../core/widgets/kid_dialogs.dart';
import '../../domain/cosmetics.dart';

String partLabel(PartType t) => switch (t) {
  PartType.hat => 'ぼうし',
  PartType.wings => 'つばさ',
  PartType.horn => 'つの',
  PartType.tail => 'しっぽ',
  PartType.weapon => 'もちもの',
  PartType.accessory => 'かざり',
};

IconData partIcon(PartType t) => switch (t) {
  PartType.hat => Icons.school,
  PartType.wings => Icons.flutter_dash,
  PartType.horn => Icons.change_history,
  PartType.tail => Icons.gesture,
  PartType.weapon => Icons.auto_fix_high,
  PartType.accessory => Icons.diamond,
};

/// Width and height of a PNG from its IHDR chunk (falls back to decoding).
(int, int) pngSize(Uint8List png) {
  const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  var isPng = png.length >= 24;
  for (var i = 0; i < sig.length && isPng; i++) {
    isPng = png[i] == sig[i];
  }
  if (isPng) {
    final d = ByteData.sublistView(png, 16, 24);
    return (d.getUint32(0), d.getUint32(4));
  }
  final decoded = img.decodeImage(png);
  if (decoded == null) throw const FormatException('not an image');
  return (decoded.width, decoded.height);
}

/// Celebrates a new おだい stamp.
Future<void> showOdaiStampMessage(BuildContext context, OdaiBadge badge) =>
    showKidMessage(
      context,
      '「${badge.text}」の スタンプを もらったよ！\nカレンダーで みてみよう',
      title: 'スタンプ ゲット！',
      icon: Icons.approval,
    );
