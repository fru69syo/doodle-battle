import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// True while a parent who passed the gate is inside おうちのひと. The router
/// refuses `/parent` otherwise.
class ParentSession extends Notifier<bool> {
  @override
  bool build() => false;

  void unlock() => state = true;
  void lock() => state = false;
}

final parentSessionProvider = NotifierProvider<ParentSession, bool>(
  ParentSession.new,
);

/// Runs the parental gate and unlocks the parent area. Returns true if
/// passed.
Future<bool> unlockParentArea(BuildContext context, WidgetRef ref) async {
  final ok = await ref.read(parentalGateProvider).verify(context);
  if (ok) ref.read(parentSessionProvider.notifier).unlock();
  return ok;
}
