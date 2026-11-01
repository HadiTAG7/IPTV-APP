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
- In-player channel panel (OK while watching): browse every list and switch channel, or list, without leaving the player.
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

## الحساب والمزامنة · Account sync

من «الحساب والمزامنة» في الإعدادات أو شاشة البداية، أنشئ حسابًا بالبريد وكلمة المرور ثم سجّل بالحساب نفسه على أجهزتك. ابدأ بالجهاز الذي عليه ترتيبك الحالي. تُدمج الاشتراكات وبيانات دخولها والقوائم وترتيب القنوات والمفضلة وسجل المتابعة وإعدادات اللغة، مع بقاء إعدادات أداء كل جهاز مستقلة. حذف اشتراك على جهاز مرتبط بالحساب يحذفه من كل الأجهزة. بعد تسجيل الدخول على جهاز جديد تُحمّل اشتراكاتك ويُحدّث فهرس القنوات تلقائيًا.

تُرسل التغييرات بعد نحو ثانيتين، أما موضع المشاهدة والقنوات الأخيرة فتُرسل كل دقيقتين على الأكثر وعند الخروج من التطبيق، وتتحقق الأجهزة المفتوحة من التحديثات كل 30 ثانية، وعند العودة للتطبيق أو الضغط على «المزامنة الآن». عند انقطاع الاتصال تبقى التغييرات محلية حتى تنجح المحاولة التالية. تسجيل الخروج يوقف المزامنة ويُبقي بيانات الجهاز، ولا تُرفع لحساب مختلف إلا إذا اخترت نقل الجهاز إليه عند تسجيل الدخول به، فتبقى بياناته كما هي وتُدمج فيه، وتحلّ محل نسخ ذلك الحساب من العناصر نفسها، ويحتفظ الحساب السابق بنسخته. ملفات M3U حتى 32 ميجابايت تُنقل مضغوطة ومقسمة، دون رفع مسارات الملفات المحلية.

The account backend is the dedicated Firebase project `hadi-iptv-sync-20261031` (email/password Auth and Firestore). Android, TV and Windows use the same authenticated REST client; no experimental Windows Firebase SDK is required. Refresh tokens are stored with platform secure storage, and account passwords are never persisted. Firestore rules restrict every account path to its authenticated owner. The client configuration contains a public API key only; no service-account credential belongs in the app.

Sync uses stable cloud identities, per-record changes, deletion tombstones and revision preconditions. Concurrent changes to different records merge; a record changed on two devices keeps the fields each device changed, and the latest successfully uploaded change wins for a field both changed, except an older playback checkpoint or recently watched channel cannot replace a newer one. A removal from a list does not undo an order made on another device meanwhile. A playlist file's record and its chunks always come from the same device. Only a tombstone deletes data on a device: records missing from the account without one (documents deleted in the console, an older backup restored) are uploaded again. Record types, fields and kinds that a newer version adds are kept as received by an older one: a subscription it gives a live format, or an account language it adds, keeps syncing there with the older version's default in its place until that setting is changed there; a subscription it moves to a new kind keeps the older device's copy, while its favourites, lists and progress keep syncing. A later version applies what an earlier one could not hold instead of taking it for a deletion. Local edits made during a request remain pending. Local-only edits commit on top of the last synced revision without re-reading the account; only a change from another device triggers a full read and merge. Playback progress and recent channels upload at most every two minutes and when the app goes to the background; an unfocused desktop window keeps syncing. An unchanged poll reads only the account revision. The source catalogue and EPG cache are downloaded separately by each device, keeping sync small. Channel playback preferences and device layout/decoder/performance choices stay local; interface/audio/subtitle language preferences sync.

Deploy backend configuration with `firebase deploy --only auth,firestore --project hadi-iptv-sync-20261031`. Client configuration can be overridden with `--dart-define=FIREBASE_PROJECT_ID=... --dart-define=FIREBASE_API_KEY=...`. Run `flutter test test/account --exclude-tags network` for local account tests. The opt-in live test creates and removes synthetic Auth users only: `IPTV_FIREBASE_LIVE=1 flutter test test/account/firebase_live_test.dart`; remove their Firestore test paths afterward using the IDs saved in the system temporary `iptv-firebase-qa-users.json` file. Never run tests using a real customer's credentials.

When a configured second device first joins an existing account, existing cloud records and deletion tombstones take precedence over that device's old copies. A subscription, list or playlist file already in the account is recognised by its current address, name or content, also when it changed after its first upload. Local-only additions merge in, and the newer viewing checkpoint is retained; a subscription or list deleted elsewhere is kept when the joining device has favourites, lists or viewing progress of its own in it. Start account setup on the device with your preferred current arrangement. On a device linked to an account, deleting a subscription removes it from every device. A device's data stays with the account it signed in with; signing in with another account offers to switch the device to it, after saying that its data stays, merges into the new account, replacing that account's copies of the same items, and that the previous account keeps its copy. That first sign-in keeps everything the device holds, also what the new account had deleted; the account's other entries follow the device's own.

## Build

Toolchain: Flutter **3.47.7** stable (Dart 3.13.5), JDK 17+, Android SDK 36, build-tools 36.0.0, NDK 28.2.13676358. On Linux, `bash tool/setup_container.sh` installs all of it idempotently (it installs `openjdk-17-jdk-headless` only when no Java 17+ is on `PATH`).

The Linux desktop build (CI and E2E runs) also needs `libsecret-1-dev`, which the setup script installs: account sign-in keeps its session in the Secret Service. A session without one, such as a bare Xvfb display, keeps a sign-in only until the app closes and then asks for it again; local data is unaffected.

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

**Signing.** Release builds use `android/key.properties` when present (`storeFile`, relative to `android/app`, plus `storePassword`, `keyAlias`, `keyPassword`; read as UTF-8 with `java.util.Properties` escaping, so write a leading space as `\ ` and a backslash as `\\`); otherwise they fall back to the debug key. Never commit keystores or `key.properties`.

**Impeller escape hatch.** `-P impellerOff=true` merges `android/app/src/impellerOff/AndroidManifest.xml` (`io.flutter.embedding.android.EnableImpeller=false`) into a release build, for boxes whose GPU drivers misrender under Impeller. Normal builds never carry the flag. CI builds it as `iptv-player-universal-compat.apk` when a manual run ticks `impeller_off`, or on every run (releases included) when the repository variable `IMPELLER_COMPAT_APK` is `true`.

**CI.** [`.github/workflows/build.yml`](.github/workflows/build.yml) is the only workflow that produces installables (versionCode = its run number, so never rename it). It runs tests, builds and checks the APKs on every push and PR, builds the Windows zip on PRs, tags and manual runs, and publishes a GitHub Release for `v*` tags. Release signing comes from the repository secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`; without them, branch builds are debug-signed (artifact suffix `-debug-signed`, do not install) and tag builds fail. Tag builds also require `.github/release-cert.sha256`, the release certificate's SHA-256 fingerprint (from `keytool -list -v -keystore release.jks`; colons allowed), and fail if the APKs are signed by any other certificate, so a replaced keystore can never ship an update that installed copies reject.

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
