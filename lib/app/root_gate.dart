import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/onboarding/onboarding_screen.dart';
import '../widgets/states.dart';
import 'home_shell.dart';
import 'providers.dart';

/// First screen: onboarding while there is no source (or while onboarding
/// holds the screen, see [onboardingHoldProvider]), else the home shell.
///
/// Sources are watched, so saving the first source switches to the shell
/// and deleting the last one returns to onboarding. Routes pushed on top
/// (e.g. an import progress page) stay where they are.
class RootGate extends ConsumerWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider);
    final hold = ref.watch(onboardingHoldProvider);
    final list = sources.value;
    if (list == null) {
      return Scaffold(
        body: sources.hasError
            ? ErrorView(onRetry: () => ref.invalidate(sourcesProvider))
            : const LoadingView(),
      );
    }
    if (list.isEmpty || hold) {
      return const Scaffold(
        key: ValueKey('onboarding'),
        body: SafeArea(child: OnboardingScreen()),
      );
    }
    return const HomeShell(key: ValueKey('home'));
  }
}
