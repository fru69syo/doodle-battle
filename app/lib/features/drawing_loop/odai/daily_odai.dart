/// きょうの おだい: a deterministic prompt per local calendar day.
library;

import '../../../domain/cosmetics.dart';
import 'odai_prompts.dart';

/// One day's prompt.
class OdaiTheme {
  const OdaiTheme({required this.id, required this.text, this.event});

  /// Stable id: `g<n>` (general), `s_<season>_<n>` or `e_<event>_<n>`.
  final String id;
  final String text;

  /// Event id (e.g. `halloween`) when it is a seasonal-event prompt.
  final String? event;

  @override
  bool operator ==(Object other) =>
      other is OdaiTheme && other.id == id && other.text == text;

  @override
  int get hashCode => Object.hash(id, text);

  @override
  String toString() => 'OdaiTheme($id, $text)';
}

/// `yyyy-mm-dd` of [local] (device local time; no time-zone conversion).
String localDateKey(DateTime local) =>
    '${local.year.toString().padLeft(4, '0')}-'
    '${local.month.toString().padLeft(2, '0')}-'
    '${local.day.toString().padLeft(2, '0')}';

/// Parses a [localDateKey] back to a (local, midnight) date; null if bad.
DateTime? parseDateKey(String key) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(key);
  if (m == null) return null;
  return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

final _epoch = DateTime.utc(2026);

/// Whole days between 2026-01-01 and the calendar date of [local]. Computed
/// on UTC dates built from the local Y/M/D, so DST and time zones never
/// shift it.
int odaiDayNumber(DateTime local) =>
    DateTime.utc(local.year, local.month, local.day).difference(_epoch).inDays;

int _mod(int a, int n) => ((a % n) + n) % n;

int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

/// A step coprime with [n], so `day * step` walks through every prompt
/// before any repeats, and consecutive days never share a prompt.
int _strideFor(int n) {
  var s = 37;
  while (_gcd(s, n) != 1) {
    s++;
  }
  return s;
}

/// How often an ordinary day uses the season pool (every 3rd day).
const int seasonEvery = 3;

/// The prompt of the local calendar day of [local]. Pure and offline: the
/// same date always gives the same prompt on every device.
///
/// 1. A Japanese event window (しょうがつ, ハロウィン, …) → the event's
///    prompts.
/// 2. Every [seasonEvery]rd day → the season pool.
/// 3. Otherwise the general pool, walked with a coprime stride.
OdaiTheme odaiFor(DateTime local) {
  final day = odaiDayNumber(local);
  for (final e in odaiEvents) {
    if (e.covers(local.month, local.day)) {
      final i = _mod(day + local.year, e.prompts.length);
      return OdaiTheme(id: 'e_${e.id}_$i', text: e.prompts[i], event: e.id);
    }
  }
  if (_mod(day, seasonEvery) == 0) {
    final season = seasonOf(local.month);
    final pool = seasonalOdai[season]!;
    final i = _mod(day ~/ seasonEvery, pool.length);
    return OdaiTheme(id: 's_${season}_$i', text: pool[i]);
  }
  final n = generalOdai.length;
  final i = _mod(day * _strideFor(n) + 11, n);
  return OdaiTheme(id: 'g$i', text: generalOdai[i]);
}

/// The badge a character drawn for [theme] on [local] gets.
OdaiBadge badgeFor(OdaiTheme theme, DateTime local) =>
    OdaiBadge(themeId: theme.id, date: localDateKey(local), text: theme.text);
