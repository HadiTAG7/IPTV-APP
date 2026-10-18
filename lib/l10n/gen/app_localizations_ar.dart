// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'مشغّل IPTV';

  @override
  String get commonOk => 'حسناً';

  @override
  String get commonCancel => 'إلغاء';

  @override
  String get commonSave => 'حفظ';

  @override
  String get commonDelete => 'حذف';

  @override
  String get commonBack => 'رجوع';

  @override
  String get commonClose => 'إغلاق';

  @override
  String get commonEdit => 'تعديل';

  @override
  String get commonAdd => 'إضافة';

  @override
  String get commonNext => 'التالي';

  @override
  String get commonDone => 'تم';

  @override
  String get commonYes => 'نعم';

  @override
  String get commonNo => 'لا';

  @override
  String get commonRetry => 'إعادة المحاولة';

  @override
  String get commonLoading => 'جارٍ التحميل…';

  @override
  String get commonEmpty => 'لا يوجد شيء هنا بعد';

  @override
  String get commonErrorGeneric => 'حدث خطأ ما';

  @override
  String get commonUnavailable => 'غير متاح';

  @override
  String get commonCopied => 'تم النسخ';

  @override
  String get commonOn => 'تشغيل';

  @override
  String get commonOff => 'إيقاف';

  @override
  String get commonSearchHint => 'ابحث في القنوات والأفلام والمسلسلات';

  @override
  String get commonPressBackAgainToExit => 'اضغط رجوع مرة أخرى للخروج';

  @override
  String get onboardingWelcomeTitle => 'أهلاً بك';

  @override
  String get onboardingWelcomeBody =>
      'شاهد مصادر IPTV الخاصة بك على التلفزيون والجوال والكمبيوتر.';

  @override
  String get onboardingChooseLanguage => 'اختر اللغة';

  @override
  String get onboardingDisclaimer => 'التطبيق مشغّل فقط ولا يوفّر أي محتوى.';

  @override
  String get onboardingLearnMore => 'اعرف أكثر';

  @override
  String get onboardingGetStarted => 'ابدأ';

  @override
  String get onboardingAddSourceTitle => 'أضف مصدراً';

  @override
  String get onboardingAddSourceBody =>
      'أضف رابط M3U أو ملف M3U أو بيانات Xtream Codes من مزوّد يحق لك استخدامه.';

  @override
  String get onboardingSkip => 'لاحقاً';

  @override
  String get sourceTypeM3uUrl => 'رابط M3U';

  @override
  String get sourceTypeM3uUrlHint =>
      'رابط قائمة تشغيل، ينتهي عادةً بامتداد m3u أو m3u8';

  @override
  String get sourceTypeM3uFile => 'ملف M3U';

  @override
  String get sourceTypeM3uFileHint => 'ملف قائمة تشغيل محفوظ على هذا الجهاز';

  @override
  String get sourceTypeXtream => 'Xtream Codes';

  @override
  String get sourceTypeXtreamHint => 'عنوان الخادم واسم المستخدم وكلمة المرور';

  @override
  String get fieldName => 'الاسم';

  @override
  String get fieldNameHint => 'مثال: البيت';

  @override
  String get fieldServer => 'الخادم';

  @override
  String get fieldServerHint => 'http://example.com:8080';

  @override
  String get fieldUsername => 'اسم المستخدم';

  @override
  String get fieldPassword => 'كلمة المرور';

  @override
  String get fieldShowPassword => 'إظهار كلمة المرور';

  @override
  String get fieldHidePassword => 'إخفاء كلمة المرور';

  @override
  String get fieldPlaylistUrl => 'رابط القائمة';

  @override
  String get fieldPlaylistUrlHint => 'http://example.com/playlist.m3u';

  @override
  String get fieldFile => 'الملف';

  @override
  String get fieldChooseFile => 'اختر ملفاً';

  @override
  String get fieldNoFileChosen => 'لم يتم اختيار ملف';

  @override
  String get fieldUserAgent => 'وكيل المستخدم (User-Agent)';

  @override
  String get fieldUserAgentCustom => 'مخصّص';

  @override
  String get fieldReferer => 'المُحيل (Referer)';

  @override
  String get fieldEpgUrl => 'رابط دليل البرامج (EPG)';

  @override
  String get fieldEpgUrlHint => 'رابط دليل XMLTV (اختياري)';

  @override
  String get fieldLiveFormat => 'صيغة البث المباشر';

  @override
  String get liveFormatTs => '⁦MPEG-TS (.ts)⁩';

  @override
  String get liveFormatHls => '⁦HLS (.m3u8)⁩';

  @override
  String get fieldAdvancedOptions => 'خيارات متقدمة';

  @override
  String get fieldRequired => 'هذا الحقل مطلوب';

  @override
  String get fieldOptional => 'اختياري';

  @override
  String get typeOnYourPhone => 'اكتب من جوالك';

  @override
  String get testAndSave => 'اختبار وحفظ';

  @override
  String get validating => 'جارٍ التحقق…';

  @override
  String get errorInvalidUrl =>
      'رابط غير صالح. يجب أن يبدأ بـ ⁦http://⁩ أو ⁦https://⁩.';

  @override
  String get errorUnreachable =>
      'تعذّر الوصول إلى الخادم. تحقّق من العنوان ومن اتصالك بالإنترنت.';

  @override
  String get errorTimeout =>
      'استغرق الخادم وقتاً طويلاً في الرد. حاول مرة أخرى لاحقاً.';

  @override
  String get errorAuthFailed => 'اسم المستخدم أو كلمة المرور غير صحيحة.';

  @override
  String errorExpired(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'انتهى هذا الاشتراك بتاريخ $dateString.';
  }

  @override
  String get errorBanned => 'حظر المزوّد هذا الحساب.';

  @override
  String get errorDisabled => 'هذا الحساب معطّل.';

  @override
  String get errorNotM3u => 'المحتوى ليس قائمة تشغيل M3U صالحة.';

  @override
  String get errorFileRead => 'تعذّرت قراءة الملف.';

  @override
  String get errorCatalogIncomplete =>
      'وصلت بعض القوائم فارغة، فاحتفظنا بالقوائم السابقة. حاول مرة أخرى لاحقًا.';

  @override
  String errorHttpStatus(int code) {
    return 'أعاد الخادم الخطأ $code.';
  }

  @override
  String get importTitle => 'جارٍ استيراد المصدر';

  @override
  String importLiveCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count قناة مباشرة',
      many: '$count قناة مباشرة',
      few: '$count قنوات مباشرة',
      two: 'قناتان مباشرتان',
      one: 'قناة مباشرة واحدة',
      zero: 'لا توجد قنوات مباشرة',
    );
    return '$_temp0';
  }

  @override
  String importMoviesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count فيلم',
      many: '$count فيلماً',
      few: '$count أفلام',
      two: 'فيلمان',
      one: 'فيلم واحد',
      zero: 'لا توجد أفلام',
    );
    return '$_temp0';
  }

  @override
  String importSeriesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مسلسل',
      many: '$count مسلسلاً',
      few: '$count مسلسلات',
      two: 'مسلسلان',
      one: 'مسلسل واحد',
      zero: 'لا توجد مسلسلات',
    );
    return '$_temp0';
  }

  @override
  String get importGuide => 'جارٍ تحميل دليل البرامج…';

  @override
  String get importCancel => 'إلغاء الاستيراد';

  @override
  String get importDone => 'اكتمل الاستيراد';

  @override
  String get importFailed => 'فشل الاستيراد';

  @override
  String get navLive => 'مباشر';

  @override
  String get navGuide => 'الدليل';

  @override
  String get navMovies => 'أفلام';

  @override
  String get navSeries => 'مسلسلات';

  @override
  String get navSearch => 'بحث';

  @override
  String get navFavorites => 'المفضلة';

  @override
  String get navSettings => 'الإعدادات';

  @override
  String get navSources => 'المصادر';

  @override
  String get navMore => 'المزيد';

  @override
  String get navSwitchSource => 'تبديل المصدر';

  @override
  String get liveAllChannels => 'كل القنوات';

  @override
  String get liveFavorites => 'المفضلة';

  @override
  String get liveRecent => 'الأخيرة';

  @override
  String get liveCategories => 'الفئات';

  @override
  String get liveNoProgrammeInfo => 'لا توجد معلومات عن البرنامج';

  @override
  String get liveNow => 'الآن';

  @override
  String get liveNext => 'التالي';

  @override
  String liveNowTitle(String title) {
    return 'الآن: ⁨$title⁩';
  }

  @override
  String liveNextTitle(String title) {
    return 'التالي: ⁨$title⁩';
  }

  @override
  String liveChannelCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count قناة',
      many: '$count قناة',
      few: '$count قنوات',
      two: 'قناتان',
      one: 'قناة واحدة',
      zero: 'لا توجد قنوات',
    );
    return '$_temp0';
  }

  @override
  String get liveNoChannels => 'لا توجد قنوات في هذه الفئة';

  @override
  String get liveAddFavorite => 'إضافة إلى المفضلة';

  @override
  String get liveRemoveFavorite => 'إزالة من المفضلة';

  @override
  String get liveHideCategory => 'إخفاء الفئة';

  @override
  String get liveAssignGuideChannel => 'ربط بقناة في الدليل';

  @override
  String get livePlayWithOtherPlayer => 'التشغيل بالمشغّل الآخر';

  @override
  String liveChannelNumber(int number) {
    return 'القناة $number';
  }

  @override
  String get guideToday => 'اليوم';

  @override
  String get guideTomorrow => 'غداً';

  @override
  String get guideNow => 'الآن';

  @override
  String get guideRefresh => 'تحديث الدليل';

  @override
  String get guideUpdating => 'جارٍ تحديث الدليل…';

  @override
  String get guideEmpty =>
      'لا توجد بيانات للدليل بعد. أضف رابط EPG من الإعدادات.';

  @override
  String guideUpdated(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'تم تحديث الدليل $dateString';
  }

  @override
  String get vodContinueWatching => 'متابعة المشاهدة';

  @override
  String get vodPlay => 'تشغيل';

  @override
  String vodResumeFrom(String time) {
    return 'استكمال من $time';
  }

  @override
  String get vodStartOver => 'من البداية';

  @override
  String get vodSeasons => 'المواسم';

  @override
  String get vodEpisodes => 'الحلقات';

  @override
  String vodSeasonN(int n) {
    return 'الموسم $n';
  }

  @override
  String vodEpisodeN(int n) {
    return 'الحلقة $n';
  }

  @override
  String vodEpisodeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count حلقة',
      many: '$count حلقة',
      few: '$count حلقات',
      two: 'حلقتان',
      one: 'حلقة واحدة',
      zero: 'لا توجد حلقات',
    );
    return '$_temp0';
  }

  @override
  String vodNextEpisodeIn(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'الحلقة التالية خلال $seconds ثانية',
      many: 'الحلقة التالية خلال $seconds ثانية',
      few: 'الحلقة التالية خلال $seconds ثوانٍ',
      two: 'الحلقة التالية خلال ثانيتين',
      one: 'الحلقة التالية خلال ثانية واحدة',
      zero: 'الحلقة التالية الآن',
    );
    return '$_temp0';
  }

  @override
  String get vodNextEpisode => 'الحلقة التالية';

  @override
  String vodMinutes(int minutes) {
    return '$minutes د';
  }

  @override
  String get vodNoEpisodes => 'لا توجد حلقات متاحة';

  @override
  String get vodWatched => 'تمت المشاهدة';

  @override
  String get vodAddFavorite => 'إضافة إلى المفضلة';

  @override
  String get vodRemoveFavorite => 'إزالة من المفضلة';

  @override
  String get playerAudio => 'الصوت';

  @override
  String get playerSubtitles => 'الترجمة';

  @override
  String get playerOff => 'إيقاف';

  @override
  String get playerAspectRatio => 'نسبة العرض';

  @override
  String get aspectFit => 'ملاءمة';

  @override
  String get aspectFill => 'ملء الشاشة';

  @override
  String get aspectStretch => 'تمديد';

  @override
  String get aspect16x9 => '16:9';

  @override
  String get aspect4x3 => '4:3';

  @override
  String get playerSwitchPlayer => 'تبديل المشغّل';

  @override
  String get playerStats => 'الإحصائيات';

  @override
  String get playerFullscreen => 'شاشة كاملة';

  @override
  String get playerExitFullscreen => 'خروج من الشاشة الكاملة';

  @override
  String get playerFavorite => 'المفضلة';

  @override
  String get playerGuide => 'الدليل';

  @override
  String get playerLive => 'مباشر';

  @override
  String get playerBuffering => 'جارٍ التخزين المؤقت…';

  @override
  String playerReconnecting(int n, int max) {
    return 'جارٍ إعادة الاتصال… ($n/$max)';
  }

  @override
  String get playerPlaybackFailed => 'تعذّر التشغيل';

  @override
  String get playerRetry => 'إعادة المحاولة';

  @override
  String get playerTryOtherFormat => 'جرّب صيغة أخرى';

  @override
  String get playerCopyReport => 'نسخ التقرير';

  @override
  String get playerSubtitlesNeedMpv => 'الترجمة تحتاج مشغّل mpv.';

  @override
  String playerTrackN(int n) {
    return 'المسار $n';
  }

  @override
  String get statsEngine => 'المشغّل';

  @override
  String get statsCodec => 'الترميز';

  @override
  String get statsResolution => 'الدقة';

  @override
  String get statsFirstFrame => 'زمن ظهور أول إطار';

  @override
  String get statsDroppedFrames => 'الإطارات المفقودة';

  @override
  String get settingsGeneral => 'عام';

  @override
  String get settingsLanguage => 'اللغة';

  @override
  String get languageAuto => 'تلقائي (لغة النظام)';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageEnglish => 'English';

  @override
  String get settingsDeviceMode => 'وضع الجهاز';

  @override
  String get deviceModeAuto => 'تلقائي';

  @override
  String get deviceModeTv => 'تلفزيون';

  @override
  String get deviceModePhone => 'جوال';

  @override
  String get settingsLiteMode => 'الوضع الخفيف';

  @override
  String get settingsLiteModeHint =>
      'ذاكرة مؤقتة أصغر وصور أقل للأجهزة التي ذاكرتها 2 جيجابايت أو أقل.';

  @override
  String get settingsPlayer => 'المشغّل';

  @override
  String get settingsLiveEngine => 'مشغّل البث المباشر';

  @override
  String get settingsVodEngine => 'مشغّل الأفلام والمسلسلات';

  @override
  String get engineAuto => 'تلقائي';

  @override
  String get engineExo => 'ExoPlayer';

  @override
  String get engineMpv => 'mpv';

  @override
  String get settingsExoViewType => 'طريقة عرض ExoPlayer';

  @override
  String get viewTypeTexture => 'Texture';

  @override
  String get viewTypePlatform => 'Platform view';

  @override
  String get settingsHardwareDecoding => 'فك الترميز بالعتاد';

  @override
  String get settingsPreferredAudioLanguage => 'لغة الصوت المفضّلة';

  @override
  String get settingsGuide => 'دليل البرامج';

  @override
  String get settingsEpgUrls => 'روابط الدليل';

  @override
  String get settingsEpgOffset => 'فرق توقيت الدليل';

  @override
  String settingsEpgOffsetMinutes(int minutes) {
    return '$minutes دقيقة';
  }

  @override
  String get settingsRefresh => 'تحديث';

  @override
  String get settingsAddSource => 'إضافة مصدر';

  @override
  String get settingsEditSource => 'تعديل المصدر';

  @override
  String get settingsDeleteSource => 'حذف المصدر';

  @override
  String settingsDeleteSourceConfirm(String name) {
    return 'هل تريد حذف «⁨$name⁩»؟ ستُحذف قنواته ومفضلته وسجل المشاهدة من هذا الجهاز.';
  }

  @override
  String get settingsSetActive => 'تعيين كمصدر نشط';

  @override
  String get settingsActive => 'نشط';

  @override
  String settingsAccountExpires(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'ينتهي الاشتراك في $dateString';
  }

  @override
  String get settingsAccountNoExpiry => 'بدون تاريخ انتهاء';

  @override
  String get settingsExpiresSoon => 'اشتراكك سينتهي قريباً';

  @override
  String settingsExpiresInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'ينتهي خلال $days يوم',
      many: 'ينتهي خلال $days يوماً',
      few: 'ينتهي خلال $days أيام',
      two: 'ينتهي خلال يومين',
      one: 'ينتهي خلال يوم واحد',
      zero: 'ينتهي اليوم',
    );
    return '$_temp0';
  }

  @override
  String settingsLastUpdated(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'آخر تحديث $dateString';
  }

  @override
  String get settingsNoSources => 'لا توجد مصادر بعد.';

  @override
  String get settingsHelpLegal => 'المساعدة والمعلومات القانونية';

  @override
  String get settingsDiagnostics => 'التشخيص';

  @override
  String get settingsAbout => 'حول التطبيق';

  @override
  String settingsVersion(String version) {
    return 'الإصدار ⁦$version⁩';
  }

  @override
  String get settingsLicenses => 'تراخيص البرمجيات مفتوحة المصدر';

  @override
  String get settingsCheckForUpdates => 'التحقق من وجود تحديث';

  @override
  String get helpTitle => 'المساعدة والمعلومات القانونية';

  @override
  String get helpAsOf => 'حتى عام 2026';

  @override
  String get helpLegalBody =>
      'التطبيق مشغّل فقط وما فيه أي قنوات؛ أنت تضيف رابط M3U أو بيانات Xtream من مصدر يحق لك استخدامه. مصادر مجانية نظامية: قوائم iptv-org العامة (روابط تنشرها القنوات نفسها، وبعضها يتوقف أو يكون محجوب جغرافياً)، أو جهاز الاستقبال الفضائي حقك إذا يصدّر M3U. تطبيقات رسمية مجانية: «الأولى»، والباقة المجانية في «شاهد»، و«ثمانية». الاشتراكات المدفوعة النظامية (شاهد ⁦VIP⁩، ⁦TOD by beIN⁩، ⁦stc tv⁩، ⁦OSN+⁩) تشتغل من تطبيقاتها الرسمية فقط وما تعطيك رابط M3U أو Xtream. انتبه من «اشتراكات IPTV» الرخيصة اللي تُباع في الواتساب والتلقرام: غالباً غير مرخّصة، ونظام حقوق المؤلف الجديد (نافذ من أغسطس 2026) يشدّد العقوبات، وفيها خطر احتيال وبرمجيات ضارة.';

  @override
  String get helpWarningSignsTitle => 'علامات البائع غير المرخّص';

  @override
  String get helpWarningSigns =>
      '• آلاف القنوات المدفوعة مقابل اشتراك سنوي رخيص\n• البيع عن طريق الواتساب أو التلقرام أو إعلانات مواقع التواصل\n• كود Xtream أو رابط M3U بدل تطبيق رسمي\n• لا يوجد سجل تجاري ولا فاتورة ضريبية';

  @override
  String get helpNotLegalAdvice => 'هذه معلومات عامة وليست استشارة قانونية.';

  @override
  String get diagTitle => 'التشخيص';

  @override
  String get diagDevice => 'الجهاز';

  @override
  String get diagTvSignals => 'مؤشرات التلفزيون';

  @override
  String get diagAbis => 'المعماريات (ABIs)';

  @override
  String get diagMemory => 'الذاكرة';

  @override
  String diagRamMb(int mb) {
    return '$mb ميجابايت من الذاكرة';
  }

  @override
  String get diagDecoders => 'مفكّكات الترميز';

  @override
  String get diagSupported => 'مدعوم';

  @override
  String get diagNotSupported => 'غير مدعوم';

  @override
  String get diagEngineTest => 'اختبار المشغّل';

  @override
  String get diagRunTest => 'تشغيل الاختبار';

  @override
  String diagFirstFrameMs(int ms) {
    return 'أول إطار خلال $ms ملّي ثانية';
  }

  @override
  String get diagTestPassed => 'نجح';

  @override
  String get diagTestFailed => 'فشل';

  @override
  String get diagLog => 'آخر السجلات';

  @override
  String get diagCopyReport => 'نسخ التقرير';

  @override
  String get diagShowQr => 'عرض رمز QR';

  @override
  String get lanScanWithPhone => 'امسح الرمز بجوالك';

  @override
  String get lanSameNetwork =>
      'يجب أن يكون جوالك متصلاً بشبكة الواي فاي نفسها المتصل بها هذا الجهاز.';

  @override
  String lanOrOpen(String url) {
    return 'أو افتح ⁦$url⁩';
  }

  @override
  String get lanWaitingForInput => 'بانتظار الإدخال…';

  @override
  String get lanReceived => 'تم الاستلام';

  @override
  String get lanCodeExpired => 'انتهت صلاحية الرمز. ابدأ من جديد.';

  @override
  String get lanNoNetwork => 'لم يتم العثور على شبكة محلية.';

  @override
  String get favoritesEmpty =>
      'لا توجد مفضلة بعد. اضغط زر القائمة على أي قناة لإضافتها.';

  @override
  String searchNoResults(String query) {
    return 'لا توجد نتائج لـ «⁨$query⁩»';
  }

  @override
  String get searchChannels => 'القنوات';

  @override
  String get searchMovies => 'الأفلام';

  @override
  String get searchSeries => 'المسلسلات';

  @override
  String get errorExpiredNoDate => 'انتهى هذا الاشتراك.';

  @override
  String get sourcesEditorType => 'نوع المصدر';

  @override
  String get sourcesKeepPassword =>
      'اتركه فارغاً للاحتفاظ بكلمة المرور المحفوظة.';

  @override
  String get sourcesReenterUrl =>
      'بيانات الدخول المحفوظة مخفية. أدخل الرابط كاملاً مرة أخرى.';

  @override
  String get sourcesXtreamLinkTitle => 'هذا رابط Xtream Codes';

  @override
  String get sourcesXtreamLinkBody =>
      'احفظه كمصدر Xtream Codes لتحصل على تفاصيل الأفلام والمسلسلات، ودليل مختصر لكل قناة، ودليل البرامج من المزوّد.';

  @override
  String get sourcesXtreamLinkConvert => 'التحويل إلى Xtream Codes';

  @override
  String get sourcesXtreamLinkConverted =>
      'تم التحويل إلى Xtream Codes. راجع البيانات ثم اضغط «اختبار وحفظ».';

  @override
  String get sourcesUserAgentDefault => 'الافتراضي';

  @override
  String get sourcesReceivedFromPhone => 'تم الاستلام من جوالك.';

  @override
  String get sourcesNoFilePicker =>
      'لا يتوفر على هذا الجهاز مستعرض للملفات. استخدم «اكتب من جوالك» لإرسال ملف قائمة التشغيل.';

  @override
  String get sourcesImportSaving => 'جارٍ الحفظ…';

  @override
  String get sourcesImportCancelled => 'تم إلغاء الاستيراد.';

  @override
  String get sourcesNeverImported => 'لم يُستورد بعد';

  @override
  String get lanNewCode => 'رمز جديد';

  @override
  String get liveShowHiddenCategories => 'إظهار الفئات المخفية';

  @override
  String get liveMoreOptions => 'خيارات أخرى';

  @override
  String get liveRecentEmpty => 'ستظهر هنا القنوات التي تشاهدها.';

  @override
  String liveTimeRange(String start, String end) {
    return '⁨$start⁩ – ⁨$end⁩';
  }

  @override
  String liveNoChannelNumber(int number) {
    return 'لا توجد قناة برقم $number';
  }

  @override
  String get favoritesEmptyMovies => 'لا توجد أفلام مفضلة بعد.';

  @override
  String get favoritesEmptySeries => 'لا توجد مسلسلات مفضلة بعد.';

  @override
  String get player_playNow => 'شغّل الآن';

  @override
  String get player_pause => 'إيقاف مؤقت';

  @override
  String get player_options => 'الخيارات';

  @override
  String get player_noTracks => 'لا توجد مسارات متاحة';

  @override
  String get player_itemUnavailable => 'لا يمكن تشغيل هذا العنصر.';

  @override
  String player_noChannelNumber(int number) {
    return 'لا توجد قناة برقم $number';
  }

  @override
  String get player_favoriteAdded => 'أُضيفت إلى المفضلة';

  @override
  String get player_favoriteRemoved => 'أُزيلت من المفضلة';

  @override
  String player_episodeLabel(int season, int episode) {
    return 'الموسم $season · الحلقة $episode';
  }

  @override
  String get player_statsBuffer => 'التخزين المؤقت';

  @override
  String get player_statsReconnects => 'مرات إعادة الاتصال';

  @override
  String get player_statsVideoOutput => 'عرض الفيديو';

  @override
  String get player_statsFormat => 'صيغة البث';

  @override
  String get player_statsAudioCodec => 'ترميز الصوت';

  @override
  String get diagnostics_app => 'التطبيق';

  @override
  String get diagnostics_platform => 'النظام';

  @override
  String get diagnostics_model => 'الطراز';

  @override
  String get diagnostics_chipset => 'الشريحة';

  @override
  String get diagnostics_cpuCores => 'أنوية المعالج';

  @override
  String get diagnostics_lowRam => 'جهاز بذاكرة منخفضة';

  @override
  String get diagnostics_detectedTv => 'مُكتشَف كتلفزيون';

  @override
  String get diagnostics_touch => 'شاشة لمس';

  @override
  String get diagnostics_layout => 'التخطيط';

  @override
  String get diagnostics_testing => 'جارٍ الاختبار…';

  @override
  String get diagnostics_notRun => 'لم يُشغَّل بعد';

  @override
  String diagnostics_testStream(int n) {
    return 'بث الاختبار $n';
  }

  @override
  String get diagnostics_testStreamsNote =>
      'بثوث اختبار عامة من Apple و Mux. يشغّلها كل مشغّل واحداً تلو الآخر.';

  @override
  String get diagnostics_unknown => 'غير معروف';

  @override
  String get diagnostics_qrHint => 'امسح هذا الرمز بجوالك لمشاركة الملخص.';

  @override
  String get diagnostics_subtitleLanguage => 'لغة الترجمة المفضلة';

  @override
  String get diagnostics_maxConnections => 'الحد الأقصى للاتصالات';

  @override
  String get diagnostics_desktop => 'سطح المكتب';

  @override
  String get diagnostics_runAgain => 'إعادة الاختبار';

  @override
  String get vod_allMovies => 'كل الأفلام';

  @override
  String get vod_allSeries => 'كل المسلسلات';

  @override
  String get vod_noMovies => 'لا توجد أفلام هنا';

  @override
  String get vod_noSeries => 'لا توجد مسلسلات هنا';

  @override
  String get vod_detailsFailed => 'تعذّر تحميل المزيد من التفاصيل.';

  @override
  String vod_cast(String names) {
    return 'البطولة: ⁨$names⁩';
  }

  @override
  String vod_director(String name) {
    return 'الإخراج: ⁨$name⁩';
  }

  @override
  String vod_playEpisode(int season, int episode) {
    return 'تشغيل الموسم $season الحلقة $episode';
  }

  @override
  String vod_resumeEpisode(int season, int episode) {
    return 'استكمال الموسم $season الحلقة $episode';
  }

  @override
  String get vod_pageLoadFailed =>
      'تعذّر تحميل بعض العناوين. ستُعاد المحاولة بعد قليل.';

  @override
  String settings_liteAuto(String state) {
    return 'تلقائي ($state)';
  }

  @override
  String get settings_preferredSubtitleLanguage => 'لغة الترجمة المفضّلة';

  @override
  String get settings_defaultAspect => 'نسبة العرض الافتراضية';

  @override
  String get settings_langArabic => 'العربية';

  @override
  String get settings_langEnglish => 'الإنجليزية';

  @override
  String get settings_langFrench => 'الفرنسية';

  @override
  String get settings_langTurkish => 'التركية';

  @override
  String settings_guideFor(String name) {
    return 'للمصدر ⁨$name⁩';
  }

  @override
  String get settings_epgNoUrls =>
      'لا توجد روابط دليل بعد. حدّث المصدر أو أضف رابطاً.';

  @override
  String get settings_addEpgUrl => 'إضافة رابط دليل';

  @override
  String get settings_epgUrlHint => 'http://example.com/guide.xml.gz';

  @override
  String get settings_epgUrlExists => 'رابط الدليل هذا موجود في القائمة.';

  @override
  String get settings_deleteEpgUrl => 'حذف رابط الدليل';

  @override
  String get settings_deleteEpgUrlBody => 'ستُحذف برامجه من هذا الجهاز.';

  @override
  String get settings_epgOriginXtream => 'من المزوّد';

  @override
  String get settings_epgOriginPlaylist => 'من قائمة التشغيل';

  @override
  String get settings_epgOriginManual => 'أضفته أنت';

  @override
  String get settings_epgStatusNever => 'لم يُحمَّل بعد';

  @override
  String get settings_epgStatusOk => 'تم التحميل';

  @override
  String get settings_epgStatusNotModified => 'محدَّث';

  @override
  String get settings_epgStatusFailed => 'فشل التحميل';

  @override
  String get settings_epgStatusCancelled => 'أُلغي';

  @override
  String settings_programmeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count برنامج',
      many: '$count برنامجاً',
      few: '$count برامج',
      two: 'برنامجان',
      one: 'برنامج واحد',
      zero: 'لا توجد برامج',
    );
    return '$_temp0';
  }

  @override
  String settings_epgLastImport(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName)
        .add_Hm();
    final String dateString = dateDateFormat.format(date);

    return 'آخر تنزيل $dateString';
  }

  @override
  String get settings_epgOffsetHint =>
      'يقدّم أو يؤخّر أوقات دليل هذا المصدر. استخدمه إذا ظهرت البرامج في وقت غير صحيح.';

  @override
  String get settings_epgOffsetNone => 'بدون فرق';

  @override
  String get settings_epgOffsetEarlier => 'تقديم نصف ساعة';

  @override
  String get settings_epgOffsetLater => 'تأخير نصف ساعة';

  @override
  String get settings_epgRefreshNow => 'تنزيل الدليل من جديد الآن';

  @override
  String get settings_epgRefreshInterval => 'فترة تحديث الدليل';

  @override
  String settings_everyHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'كل $hours ساعة',
      many: 'كل $hours ساعة',
      few: 'كل $hours ساعات',
      two: 'كل ساعتين',
      one: 'كل ساعة',
      zero: 'كل $hours ساعة',
    );
    return '$_temp0';
  }

  @override
  String get settings_saveFailed => 'تعذّر حفظ التغيير.';

  @override
  String get help_playerOnlyTitle => 'التطبيق مشغّل فقط';

  @override
  String get help_playerOnlyBody =>
      'لا يحتوي التطبيق على أي قنوات أو قوائم تشغيل أو روابط مزوّدين. يشغّل فقط روابط M3U وبيانات دخول Xtream التي تضيفها بنفسك من مصدر يحق لك استخدامه.';

  @override
  String get help_freeSourcesTitle => 'مصادر مجانية نظامية';

  @override
  String get help_freeSourcesBody =>
      'مشروع iptv-org ينشر قوائم عامة بروابط تتيحها القنوات نفسها، مثل العربية والجزيرة وسكاي نيوز عربية وفرانس 24 ودويتشه فيله وبي بي سي عربي. بعض الروابط يتوقف أو يكون محجوباً جغرافياً، والرابط العام لا يعني دائماً أن استخدامه في تطبيقات أخرى مسموح، فالأفضل اختيار القنوات المستضافة على مواقع القنوات نفسها. التطبيق لا يضيف هذه القوائم من تلقاء نفسه: اكتب الرابط بنفسك عند إضافة مصدر.';

  @override
  String get help_iptvOrgSaudi => 'القنوات السعودية';

  @override
  String get help_iptvOrgArabic => 'القنوات الناطقة بالعربية';

  @override
  String get help_addAsSource => 'إضافة كمصدر';

  @override
  String get help_receiverBody =>
      'يمكن لجهاز الاستقبال الفضائي الخاص بك (مثل ⁦Enigma2⁩ مع ⁦OpenWebif⁩ أو ⁦Tvheadend⁩ أو موالف ⁦SAT>IP⁩) تصدير M3U و XMLTV للقنوات المجانية التي تستقبلها أصلاً، وهي أنظف طريقة نظامية للحصول على قائمة تشغيل مع دليل برامج.';

  @override
  String get help_officialAppsTitle => 'التطبيقات الرسمية';

  @override
  String get help_officialAppsBody =>
      'المجانية: «الأولى» (القنوات السعودية)، والباقة المجانية في «شاهد»، و«ثمانية»، و⁦Samsung TV Plus⁩. المدفوعة: شاهد ⁦VIP⁩، و⁦TOD by beIN⁩، و⁦stc tv⁩، و⁦OSN+⁩. هذه الخدمات تعمل من تطبيقاتها الرسمية فقط ولا تعطيك رابط M3U أو بيانات Xtream، لذلك لا يمكن إضافتها هنا. ولا توجد خدمة سعودية مرخّصة تبيع القنوات المدفوعة بصيغة M3U أو Xtream.';

  @override
  String get help_warningSignsMore =>
      '• تجربة مجانية لمدة 24 ساعة\n• الدفع بتحويل لشخص أو ببطاقات هدايا أو عملات رقمية\n• يشترط لتشغيل القنوات تثبيت تطبيقه الخاص أو نسخة معدّلة من تطبيق معروف، أو استخدام ⁦VPN⁩';

  @override
  String get help_legitServices =>
      'الخدمات النظامية تقدّمها قنوات أو شركات اتصالات معروفة، ولها تطبيقات رسمية في المتاجر وفواتير ضريبية ووسائل دفع رسمية.';

  @override
  String get help_updatesTitle => 'طريقة تثبيت التحديثات';

  @override
  String get help_updatesBody =>
      'هذا التطبيق مجاني ولا يُنشر إلا في صفحة الإصدارات الخاصة بالمشروع، ولا يُباع أبداً، فلا تأخذه من أي بائع. نزّل أحدث إصدار من هناك وثبّته فوق النسخة الحالية، وتبقى مصادرك ومفضلتك وسجل المشاهدة كما هي. على أندرويد TV أو ⁦Fire TV⁩ اكتب هذا الرابط في تطبيق ⁦Downloader⁩. على ويندوز أغلق التطبيق وفك ضغط ملف zip الجديد في المجلد نفسه.';

  @override
  String get help_downloadLink => 'رابط التنزيل';

  @override
  String get guideRefreshFailed => 'تعذّر تحديث الدليل';

  @override
  String guideMinutesLeft(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'تبقّت $minutes دقيقة',
      many: 'تبقّت $minutes دقيقة',
      few: 'تبقّت $minutes دقائق',
      two: 'تبقّت دقيقتان',
      one: 'تبقّت دقيقة واحدة',
      zero: 'ينتهي الآن',
    );
    return '$_temp0';
  }

  @override
  String get guideWatchChannel => 'مشاهدة القناة';
}
