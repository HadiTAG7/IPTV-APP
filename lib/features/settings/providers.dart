// Providers of the Settings screen.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/providers.dart';
import '../../core/db/app_db.dart';

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

/// What Settings calls to refresh a source's guide. The default does
/// nothing; the app wires it to the EPG service, for example
/// `epgService.refresh(id, force: force, refreshHours: ..., lite: ...)`.
final refreshGuideActionProvider = Provider<RefreshGuideAction>(
  (ref) => _noRefresh,
  name: 'refreshGuideActionProvider',
);

Future<void> _noRefresh(int sourceId, {required bool force}) async {}

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
