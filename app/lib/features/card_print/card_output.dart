import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import 'card_pdf.dart';

/// Sends a finished card PDF out of the app. Always called *after* the
/// parental gate (docs/FAMILY.md). Replaced by a fake in tests.
abstract interface class CardOutput {
  /// System print dialog (Android print framework).
  Future<void> printPdf(Uint8List pdf, {required String name});

  /// System share sheet (save to files, send to a family member, …).
  Future<void> sharePdf(Uint8List pdf, {required String filename});
}

/// `printing` package implementation (works offline; no network).
class PrintingCardOutput implements CardOutput {
  const PrintingCardOutput();

  @override
  Future<void> printPdf(Uint8List pdf, {required String name}) =>
      Printing.layoutPdf(onLayout: (_) async => pdf, name: name);

  @override
  Future<void> sharePdf(Uint8List pdf, {required String filename}) =>
      Printing.sharePdf(bytes: pdf, filename: filename);
}

final cardOutputProvider = Provider<CardOutput>(
  (ref) => const PrintingCardOutput(),
);

/// Bundled Zen Maru Gothic for the PDF (the same files the app uses).
final cardFontsProvider = FutureProvider<CardFonts>((ref) async {
  final regular = await rootBundle.load(
    'assets/fonts/ZenMaruGothic-Regular.ttf',
  );
  final bold = await rootBundle.load('assets/fonts/ZenMaruGothic-Bold.ttf');
  return CardFonts(regular: regular, bold: bold);
});
