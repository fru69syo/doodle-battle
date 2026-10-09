import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/app_state.dart';
import 'monetization_service.dart';

/// Notice shown with the shop and before every purchase (SPEC §7).
const purchaseNoticeText = 'おかねが かかるよ。おうちのひとと いっしょに かってね';

/// Shop inside おうちのひと (parent-facing). Hidden unless purchases are
/// allowed. Every purchase: parental gate again → confirmation with the
/// store price and the notice → Google Play's purchase sheet.
class ShopSection extends ConsumerStatefulWidget {
  const ShopSection({super.key});

  @override
  ConsumerState<ShopSection> createState() => _ShopSectionState();
}

class _ShopSectionState extends ConsumerState<ShopSection> {
  bool _refreshed = false;
  bool _restoring = false;

  void _refreshOnce() {
    if (_refreshed) return;
    _refreshed = true;
    ref.read(monetizationServiceProvider).refreshStore();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    if (!(settings?.consents.purchases ?? false)) {
      return const ListTile(
        key: Key('shop-disabled'),
        leading: Icon(Icons.shopping_bag_outlined),
        title: Text('ショップ'),
        subtitle: Text('アプリ内課金が許可されていないため表示していません。'),
      );
    }
    _refreshOnce();
    final store = ref.watch(monetizationServiceProvider);
    final owned = settings?.entitlements ?? const <String>{};
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Column(
        key: const Key('shop'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Notice(),
          if (!store.storeAvailable)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'ストアに接続できません。Google Play にログインしているか、'
                'インターネットにつながっているかをご確認ください。',
                key: Key('shop-unavailable'),
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
              subtitle: Text(
                '${p.description}\n'
                '${owned.contains(p.id) ? '購入済み' : '価格: ${store.priceOf(p) ?? '—'}'}'
                '（1回だけの購入。定期購入ではありません）',
                key: Key('shop-price-${p.id}'),
              ),
              isThreeLine: true,
              trailing: owned.contains(p.id)
                  ? const Chip(label: Text('購入済み'))
                  : FilledButton(
                      key: Key('buy-${p.id}'),
                      onPressed: store.priceOf(p) != null
                          ? () => _buy(p)
                          : null,
                      child: const Text('買う'),
                    ),
            ),
          TextButton(
            key: const Key('shop-restore'),
            onPressed: _restoring ? null : _restore,
            child: const Text('購入を復元する'),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '支払いと返金は Google Play が行います。購入の記録は Google のアカウントに'
              '保存され、アプリを入れ直しても「購入を復元する」で戻せます。',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _restore() async {
    setState(() => _restoring = true);
    final ok = await ref.read(monetizationServiceProvider).restorePurchases();
    if (!mounted) return;
    setState(() => _restoring = false);
    _snack(ok ? '購入状況を更新しました。' : 'ストアに接続できませんでした。時間をおいてお試しください。');
  }

  Future<void> _buy(Product p) async {
    // A parental gate before *every* purchase, even inside おうちのひと.
    if (!await ref.read(parentalGateProvider).verify(context)) return;
    if (!mounted) return;
    final store = ref.read(monetizationServiceProvider);
    final price = store.priceOf(p);
    if (price == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.shopping_bag, size: 48),
        title: Text(p.title, textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              price,
              key: const Key('purchase-price'),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text('1回だけの購入（定期購入ではありません）'),
            const SizedBox(height: 12),
            const _Notice(textKey: Key('purchase-notice')),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton(
            key: const Key('purchase-cancel'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('やめる'),
          ),
          FilledButton(
            key: const Key('purchase-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text('$price で買う'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final result = await store.purchase(p);
    if (!mounted) return;
    _snack(switch (result) {
      PurchaseResult.purchased => '購入しました。ありがとうございます。',
      PurchaseResult.pending => '支払いの手続き中です。支払いが完了するとアプリに反映されます。',
      PurchaseResult.cancelled => '購入をキャンセルしました。',
      PurchaseResult.unavailable => 'ストアに接続できませんでした。',
      PurchaseResult.error => '購入できませんでした。時間をおいてお試しください。',
    });
  }
}

class _Notice extends StatelessWidget {
  const _Notice({this.textKey = const Key('shop-notice')});
  final Key textKey;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFE9A8),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        const Icon(Icons.warning_amber, size: 32),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            purchaseNoticeText,
            key: textKey,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}
