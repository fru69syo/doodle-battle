import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/kid_dialogs.dart';
import '../../data/app_state.dart';
import '../parent/play_time.dart';
import 'monetization_service.dart';
import 'monetization_sync.dart';

/// Notice shown before every ad (SPEC §7).
const adNoticeText = 'おうちのひとに きいてから みてね\nこうこくが ながれるよ';

/// Shown when today's ad boosts are used up.
const adCapText = 'きょうの どうがは おしまい。また あした みてね';

/// Shown when today's こうこくなしパス bonuses are used up (same cap).
const passCapText = 'きょうの 2ばいは おしまい。また あした ね';

/// Shown while no ad could be loaded (offline / no fill).
const adUnavailableText = 'いまは どうがが ないみたい。また こんど みてね';

/// Post-battle 「どうがを みて けいけんち 2ばい」. Hidden unless the parent
/// allowed ads. With こうこくなしパス no ad is shown or loaded: the bonus is
/// given without an ad, within the same daily cap (SPEC §11.4). One bonus
/// per battle.
class RewardedAdButton extends ConsumerStatefulWidget {
  const RewardedAdButton({super.key, required this.onRewarded});

  final Future<void> Function() onRewarded;

  @override
  ConsumerState<RewardedAdButton> createState() => _RewardedAdButtonState();
}

class _RewardedAdButtonState extends ConsumerState<RewardedAdButton> {
  bool _used = false;
  bool _busy = false;

  bool _preloadAsked = false;

  /// Retries a failed / missing preload once when the result screen opens
  /// (the service ignores this unless ads are allowed, and backs off).
  /// Only for the ad button: never with こうこくなしパス.
  void _preloadOnce() {
    if (_preloadAsked) return;
    _preloadAsked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(monetizationServiceProvider).preloadRewardedAd();
    });
  }

  static bool _hasPass(Set<String>? entitlements) =>
      entitlements?.contains(Product.noAdsPass.id) ?? false;

  String get _today => dateKey(ref.read(clockProvider)());

  Future<void> _reward() async {
    await widget.onRewarded();
    if (mounted) setState(() => _used = true);
  }

  /// こうこくなしパス: counts against the same daily cap as an ad.
  Future<void> _passReward() async {
    setState(() => _busy = true);
    await widget.onRewarded();
    await ref.read(progressProvider.notifier).recordAdBoost(_today);
    if (mounted) {
      setState(() {
        _used = true;
        _busy = false;
      });
    }
  }

  Future<void> _watchAd() async {
    final ok = await askKid(
      context,
      adNoticeText,
      title: 'どうがを みる まえに',
      yesLabel: 'みる',
      noLabel: 'やめる',
      icon: Icons.ondemand_video,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final result = await ref.read(monetizationServiceProvider).showRewardedAd();
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case RewardedAdResult.rewarded:
        await ref.read(progressProvider.notifier).recordAdBoost(_today);
        await _reward();
      case RewardedAdResult.notRewarded:
        await showKidMessage(context, 'さいごまで みると けいけんちが 2ばいに なるよ');
      case RewardedAdResult.unavailable:
        await showKidMessage(context, adUnavailableText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    final pass = _hasPass(settings?.ownedProducts);
    final adsAllowed = settings?.consents.ads ?? false;
    if (!pass && !adsAllowed) return const SizedBox.shrink();
    if (_used) {
      return const Text(
        'けいけんちが 2ばいに なったよ！',
        key: Key('ad-done'),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.success,
        ),
      );
    }
    final progress = ref.watch(progressProvider).value;
    if (progress == null) return const SizedBox.shrink();
    final left = adBoostsLeft(
      cap: dailyAdBoostCap,
      usedToday: progress.adBoostsOn(_today),
    );
    if (pass) {
      if (left == 0) return const _Note(key: Key('ad-cap'), text: passCapText);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            key: const Key('ad-double-xp'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.pink),
            icon: const Icon(Icons.favorite),
            label: const Text('こうこくなしパスで けいけんち 2ばい'),
            onPressed: _busy ? null : _passReward,
          ),
          const SizedBox(height: 4),
          _LeftToday(left: left),
        ],
      );
    }
    if (left == 0) return const _Note(key: Key('ad-cap'), text: adCapText);
    _preloadOnce();
    final service = ref.watch(monetizationServiceProvider);
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final state = service.adState;
        if (state == AdState.unavailable) {
          return const _Note(
            key: Key('ad-unavailable'),
            text: adUnavailableText,
          );
        }
        final ready = state == AdState.ready;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              key: const Key('ad-double-xp'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.pink),
              icon: const Icon(Icons.ondemand_video),
              label: Text(ready ? 'どうがを みて けいけんち 2ばい' : 'どうがを じゅんび しているよ…'),
              onPressed: _busy || !ready ? null : _watchAd,
            ),
            const SizedBox(height: 4),
            _LeftToday(left: left),
          ],
        );
      },
    );
  }
}

class _LeftToday extends StatelessWidget {
  const _LeftToday({required this.left});
  final int left;

  @override
  Widget build(BuildContext context) => Text(
    'きょうは あと $left かい',
    key: const Key('ad-left'),
    textAlign: TextAlign.center,
    style: const TextStyle(fontSize: 15),
  );
}

class _Note extends StatelessWidget {
  const _Note({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: const TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: AppColors.secondary,
    ),
  );
}
