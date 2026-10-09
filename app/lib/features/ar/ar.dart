/// AR feature (SPEC §6) — public API for other teams.
library;

export 'ar_debug_page.dart' show ArDebugPage;
export 'ar_effects.dart' show ArEffects, ArColor, elementAuraColor;
export 'ar_support.dart'
    show ArSupport, ArInstallResult, checkArSupport, requestArCoreInstall;
export 'ar_view_screen.dart' show ArViewScreen, ArViewDependencies;
export 'glb/standee_glb.dart'
    show
        StandeeGlb,
        StandeeGlbOptions,
        buildStandeeGlb,
        buildStandeeGlbInBackground;
