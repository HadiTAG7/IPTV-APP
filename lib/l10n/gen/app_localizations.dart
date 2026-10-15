import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// App name shown in the launcher, title bar and About.
  ///
  /// In en, this message translates to:
  /// **'IPTV Player'**
  String get appTitle;

  /// No description provided for @commonOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// No description provided for @commonAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// No description provided for @commonNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get commonNext;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get commonYes;

  /// No description provided for @commonNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get commonNo;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get commonLoading;

  /// No description provided for @commonEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get commonEmpty;

  /// No description provided for @commonErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get commonErrorGeneric;

  /// No description provided for @commonUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get commonUnavailable;

  /// No description provided for @commonCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get commonCopied;

  /// No description provided for @commonOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get commonOn;

  /// No description provided for @commonOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get commonOff;

  /// No description provided for @commonSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search channels, movies and series'**
  String get commonSearchHint;

  /// No description provided for @commonPressBackAgainToExit.
  ///
  /// In en, this message translates to:
  /// **'Press back again to exit'**
  String get commonPressBackAgainToExit;

  /// No description provided for @onboardingWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get onboardingWelcomeTitle;

  /// No description provided for @onboardingWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Watch your own IPTV sources on your TV, phone and PC.'**
  String get onboardingWelcomeBody;

  /// No description provided for @onboardingChooseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose language'**
  String get onboardingChooseLanguage;

  /// No description provided for @onboardingDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'The app is a player only and provides no content.'**
  String get onboardingDisclaimer;

  /// No description provided for @onboardingLearnMore.
  ///
  /// In en, this message translates to:
  /// **'Learn more'**
  String get onboardingLearnMore;

  /// No description provided for @onboardingGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get onboardingGetStarted;

  /// No description provided for @onboardingAddSourceTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a source'**
  String get onboardingAddSourceTitle;

  /// No description provided for @onboardingAddSourceBody.
  ///
  /// In en, this message translates to:
  /// **'Add an M3U link, an M3U file or an Xtream Codes login from a provider you have the right to use.'**
  String get onboardingAddSourceBody;

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get onboardingSkip;

  /// No description provided for @sourceTypeM3uUrl.
  ///
  /// In en, this message translates to:
  /// **'M3U link'**
  String get sourceTypeM3uUrl;

  /// No description provided for @sourceTypeM3uUrlHint.
  ///
  /// In en, this message translates to:
  /// **'A playlist URL, usually ending in .m3u or .m3u8'**
  String get sourceTypeM3uUrlHint;

  /// No description provided for @sourceTypeM3uFile.
  ///
  /// In en, this message translates to:
  /// **'M3U file'**
  String get sourceTypeM3uFile;

  /// No description provided for @sourceTypeM3uFileHint.
  ///
  /// In en, this message translates to:
  /// **'A playlist file saved on this device'**
  String get sourceTypeM3uFileHint;

  /// No description provided for @sourceTypeXtream.
  ///
  /// In en, this message translates to:
  /// **'Xtream Codes'**
  String get sourceTypeXtream;

  /// No description provided for @sourceTypeXtreamHint.
  ///
  /// In en, this message translates to:
  /// **'Server address, username and password'**
  String get sourceTypeXtreamHint;

  /// No description provided for @fieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get fieldName;

  /// No description provided for @fieldNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Home'**
  String get fieldNameHint;

  /// No description provided for @fieldServer.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get fieldServer;

  /// No description provided for @fieldServerHint.
  ///
  /// In en, this message translates to:
  /// **'http://example.com:8080'**
  String get fieldServerHint;

  /// No description provided for @fieldUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get fieldUsername;

  /// No description provided for @fieldPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get fieldPassword;

  /// No description provided for @fieldShowPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get fieldShowPassword;

  /// No description provided for @fieldHidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get fieldHidePassword;

  /// No description provided for @fieldPlaylistUrl.
  ///
  /// In en, this message translates to:
  /// **'Playlist URL'**
  String get fieldPlaylistUrl;

  /// No description provided for @fieldPlaylistUrlHint.
  ///
  /// In en, this message translates to:
  /// **'http://example.com/playlist.m3u'**
  String get fieldPlaylistUrlHint;

  /// No description provided for @fieldFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get fieldFile;

  /// No description provided for @fieldChooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get fieldChooseFile;

  /// No description provided for @fieldNoFileChosen.
  ///
  /// In en, this message translates to:
  /// **'No file chosen'**
  String get fieldNoFileChosen;

  /// No description provided for @fieldUserAgent.
  ///
  /// In en, this message translates to:
  /// **'User agent'**
  String get fieldUserAgent;

  /// No description provided for @fieldUserAgentCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get fieldUserAgentCustom;

  /// No description provided for @fieldReferer.
  ///
  /// In en, this message translates to:
  /// **'Referer'**
  String get fieldReferer;

  /// No description provided for @fieldEpgUrl.
  ///
  /// In en, this message translates to:
  /// **'EPG URL'**
  String get fieldEpgUrl;

  /// No description provided for @fieldEpgUrlHint.
  ///
  /// In en, this message translates to:
  /// **'XMLTV guide link (optional)'**
  String get fieldEpgUrlHint;

  /// No description provided for @fieldLiveFormat.
  ///
  /// In en, this message translates to:
  /// **'Live format'**
  String get fieldLiveFormat;

  /// No description provided for @liveFormatTs.
  ///
  /// In en, this message translates to:
  /// **'MPEG-TS (.ts)'**
  String get liveFormatTs;

  /// No description provided for @liveFormatHls.
  ///
  /// In en, this message translates to:
  /// **'HLS (.m3u8)'**
  String get liveFormatHls;

  /// No description provided for @fieldAdvancedOptions.
  ///
  /// In en, this message translates to:
  /// **'Advanced options'**
  String get fieldAdvancedOptions;

  /// No description provided for @fieldRequired.
  ///
  /// In en, this message translates to:
  /// **'This field is required'**
  String get fieldRequired;

  /// No description provided for @fieldOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get fieldOptional;

  /// No description provided for @typeOnYourPhone.
  ///
  /// In en, this message translates to:
  /// **'Type on your phone'**
  String get typeOnYourPhone;

  /// No description provided for @testAndSave.
  ///
  /// In en, this message translates to:
  /// **'Test & save'**
  String get testAndSave;

  /// No description provided for @validating.
  ///
  /// In en, this message translates to:
  /// **'Validating…'**
  String get validating;

  /// No description provided for @errorInvalidUrl.
  ///
  /// In en, this message translates to:
  /// **'Invalid URL. It must start with http:// or https://.'**
  String get errorInvalidUrl;

  /// No description provided for @errorUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the server. Check the address and your internet connection.'**
  String get errorUnreachable;

  /// No description provided for @errorTimeout.
  ///
  /// In en, this message translates to:
  /// **'The server took too long to respond. Try again later.'**
  String get errorTimeout;

  /// No description provided for @errorAuthFailed.
  ///
  /// In en, this message translates to:
  /// **'Wrong username or password.'**
  String get errorAuthFailed;

  /// Account expiry error with the expiry date.
  ///
  /// In en, this message translates to:
  /// **'This subscription expired on {date}.'**
  String errorExpired(DateTime date);

  /// No description provided for @errorBanned.
  ///
  /// In en, this message translates to:
  /// **'This account has been banned by the provider.'**
  String get errorBanned;

  /// No description provided for @errorDisabled.
  ///
  /// In en, this message translates to:
  /// **'This account is disabled.'**
  String get errorDisabled;

  /// No description provided for @errorNotM3u.
  ///
  /// In en, this message translates to:
  /// **'This doesn\'t look like an M3U playlist.'**
  String get errorNotM3u;

  /// No description provided for @errorFileRead.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read the file.'**
  String get errorFileRead;

  /// No description provided for @errorHttpStatus.
  ///
  /// In en, this message translates to:
  /// **'The server returned error {code}.'**
  String errorHttpStatus(int code);

  /// No description provided for @importTitle.
  ///
  /// In en, this message translates to:
  /// **'Importing your source'**
  String get importTitle;

  /// Number of live channels imported so far.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No live channels} =1{1 live channel} other{{count} live channels}}'**
  String importLiveCount(int count);

  /// No description provided for @importMoviesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No movies} =1{1 movie} other{{count} movies}}'**
  String importMoviesCount(int count);

  /// No description provided for @importSeriesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No series} =1{1 series} other{{count} series}}'**
  String importSeriesCount(int count);

  /// No description provided for @importGuide.
  ///
  /// In en, this message translates to:
  /// **'Loading the TV guide…'**
  String get importGuide;

  /// No description provided for @importCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel import'**
  String get importCancel;

  /// No description provided for @importDone.
  ///
  /// In en, this message translates to:
  /// **'Import complete'**
  String get importDone;

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed'**
  String get importFailed;

  /// No description provided for @navLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get navLive;

  /// No description provided for @navGuide.
  ///
  /// In en, this message translates to:
  /// **'Guide'**
  String get navGuide;

  /// No description provided for @navMovies.
  ///
  /// In en, this message translates to:
  /// **'Movies'**
  String get navMovies;

  /// No description provided for @navSeries.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get navSeries;

  /// No description provided for @navSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

  /// No description provided for @navFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get navFavorites;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @navSources.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get navSources;

  /// No description provided for @navMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get navMore;

  /// No description provided for @navSwitchSource.
  ///
  /// In en, this message translates to:
  /// **'Switch source'**
  String get navSwitchSource;

  /// No description provided for @liveAllChannels.
  ///
  /// In en, this message translates to:
  /// **'All channels'**
  String get liveAllChannels;

  /// No description provided for @liveFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get liveFavorites;

  /// No description provided for @liveRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get liveRecent;

  /// No description provided for @liveCategories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get liveCategories;

  /// No description provided for @liveNoProgrammeInfo.
  ///
  /// In en, this message translates to:
  /// **'No programme info'**
  String get liveNoProgrammeInfo;

  /// No description provided for @liveNow.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get liveNow;

  /// No description provided for @liveNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get liveNext;

  /// {title} is wrapped in U+2068/U+2069 (first-strong isolate) so text in either script keeps its own direction.
  ///
  /// In en, this message translates to:
  /// **'Now: ⁨{title}⁩'**
  String liveNowTitle(String title);

  /// {title} is wrapped in U+2068/U+2069 (first-strong isolate) so text in either script keeps its own direction.
  ///
  /// In en, this message translates to:
  /// **'Next: ⁨{title}⁩'**
  String liveNextTitle(String title);

  /// No description provided for @liveChannelCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No channels} =1{1 channel} other{{count} channels}}'**
  String liveChannelCount(int count);

  /// No description provided for @liveNoChannels.
  ///
  /// In en, this message translates to:
  /// **'No channels in this category'**
  String get liveNoChannels;

  /// No description provided for @liveAddFavorite.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get liveAddFavorite;

  /// No description provided for @liveRemoveFavorite.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get liveRemoveFavorite;

  /// No description provided for @liveHideCategory.
  ///
  /// In en, this message translates to:
  /// **'Hide category'**
  String get liveHideCategory;

  /// No description provided for @liveAssignGuideChannel.
  ///
  /// In en, this message translates to:
  /// **'Assign guide channel'**
  String get liveAssignGuideChannel;

  /// No description provided for @livePlayWithOtherPlayer.
  ///
  /// In en, this message translates to:
  /// **'Play with the other player'**
  String get livePlayWithOtherPlayer;

  /// No description provided for @liveChannelNumber.
  ///
  /// In en, this message translates to:
  /// **'Channel {number}'**
  String liveChannelNumber(int number);

  /// No description provided for @guideToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get guideToday;

  /// No description provided for @guideTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get guideTomorrow;

  /// No description provided for @guideNow.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get guideNow;

  /// No description provided for @guideRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh guide'**
  String get guideRefresh;

  /// No description provided for @guideUpdating.
  ///
  /// In en, this message translates to:
  /// **'Updating the guide…'**
  String get guideUpdating;

  /// No description provided for @guideEmpty.
  ///
  /// In en, this message translates to:
  /// **'No guide data yet. Add an EPG URL in Settings.'**
  String get guideEmpty;

  /// No description provided for @guideUpdated.
  ///
  /// In en, this message translates to:
  /// **'Guide updated {date}'**
  String guideUpdated(DateTime date);

  /// No description provided for @vodContinueWatching.
  ///
  /// In en, this message translates to:
  /// **'Continue watching'**
  String get vodContinueWatching;

  /// No description provided for @vodPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get vodPlay;

  /// Resume button; time is a formatted position such as 42:10.
  ///
  /// In en, this message translates to:
  /// **'Resume from {time}'**
  String vodResumeFrom(String time);

  /// No description provided for @vodStartOver.
  ///
  /// In en, this message translates to:
  /// **'Start over'**
  String get vodStartOver;

  /// No description provided for @vodSeasons.
  ///
  /// In en, this message translates to:
  /// **'Seasons'**
  String get vodSeasons;

  /// No description provided for @vodEpisodes.
  ///
  /// In en, this message translates to:
  /// **'Episodes'**
  String get vodEpisodes;

  /// No description provided for @vodSeasonN.
  ///
  /// In en, this message translates to:
  /// **'Season {n}'**
  String vodSeasonN(int n);

  /// No description provided for @vodEpisodeN.
  ///
  /// In en, this message translates to:
  /// **'Episode {n}'**
  String vodEpisodeN(int n);

  /// No description provided for @vodEpisodeCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No episodes} =1{1 episode} other{{count} episodes}}'**
  String vodEpisodeCount(int count);

  /// No description provided for @vodNextEpisodeIn.
  ///
  /// In en, this message translates to:
  /// **'{seconds, plural, =1{Next episode in 1 second} other{Next episode in {seconds} seconds}}'**
  String vodNextEpisodeIn(int seconds);

  /// No description provided for @vodNextEpisode.
  ///
  /// In en, this message translates to:
  /// **'Next episode'**
  String get vodNextEpisode;

  /// Runtime, e.g. 95 min.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String vodMinutes(int minutes);

  /// No description provided for @vodNoEpisodes.
  ///
  /// In en, this message translates to:
  /// **'No episodes available'**
  String get vodNoEpisodes;

  /// No description provided for @vodWatched.
  ///
  /// In en, this message translates to:
  /// **'Watched'**
  String get vodWatched;

  /// No description provided for @vodAddFavorite.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get vodAddFavorite;

  /// No description provided for @vodRemoveFavorite.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get vodRemoveFavorite;

  /// No description provided for @playerAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get playerAudio;

  /// No description provided for @playerSubtitles.
  ///
  /// In en, this message translates to:
  /// **'Subtitles'**
  String get playerSubtitles;

  /// No description provided for @playerOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get playerOff;

  /// No description provided for @playerAspectRatio.
  ///
  /// In en, this message translates to:
  /// **'Aspect ratio'**
  String get playerAspectRatio;

  /// No description provided for @aspectFit.
  ///
  /// In en, this message translates to:
  /// **'Fit'**
  String get aspectFit;

  /// No description provided for @aspectFill.
  ///
  /// In en, this message translates to:
  /// **'Fill'**
  String get aspectFill;

  /// No description provided for @aspectStretch.
  ///
  /// In en, this message translates to:
  /// **'Stretch'**
  String get aspectStretch;

  /// No description provided for @aspect16x9.
  ///
  /// In en, this message translates to:
  /// **'16:9'**
  String get aspect16x9;

  /// No description provided for @aspect4x3.
  ///
  /// In en, this message translates to:
  /// **'4:3'**
  String get aspect4x3;

  /// No description provided for @playerSwitchPlayer.
  ///
  /// In en, this message translates to:
  /// **'Switch player'**
  String get playerSwitchPlayer;

  /// No description provided for @playerStats.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get playerStats;

  /// No description provided for @playerFavorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get playerFavorite;

  /// No description provided for @playerGuide.
  ///
  /// In en, this message translates to:
  /// **'Guide'**
  String get playerGuide;

  /// No description provided for @playerLive.
  ///
  /// In en, this message translates to:
  /// **'LIVE'**
  String get playerLive;

  /// No description provided for @playerBuffering.
  ///
  /// In en, this message translates to:
  /// **'Buffering…'**
  String get playerBuffering;

  /// Reconnect banner with attempt number and maximum attempts.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting… ({n}/{max})'**
  String playerReconnecting(int n, int max);

  /// No description provided for @playerPlaybackFailed.
  ///
  /// In en, this message translates to:
  /// **'Playback failed'**
  String get playerPlaybackFailed;

  /// No description provided for @playerRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get playerRetry;

  /// No description provided for @playerTryOtherFormat.
  ///
  /// In en, this message translates to:
  /// **'Try other format'**
  String get playerTryOtherFormat;

  /// No description provided for @playerCopyReport.
  ///
  /// In en, this message translates to:
  /// **'Copy report'**
  String get playerCopyReport;

  /// No description provided for @playerSubtitlesNeedMpv.
  ///
  /// In en, this message translates to:
  /// **'Subtitles need the mpv player.'**
  String get playerSubtitlesNeedMpv;

  /// No description provided for @playerTrackN.
  ///
  /// In en, this message translates to:
  /// **'Track {n}'**
  String playerTrackN(int n);

  /// No description provided for @statsEngine.
  ///
  /// In en, this message translates to:
  /// **'Engine'**
  String get statsEngine;

  /// No description provided for @statsCodec.
  ///
  /// In en, this message translates to:
  /// **'Codec'**
  String get statsCodec;

  /// No description provided for @statsResolution.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get statsResolution;

  /// No description provided for @statsFirstFrame.
  ///
  /// In en, this message translates to:
  /// **'Time to first frame'**
  String get statsFirstFrame;

  /// No description provided for @statsDroppedFrames.
  ///
  /// In en, this message translates to:
  /// **'Dropped frames'**
  String get statsDroppedFrames;

  /// No description provided for @settingsGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsGeneral;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @languageAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto (system)'**
  String get languageAuto;

  /// No description provided for @languageArabic.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get languageArabic;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @settingsDeviceMode.
  ///
  /// In en, this message translates to:
  /// **'Device mode'**
  String get settingsDeviceMode;

  /// No description provided for @deviceModeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get deviceModeAuto;

  /// No description provided for @deviceModeTv.
  ///
  /// In en, this message translates to:
  /// **'TV'**
  String get deviceModeTv;

  /// No description provided for @deviceModePhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get deviceModePhone;

  /// No description provided for @settingsLiteMode.
  ///
  /// In en, this message translates to:
  /// **'Lite mode'**
  String get settingsLiteMode;

  /// No description provided for @settingsLiteModeHint.
  ///
  /// In en, this message translates to:
  /// **'Smaller buffers and fewer images for devices with 2 GB of RAM or less.'**
  String get settingsLiteModeHint;

  /// No description provided for @settingsPlayer.
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get settingsPlayer;

  /// No description provided for @settingsLiveEngine.
  ///
  /// In en, this message translates to:
  /// **'Live engine'**
  String get settingsLiveEngine;

  /// No description provided for @settingsVodEngine.
  ///
  /// In en, this message translates to:
  /// **'VOD engine'**
  String get settingsVodEngine;

  /// No description provided for @engineAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get engineAuto;

  /// No description provided for @engineExo.
  ///
  /// In en, this message translates to:
  /// **'ExoPlayer'**
  String get engineExo;

  /// No description provided for @engineMpv.
  ///
  /// In en, this message translates to:
  /// **'mpv'**
  String get engineMpv;

  /// No description provided for @settingsExoViewType.
  ///
  /// In en, this message translates to:
  /// **'ExoPlayer view'**
  String get settingsExoViewType;

  /// No description provided for @viewTypeTexture.
  ///
  /// In en, this message translates to:
  /// **'Texture'**
  String get viewTypeTexture;

  /// No description provided for @viewTypePlatform.
  ///
  /// In en, this message translates to:
  /// **'Platform view'**
  String get viewTypePlatform;

  /// No description provided for @settingsHardwareDecoding.
  ///
  /// In en, this message translates to:
  /// **'Hardware decoding'**
  String get settingsHardwareDecoding;

  /// No description provided for @settingsPreferredAudioLanguage.
  ///
  /// In en, this message translates to:
  /// **'Preferred audio language'**
  String get settingsPreferredAudioLanguage;

  /// No description provided for @settingsGuide.
  ///
  /// In en, this message translates to:
  /// **'TV guide'**
  String get settingsGuide;

  /// No description provided for @settingsEpgUrls.
  ///
  /// In en, this message translates to:
  /// **'Guide URLs'**
  String get settingsEpgUrls;

  /// No description provided for @settingsEpgOffset.
  ///
  /// In en, this message translates to:
  /// **'EPG offset'**
  String get settingsEpgOffset;

  /// EPG time shift; minutes may be negative.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String settingsEpgOffsetMinutes(int minutes);

  /// No description provided for @settingsRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get settingsRefresh;

  /// No description provided for @settingsAddSource.
  ///
  /// In en, this message translates to:
  /// **'Add source'**
  String get settingsAddSource;

  /// No description provided for @settingsEditSource.
  ///
  /// In en, this message translates to:
  /// **'Edit source'**
  String get settingsEditSource;

  /// No description provided for @settingsDeleteSource.
  ///
  /// In en, this message translates to:
  /// **'Delete source'**
  String get settingsDeleteSource;

  /// {name} is wrapped in U+2068/U+2069 (first-strong isolate) so text in either script keeps its own direction.
  ///
  /// In en, this message translates to:
  /// **'Delete “⁨{name}⁩”? Its channels, favorites and watch progress will be removed from this device.'**
  String settingsDeleteSourceConfirm(String name);

  /// No description provided for @settingsSetActive.
  ///
  /// In en, this message translates to:
  /// **'Set active'**
  String get settingsSetActive;

  /// No description provided for @settingsActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get settingsActive;

  /// No description provided for @settingsAccountExpires.
  ///
  /// In en, this message translates to:
  /// **'Account expires {date}'**
  String settingsAccountExpires(DateTime date);

  /// No description provided for @settingsAccountNoExpiry.
  ///
  /// In en, this message translates to:
  /// **'No expiry date'**
  String get settingsAccountNoExpiry;

  /// No description provided for @settingsExpiresSoon.
  ///
  /// In en, this message translates to:
  /// **'Your subscription expires soon'**
  String get settingsExpiresSoon;

  /// No description provided for @settingsExpiresInDays.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =0{Expires today} =1{Expires in 1 day} other{Expires in {days} days}}'**
  String settingsExpiresInDays(int days);

  /// No description provided for @settingsLastUpdated.
  ///
  /// In en, this message translates to:
  /// **'Last updated {date}'**
  String settingsLastUpdated(DateTime date);

  /// No description provided for @settingsNoSources.
  ///
  /// In en, this message translates to:
  /// **'No sources yet.'**
  String get settingsNoSources;

  /// No description provided for @settingsHelpLegal.
  ///
  /// In en, this message translates to:
  /// **'Help & legal'**
  String get settingsHelpLegal;

  /// No description provided for @settingsDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get settingsDiagnostics;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String settingsVersion(String version);

  /// No description provided for @settingsLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open-source licences'**
  String get settingsLicenses;

  /// No description provided for @settingsCheckForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get settingsCheckForUpdates;

  /// No description provided for @helpTitle.
  ///
  /// In en, this message translates to:
  /// **'Help & legal'**
  String get helpTitle;

  /// No description provided for @helpAsOf.
  ///
  /// In en, this message translates to:
  /// **'As of 2026'**
  String get helpAsOf;

  /// No description provided for @helpLegalBody.
  ///
  /// In en, this message translates to:
  /// **'The app is only a player and contains no channels. You add an M3U link or an Xtream login from a source you have the right to use. Free legal sources: the public iptv-org playlists (links published by the broadcasters themselves; some stop working or are geo-blocked), or your own satellite receiver if it can export M3U. Free official apps: Aloula, Shahid\'s free tier and Thmanyah. Legal paid subscriptions (Shahid VIP, TOD by beIN, stc tv, OSN+) work only in their official apps and don\'t give you an M3U link or Xtream login. Beware of cheap “IPTV subscriptions” sold on WhatsApp and Telegram: they are usually unlicensed, the new Saudi Copyright Law (in force since August 2026) raises the penalties, and they carry a real risk of fraud and malware.'**
  String get helpLegalBody;

  /// No description provided for @helpWarningSignsTitle.
  ///
  /// In en, this message translates to:
  /// **'Signs of an unlicensed seller'**
  String get helpWarningSignsTitle;

  /// No description provided for @helpWarningSigns.
  ///
  /// In en, this message translates to:
  /// **'• Thousands of premium channels for a small yearly fee\n• Sold through WhatsApp, Telegram or social media ads\n• An Xtream code or M3U link instead of an official app\n• No commercial registration and no VAT invoice'**
  String get helpWarningSigns;

  /// No description provided for @helpNotLegalAdvice.
  ///
  /// In en, this message translates to:
  /// **'This is general information, not legal advice.'**
  String get helpNotLegalAdvice;

  /// No description provided for @diagTitle.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagTitle;

  /// No description provided for @diagDevice.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get diagDevice;

  /// No description provided for @diagTvSignals.
  ///
  /// In en, this message translates to:
  /// **'TV signals'**
  String get diagTvSignals;

  /// No description provided for @diagAbis.
  ///
  /// In en, this message translates to:
  /// **'ABIs'**
  String get diagAbis;

  /// No description provided for @diagMemory.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get diagMemory;

  /// No description provided for @diagRamMb.
  ///
  /// In en, this message translates to:
  /// **'{mb} MB RAM'**
  String diagRamMb(int mb);

  /// No description provided for @diagDecoders.
  ///
  /// In en, this message translates to:
  /// **'Decoders'**
  String get diagDecoders;

  /// No description provided for @diagSupported.
  ///
  /// In en, this message translates to:
  /// **'Supported'**
  String get diagSupported;

  /// No description provided for @diagNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Not supported'**
  String get diagNotSupported;

  /// No description provided for @diagEngineTest.
  ///
  /// In en, this message translates to:
  /// **'Engine test'**
  String get diagEngineTest;

  /// No description provided for @diagRunTest.
  ///
  /// In en, this message translates to:
  /// **'Run test'**
  String get diagRunTest;

  /// No description provided for @diagFirstFrameMs.
  ///
  /// In en, this message translates to:
  /// **'First frame in {ms} ms'**
  String diagFirstFrameMs(int ms);

  /// No description provided for @diagTestPassed.
  ///
  /// In en, this message translates to:
  /// **'Passed'**
  String get diagTestPassed;

  /// No description provided for @diagTestFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get diagTestFailed;

  /// No description provided for @diagLog.
  ///
  /// In en, this message translates to:
  /// **'Recent log'**
  String get diagLog;

  /// No description provided for @diagCopyReport.
  ///
  /// In en, this message translates to:
  /// **'Copy report'**
  String get diagCopyReport;

  /// No description provided for @diagShowQr.
  ///
  /// In en, this message translates to:
  /// **'Show QR'**
  String get diagShowQr;

  /// No description provided for @lanScanWithPhone.
  ///
  /// In en, this message translates to:
  /// **'Scan with your phone'**
  String get lanScanWithPhone;

  /// No description provided for @lanSameNetwork.
  ///
  /// In en, this message translates to:
  /// **'Your phone must be on the same Wi-Fi network as this device.'**
  String get lanSameNetwork;

  /// No description provided for @lanOrOpen.
  ///
  /// In en, this message translates to:
  /// **'Or open {url}'**
  String lanOrOpen(String url);

  /// No description provided for @lanWaitingForInput.
  ///
  /// In en, this message translates to:
  /// **'Waiting for input…'**
  String get lanWaitingForInput;

  /// No description provided for @lanReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get lanReceived;

  /// No description provided for @lanCodeExpired.
  ///
  /// In en, this message translates to:
  /// **'The code has expired. Start again.'**
  String get lanCodeExpired;

  /// No description provided for @lanNoNetwork.
  ///
  /// In en, this message translates to:
  /// **'No local network found.'**
  String get lanNoNetwork;

  /// No description provided for @favoritesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No favorites yet. Press Menu on a channel to add it.'**
  String get favoritesEmpty;

  /// {query} is wrapped in U+2068/U+2069 (first-strong isolate) so text in either script keeps its own direction.
  ///
  /// In en, this message translates to:
  /// **'No results for “⁨{query}⁩”'**
  String searchNoResults(String query);

  /// No description provided for @searchChannels.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get searchChannels;

  /// No description provided for @searchMovies.
  ///
  /// In en, this message translates to:
  /// **'Movies'**
  String get searchMovies;

  /// No description provided for @searchSeries.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get searchSeries;

  /// Account expiry error when the provider sent no expiry date.
  ///
  /// In en, this message translates to:
  /// **'This subscription has expired.'**
  String get errorExpiredNoDate;

  /// No description provided for @liveShowHiddenCategories.
  ///
  /// In en, this message translates to:
  /// **'Show hidden categories'**
  String get liveShowHiddenCategories;

  /// No description provided for @liveMoreOptions.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get liveMoreOptions;

  /// No description provided for @liveRecentEmpty.
  ///
  /// In en, this message translates to:
  /// **'Channels you watch will appear here.'**
  String get liveRecentEmpty;

  /// Start and end time of a programme. Each time is wrapped in U+2068/U+2069 (first-strong isolate).
  ///
  /// In en, this message translates to:
  /// **'⁨{start}⁩ – ⁨{end}⁩'**
  String liveTimeRange(String start, String end);

  /// Shown when the number typed on the remote matches no channel in the list.
  ///
  /// In en, this message translates to:
  /// **'No channel {number}'**
  String liveNoChannelNumber(int number);

  /// No description provided for @favoritesEmptyMovies.
  ///
  /// In en, this message translates to:
  /// **'No favorite movies yet.'**
  String get favoritesEmptyMovies;

  /// No description provided for @favoritesEmptySeries.
  ///
  /// In en, this message translates to:
  /// **'No favorite series yet.'**
  String get favoritesEmptySeries;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
