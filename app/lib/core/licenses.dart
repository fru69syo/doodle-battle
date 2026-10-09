import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds licences of bundled assets (fonts) to Flutter's [LicenseRegistry] so
/// they appear on the licence page in おうちのひと.
void registerAssetLicenses() {
  LicenseRegistry.addLicense(() async* {
    final ofl = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['Zen Maru Gothic'], ofl);
  });
}
