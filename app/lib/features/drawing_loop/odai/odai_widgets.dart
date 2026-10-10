import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/character_picture.dart';
import '../../../core/widgets/kid_dialogs.dart';
import '../../../data/app_state.dart';
import 'daily_odai.dart';
import 'odai_controller.dart';
import 'stamp_card.dart';

IconData stampIcon(StampDesign d) => switch (d) {
  StampDesign.hanamaru => Icons.local_florist,
  StampDesign.hoshi => Icons.star,
  StampDesign.niji => Icons.looks,
  StampDesign.oukan => Icons.workspace_premium,
  StampDesign.rocket => Icons.rocket_launch,
};

Color stampColor(StampDesign d) => switch (d) {
  StampDesign.hanamaru => AppColors.pink,
  StampDesign.hoshi => AppColors.gold,
  StampDesign.niji => AppColors.purple,
  StampDesign.oukan => AppColors.primary,
  StampDesign.rocket => AppColors.secondary,
};

/// A round stamp.
class OdaiStampMark extends StatelessWidget {
  const OdaiStampMark({super.key, required this.design, this.size = 36});
  final StampDesign design;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: stampColor(design).withValues(alpha: 0.15),
      border: Border.all(color: stampColor(design), width: size / 14),
    ),
    child: Icon(stampIcon(design), color: stampColor(design), size: size * 0.6),
  );
}

/// きょうの おだい on the home screen. No timers, no streaks, no "last
/// chance" wording: the prompt is an invitation, not a duty.
class OdaiHomeCard extends ConsumerWidget {
  const OdaiHomeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(todaysOdaiProvider);
    final today = localDateKey(ref.watch(clockProvider)());
    final card = ref.watch(stampCardProvider).value ?? OdaiStampCard.empty;
    final stamped = card.hasStampOn(today);
    return Card(
      key: const Key('odai-card'),
      color: const Color(0xFFFFF1C9),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.lightbulb, color: AppColors.gold, size: 30),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'きょうの おだい',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  key: const Key('odai-calendar'),
                  icon: const Icon(Icons.calendar_month),
                  label: Text('スタンプ ${card.total}'),
                  onPressed: () => context.push(Routes.odai),
                ),
              ],
            ),
            Text(
              '「${theme.text}」',
              key: const Key('odai-text'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (stamped)
              Row(
                key: const Key('odai-stamped'),
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OdaiStampMark(design: card.designOf(today), size: 28),
                  const SizedBox(width: 8),
                  const Text(
                    'きょうの スタンプ もらったよ！',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            const SizedBox(height: 6),
            Center(
              child: FilledButton.icon(
                key: const Key('odai-draw'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.pink),
                icon: const Icon(Icons.brush),
                label: Text(stamped ? 'また かいてみる' : 'おだいで かく'),
                onPressed: () => startOdaiDrawing(context, ref),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「おだいで かく」: remembers the theme, then opens かく — or, when the
/// ずかん is full, explains that drawing a part or a move for one of the
/// characters also answers the theme.
Future<void> startOdaiDrawing(BuildContext context, WidgetRef ref) async {
  ref.read(activeOdaiProvider.notifier).start(ref.read(todaysOdaiProvider));
  final count = ref.read(charactersProvider).value?.length ?? 0;
  if (count >= ref.read(collectionLimitProvider)) {
    await showKidMessage(
      context,
      'ずかんが いっぱい だから、すきな キャラに パーツや わざの えを かいて こたえよう！',
      icon: Icons.lightbulb,
    );
    if (context.mounted) await context.push(Routes.zukan);
    return;
  }
  await context.push(Routes.draw);
}

/// おだい カレンダー: stamps by month.
class StampCardScreen extends ConsumerStatefulWidget {
  const StampCardScreen({super.key});

  @override
  ConsumerState<StampCardScreen> createState() => _StampCardScreenState();
}

class _StampCardScreenState extends ConsumerState<StampCardScreen> {
  late DateTime _month = () {
    final now = ref.read(clockProvider)();
    return DateTime(now.year, now.month);
  }();

  void _shift(int months) =>
      setState(() => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final card = ref.watch(stampCardProvider).value ?? OdaiStampCard.empty;
    final now = ref.watch(clockProvider)();
    final today = DateTime(now.year, now.month, now.day);
    final stamps = card.inMonth(_month.year, _month.month);
    final toNext = card.stampsToNextDesign;
    final upcoming = card.upcomingDesign;
    final isCurrentMonth =
        _month.year == today.year && _month.month == today.month;
    return Scaffold(
      appBar: AppBar(title: const Text('おだい カレンダー')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Text(
                      'あつめた スタンプ ${card.total} こ',
                      key: const Key('stamp-total'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (toNext != null && upcoming != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              'あと $toNext こ あつめると「${upcoming.label}」の スタンプに なるよ',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                          const SizedBox(width: 6),
                          OdaiStampMark(design: upcoming, size: 28),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    const Text(
                      'すきな ひに かいてね。かいた ひに スタンプが つくよ',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  key: const Key('stamp-prev'),
                  icon: const Icon(Icons.chevron_left, size: 36),
                  onPressed: () => _shift(-1),
                ),
                Expanded(
                  child: Text(
                    '${_month.year}ねん ${_month.month}がつ',
                    key: const Key('stamp-month'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('stamp-next'),
                  icon: const Icon(Icons.chevron_right, size: 36),
                  onPressed: isCurrentMonth ? null : () => _shift(1),
                ),
              ],
            ),
            _MonthGrid(
              month: _month,
              today: today,
              stamps: stamps,
              designOf: card.designOf,
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthGrid extends ConsumerWidget {
  const _MonthGrid({
    required this.month,
    required this.today,
    required this.stamps,
    required this.designOf,
  });

  final DateTime month;
  final DateTime today;
  final Map<int, OdaiStamp> stamps;
  final StampDesign Function(String dateKey) designOf;

  static const _weekdays = ['にち', 'げつ', 'か', 'すい', 'もく', 'きん', 'ど'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = DateTime(month.year, month.month + 1, 0).day;
    final lead = DateTime(month.year, month.month).weekday % 7; // Sunday = 0
    final cells = lead + days;
    return Column(
      children: [
        Row(
          children: [
            for (final w in _weekdays)
              Expanded(
                child: Text(
                  w,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.8,
          children: [
            for (var i = 0; i < cells; i++)
              if (i < lead)
                const SizedBox.shrink()
              else
                _DayCell(
                  date: DateTime(month.year, month.month, i - lead + 1),
                  isToday:
                      DateTime(month.year, month.month, i - lead + 1) == today,
                  stamp: stamps[i - lead + 1],
                  designOf: designOf,
                ),
          ],
        ),
      ],
    );
  }
}

class _DayCell extends ConsumerWidget {
  const _DayCell({
    required this.date,
    required this.isToday,
    required this.stamp,
    required this.designOf,
  });

  final DateTime date;
  final bool isToday;
  final OdaiStamp? stamp;
  final StampDesign Function(String dateKey) designOf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stamp;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        key: Key('stamp-day-${date.day}'),
        borderRadius: BorderRadius.circular(10),
        onTap: s == null ? null : () => _show(context, ref, s),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isToday ? AppColors.primary : const Color(0xFFE6E0D4),
              width: isToday ? 3 : 1,
            ),
          ),
          child: Column(
            children: [
              Text('${date.day}', style: const TextStyle(fontSize: 13)),
              if (s != null)
                Expanded(
                  child: FittedBox(
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: OdaiStampMark(
                        key: Key('stamp-mark-${date.day}'),
                        design: designOf(s.date),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _show(BuildContext context, WidgetRef ref, OdaiStamp s) {
    final c = s.characterId == null
        ? null
        : ref.read(characterByIdProvider(s.characterId!));
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: OdaiStampMark(design: designOf(s.date), size: 56),
        title: Text('${date.month}がつ ${date.day}にち'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '「${s.text}」',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            if (c != null) ...[
              const SizedBox(height: 12),
              CharacterPicture(character: c, size: 120),
              Text(c.name, style: const TextStyle(fontSize: 18)),
            ],
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            key: const Key('kid-message-ok'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('とじる'),
          ),
        ],
      ),
    );
  }
}
