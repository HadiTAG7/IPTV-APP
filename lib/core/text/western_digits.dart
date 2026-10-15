// Digits in Arabic text: the app shows Western digits (0-9) everywhere, the
// same digits as on the remote's keys and in channel numbers.
import 'package:intl/intl.dart' show DateFormat;

/// Makes every [DateFormat] in Arabic print Western digits, including the
/// dates of the generated localized messages.
///
/// Flutter's own `ar` date symbols (loaded by the Material localizations)
/// default to Arabic-Indic digits; number formats already use Western ones.
/// Call once at start (bootstrap; tests do it in `flutter_test_config`).
void useWesternDigits() => DateFormat.useNativeDigitsByDefaultFor('ar', false);
