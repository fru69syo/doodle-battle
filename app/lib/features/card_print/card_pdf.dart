/// キャラカード PDF (SPEC §11.2-4, docs/FAMILY.md): 63 × 88 mm cards, either
/// 3 × 3 on A4 sheets with cut lines or one card-sized page per card. Uses
/// the bundled Zen Maru Gothic (subset into the PDF). Pure Dart (`pdf`).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/config/app_config.dart';
import '../../domain/character_v2_view.dart';
import '../../domain/element_type.dart';
import '../../domain/stats.dart';
import 'card_content.dart';

/// How cards are laid out.
enum CardLayout {
  /// A4 portrait, up to [cardsPerSheet] cards per page, with cut lines.
  a4Sheet,

  /// One 63 × 88 mm page per card.
  single,
}

/// Raw TTF bytes of Zen Maru Gothic (regular and bold).
class CardFonts {
  const CardFonts({required this.regular, required this.bold});
  final ByteData regular;
  final ByteData bold;
}

const _mm = PdfPageFormat.mm;
final _cardFormat = PdfPageFormat(
  cardWidthMm * _mm,
  cardHeightMm * _mm,
  marginAll: 0,
);

const _ink = PdfColor.fromInt(0xFF1F1A3D);
const _gold = PdfColor.fromInt(0xFFFFB800);
const _logo = PdfColor.fromInt(0xFFFF6B35);
const _starOff = PdfColor.fromInt(0xFFD9D3C7);
const _cutLine = PdfColor.fromInt(0xFFB0B0B0);

PdfColor _elementColour(ElementType e) => switch (e) {
  ElementType.fire => const PdfColor.fromInt(0xFFE8452C),
  ElementType.water => const PdfColor.fromInt(0xFF1E7FE0),
  ElementType.leaf => const PdfColor.fromInt(0xFF2E9E44),
  ElementType.thunder => const PdfColor.fromInt(0xFFF2B700),
  ElementType.shadow => const PdfColor.fromInt(0xFF5B3F8C),
  ElementType.rainbow => const PdfColor.fromInt(0xFFE84393),
};

/// Very light tint of the element colour for the card body.
PdfColor _tint(PdfColor c, double amount) => PdfColor(
  1 - (1 - c.red) * amount,
  1 - (1 - c.green) * amount,
  1 - (1 - c.blue) * amount,
);

String _hex(PdfColor c) =>
    '#${(c.toInt() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Simple 24 × 24 element icons (drawn here so no icon font is needed).
String _elementPath(ElementType e) => switch (e) {
  ElementType.fire =>
    'M12 2C12 2 5 9 5 14a7 7 0 0 0 14 0c0-3-2-5-3-6 0 2-1 3-2 3 0-3-2-6-2-9z',
  ElementType.water => 'M12 2C12 2 5 10 5 15a7 7 0 0 0 14 0C19 10 12 2 12 2z',
  ElementType.leaf => 'M4 20C4 10 10 4 21 3c0 11-6 17-17 17zM4 20l9-9',
  ElementType.thunder => 'M13 2L4 14h7l-2 8 11-13h-7l2-7z',
  ElementType.shadow => 'M15 3a9 9 0 1 0 6 15A8 8 0 0 1 15 3z',
  ElementType.rainbow =>
    'M12 2l2.5 7.5L22 12l-7.5 2.5L12 22l-2.5-7.5L2 12l7.5-2.5z',
};

pw.Widget _icon(String path, PdfColor colour, double size) => pw.SvgImage(
  svg:
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
      '<path d="$path" fill="${_hex(colour)}" stroke="${_hex(colour)}" '
      'stroke-width="1" stroke-linejoin="round"/></svg>',
  width: size,
  height: size,
);

final String _starPath = () {
  final b = StringBuffer();
  for (var i = 0; i < 10; i++) {
    final r = i.isEven ? 11.0 : 4.6;
    final a = -math.pi / 2 + i * math.pi / 5;
    b
      ..write(i == 0 ? 'M' : 'L')
      ..write((12 + r * math.cos(a)).toStringAsFixed(2))
      ..write(' ')
      ..write((12.5 + r * math.sin(a)).toStringAsFixed(2));
  }
  return '${b}z';
}();

/// Builds the PDF. With [CardLayout.a4Sheet] cards fill A4 pages nine at a
/// time; with [CardLayout.single] every card gets its own card-sized page.
/// [compress] = false keeps streams readable (tests).
Future<Uint8List> buildCardPdf(
  List<CardContent> cards, {
  required CardFonts fonts,
  CardLayout layout = CardLayout.a4Sheet,
  bool compress = true,
}) {
  if (cards.isEmpty) throw ArgumentError('no cards');
  final doc = pw.Document(
    compress: compress,
    title: '$appDisplayName キャラカード',
    author: appDisplayName,
    creator: appDisplayName,
    theme: pw.ThemeData.withFont(
      base: pw.Font.ttf(fonts.regular),
      bold: pw.Font.ttf(fonts.bold),
    ),
  );
  switch (layout) {
    case CardLayout.single:
      for (final c in cards) {
        doc.addPage(pw.Page(pageFormat: _cardFormat, build: (_) => _card(c)));
      }
    case CardLayout.a4Sheet:
      for (var i = 0; i < cards.length; i += cardsPerSheet) {
        final page = cards.sublist(
          i,
          math.min(i + cardsPerSheet, cards.length),
        );
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4.copyWith(
              marginLeft: 0,
              marginTop: 0,
              marginRight: 0,
              marginBottom: 0,
            ),
            build: (_) => _sheet(page),
          ),
        );
      }
  }
  return doc.save();
}

pw.Widget _sheet(List<CardContent> cards) {
  const w = cardWidthMm * _mm;
  const h = cardHeightMm * _mm;
  final left = (PdfPageFormat.a4.width - 3 * w) / 2;
  final top = (PdfPageFormat.a4.height - 3 * h) / 2;
  return pw.Stack(
    children: [
      pw.Positioned(
        left: left,
        top: top - 9 * _mm,
        child: pw.Text(
          '$appDisplayName キャラカード ・ せんに そって きってね',
          style: pw.TextStyle(
            fontSize: 10,
            color: _ink,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
      for (final (i, c) in cards.indexed)
        pw.Positioned(
          left: left + (i % 3) * w,
          top: top + (i ~/ 3) * h,
          child: pw.Stack(
            children: [
              _card(c),
              // Cut line on top of the card edge.
              pw.Container(
                width: w,
                height: h,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _cutLine, width: 0.4),
                ),
              ),
            ],
          ),
        ),
      pw.Positioned(
        left: left,
        bottom: 6 * _mm,
        child: pw.Text(
          '印刷するときは「実際のサイズ（100%）」を選ぶと、カードの大きさ（63×88mm）になります。',
          style: const pw.TextStyle(fontSize: 7, color: _ink),
        ),
      ),
    ],
  );
}

pw.Widget _card(CardContent c) {
  final el = _elementColour(c.element);
  final (PdfColor frame, double frameWidth) = switch (c.stage) {
    EvolutionStage.normal => (el, 1.4 * _mm),
    EvolutionStage.kagayaki => (el, 2.0 * _mm),
    EvolutionStage.densetsu => (_gold, 2.4 * _mm),
  };
  final body = switch (c.background) {
    CardBackground.plain => pw.BoxDecoration(
      color: _tint(el, 0.12),
      borderRadius: pw.BorderRadius.circular(2 * _mm),
    ),
    CardBackground.hoshi => pw.BoxDecoration(
      color: const PdfColor.fromInt(0xFFFFF3B0),
      borderRadius: pw.BorderRadius.circular(2 * _mm),
    ),
    CardBackground.hana => pw.BoxDecoration(
      color: const PdfColor.fromInt(0xFFFFE0EE),
      borderRadius: pw.BorderRadius.circular(2 * _mm),
    ),
    CardBackground.niji => pw.BoxDecoration(
      gradient: const pw.LinearGradient(
        begin: pw.Alignment.topLeft,
        end: pw.Alignment.bottomRight,
        colors: [
          PdfColor.fromInt(0xFFFFE3DC),
          PdfColor.fromInt(0xFFFFF6C8),
          PdfColor.fromInt(0xFFDDF5E0),
          PdfColor.fromInt(0xFFDCEBFF),
          PdfColor.fromInt(0xFFEFE0FF),
        ],
      ),
      borderRadius: pw.BorderRadius.circular(2 * _mm),
    ),
  };
  return pw.Container(
    width: cardWidthMm * _mm,
    height: cardHeightMm * _mm,
    padding: pw.EdgeInsets.all(frameWidth),
    decoration: pw.BoxDecoration(
      color: frame,
      borderRadius: pw.BorderRadius.circular(3 * _mm),
    ),
    child: pw.Container(
      decoration: body,
      padding: const pw.EdgeInsets.fromLTRB(
        2 * _mm,
        1.6 * _mm,
        2 * _mm,
        1.4 * _mm,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _header(c),
          pw.SizedBox(height: 1.2 * _mm),
          pw.Expanded(child: _picture(c, el)),
          pw.SizedBox(height: 1.4 * _mm),
          _elementRow(c, el),
          pw.SizedBox(height: 1.2 * _mm),
          _stars(c),
          pw.SizedBox(height: 1.2 * _mm),
          _moves(c, el),
          pw.SizedBox(height: 1.2 * _mm),
          _footer(c),
        ],
      ),
    ),
  );
}

pw.Widget _header(CardContent c) => pw.Row(
  crossAxisAlignment: pw.CrossAxisAlignment.end,
  children: [
    pw.Expanded(
      // Fixed height: a FittedBox with unbounded height would grow with the
      // aspect ratio of a short name and squeeze the picture.
      child: pw.SizedBox(
        height: 6 * _mm,
        child: pw.FittedBox(
          fit: pw.BoxFit.scaleDown,
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(
            c.name,
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
        ),
      ),
    ),
    pw.SizedBox(width: 1.5 * _mm),
    pw.Text(
      'Lv${c.level}',
      style: pw.TextStyle(
        fontSize: 11,
        fontWeight: pw.FontWeight.bold,
        color: _ink,
      ),
    ),
  ],
);

pw.Widget _picture(CardContent c, PdfColor el) {
  final image = c.image;
  final stage = cardStageLabel(c.stage);
  final accent = c.stage == EvolutionStage.densetsu ? _gold : el;
  return pw.Stack(
    fit: pw.StackFit.expand,
    children: [
      pw.Container(
        padding: const pw.EdgeInsets.all(1.5 * _mm),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(2 * _mm),
          border: pw.Border.all(
            color: accent,
            width: c.stage == EvolutionStage.normal ? 0.6 : 1.2,
          ),
        ),
        child: pw.Center(
          child: image == null
              ? _icon(_elementPath(c.element), el, 20 * _mm)
              : pw.Image(pw.MemoryImage(image), fit: pw.BoxFit.contain),
        ),
      ),
      if (c.stage != EvolutionStage.normal) ...[
        pw.Align(
          alignment: pw.Alignment.topRight,
          child: pw.Padding(
            padding: const pw.EdgeInsets.all(1 * _mm),
            child: _icon(_elementPath(ElementType.rainbow), accent, 4 * _mm),
          ),
        ),
        pw.Align(
          alignment: pw.Alignment.bottomLeft,
          child: pw.Padding(
            padding: const pw.EdgeInsets.all(1 * _mm),
            child: _icon(_elementPath(ElementType.rainbow), accent, 3 * _mm),
          ),
        ),
        pw.Align(
          alignment: pw.Alignment.topLeft,
          child: pw.Container(
            margin: const pw.EdgeInsets.all(1 * _mm),
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 1.4 * _mm,
              vertical: 0.3 * _mm,
            ),
            decoration: pw.BoxDecoration(
              color: accent,
              borderRadius: pw.BorderRadius.circular(2 * _mm),
            ),
            child: pw.Text(
              stage,
              style: pw.TextStyle(
                fontSize: 6.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

pw.Widget _elementRow(CardContent c, PdfColor el) => pw.Row(
  children: [
    pw.Container(
      padding: const pw.EdgeInsets.symmetric(
        horizontal: 1.6 * _mm,
        vertical: 0.4 * _mm,
      ),
      decoration: pw.BoxDecoration(
        color: el,
        borderRadius: pw.BorderRadius.circular(3 * _mm),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          _icon(_elementPath(c.element), PdfColors.white, 3 * _mm),
          pw.SizedBox(width: 0.8 * _mm),
          pw.Text(
            c.element.label,
            style: pw.TextStyle(
              fontSize: 7.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
        ],
      ),
    ),
  ],
);

pw.Widget _stars(CardContent c) {
  pw.Widget cell(StatKind k) => pw.Expanded(
    child: pw.Row(
      children: [
        pw.SizedBox(
          width: 11 * _mm,
          child: pw.Text(
            cardStatLabel(k),
            style: const pw.TextStyle(fontSize: 6, color: _ink),
          ),
        ),
        for (var i = 0; i < cardMaxStars; i++)
          _icon(_starPath, i < (c.stars[k] ?? 1) ? _gold : _starOff, 2.9 * _mm),
      ],
    ),
  );
  return pw.Column(
    children: [
      pw.Row(children: [cell(StatKind.hp), cell(StatKind.atk)]),
      pw.SizedBox(height: 0.6 * _mm),
      pw.Row(children: [cell(StatKind.def), cell(StatKind.spd)]),
    ],
  );
}

pw.Widget _moves(CardContent c, PdfColor el) {
  pw.Widget move(String name) => pw.Expanded(
    child: pw.Container(
      height: 4.6 * _mm,
      margin: const pw.EdgeInsets.all(0.4 * _mm),
      padding: const pw.EdgeInsets.symmetric(horizontal: 1 * _mm),
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: el, width: 0.6),
        borderRadius: pw.BorderRadius.circular(2.3 * _mm),
      ),
      child: pw.FittedBox(
        fit: pw.BoxFit.scaleDown,
        child: pw.Text(
          name,
          style: pw.TextStyle(
            fontSize: 6.5,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
          ),
        ),
      ),
    ),
  );
  final m = c.moves;
  return pw.Column(
    children: [
      pw.Row(children: [move(m[0]), move(m[1])]),
      pw.Row(children: [move(m[2]), move(m[3])]),
    ],
  );
}

pw.Widget _footer(CardContent c) => pw.Row(
  crossAxisAlignment: pw.CrossAxisAlignment.end,
  children: [
    pw.Text(
      appDisplayName,
      style: pw.TextStyle(
        fontSize: 7.5,
        fontWeight: pw.FontWeight.bold,
        color: _logo,
      ),
    ),
    pw.Spacer(),
    pw.Text(
      'うまれた ひ ${cardDateLabel(c.date)}',
      style: const pw.TextStyle(fontSize: 5.5, color: _ink),
    ),
  ],
);
