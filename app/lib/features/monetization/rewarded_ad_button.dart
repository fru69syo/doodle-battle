import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/kid_dialogs.dart';
import '../../data/app_state.dart';
import 'monetization_service.dart';

/// Notice shown before every ad (SPEC §7).
const adNoticeText = 'おうちのひとに きいてから みてね\nこうこくが ながれるよ';

/// Post-battle 「どうがを みて けいけんち 2ばい」. Hidden unless the parent
/// allowed ads. With おうえんパス the bonus is given without an ad.
class RewardedAdButton extends ConsumerStatefulWidget {
  const RewardedAdButton({super.key, required this.onRewarded});

  final Future<void> Function() onRewarded;

  @override
  ConsumerState<RewardedAdButton> createState() => _RewardedAdButtonState();
}

class _RewardedAdButtonState extends ConsumerState<RewardedAdButton> {
  bool _used = false;
  bool _busy = false;

  Future<void> _reward() async {
    await widget.onRewarded();
    if (mounted) setState(() => _used = true);
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
        await _reward();
      case RewardedAdResult.notRewarded:
        await showKidMessage(context, 'さいごまで みると けいけんちが 2ばいに なるよ');
      case RewardedAdResult.unavailable:
        await showKidMessage(context, 'いまは どうがが ないみたい。また こんど みてね');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    final pass = settings?.entitlements.contains(Product.ouenPass.id) ?? false;
    if (!pass && !(settings?.consents.ads ?? false)) {
      return const SizedBox.shrink();
    }
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
    return FilledButton.icon(
      key: const Key('ad-double-xp'),
      style: FilledButton.styleFrom(backgroundColor: AppColors.pink),
      icon: Icon(pass ? Icons.favorite : Icons.ondemand_video),
      label: Text(pass ? 'おうえんパスで けいけんち 2ばい' : 'どうがを みて けいけんち 2ばい'),
      onPressed: _busy ? null : (pass ? _reward : _watchAd),
    );
  }
}
