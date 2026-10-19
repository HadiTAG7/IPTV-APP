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
  String get errorCatalogIncomplete =>
      'Some lists came back empty, so the previous ones were kept. Try again later.';

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
  String get playerFullscreen => 'Full screen';

  @override
  String get playerExitFullscreen => 'Exit full screen';

  @override
  String get playerFavorite => 'Favorite';

  @override
  String get playerGuide => 'Guide';

  @override
  String get playerChannels => 'Channels';

  @override
  String get playerDetach => 'Separate window';

  @override
  String get playerDetachFailed => 'Couldn\'t open the separate window.';

  @override
  String detachInUseTitle(String channel) {
    return '“⁨$channel⁩” is playing in a separate window';
  }

  @override
  String get detachInUseMessage =>
      'Your subscription can\'t play another channel at the same time.';

  @override
  String get detachPlayInWindow => 'Play this channel in the window instead';

  @override
  String get detachCloseWindow => 'Close the window and play here';

  @override
  String get detachPlayInWindowFailed =>
      'Couldn\'t play in the separate window.';

  @override
  String get viewerMute => 'Mute';

  @override
  String get viewerUnmute => 'Unmute';

  @override
  String get viewerVolume => 'Volume';

  @override
  String get viewerPin => 'Keep on top';

  @override
  String get viewerUnpin => 'Stop keeping on top';

  @override
  String get viewerCompact => 'Small window';

  @override
  String get viewerNormalSize => 'Normal size';

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
      'No favorites yet. Choose “Add to favorites” in a channel\'s options.';

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

  @override
  String get errorExpiredNoDate => 'This subscription has expired.';

  @override
  String get sourcesEditorType => 'Source type';

  @override
  String get sourcesKeepPassword => 'Leave empty to keep the saved password.';

  @override
  String get sourcesReenterUrl =>
      'Saved credentials are hidden. Enter the full link again.';

  @override
  String get sourcesXtreamLinkTitle => 'This is an Xtream Codes link';

  @override
  String get sourcesXtreamLinkBody =>
      'Save it as an Xtream Codes source to get movie and series details, a short guide for each channel and the provider\'s TV guide.';

  @override
  String get sourcesXtreamLinkConvert => 'Use Xtream Codes';

  @override
  String get sourcesXtreamLinkConverted =>
      'Switched to Xtream Codes. Check the details, then press Test & save.';

  @override
  String get sourcesUserAgentDefault => 'Default';

  @override
  String get sourcesReceivedFromPhone => 'Received from your phone.';

  @override
  String get sourcesNoFilePicker =>
      'This device has no file picker. Use Type on your phone to send the playlist file.';

  @override
  String get sourcesImportSaving => 'Saving…';

  @override
  String get sourcesImportCancelled => 'Import cancelled.';

  @override
  String get sourcesNeverImported => 'Not imported yet';

  @override
  String get lanNewCode => 'New code';

  @override
  String get liveShowHiddenCategories => 'Show hidden categories';

  @override
  String get liveMoreOptions => 'More options';

  @override
  String get liveRecentEmpty => 'Channels you watch will appear here.';

  @override
  String get liveAddToList => 'Add to list…';

  @override
  String get liveAddToListTitle => 'Add to list';

  @override
  String get liveNewList => 'New list…';

  @override
  String get liveNewListTitle => 'New list';

  @override
  String get liveListName => 'List name';

  @override
  String get liveListNameHint => 'e.g. Sports';

  @override
  String get liveListCreate => 'Create';

  @override
  String get liveListNameEmpty => 'Enter a name for the list.';

  @override
  String get liveListNameTaken => 'You already have a list with this name.';

  @override
  String liveListAdded(String name) {
    return 'Added to “⁨$name⁩”';
  }

  @override
  String liveListRemoved(String name) {
    return 'Removed from “⁨$name⁩”';
  }

  @override
  String get liveListEmpty =>
      'This list is empty. Choose “Add to list…” in a channel\'s options.';

  @override
  String get liveRenameList => 'Rename list';

  @override
  String get liveDeleteList => 'Delete list';

  @override
  String liveDeleteListConfirm(String name) {
    return 'Delete the list “⁨$name⁩”? Only the list is deleted; its channels stay in the source.';
  }

  @override
  String get liveMoveUp => 'Move up';

  @override
  String get liveMoveDown => 'Move down';

  @override
  String liveRemoveFromList(String name) {
    return 'Remove from “⁨$name⁩”';
  }

  @override
  String liveTimeRange(String start, String end) {
    return '⁨$start⁩ – ⁨$end⁩';
  }

  @override
  String liveNoChannelNumber(int number) {
    return 'No channel $number';
  }

  @override
  String get favoritesEmptyMovies => 'No favorite movies yet.';

  @override
  String get favoritesEmptySeries => 'No favorite series yet.';

  @override
  String get player_playNow => 'Play now';

  @override
  String get player_pause => 'Pause';

  @override
  String get player_options => 'Options';

  @override
  String get player_noTracks => 'No tracks available';

  @override
  String get player_itemUnavailable => 'This item can\'t be played.';

  @override
  String player_noChannelNumber(int number) {
    return 'No channel $number';
  }

  @override
  String get player_favoriteAdded => 'Added to favorites';

  @override
  String get player_favoriteRemoved => 'Removed from favorites';

  @override
  String player_episodeLabel(int season, int episode) {
    return 'Season $season · Episode $episode';
  }

  @override
  String get player_statsBuffer => 'Buffer';

  @override
  String get player_statsReconnects => 'Reconnects';

  @override
  String get player_statsVideoOutput => 'Video output';

  @override
  String get player_statsFormat => 'Stream format';

  @override
  String get player_statsAudioCodec => 'Audio codec';

  @override
  String get diagnostics_app => 'App';

  @override
  String get diagnostics_platform => 'Platform';

  @override
  String get diagnostics_model => 'Model';

  @override
  String get diagnostics_chipset => 'Chipset';

  @override
  String get diagnostics_cpuCores => 'CPU cores';

  @override
  String get diagnostics_lowRam => 'Low-RAM device';

  @override
  String get diagnostics_detectedTv => 'Detected as TV';

  @override
  String get diagnostics_touch => 'Touchscreen';

  @override
  String get diagnostics_layout => 'Layout';

  @override
  String get diagnostics_testing => 'Testing…';

  @override
  String get diagnostics_notRun => 'Not run yet';

  @override
  String diagnostics_testStream(int n) {
    return 'Test stream $n';
  }

  @override
  String get diagnostics_testStreamsNote =>
      'Public test streams from Apple and Mux. Each engine plays them one after the other.';

  @override
  String get diagnostics_unknown => 'Unknown';

  @override
  String get diagnostics_qrHint =>
      'Scan this code with your phone to share the summary.';

  @override
  String get diagnostics_subtitleLanguage => 'Preferred subtitle language';

  @override
  String get diagnostics_maxConnections => 'Max connections';

  @override
  String get diagnostics_desktop => 'Desktop';

  @override
  String get diagnostics_runAgain => 'Run again';

  @override
  String get vod_allMovies => 'All movies';

  @override
  String get vod_allSeries => 'All series';

  @override
  String get vod_noMovies => 'No movies here';

  @override
  String get vod_noSeries => 'No series here';

  @override
  String get vod_detailsFailed => 'Couldn\'t load more details.';

  @override
  String vod_cast(String names) {
    return 'Cast: ⁨$names⁩';
  }

  @override
  String vod_director(String name) {
    return 'Director: ⁨$name⁩';
  }

  @override
  String vod_playEpisode(int season, int episode) {
    return 'Play S$season E$episode';
  }

  @override
  String vod_resumeEpisode(int season, int episode) {
    return 'Resume S$season E$episode';
  }

  @override
  String get vod_pageLoadFailed =>
      'Some titles couldn\'t be loaded. Trying again shortly.';

  @override
  String settings_liteAuto(String state) {
    return 'Auto ($state)';
  }

  @override
  String get settings_preferredSubtitleLanguage =>
      'Preferred subtitle language';

  @override
  String get settings_defaultAspect => 'Default aspect ratio';

  @override
  String get settings_langArabic => 'Arabic';

  @override
  String get settings_langEnglish => 'English';

  @override
  String get settings_langFrench => 'French';

  @override
  String get settings_langTurkish => 'Turkish';

  @override
  String settings_guideFor(String name) {
    return 'For ⁨$name⁩';
  }

  @override
  String get settings_epgNoUrls =>
      'No guide URLs yet. Sync the source or add one.';

  @override
  String get settings_addEpgUrl => 'Add guide URL';

  @override
  String get settings_epgUrlHint => 'http://example.com/guide.xml.gz';

  @override
  String get settings_epgUrlExists => 'This guide URL is already in the list.';

  @override
  String get settings_deleteEpgUrl => 'Delete guide URL';

  @override
  String get settings_deleteEpgUrlBody =>
      'Its programmes will be removed from this device.';

  @override
  String get settings_epgOriginXtream => 'From the provider';

  @override
  String get settings_epgOriginPlaylist => 'From the playlist';

  @override
  String get settings_epgOriginManual => 'Added by you';

  @override
  String get settings_epgStatusNever => 'Not loaded yet';

  @override
  String get settings_epgStatusOk => 'Loaded';

  @override
  String get settings_epgStatusNotModified => 'Up to date';

  @override
  String get settings_epgStatusFailed => 'Failed';

  @override
  String get settings_epgStatusCancelled => 'Cancelled';

  @override
  String settings_programmeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count programmes',
      one: '1 programme',
      zero: 'No programmes',
    );
    return '$_temp0';
  }

  @override
  String settings_epgLastImport(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName)
        .add_Hm();
    final String dateString = dateDateFormat.format(date);

    return 'Imported $dateString';
  }

  @override
  String get settings_epgOffsetHint =>
      'Moves this source\'s guide times. Use it when programmes show at the wrong time.';

  @override
  String get settings_epgOffsetNone => 'No offset';

  @override
  String get settings_epgOffsetEarlier => '30 minutes earlier';

  @override
  String get settings_epgOffsetLater => '30 minutes later';

  @override
  String get settings_epgRefreshNow => 'Download the guide again now';

  @override
  String get settings_epgRefreshInterval => 'Guide refresh interval';

  @override
  String settings_everyHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'Every $hours hours',
      one: 'Every hour',
    );
    return '$_temp0';
  }

  @override
  String get settings_saveFailed => 'Couldn\'t save the change.';

  @override
  String get help_playerOnlyTitle => 'The app is a player only';

  @override
  String get help_playerOnlyBody =>
      'IPTV Player contains no channels, playlists or provider links. It plays only the M3U links and Xtream logins you add yourself, from sources you have the right to use.';

  @override
  String get help_freeSourcesTitle => 'Free legal sources';

  @override
  String get help_freeSourcesBody =>
      'The iptv-org project lists public links that broadcasters such as Al Arabiya, Al Jazeera, Sky News Arabia, France 24, DW and BBC Arabic publish themselves. Some links stop working or are geo-blocked, and a public link is not always cleared for use in other apps, so prefer channels hosted on the broadcasters\' own sites. The app never adds these lists for you: type a link when you add a source.';

  @override
  String get help_iptvOrgSaudi => 'Saudi channels';

  @override
  String get help_iptvOrgArabic => 'Arabic-language channels';

  @override
  String get help_addAsSource => 'Add as source';

  @override
  String get help_receiverBody =>
      'Your own satellite receiver (for example Enigma2 with OpenWebif, Tvheadend or a SAT>IP tuner) can export M3U and XMLTV for the free-to-air channels you already receive. It is the cleanest legal way to get a playlist with a guide.';

  @override
  String get help_officialAppsTitle => 'Official apps';

  @override
  String get help_officialAppsBody =>
      'Free: Aloula (the Saudi channels), Shahid\'s free tier, Thmanyah and Samsung TV Plus. Paid: Shahid VIP, TOD by beIN, stc tv and OSN+. These services work only in their own apps and don\'t give M3U links or Xtream logins, so they can\'t be added here. No licensed Saudi service sells premium channels as M3U or Xtream.';

  @override
  String get help_warningSignsMore =>
      '• Free 24-hour trials\n• Payment by transfer to a person, gift cards or crypto\n• Asks you to install the seller\'s own app or a modified copy of a known app, or to use a VPN, to get the channels';

  @override
  String get help_legitServices =>
      'Legitimate services are known broadcasters or telecom companies, with official store apps, VAT invoices and official payment methods.';

  @override
  String get help_updatesTitle => 'How to install updates';

  @override
  String get help_updatesBody =>
      'This app is free and is published only on its project\'s releases page; it is never sold, so don\'t get it from a seller. Download the latest version from there and install it over the current one; your sources, favorites and watch progress stay. On Android TV or Fire TV, type this link into the Downloader app. On Windows, close the app and extract the new zip into the same folder.';

  @override
  String get help_downloadLink => 'Download link';

  @override
  String get guideRefreshFailed => 'Couldn\'t update the guide';

  @override
  String guideMinutesLeft(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes min left',
      one: '1 min left',
      zero: 'Ending now',
    );
    return '$_temp0';
  }

  @override
  String get guideWatchChannel => 'Watch channel';
}
