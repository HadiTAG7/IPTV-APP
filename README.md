# IPTV Player · مشغّل IPTV

[![build](https://github.com/HadiTAG7/IPTV-APP/actions/workflows/build.yml/badge.svg)](https://github.com/HadiTAG7/IPTV-APP/actions/workflows/build.yml)

A personal IPTV **player** for Android phones and tablets, Android TV, Google TV, Android boxes and Fire TV, plus a portable Windows build.

Status: under active development; features land milestone by milestone (see the releases).

> **The app ships no channels, playlists, EPG URLs or provider links.** You add an M3U URL/file or an Xtream Codes login from a source you have the right to use. See [docs/LEGAL_SOURCES_AR.md](docs/LEGAL_SOURCES_AR.md).

## بالعربي

مشغّل IPTV شخصي للجوال والتابلت وأجهزة التلفزيون (Android TV و Google TV والبوكسات و Fire TV)، مع نسخة محمولة لويندوز.

- **التطبيق مشغّل فقط**: ما فيه أي قنوات أو قوائم أو روابط. أنت تضيف رابط M3U أو ملف M3U أو بيانات Xtream من مصدر يحق لك استخدامه.
- **المميزات**: قنوات مباشرة بالفئات، ومفضلة، وبحث؛ دليل البرامج (EPG)؛ أفلام ومسلسلات مع المتابعة من حيث وقفت؛ أكثر من اشتراك؛ واجهة عربية وإنجليزية كاملة من اليمين لليسار؛ تحكم كامل بالريموت.
- **التنزيل**: من [صفحة الإصدارات](https://github.com/HadiTAG7/IPTV-APP/releases/latest). للتلفزيون اكتب هذا الرابط في تطبيق Downloader:
  `https://github.com/HadiTAG7/IPTV-APP/releases/latest/download/iptv-player-universal.apk`
- **الأدلة**: [طريقة التثبيت](docs/INSTALL_AR.md) · [المصادر النظامية](docs/LEGAL_SOURCES_AR.md) · [قائمة فحص الجهاز](docs/DEVICE_QA_AR.md)

## Features

- Live TV with categories, favourites, recents and search (Arabic/Latin-normalised).
- EPG from Xtream `xmltv.php`, M3U `url-tvg` or a manual XMLTV URL: now/next and a guide grid.
- Movies and series with seasons, episodes, resume and next-episode countdown.
- Several sources (M3U URL, M3U file, Xtream Codes) with switching.
- Two player engines behind one interface: ExoPlayer (`video_player`) and mpv (`media_kit`), with automatic fallback and a per-channel "Switch player".
- TV-first UI: D-pad focus, `LEANBACK_LAUNCHER` + banner, back handled through `PopScope`, phone-to-TV text entry via QR.
- Full Arabic and English UI with right-to-left layout.

## Download

| File | For |
|---|---|
| `iptv-player-universal.apk` | Any supported Android device (pick this if unsure) |
| `iptv-player-armeabi-v7a.apk` | Fire TV Stick and low-cost boxes (32-bit) |
| `iptv-player-arm64-v8a.apk` | Modern phones, Nvidia Shield, Google TV |
| `iptv-player-windows-x64.zip` | Windows 10/11 x64, portable |

Fixed TV download URL (Downloader app or a TV browser):
`https://github.com/HadiTAG7/IPTV-APP/releases/latest/download/iptv-player-universal.apk`

Requires Android 7.0 (API 24) or newer. Fire TV devices running Vega OS cannot install APKs. Each release includes `SHA256SUMS.txt`. Install steps (Arabic): [docs/INSTALL_AR.md](docs/INSTALL_AR.md).

## Build

Toolchain: Flutter **3.47.7** stable (Dart 3.13.5), JDK 17+, Android SDK 36, build-tools 36.0.0, NDK 28.2.13676358. On Linux, `bash tool/setup_container.sh` installs all of it idempotently.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test --exclude-tags network,bench

# Android: per-ABI APKs and a universal APK (ARM only)
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 \
  --build-name 0.0.0-dev --build-number 1 -P force-version-code-ignoring-abi=true
flutter build apk --release --target-platform android-arm,android-arm64 \
  --build-name 0.0.0-dev --build-number 1 -P force-version-code-ignoring-abi=true
bash tool/check_apk.sh build/app/outputs/flutter-apk/app-arm64-v8a-release.apk 90

# Windows (on Windows)
flutter build windows --release
```

**Signing.** Release builds use `android/key.properties` when present (`storeFile`, relative to `android/app`, plus `storePassword`, `keyAlias`, `keyPassword`); otherwise they fall back to the debug key. Never commit keystores or `key.properties`.

**CI.** [`.github/workflows/build.yml`](.github/workflows/build.yml) is the only workflow that produces installables (versionCode = its run number, so never rename it). It runs tests, builds and checks the APKs on every push and PR, builds the Windows zip on tags and manual runs, and publishes a GitHub Release for `v*` tags. Release signing comes from the repository secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`; without them, branch builds are debug-signed (artifact suffix `-debug-signed`, do not install) and tag builds fail.

## Project structure

```
lib/
  app/        MaterialApp, shells (TV / phone), form factor
  core/       platform (DeviceCaps channel), net (dio, redaction), db (drift), text, time, log
  sources/    SourceAdapter, M3U and Xtream adapters, sync service
  epg/        XMLTV pipeline and channel matcher
  player/     PlayerEngine (Exo + mpv), session control, player UI
  tv/         focus toolkit for D-pad navigation
  features/   onboarding, live, guide, movies, series, favourites, search, settings, help, diagnostics
  l10n/       Arabic and English strings
android/      TV-ready manifest, banner, DeviceCaps MethodChannel (app/device)
windows/      desktop runner
test/         unit, widget, golden and contract tests (synthetic fixtures only)
tool/         setup_container.sh, check_apk.sh, gen_brand_assets.py
docs/         Arabic install, legal-sources and device QA guides
```

## Legal

This project is a media player only. It does not provide, host, link to or recommend any channels, playlists or subscriptions, and it contains no provider URLs. Use it only with content you are entitled to watch. Unlicensed IPTV subscriptions are illegal under Saudi copyright law and carry fraud and malware risks; see [docs/LEGAL_SOURCES_AR.md](docs/LEGAL_SOURCES_AR.md) for legal options.

## License

Copyright (C) 2026 the IPTV Player contributors.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version (**GPL-3.0-or-later**). See [LICENSE](LICENSE).

The bundled Tajawal font is licensed under the SIL Open Font License 1.1 ([assets/fonts/OFL.txt](assets/fonts/OFL.txt)).
