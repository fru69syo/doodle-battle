import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/element_badge.dart';
import '../../core/widgets/stat_bars.dart';
import '../../domain/battle/battle.dart';
import '../battle_ui/move_labels.dart';
import 'pending_birth.dart';

/// Total length of the reveal animation.
const birthRevealDuration = Duration(milliseconds: 4200);

/// 「たんじょう」: fun reveal of the new character (SPEC §2-3).
class BirthScreen extends ConsumerStatefulWidget {
  const BirthScreen({super.key});

  @override
  ConsumerState<BirthScreen> createState() => _BirthScreenState();
}

class _BirthScreenState extends ConsumerState<BirthScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: birthRevealDuration,
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final birth = ref.watch(pendingBirthProvider);
    if (birth == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('キャラが いないよ')),
      );
    }
    final spec = ref.watch(battleSpecProvider).value;
    final hpMul = spec?.hpMultiplier ?? 3;
    final growthTimes = spec == null
        ? 3
        : spec.growth.shoboLevelUpStatPct ~/ spec.growth.levelUpStatPct;
    return Scaffold(
      appBar: AppBar(title: const Text('たんじょう！')),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _c.value = 1, // tap to skip the animation
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => _Reveal(
              birth: birth,
              t: _c.value,
              hpMultiplier: hpMul,
              shoboGrowthTimes: growthTimes,
            ),
          ),
        ),
      ),
    );
  }
}

class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.birth,
    required this.t,
    required this.hpMultiplier,
    required this.shoboGrowthTimes,
  });

  final PendingBirth birth;

  /// Animation progress 0..1.
  final double t;
  final int hpMultiplier;
  final int shoboGrowthTimes;

  double _phase(double start, double end) =>
      ((t - start) / (end - start)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final r = birth.result;
    final appear = Curves.elasticOut.transform(_phase(0.25, 0.45));
    final shake = t < 0.25 ? sin(t * 120) * 8 * (t / 0.25) : 0.0;
    final statsVisible = (_phase(0.45, 0.75) * 4).ceil();
    final details = _phase(0.75, 0.85);
    final shoboBanner = _phase(0.85, 1.0);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SizedBox(
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (t < 0.3)
                Transform.translate(
                  offset: Offset(shake, 0),
                  child: Opacity(
                    opacity: 1 - _phase(0.25, 0.3),
                    child: const Icon(
                      Icons.egg,
                      size: 160,
                      color: AppColors.gold,
                    ),
                  ),
                ),
              if (t >= 0.25)
                Transform.scale(
                  scale: appear,
                  child: Container(
                    width: 200,
                    height: 200,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: AppColors.element(r.element),
                        width: 4,
                      ),
                    ),
                    child: Image.memory(r.cutoutPng, fit: BoxFit.contain),
                  ),
                ),
            ],
          ),
        ),
        Text(
          t < 0.25 ? 'なにかが うまれそう…！' : 'うまれたよ！',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        StatBars(
          stats: r.baseStats,
          hpMultiplier: hpMultiplier,
          visible: statsVisible,
        ),
        Opacity(
          opacity: details,
          child: _Details(birth: birth),
        ),
        if (r.isShobo)
          Opacity(
            opacity: shoboBanner,
            child: _ShoboBanner(growthTimes: shoboGrowthTimes),
          ),
        const SizedBox(height: 16),
        if (t >= 1)
          FilledButton.icon(
            key: const Key('birth-name'),
            icon: const Icon(Icons.edit),
            label: const Text('なまえを つける'),
            onPressed: () => context.pushReplacement(Routes.naming),
          ),
      ],
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.birth});
  final PendingBirth birth;

  @override
  Widget build(BuildContext context) {
    final r = birth.result;
    final cloud = birth.cloud;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              ElementBadge(r.element, big: true),
              if (r.isShobo) const ShoboBadge(),
              if (cloud?.subject != null)
                Chip(label: Text('${cloud!.subject} の キャラ')),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'わざ',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final a in [
                BattleAction.tackle,
                BattleAction.element,
                BattleAction.guard,
                BattleAction.special,
              ])
                Chip(
                  label: Text(
                    moveLabel(
                      a,
                      element: r.element,
                      elementMoveName: cloud?.elementMoveName,
                      specialMoveName: cloud?.specialMoveName,
                    ),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// しょぼキャラ: humorous message + it grows fast (SPEC §4.2).
class _ShoboBanner extends StatelessWidget {
  const _ShoboBanner({required this.growthTimes});

  /// しょぼ growth rate ÷ normal growth rate (from the battle spec).
  final int growthTimes;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('birth-shobo'),
    color: const Color(0xFFF1E6FF),
    margin: const EdgeInsets.only(top: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Icon(Icons.palette, size: 48, color: AppColors.purple),
          const SizedBox(height: 8),
          const Text(
            'げいじゅつか すぎて しょぼキャラに なっちゃった！',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.purple,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'でも だいじょうぶ！ しょぼキャラは そだつのが $growthTimesばい はやい！'
            'けいけんちも たくさん もらえるよ。バトルで そだてて みよう！',
            key: const Key('birth-shobo-growth'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18),
          ),
        ],
      ),
    ),
  );
}
