// Providers and constants of the Help screen.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Public iptv-org playlist of channels from Saudi Arabia. Shown as text the
/// user can type; the app never adds it on its own.
const kIptvOrgSaudiUrl = 'https://iptv-org.github.io/iptv/countries/sa.m3u';

/// Public iptv-org playlist of Arabic-language channels.
const kIptvOrgArabicUrl = 'https://iptv-org.github.io/iptv/languages/ara.m3u';

/// Fixed download link of the newest universal APK (typed into Downloader on
/// Android TV and Fire TV).
const kLatestApkUrl =
    'https://github.com/HadiTAG7/IPTV-APP/releases/latest/download/iptv-player-universal.apk';

/// Opens the source editor pre-filled with an M3U [url] and a suggested
/// [name]. The user still reviews and saves it.
typedef AddSourcePrefill = Future<void> Function(
  BuildContext context, {
  required String url,
  required String name,
});

/// What Help's "Add as source" buttons call. Null (the default) means no
/// source editor route is available, and the buttons are hidden; the app
/// wires it to the source editor.
final addSourcePrefillProvider = Provider<AddSourcePrefill?>(
  (ref) => null,
  name: 'addSourcePrefillProvider',
);
