import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/app_state.dart';
import '../drawing_loop/drawing_loop.dart';
import 'parent_session.dart';

/// 「すべてのデータを削除」: server (`deleteMyData`) first, then local.
/// Returns true when everything was deleted.
Future<bool> deleteAllData(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('すべてのデータを削除しますか？'),
      content: const Text(
        'この端末のキャラクター・進み具合・設定と、サーバー上のデータ'
        '（登録したキャラクター・対戦の記録など）をすべて削除します。'
        '元に戻すことはできません。\n'
        '購入した商品は Google Play のアカウントに記録されているため、'
        '削除のあとも使えます。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          key: const Key('delete-confirm'),
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('削除する'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  final backend = ref.read(backendApiProvider);
  if (backend.isAvailable) {
    try {
      await backend.deleteMyData();
    } on Object {
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('削除できませんでした'),
            content: const Text(
              'サーバーのデータを削除できませんでした。インターネットにつながる場所で、もう一度お試しください。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return false;
    }
  }
  await ref.read(charactersProvider.notifier).deleteAll();
  await ref.read(settingsProvider.notifier).resetLocal();
  // Purchases live in the parent's Google account, not in our data: put
  // them back into the (now empty) local cache.
  if (ref.read(iapEnabledProvider)) {
    unawaited(ref.read(monetizationServiceProvider).restorePurchases());
  }
  ref.invalidate(progressProvider);
  ref.invalidate(stampCardProvider);
  ref.invalidate(activeOdaiProvider);
  ref.read(parentSessionProvider.notifier).lock();
  return true;
}
