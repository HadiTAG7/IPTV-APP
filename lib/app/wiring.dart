// Connections between features that cannot import each other.
//
// A feature that needs another feature's screen exposes a provider hook, and
// this file fills it in at the app level: the screens import the home shell
// (and the shell imports every screen), so a direct import from one feature
// screen to another would close an import cycle through the shell.
//
// Hooks whose real implementation needs no such import are wired by their
// own defaults instead:
// * `vodDetailNavigatorProvider` (Favorites, Search) pushes the movie and
//   series detail pages;
// * `onChannelPlayedProvider` (player) and `markChannelPlayedProvider`
//   (Live, Favorites, Search) record Recent channels;
// * `refreshGuideActionProvider` (Settings) runs `guideRefreshProvider`;
// * `IptvApp` keeps `epgAutoRefreshProvider` (the guide schedule) alive.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../features/help/providers.dart';
import '../features/sources/source_editor_screen.dart';
import '../sources/source_repository.dart';
import 'providers.dart';

/// The overrides that connect the features: bootstrap's [ProviderScope],
/// and the tests that run the whole app.
List<Override> appWiring() => [
  addSourcePrefillProvider.overrideWith((ref) => prefillSourceEditor(ref)),
];

/// Help's "Add as source": the source editor with the playlist link and a
/// suggested name filled in. The user reviews and saves it. Before the
/// first source exists (Help opened from onboarding) the editor runs the
/// first-run flow, so onboarding stays until the import is over.
AddSourcePrefill prefillSourceEditor(Ref ref) =>
    (context, {required url, required name}) {
      final sources = ref.read(sourcesProvider).value ?? const <SourceView>[];
      return openSourceEditor(
        context,
        onboarding: sources.isEmpty,
        initialUrl: url,
        initialName: name,
      );
    };
