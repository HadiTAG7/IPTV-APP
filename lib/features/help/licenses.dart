// Licences of bundled assets that are not Dart packages.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Asset holding the SIL Open Font License of the bundled Tajawal font.
const kTajawalLicenseAsset = 'assets/fonts/OFL.txt';

/// Package name under which the font licence is listed.
const kTajawalLicensePackage = 'Tajawal';

bool _fontLicensesRegistered = false;

/// Adds the Tajawal font licence (SIL OFL 1.1) to [LicenseRegistry], so it
/// shows on the licences page. Call once at app start; later calls do
/// nothing. The text is read lazily from [bundle] (default [rootBundle])
/// when the licences page is opened.
void registerFontLicenses({AssetBundle? bundle}) {
  if (_fontLicensesRegistered) return;
  _fontLicensesRegistered = true;
  LicenseRegistry.addLicense(() async* {
    final text = await (bundle ?? rootBundle).loadString(kTajawalLicenseAsset);
    yield LicenseEntryWithLineBreaks(const [kTajawalLicensePackage], text);
  });
}

/// Lets tests register again after `LicenseRegistry.reset()`.
@visibleForTesting
void resetFontLicensesForTest() => _fontLicensesRegistered = false;
