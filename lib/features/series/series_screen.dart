import 'package:flutter/widgets.dart';

import '../vod_common/vod_browser.dart';
import '../vod_common/vod_providers.dart';

/// Series categories, poster grid and Continue watching (by series); OK
/// opens the series page with its seasons and episodes.
///
/// Body content only: the home shells provide the Scaffold (see
/// [VodBrowser] for the layout and remote navigation).
class SeriesScreen extends StatelessWidget {
  const SeriesScreen({super.key});

  @override
  Widget build(BuildContext context) => const VodBrowser(kind: VodKind.series);
}
