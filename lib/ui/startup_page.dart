import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import '../theme/app_theme.dart';
import 'widgets/brand_logo.dart';
import 'pages/settings_page.dart' show restoreLocalBackup;

class StartupPage extends StatelessWidget {
  const StartupPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final loading = controller.startupState == StartupState.connecting;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.25,
            colors: [context.palette.violetSoft, context.palette.canvas],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: context.palette.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: context.palette.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandLogo(key: Key('startup-brand-logo'), size: 56),
                  const SizedBox(height: 20),
                  Text(
                    'expeneses tracker offline',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    loading
                        ? 'Opening your tracker…'
                        : 'Could not open your saved data',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    loading
                        ? 'Your money, stored on your phone.'
                        : controller.errorMessage ??
                              'Please try opening your tracker again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: loading
                          ? context.palette.muted
                          : context.palette.red,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (loading)
                    const CircularProgressIndicator()
                  else ...[
                    FilledButton.icon(
                      onPressed: controller.initialize,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try again'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => restoreLocalBackup(context, controller),
                      icon: const Icon(Icons.restore_rounded),
                      label: const Text('Restore backup'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
