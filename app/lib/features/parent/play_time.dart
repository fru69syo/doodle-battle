import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/app_state.dart';

String dateKey(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

/// Foreground session start (not persisted; flushed into GameProgress when
/// the app goes to the background).
class PlayClock {
  DateTime? sessionStart;
}

final playClockProvider = Provider<PlayClock>((ref) => PlayClock());

/// Seconds played today including the running session.
final playSecondsTodayProvider = Provider<int>((ref) {
  final now = ref.watch(clockProvider)();
  final p = ref.watch(progressProvider).value;
  final stored = p != null && p.playDate == dateKey(now)
      ? p.playSecondsToday
      : 0;
  final start = ref.watch(playClockProvider).sessionStart;
  final running = start == null ? 0 : now.difference(start).inSeconds;
  return stored + (running > 0 ? running : 0);
});

/// Tracks foreground time for the play-time guideline (SPEC §7) without
/// timers: the session is measured between resume and pause.
class PlayTimeTracker extends ConsumerStatefulWidget {
  const PlayTimeTracker({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<PlayTimeTracker> createState() => _PlayTimeTrackerState();
}

class _PlayTimeTrackerState extends ConsumerState<PlayTimeTracker> {
  late final AppLifecycleListener _listener;

  PlayClock get _clock => ref.read(playClockProvider);
  DateTime _now() => ref.read(clockProvider)();

  @override
  void initState() {
    super.initState();
    _clock.sessionStart = _now();
    _listener = AppLifecycleListener(
      onResume: () => _clock.sessionStart = _now(),
      onPause: _flush,
    );
  }

  void _flush() {
    final start = _clock.sessionStart;
    if (start == null) return;
    final now = _now();
    _clock.sessionStart = null;
    final seconds = now.difference(start).inSeconds;
    if (seconds > 0) {
      ref.read(progressProvider.notifier).addPlayTime(dateKey(now), seconds);
    }
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
