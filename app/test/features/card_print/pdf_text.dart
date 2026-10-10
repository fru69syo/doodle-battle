import 'dart:convert';
import 'dart:typed_data';

/// Minimal text extraction for PDFs written by the `pdf` package with
/// `compress: false`: every `/Type0` font writes an Identity-H ToUnicode
/// CMap (`<cid> <unicode>` lines) and the page content shows text as
/// `<cid cid …>` hex strings (Tj / TJ). Returns, per CMap, all hex strings decoded
/// with that CMap and concatenated in content order — text drawn with that
/// font reads correctly in one of them.
List<String> pdfTexts(Uint8List bytes) {
  final s = latin1.decode(bytes);
  final cmaps = <Map<int, int>>[];
  final cmapRe = RegExp(r'beginbfchar\n([\s\S]*?)endbfchar');
  final pairRe = RegExp(r'<([0-9A-Fa-f]{4})> <([0-9A-Fa-f]{4,})>');
  for (final m in cmapRe.allMatches(s)) {
    cmaps.add({
      for (final p in pairRe.allMatches(m.group(1)!))
        int.parse(p.group(1)!, radix: 16): int.parse(p.group(2)!, radix: 16),
    });
  }
  // `<…> Tj` or `[<…> kern <…>] TJ`.
  final showRe = RegExp(r'(\[[^\]]*\]\s*TJ|<[0-9a-fA-F]+>\s*Tj)');
  final hexRe = RegExp(r'<([0-9a-fA-F]{4,})>');
  final shown = [
    for (final m in showRe.allMatches(s))
      for (final h in hexRe.allMatches(m.group(1)!)) h.group(1)!,
  ];
  return [
    for (final cmap in cmaps)
      shown.map((h) {
        final b = StringBuffer();
        for (var i = 0; i + 4 <= h.length; i += 4) {
          final u = cmap[int.parse(h.substring(i, i + 4), radix: 16)];
          if (u != null) b.writeCharCode(u);
        }
        return b.toString();
      }).join(),
  ];
}

/// Number of pages (`/Type /Page` objects, uncompressed PDF).
int pdfPageCount(Uint8List bytes) =>
    RegExp(r'/Type\s*/Page(?![s\w])').allMatches(latin1.decode(bytes)).length;
