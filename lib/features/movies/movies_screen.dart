import 'package:flutter/widgets.dart';

import '../vod_common/vod_browser.dart';
import '../vod_common/vod_providers.dart';

/// Movie categories, poster grid and Continue watching; OK opens the
/// movie's detail page.
///
/// Body content only: the home shells provide the Scaffold (see
/// [VodBrowser] for the layout and remote navigation).
class MoviesScreen extends StatelessWidget {
  const MoviesScreen({super.key});

  @override
  Widget build(BuildContext context) => const VodBrowser(kind: VodKind.movie);
}
