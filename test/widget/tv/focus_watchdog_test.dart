import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/tv/focus_watchdog.dart';
import 'package:iptv_player/tv/pane_scope.dart';
import 'package:iptv_player/tv/tv_focusable.dart';

import '../support/tv_harness.dart';

/// A pane of items whose list can be changed while a dialog is open.
class _Screen extends StatelessWidget {
  const _Screen({
    required this.items,
    required this.nodes,
    required this.enabled,
  });

  final ValueNotifier<List<int>> items;
  final Map<int, FocusNode> nodes;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return FocusWatchdog(
      enabled: enabled,
      child: PaneScope(
        debugLabel: 'pane',
        child: ValueListenableBuilder<List<int>>(
          valueListenable: items,
          builder: (context, ids, _) => Column(
            children: [
              for (final id in ids)
                TvFocusable(
                  key: ValueKey(id),
                  focusNode: nodes.putIfAbsent(
                    id,
                    () => FocusNode(debugLabel: 'item-$id'),
                  ),
                  onSelect: () {},
                  child: SizedBox(height: 48, child: Text('Item $id')),
                ),
              Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      content: const Text('Dialog'),
                      actions: [
                        TextButton(
                          autofocus: true,
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close dialog'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('Open dialog'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  late ValueNotifier<List<int>> items;
  late Map<int, FocusNode> nodes;

  setUp(() {
    items = ValueNotifier([0, 1, 2, 3]);
    nodes = {};
  });

  tearDown(() {
    items.dispose();
  });

  Future<void> openDialogFrom(WidgetTester tester, int id) async {
    nodes[id]!.requestFocus();
    await tester.pumpAndSettle();
    expect(nodes[id]!.hasPrimaryFocus, isTrue);
    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    expect(find.text('Dialog'), findsOneWidget);
  }

  Future<void> removeAndClose(WidgetTester tester, int id) async {
    items.value = [...items.value]..remove(id);
    await tester.pump();
    nodes.remove(id)!.dispose();
    await tester.tap(find.text('Close dialog'));
    await tester.pumpAndSettle();
  }

  for (final locale in testLocales) {
    group('FocusWatchdog (${locale.languageCode})', () {
      testWidgets('re-focuses the pane after its item vanished under a '
          'dialog', (tester) async {
        await pumpTv(
          tester,
          _Screen(items: items, nodes: nodes, enabled: true),
          locale: locale,
        );
        await openDialogFrom(tester, 2);
        await removeAndClose(tester, 2);

        final focus = primary;
        expect(focus, isNotNull);
        expect(focus, isNot(isA<FocusScopeNode>()));
        expect(nodes[0]!.hasPrimaryFocus, isTrue);

        // Navigation keeps working from there.
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(nodes[1]!.hasPrimaryFocus, isTrue);
      });

      testWidgets('without the watchdog focus is left on a bare scope', (
        tester,
      ) async {
        await pumpTv(
          tester,
          _Screen(items: items, nodes: nodes, enabled: false),
          locale: locale,
        );
        await openDialogFrom(tester, 2);
        await removeAndClose(tester, 2);
        expect(primary, isA<FocusScopeNode>());
      });

      testWidgets('leaves a normal dialog return alone', (tester) async {
        await pumpTv(
          tester,
          _Screen(items: items, nodes: nodes, enabled: true),
          locale: locale,
        );
        await openDialogFrom(tester, 3);
        await tester.tap(find.text('Close dialog'));
        await tester.pumpAndSettle();
        expect(nodes[3]!.hasPrimaryFocus, isTrue);
      });
    });
  }

  testWidgets('restores a registered fallback after focus is dropped', (
    tester,
  ) async {
    final fallback = FocusNode(debugLabel: 'fallback');
    final other = FocusNode(debugLabel: 'other');
    addTearDown(fallback.dispose);
    addTearDown(other.dispose);
    final key = GlobalKey<FocusWatchdogState>();
    await pumpTv(
      tester,
      FocusWatchdog(
        key: key,
        child: Column(
          children: [
            TvFocusable(
              focusNode: other,
              autofocus: true,
              child: const SizedBox(height: 40),
            ),
            TvFocusable(focusNode: fallback, child: const SizedBox(height: 40)),
          ],
        ),
      ),
    );
    key.currentState!.register(fallback);
    expect(key.currentState!.fallbacks, [fallback]);
    expect(other.hasPrimaryFocus, isTrue);

    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pumpAndSettle();
    expect(fallback.hasPrimaryFocus, isTrue);

    key.currentState!.unregister(fallback);
    expect(key.currentState!.fallbacks, isEmpty);
  });

  testWidgets('focused panes register themselves', (tester) async {
    final a = FocusNode();
    addTearDown(a.dispose);
    final key = GlobalKey<FocusWatchdogState>();
    final pane = GlobalKey<PaneScopeState>();
    await pumpTv(
      tester,
      FocusWatchdog(
        key: key,
        child: PaneScope(
          key: pane,
          autofocus: true,
          child: TvFocusable(focusNode: a, child: const SizedBox(height: 40)),
        ),
      ),
    );
    await tester.pump();
    expect(a.hasPrimaryFocus, isTrue);
    expect(key.currentState!.fallbacks, [pane.currentState!.node]);
  });
}
