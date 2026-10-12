import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/attr_badge.dart';
import '../../domain/character_v2.dart';
import '../../domain/character_v2_view.dart';
import '../drawing_analysis/feature_words.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('たんじょう！')),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _c.value = 1, // tap to skip the animation
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => _Reveal(birth: birth, t: _c.value),
          ),
        ),
      ),
    );
  }
}

class _Reveal extends StatelessWidget {
  const _Reveal({required this.birth, required this.t});

  final PendingBirth birth;

  /// Animation progress 0..1.
  final double t;

  double _phase(double start, double end) =>
      ((t - start) / (end - start)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final r = birth.result;
    final appear = Curves.elasticOut.transform(_phase(0.25, 0.45));
    final shake = t < 0.25 ? sin(t * 120) * 8 * (t / 0.25) : 0.0;
    final traits = positiveTraits(r.features);
    final traitsVisible = (_phase(0.45, 0.75) * traits.length).ceil();
    final details = _phase(0.75, 0.9);
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
        _Traits(traits: traits, visible: traitsVisible),
        Opacity(
          opacity: details,
          child: _Details(birth: birth),
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

/// Preview per birth (the reveal rebuilds every frame).
final _preview = Expando<CharacterV2>();

class _Details extends StatelessWidget {
  const _Details({required this.birth});
  final PendingBirth birth;

  @override
  Widget build(BuildContext context) {
    final c = _preview[birth] ??= birth.character();
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
              AttrBadge(c.attribute(), big: true),
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
              for (final (i, m) in c.unlockedMoves.indexed)
                Chip(
                  key: Key('birth-move-$i'),
                  avatar: Icon(attrIcon(m.attr), color: attrColor(m.attr)),
                  label: Text(
                    moveDisplayName(m),
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

/// 「とくちょう」: positive words about the drawing (SPEC §11.1). No scores,
/// no ranking: every drawing gets its own special points.
class _Traits extends StatelessWidget {
  const _Traits({required this.traits, required this.visible});
  final List<DrawingTrait> traits;
  final int visible;

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('birth-traits'),
    children: [
      const Text(
        'この えの とくちょう',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (var i = 0; i < traits.length; i++)
            AnimatedOpacity(
              opacity: i < visible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Chip(
                key: Key('birth-trait-${traits[i].name}'),
                avatar: const Icon(Icons.star, color: AppColors.gold),
                label: Text(
                  traits[i].label,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    ],
  );
}
