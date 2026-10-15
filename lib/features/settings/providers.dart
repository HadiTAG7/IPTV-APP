// Providers of the Settings screen.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/providers.dart';
import '../../core/db/app_db.dart';
import '../../epg/epg_providers.dart';

/// Re-downloads the guide of a source. [force] downloads every guide in full
/// (the "Refresh guide" button and a changed offset); without it only guides
/// that are new, due or missing data are fetched (after adding or enabling a
/// guide URL).
///
/// The returned future completes when the refresh has finished, or at once
/// when the work continues in the background.
typedef RefreshGuideAction = Future<void> Function(
  int sourceId, {
  required bool force,
});

/// What Settings calls to refresh a source's guide: a run of the source's
/// [guideRefreshProvider] (the Guide screen shows the same run), with the
/// Settings refresh interval and Lite mode. Completes when the run ends.
final refreshGuideActionProvider = Provider<RefreshGuideAction>(
  (ref) =>
      (sourceId, {required force}) =>
          ref.read(guideRefreshProvider(sourceId).notifier).run(force: force),
  name: 'refreshGuideActionProvider',
);

/// Guide URLs of a source in priority order, updated on every change.
final epgSourcesProvider = StreamProvider.autoDispose
    .family<List<EpgSourceRow>, int>(
      (ref, sourceId) => ref.watch(epgDaoProvider).watchEpgSources(sourceId),
    );

/// The app version for About, e.g. `0.1.0 (12)`, or null when the platform
/// cannot tell.
final appVersionProvider = FutureProvider<String?>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    final version = info.version.trim();
    if (version.isEmpty) return null;
    final build = info.buildNumber.trim();
    return build.isEmpty ? version : '$version ($build)';
  } on Object catch (e) {
    ref.read(ringLogProvider).warn('Package info unavailable: $e');
    return null;
  }
}, name: 'appVersionProvider');
