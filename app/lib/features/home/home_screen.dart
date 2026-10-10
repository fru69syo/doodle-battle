import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/big_button.dart';
import '../../data/app_state.dart';
import '../drawing_loop/drawing_loop.dart';
import '../parent/parent_session.dart';
import '../parent/play_time.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value;
    final onlineAllowed = settings?.consents.online ?? false;
    final serverReady = ref.watch(backendApiProvider).isAvailable;
    final count = ref.watch(charactersProvider).value?.length ?? 0;
    final limit = ref.watch(collectionLimitProvider);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const _Title(),
            const _PlayTimeBanner(),
            const SizedBox(height: 8),
            const OdaiHomeCard(),
            const SizedBox(height: 12),
            BigActionButton(
              key: const Key('home-draw'),
              icon: Icons.brush,
              label: 'かく',
              subtitle: 'えを しゃしんに とって キャラに しよう',
              color: AppColors.primary,
              onPressed: () {
                // A plain drawing, not for today's theme.
                ref.read(activeOdaiProvider.notifier).clear();
                context.push(Routes.draw);
              },
            ),
            const SizedBox(height: 14),
            BigActionButton(
              key: const Key('home-zukan'),
              icon: Icons.collections_bookmark,
              label: 'ずかん',
              subtitle: '$count / $limit たい',
              color: AppColors.success,
              onPressed: () => context.push(Routes.zukan),
            ),
            const SizedBox(height: 14),
            BigActionButton(
              key: const Key('home-battle'),
              icon: Icons.sports_martial_arts,
              label: 'バトル',
              subtitle: 'コンピューターと たたかおう',
              color: AppColors.secondary,
              onPressed: () => context.push(Routes.battle),
            ),
            const SizedBox(height: 14),
            BigActionButton(
              key: const Key('home-family'),
              icon: Icons.groups,
              label: 'かぞくで たいせん',
              subtitle: '1だいで いっしょに あそぼう',
              color: AppColors.pink,
              onPressed: () => context.push(Routes.family),
            ),
            if (onlineAllowed) ...[
              const SizedBox(height: 14),
              BigActionButton(
                key: const Key('home-online'),
                icon: Icons.public,
                label: 'オンライン',
                subtitle: serverReady ? 'みんなの キャラと たたかおう' : 'じゅんびちゅう',
                color: AppColors.purple,
                onPressed: serverReady
                    ? () => context.push(Routes.online)
                    : null,
              ),
            ],
            const SizedBox(height: 32),
            Center(
              child: OutlinedButton.icon(
                key: const Key('home-parent'),
                icon: const Icon(Icons.family_restroom),
                label: const Text('おうちのひと'),
                onPressed: () async {
                  if (await unlockParentArea(context, ref) && context.mounted) {
                    await context.push(Routes.parent);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.draw, size: 44, color: AppColors.primary),
        SizedBox(width: 8),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              appDisplayName,
              key: Key('home-title'),
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Gentle reminder once today's play time passes the parent's guideline.
class _PlayTimeBanner extends ConsumerWidget {
  const _PlayTimeBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minutes = ref.watch(settingsProvider).value?.playTimeMinutes;
    if (minutes == null) return const SizedBox.shrink();
    if (ref.watch(playSecondsTodayProvider) < minutes * 60) {
      return const SizedBox.shrink();
    }
    return Card(
      key: const Key('playtime-banner'),
      color: const Color(0xFFFFE9A8),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.bedtime, size: 40),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'きょうは たくさん あそんだね。そろそろ おやすみ しよう！',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
