import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/app_state.dart';
import '../../domain/character.dart';
import '../../domain/cosmetics.dart';
import '../../features/battle_ui/battle_outcome.dart';
import '../../features/battle_ui/battle_result_screen.dart';
import '../../features/battle_ui/battle_select_screen.dart';
import '../../features/battle_ui/cpu_battle_screen.dart';
import '../../features/battle_ui/stage_select_screen.dart';
import '../../features/birth/birth_screen.dart';
import '../../features/birth/naming_screen.dart';
import '../../features/collection/character_ar_screen.dart';
import '../../features/collection/character_detail_screen.dart';
import '../../features/collection/collection_screen.dart';
import '../../features/card_print/card_print_screen.dart';
import '../../features/card_print/card_select_screen.dart';
import '../../features/draw/draw_screen.dart';
import '../../features/drawing_loop/drawing_loop.dart';
import '../../features/family_battle/family_battle_screen.dart';
import '../../features/family_battle/family_setup.dart';
import '../../features/family_battle/family_setup_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/onboarding/setup_screen.dart';
import '../../features/online/online_battle_screen.dart';
import '../../features/online/online_lobby_screen.dart';
import '../../features/parent/parent_session.dart';
import '../../features/parent/parent_settings_screen.dart';
import '../../features/spike25d/spike25d_debug_page.dart';
import 'routes.dart';

/// Where the router should send [location] given the app state; null to
/// stay. Pure so it can be unit-tested.
String? redirectFor({
  required String location,
  required AsyncValue<Object?> settingsState,
  required bool needsSetup,
  required bool parentUnlocked,
}) {
  if (!settingsState.hasValue && !settingsState.hasError) {
    return location == Routes.splash ? null : Routes.splash;
  }
  if (needsSetup) return location == Routes.setup ? null : Routes.setup;
  if (location == Routes.setup || location == Routes.splash) return Routes.home;
  if (location.startsWith(Routes.parent) && !parentUnlocked) return Routes.home;
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(settingsProvider, (_, _) => refresh.value++);
  ref.listen(parentSessionProvider, (_, _) => refresh.value++);
  final router = GoRouter(
    // Debug builds can start on a debug page:
    // flutter run --dart-define=INITIAL_ROUTE=/debug/25d
    initialLocation: kDebugMode
        ? const String.fromEnvironment(
            'INITIAL_ROUTE',
            defaultValue: Routes.home,
          )
        : Routes.home,
    refreshListenable: refresh,
    redirect: (context, state) {
      // 2.5D spike debug route: reachable before setup in debug builds only.
      if (kDebugMode && state.matchedLocation.startsWith(Routes.debug25d)) {
        return null;
      }
      final settings = ref.read(settingsProvider);
      return redirectFor(
        location: state.matchedLocation,
        settingsState: settings,
        needsSetup: settings.value?.needsSetup ?? settings.hasError,
        parentUnlocked: ref.read(parentSessionProvider),
      );
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const _Splash()),
      GoRoute(path: Routes.setup, builder: (_, _) => const SetupScreen()),
      GoRoute(
        path: Routes.home,
        builder: (_, _) => const HomeScreen(),
        routes: [
          GoRoute(path: 'draw', builder: (_, _) => const DrawScreen()),
          GoRoute(path: 'odai', builder: (_, _) => const StampCardScreen()),
          GoRoute(
            path: 'birth',
            builder: (_, _) => const BirthScreen(),
            routes: [
              GoRoute(path: 'name', builder: (_, _) => const NamingScreen()),
            ],
          ),
          GoRoute(
            path: 'zukan',
            builder: (_, _) => const CollectionScreen(),
            routes: [
              // Before ':id' so 'cards' is not taken for a character id.
              GoRoute(
                path: 'cards',
                builder: (_, _) => const CardSelectScreen(),
                routes: [
                  GoRoute(
                    path: 'print',
                    builder: (_, s) => CardPrintScreen(
                      characterIds: (s.uri.queryParameters['ids'] ?? '')
                          .split(',')
                          .where((id) => id.isNotEmpty)
                          .toList(),
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: ':id',
                builder: (_, s) =>
                    CharacterDetailScreen(characterId: s.pathParameters['id']!),
                routes: [
                  GoRoute(
                    path: 'ar',
                    builder: (_, s) =>
                        CharacterArScreen(characterId: s.pathParameters['id']!),
                  ),
                  GoRoute(
                    path: 'parts',
                    builder: (_, s) =>
                        PartStudioScreen(characterId: s.pathParameters['id']!),
                    routes: [
                      GoRoute(
                        path: 'new',
                        builder: (_, s) => PartStudioScreen(
                          characterId: s.pathParameters['id']!,
                          addNew: true,
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'effect/:move',
                    builder: (_, s) => EffectDrawScreen(
                      characterId: s.pathParameters['id']!,
                      move: DrawnMove.values.firstWhere(
                        (m) => m.name == s.pathParameters['move'],
                        orElse: () => DrawnMove.element,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: 'battle',
            builder: (_, _) => const BattleSelectScreen(),
            routes: [
              GoRoute(
                path: 'result',
                builder: (_, s) => s.extra is BattleOutcome
                    ? BattleResultScreen(outcome: s.extra! as BattleOutcome)
                    : const HomeScreen(),
              ),
              GoRoute(
                path: ':id/stages',
                builder: (_, s) =>
                    StageSelectScreen(characterId: s.pathParameters['id']!),
              ),
              GoRoute(
                path: ':id/stage/:stage',
                builder: (_, s) => CpuBattleScreen(
                  characterId: s.pathParameters['id']!,
                  stage: int.parse(s.pathParameters['stage']!),
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'online',
            builder: (_, _) => const OnlineLobbyScreen(),
            routes: [
              GoRoute(
                path: 'queue/:id',
                builder: (_, s) => _WithCharacter(
                  id: s.pathParameters['id']!,
                  builder: (c) => OnlineQueueScreen(character: c),
                ),
              ),
              GoRoute(
                path: 'match/:matchId',
                builder: (_, s) => _WithCharacter(
                  id: s.uri.queryParameters['c'] ?? '',
                  builder: (c) => OnlineBattleScreen(
                    matchId: s.pathParameters['matchId']!,
                    character: c,
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'family',
            builder: (_, _) => const FamilySetupScreen(),
            routes: [
              GoRoute(
                path: 'battle',
                builder: (_, s) => s.extra is FamilyBattleConfig
                    ? FamilyBattleScreen(config: s.extra! as FamilyBattleConfig)
                    : const FamilySetupScreen(),
              ),
            ],
          ),
          GoRoute(
            path: 'parent',
            builder: (_, _) => const ParentSettingsScreen(),
          ),
          // v2.0 2.5D spike (docs/V2_25D_TECH.md); debug builds only.
          if (kDebugMode)
            GoRoute(
              path: 'debug/25d',
              builder: (_, _) => const Spike25dDebugPage(),
            ),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

/// Resolves a stored character for routes that only carry its id.
class _WithCharacter extends ConsumerWidget {
  const _WithCharacter({required this.id, required this.builder});
  final String id;
  final Widget Function(Character c) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(characterByIdProvider(id));
    if (c == null) return const _Splash();
    return builder(c);
  }
}
