/// The おだい stamp card (カレンダー). Cumulative only: there are no
/// streaks, nothing is ever taken away, and a day without drawing is simply
/// a plain day on the calendar.
library;

import '../../../domain/cosmetics.dart';
import 'daily_odai.dart';

/// How a stamp was earned.
enum StampKind {
  /// A new character drawn for the theme.
  character,

  /// A part drawn for the theme (e.g. when the ずかん is full).
  part,

  /// A move effect drawn for the theme.
  effect;

  static StampKind fromName(String? n) => StampKind.values.firstWhere(
    (k) => k.name == n,
    orElse: () => StampKind.character,
  );
}

class OdaiStamp {
  const OdaiStamp({
    required this.date,
    required this.themeId,
    required this.text,
    required this.kind,
    this.characterId,
  });

  /// Local date (yyyy-mm-dd) of the theme.
  final String date;
  final String themeId;
  final String text;
  final StampKind kind;

  /// The character the drawing belongs to (shown on the calendar while it
  /// still exists).
  final String? characterId;

  Map<String, Object?> toJson() => {
    'date': date,
    'themeId': themeId,
    'text': text,
    'kind': kind.name,
    'characterId': ?characterId,
  };

  factory OdaiStamp.fromJson(Map<String, Object?> j) => OdaiStamp(
    date: j['date']! as String,
    themeId: j['themeId'] as String? ?? '',
    text: j['text'] as String? ?? '',
    kind: StampKind.fromName(j['kind'] as String?),
    characterId: j['characterId'] as String?,
  );
}

/// Stamp designs unlocked by the total number of stamps (every
/// [StampDesign.every] stamps a new one). Purely cosmetic.
enum StampDesign {
  hanamaru('はなまる'),
  hoshi('ほし'),
  niji('にじ'),
  oukan('おうかん'),
  rocket('ロケット');

  const StampDesign(this.label);
  final String label;

  static const int every = 5;

  /// Design of the [ordinal]-th stamp ever earned (1-based).
  static StampDesign forOrdinal(int ordinal) {
    final i = ((ordinal - 1) ~/ every).clamp(0, values.length - 1);
    return values[i];
  }
}

class OdaiStampCard {
  const OdaiStampCard([this.byDate = const {}]);

  static const empty = OdaiStampCard();

  /// Stamps by local date (at most one per day).
  final Map<String, OdaiStamp> byDate;

  int get total => byDate.length;

  bool hasStampOn(String dateKey) => byDate.containsKey(dateKey);

  /// Adds [stamp] unless that day already has one (the first drawing of the
  /// day keeps its stamp; drawing more never hurts and never doubles up).
  OdaiStampCard withStamp(OdaiStamp stamp) {
    if (byDate.containsKey(stamp.date)) return this;
    return OdaiStampCard({...byDate, stamp.date: stamp});
  }

  /// Stamps of the given month, by day of month.
  Map<int, OdaiStamp> inMonth(int year, int month) {
    final out = <int, OdaiStamp>{};
    for (final s in byDate.values) {
      final d = parseDateKey(s.date);
      if (d != null && d.year == year && d.month == month) out[d.day] = s;
    }
    return out;
  }

  /// 1-based position of the stamp of [dateKey] in date order.
  int ordinalOf(String dateKey) {
    final keys = byDate.keys.toList()..sort();
    return keys.indexOf(dateKey) + 1;
  }

  StampDesign designOf(String dateKey) =>
      StampDesign.forOrdinal(ordinalOf(dateKey));

  /// Stamps still to collect before the stamps get a new design, or null
  /// once every design is open.
  int? get stampsToNextDesign =>
      total >= StampDesign.every * (StampDesign.values.length - 1)
      ? null
      : StampDesign.every - total % StampDesign.every;

  /// The design that opens after [stampsToNextDesign] more stamps.
  StampDesign? get upcomingDesign {
    final n = stampsToNextDesign;
    return n == null ? null : StampDesign.forOrdinal(total + n + 1);
  }

  /// The design the next stamp will have.
  StampDesign get nextDesign => StampDesign.forOrdinal(total + 1);

  Map<String, Object?> toJson() => {
    'version': 1,
    'stamps': [
      for (final k in (byDate.keys.toList()..sort())) byDate[k]!.toJson(),
    ],
  };

  /// Lenient (bad entries are skipped).
  factory OdaiStampCard.fromJson(Map<String, Object?>? j) {
    final list = j?['stamps'];
    if (list is! List) return empty;
    final out = <String, OdaiStamp>{};
    for (final e in list) {
      try {
        if (e is! Map) continue;
        final s = OdaiStamp.fromJson(e.cast());
        if (parseDateKey(s.date) == null) continue;
        out.putIfAbsent(s.date, () => s);
      } on Object {
        // skip
      }
    }
    return OdaiStampCard(out);
  }

  /// The stamp for drawing [badge]'s theme.
  static OdaiStamp stampFor(
    OdaiBadge badge, {
    required StampKind kind,
    String? characterId,
  }) => OdaiStamp(
    date: badge.date,
    themeId: badge.themeId,
    text: badge.text,
    kind: kind,
    characterId: characterId,
  );
}
