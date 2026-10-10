import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/monetization/monetization_sync.dart';
import 'features/parent/play_time.dart';

class DoodleBattleApp extends ConsumerWidget {
  const DoodleBattleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(monetizationSyncProvider);
    return PlayTimeTracker(
      child: MaterialApp.router(
        title: appDisplayName,
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        locale: const Locale('ja'),
        supportedLocales: const [Locale('ja')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        routerConfig: ref.watch(routerProvider),
        // Keep big text readable without breaking layouts.
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: child!,
        ),
      ),
    );
  }
}
