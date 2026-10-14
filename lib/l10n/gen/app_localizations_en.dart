// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'IPTV Player';

  @override
  String get commonOk => 'OK';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonBack => 'Back';

  @override
  String get commonClose => 'Close';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonAdd => 'Add';

  @override
  String get commonNext => 'Next';

  @override
  String get commonDone => 'Done';

  @override
  String get commonYes => 'Yes';

  @override
  String get commonNo => 'No';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get commonEmpty => 'Nothing here yet';

  @override
  String get commonErrorGeneric => 'Something went wrong';

  @override
  String get commonUnavailable => 'Unavailable';

  @override
  String get commonCopied => 'Copied';

  @override
  String get commonOn => 'On';

  @override
  String get commonOff => 'Off';

  @override
  String get commonSearchHint => 'Search channels, movies and series';

  @override
  String get commonPressBackAgainToExit => 'Press back again to exit';

  @override
  String get onboardingWelcomeTitle => 'Welcome';

  @override
  String get onboardingWelcomeBody =>
      'Watch your own IPTV sources on your TV, phone and PC.';

  @override
  String get onboardingChooseLanguage => 'Choose language';

  @override
  String get onboardingDisclaimer =>
      'The app is a player only and provides no content.';

  @override
  String get onboardingLearnMore => 'Learn more';

  @override
  String get onboardingGetStarted => 'Get started';

  @override
  String get onboardingAddSourceTitle => 'Add a source';

  @override
  String get onboardingAddSourceBody =>
      'Add an M3U link, an M3U file or an Xtream Codes login from a provider you have the right to use.';

  @override
  String get onboardingSkip => 'Skip for now';

  @override
  String get sourceTypeM3uUrl => 'M3U link';

  @override
  String get sourceTypeM3uUrlHint =>
      'A playlist URL, usually ending in .m3u or .m3u8';

  @override
  String get sourceTypeM3uFile => 'M3U file';

  @override
  String get sourceTypeM3uFileHint => 'A playlist file saved on this device';

  @override
  String get sourceTypeXtream => 'Xtream Codes';

  @override
  String get sourceTypeXtreamHint => 'Server address, username and password';

  @override
  String get fieldName => 'Name';

  @override
  String get fieldNameHint => 'e.g. Home';

  @override
  String get fieldServer => 'Server';

  @override
  String get fieldServerHint => 'http://example.com:8080';

  @override
  String get fieldUsername => 'Username';

  @override
  String get fieldPassword => 'Password';

  @override
  String get fieldShowPassword => 'Show password';

  @override
  String get fieldHidePassword => 'Hide password';

  @override
  String get fieldPlaylistUrl => 'Playlist URL';

  @override
  String get fieldPlaylistUrlHint => 'http://example.com/playlist.m3u';

  @override
  String get fieldFile => 'File';

  @override
  String get fieldChooseFile => 'Choose file';

  @override
  String get fieldNoFileChosen => 'No file chosen';

  @override
  String get fieldUserAgent => 'User agent';

  @override
  String get fieldUserAgentCustom => 'Custom';

  @override
  String get fieldReferer => 'Referer';

  @override
  String get fieldEpgUrl => 'EPG URL';

  @override
  String get fieldEpgUrlHint => 'XMLTV guide link (optional)';

  @override
  String get fieldLiveFormat => 'Live format';

  @override
  String get liveFormatTs => 'MPEG-TS (.ts)';

  @override
  String get liveFormatHls => 'HLS (.m3u8)';

  @override
  String get fieldAdvancedOptions => 'Advanced options';

  @override
  String get fieldRequired => 'This field is required';

  @override
  String get fieldOptional => 'Optional';

  @override
  String get typeOnYourPhone => 'Type on your phone';

  @override
  String get testAndSave => 'Test & save';

  @override
  String get validating => 'Validating…';

  @override
  String get errorInvalidUrl =>
      'Invalid URL. It must start with http:// or https://.';

  @override
  String get errorUnreachable =>
      'Can\'t reach the server. Check the address and your internet connection.';

  @override
  String get errorTimeout =>
      'The server took too long to respond. Try again later.';

  @override
  String get errorAuthFailed => 'Wrong username or password.';

  @override
  String errorExpired(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'This subscription expired on $dateString.';
  }

  @override
  String get errorBanned => 'This account has been banned by the provider.';

  @override
  String get errorDisabled => 'This account is disabled.';

  @override
  String get errorNotM3u => 'This doesn\'t look like an M3U playlist.';

  @override
  String get errorFileRead => 'Couldn\'t read the file.';

  @override
  String errorHttpStatus(int code) {
    return 'The server returned error $code.';
  }

  @override
  String get importTitle => 'Importing your source';

  @override
  String importLiveCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count live channels',
      one: '1 live channel',
      zero: 'No live channels',
    );
    return '$_temp0';
  }

  @override
  String importMoviesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count movies',
      one: '1 movie',
      zero: 'No movies',
    );
    return '$_temp0';
  }

  @override
  String importSeriesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count series',
      one: '1 series',
      zero: 'No series',
    );
    return '$_temp0';
  }

  @override
  String get importGuide => 'Loading the TV guide…';

  @override
  String get importCancel => 'Cancel import';

  @override
  String get importDone => 'Import complete';

  @override
  String get importFailed => 'Import failed';

  @override
  String get navLive => 'Live';

  @override
  String get navGuide => 'Guide';

  @override
  String get navMovies => 'Movies';

  @override
  String get navSeries => 'Series';

  @override
  String get navSearch => 'Search';

  @override
  String get navFavorites => 'Favorites';

  @override
  String get navSettings => 'Settings';

  @override
  String get navSources => 'Sources';

  @override
  String get navMore => 'More';

  @override
  String get navSwitchSource => 'Switch source';

  @override
  String get liveAllChannels => 'All channels';

  @override
  String get liveFavorites => 'Favorites';

  @override
  String get liveRecent => 'Recent';

  @override
  String get liveCategories => 'Categories';

  @override
  String get liveNoProgrammeInfo => 'No programme info';

  @override
  String get liveNow => 'Now';

  @override
  String get liveNext => 'Next';

  @override
  String liveNowTitle(String title) {
    return 'Now: ⁨$title⁩';
  }

  @override
  String liveNextTitle(String title) {
    return 'Next: ⁨$title⁩';
  }

  @override
  String liveChannelCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count channels',
      one: '1 channel',
      zero: 'No channels',
    );
    return '$_temp0';
  }

  @override
  String get liveNoChannels => 'No channels in this category';

  @override
  String get liveAddFavorite => 'Add to favorites';

  @override
  String get liveRemoveFavorite => 'Remove from favorites';

  @override
  String get liveHideCategory => 'Hide category';

  @override
  String get liveAssignGuideChannel => 'Assign guide channel';

  @override
  String get livePlayWithOtherPlayer => 'Play with the other player';

  @override
  String liveChannelNumber(int number) {
    return 'Channel $number';
  }

  @override
  String get guideToday => 'Today';

  @override
  String get guideTomorrow => 'Tomorrow';

  @override
  String get guideNow => 'Now';

  @override
  String get guideRefresh => 'Refresh guide';

  @override
  String get guideUpdating => 'Updating the guide…';

  @override
  String get guideEmpty => 'No guide data yet. Add an EPG URL in Settings.';

  @override
  String guideUpdated(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Guide updated $dateString';
  }

  @override
  String get vodContinueWatching => 'Continue watching';

  @override
  String get vodPlay => 'Play';

  @override
  String vodResumeFrom(String time) {
    return 'Resume from $time';
  }

  @override
  String get vodStartOver => 'Start over';

  @override
  String get vodSeasons => 'Seasons';

  @override
  String get vodEpisodes => 'Episodes';

  @override
  String vodSeasonN(int n) {
    return 'Season $n';
  }

  @override
  String vodEpisodeN(int n) {
    return 'Episode $n';
  }

  @override
  String vodEpisodeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes',
      one: '1 episode',
      zero: 'No episodes',
    );
    return '$_temp0';
  }

  @override
  String vodNextEpisodeIn(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'Next episode in $seconds seconds',
      one: 'Next episode in 1 second',
    );
    return '$_temp0';
  }

  @override
  String get vodNextEpisode => 'Next episode';

  @override
  String vodMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get vodNoEpisodes => 'No episodes available';

  @override
  String get vodWatched => 'Watched';

  @override
  String get vodAddFavorite => 'Add to favorites';

  @override
  String get vodRemoveFavorite => 'Remove from favorites';

  @override
  String get playerAudio => 'Audio';

  @override
  String get playerSubtitles => 'Subtitles';

  @override
  String get playerOff => 'Off';

  @override
  String get playerAspectRatio => 'Aspect ratio';

  @override
  String get aspectFit => 'Fit';

  @override
  String get aspectFill => 'Fill';

  @override
  String get aspectStretch => 'Stretch';

  @override
  String get aspect16x9 => '16:9';

  @override
  String get aspect4x3 => '4:3';

  @override
  String get playerSwitchPlayer => 'Switch player';

  @override
  String get playerStats => 'Stats';

  @override
  String get playerFavorite => 'Favorite';

  @override
  String get playerGuide => 'Guide';

  @override
  String get playerLive => 'LIVE';

  @override
  String get playerBuffering => 'Buffering…';

  @override
  String playerReconnecting(int n, int max) {
    return 'Reconnecting… ($n/$max)';
  }

  @override
  String get playerPlaybackFailed => 'Playback failed';

  @override
  String get playerRetry => 'Retry';

  @override
  String get playerTryOtherFormat => 'Try other format';

  @override
  String get playerCopyReport => 'Copy report';

  @override
  String get playerSubtitlesNeedMpv => 'Subtitles need the mpv player.';

  @override
  String playerTrackN(int n) {
    return 'Track $n';
  }

  @override
  String get statsEngine => 'Engine';

  @override
  String get statsCodec => 'Codec';

  @override
  String get statsResolution => 'Resolution';

  @override
  String get statsFirstFrame => 'Time to first frame';

  @override
  String get statsDroppedFrames => 'Dropped frames';

  @override
  String get settingsGeneral => 'General';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get languageAuto => 'Auto (system)';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageEnglish => 'English';

  @override
  String get settingsDeviceMode => 'Device mode';

  @override
  String get deviceModeAuto => 'Auto';

  @override
  String get deviceModeTv => 'TV';

  @override
  String get deviceModePhone => 'Phone';

  @override
  String get settingsLiteMode => 'Lite mode';

  @override
  String get settingsLiteModeHint =>
      'Smaller buffers and fewer images for devices with 2 GB of RAM or less.';

  @override
  String get settingsPlayer => 'Player';

  @override
  String get settingsLiveEngine => 'Live engine';

  @override
  String get settingsVodEngine => 'VOD engine';

  @override
  String get engineAuto => 'Auto';

  @override
  String get engineExo => 'ExoPlayer';

  @override
  String get engineMpv => 'mpv';

  @override
  String get settingsExoViewType => 'ExoPlayer view';

  @override
  String get viewTypeTexture => 'Texture';

  @override
  String get viewTypePlatform => 'Platform view';

  @override
  String get settingsHardwareDecoding => 'Hardware decoding';

  @override
  String get settingsPreferredAudioLanguage => 'Preferred audio language';

  @override
  String get settingsGuide => 'TV guide';

  @override
  String get settingsEpgUrls => 'Guide URLs';

  @override
  String get settingsEpgOffset => 'EPG offset';

  @override
  String settingsEpgOffsetMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get settingsRefresh => 'Refresh';

  @override
  String get settingsAddSource => 'Add source';

  @override
  String get settingsEditSource => 'Edit source';

  @override
  String get settingsDeleteSource => 'Delete source';

  @override
  String settingsDeleteSourceConfirm(String name) {
    return 'Delete “⁨$name⁩”? Its channels, favorites and watch progress will be removed from this device.';
  }

  @override
  String get settingsSetActive => 'Set active';

  @override
  String get settingsActive => 'Active';

  @override
  String settingsAccountExpires(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Account expires $dateString';
  }

  @override
  String get settingsAccountNoExpiry => 'No expiry date';

  @override
  String get settingsExpiresSoon => 'Your subscription expires soon';

  @override
  String settingsExpiresInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Expires in $days days',
      one: 'Expires in 1 day',
      zero: 'Expires today',
    );
    return '$_temp0';
  }

  @override
  String settingsLastUpdated(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Last updated $dateString';
  }

  @override
  String get settingsNoSources => 'No sources yet.';

  @override
  String get settingsHelpLegal => 'Help & legal';

  @override
  String get settingsDiagnostics => 'Diagnostics';

  @override
  String get settingsAbout => 'About';

  @override
  String settingsVersion(String version) {
    return 'Version $version';
  }

  @override
  String get settingsLicenses => 'Open-source licences';

  @override
  String get settingsCheckForUpdates => 'Check for updates';

  @override
  String get helpTitle => 'Help & legal';

  @override
  String get helpAsOf => 'As of 2026';

  @override
  String get helpLegalBody =>
      'The app is only a player and contains no channels. You add an M3U link or an Xtream login from a source you have the right to use. Free legal sources: the public iptv-org playlists (links published by the broadcasters themselves; some stop working or are geo-blocked), or your own satellite receiver if it can export M3U. Free official apps: Aloula, Shahid\'s free tier and Thmanyah. Legal paid subscriptions (Shahid VIP, TOD by beIN, stc tv, OSN+) work only in their official apps and don\'t give you an M3U link or Xtream login. Beware of cheap “IPTV subscriptions” sold on WhatsApp and Telegram: they are usually unlicensed, the new Saudi Copyright Law (in force since August 2026) raises the penalties, and they carry a real risk of fraud and malware.';

  @override
  String get helpWarningSignsTitle => 'Signs of an unlicensed seller';

  @override
  String get helpWarningSigns =>
      '• Thousands of premium channels for a small yearly fee\n• Sold through WhatsApp, Telegram or social media ads\n• An Xtream code or M3U link instead of an official app\n• No commercial registration and no VAT invoice';

  @override
  String get helpNotLegalAdvice =>
      'This is general information, not legal advice.';

  @override
  String get diagTitle => 'Diagnostics';

  @override
  String get diagDevice => 'Device';

  @override
  String get diagTvSignals => 'TV signals';

  @override
  String get diagAbis => 'ABIs';

  @override
  String get diagMemory => 'Memory';

  @override
  String diagRamMb(int mb) {
    return '$mb MB RAM';
  }

  @override
  String get diagDecoders => 'Decoders';

  @override
  String get diagSupported => 'Supported';

  @override
  String get diagNotSupported => 'Not supported';

  @override
  String get diagEngineTest => 'Engine test';

  @override
  String get diagRunTest => 'Run test';

  @override
  String diagFirstFrameMs(int ms) {
    return 'First frame in $ms ms';
  }

  @override
  String get diagTestPassed => 'Passed';

  @override
  String get diagTestFailed => 'Failed';

  @override
  String get diagLog => 'Recent log';

  @override
  String get diagCopyReport => 'Copy report';

  @override
  String get diagShowQr => 'Show QR';

  @override
  String get lanScanWithPhone => 'Scan with your phone';

  @override
  String get lanSameNetwork =>
      'Your phone must be on the same Wi-Fi network as this device.';

  @override
  String lanOrOpen(String url) {
    return 'Or open $url';
  }

  @override
  String get lanWaitingForInput => 'Waiting for input…';

  @override
  String get lanReceived => 'Received';

  @override
  String get lanCodeExpired => 'The code has expired. Start again.';

  @override
  String get lanNoNetwork => 'No local network found.';

  @override
  String get favoritesEmpty =>
      'No favorites yet. Press Menu on a channel to add it.';

  @override
  String searchNoResults(String query) {
    return 'No results for “⁨$query⁩”';
  }

  @override
  String get searchChannels => 'Channels';

  @override
  String get searchMovies => 'Movies';

  @override
  String get searchSeries => 'Series';
}
