import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/app_state.dart';
import 'monetization_service.dart';

/// Notice shown above the shop (SPEC §7).
const purchaseNoticeText = 'おかねが かかるよ。おうちのひとと いっしょに かってね';

/// Shop inside おうちのひと. Hidden unless purchases are allowed; every
/// purchase passes the parental gate again.
class ShopSection extends ConsumerWidget {
  const ShopSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value;
    if (!(settings?.consents.purchases ?? false)) {
      return const ListTile(
        key: Key('shop-disabled'),
        leading: Icon(Icons.shopping_bag_outlined),
        title: Text('ショップ'),
        subtitle: Text('アプリ内課金が許可されていないため表示していません。'),
      );
    }
    final store = ref.watch(monetizationServiceProvider);
    final owned = settings?.entitlements ?? const <String>{};
    return Column(
      key: const Key('shop'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFE9A8),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            children: [
              Icon(Icons.warning_amber, size: 32),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  purchaseNoticeText,
                  key: Key('shop-notice'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        if (!store.storeAvailable)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'ストアは準備中です。',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        for (final p in Product.values)
          ListTile(
            key: Key('shop-${p.id}'),
            title: Text(
              p.title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(p.description),
            trailing: owned.contains(p.id)
                ? const Chip(label: Text('購入済み'))
                : FilledButton(
                    key: Key('buy-${p.id}'),
                    onPressed: store.storeAvailable
                        ? () => _buy(context, ref, p)
                        : null,
                    child: const Text('買う'),
                  ),
          ),
        TextButton(
          key: const Key('shop-restore'),
          onPressed: store.storeAvailable
              ? () => store.restorePurchases()
              : null,
          child: const Text('購入を復元する'),
        ),
      ],
    );
  }

  Future<void> _buy(BuildContext context, WidgetRef ref, Product p) async {
    // A parental gate before *every* purchase, even inside おうちのひと.
    if (!await ref.read(parentalGateProvider).verify(context)) return;
    final result = await ref.read(monetizationServiceProvider).purchase(p);
    if (!context.mounted) return;
    final text = switch (result) {
      PurchaseResult.purchased => '購入しました。',
      PurchaseResult.pending => '購入手続き中です。完了するとアプリに反映されます。',
      PurchaseResult.cancelled => '購入をキャンセルしました。',
      PurchaseResult.unavailable => 'ストアは準備中です。',
      PurchaseResult.error => '購入できませんでした。時間をおいてお試しください。',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

/// Mirrors the store's entitlements into settings (cached for offline).
final entitlementSyncProvider = Provider<void>((ref) {
  final sub = ref.watch(monetizationServiceProvider).entitlements.listen((
    owned,
  ) {
    ref.read(settingsProvider.notifier).setEntitlements({
      for (final p in owned) p.id,
    });
  });
  ref.onDispose(sub.cancel);
});
