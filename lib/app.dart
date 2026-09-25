import 'dart:async';

import 'package:flutter/material.dart';

import 'core/config_store.dart';
import 'state/app_controller.dart';
import 'theme/app_theme.dart';
import 'ui/app_shell.dart';
import 'ui/startup_page.dart';

class BudgetTrackerApp extends StatefulWidget {
  const BudgetTrackerApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<BudgetTrackerApp> createState() => _BudgetTrackerAppState();
}

class _BudgetTrackerAppState extends State<BudgetTrackerApp>
    with WidgetsBindingObserver {
  Future<void>? _initializationFuture;
  late AppThemePreference _themePreference;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _themePreference = widget.controller.config.themePreference;
    widget.controller.addListener(_handleControllerChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initializationFuture = widget.controller.initialize();
    });
  }

  @override
  void didUpdateWidget(covariant BudgetTrackerApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(
      identical(oldWidget.controller, widget.controller),
      'BudgetTrackerApp owns one controller for its full lifetime.',
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_handleControllerChange);
    final initialization = _initializationFuture;
    if (initialization == null) {
      widget.controller.dispose();
    } else {
      unawaited(initialization.whenComplete(widget.controller.dispose));
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.controller.startupState == StartupState.ready) {
      unawaited(_refreshAfterResume());
    }
  }

  Future<void> _refreshAfterResume() async {
    await widget.controller.refreshAll();
  }

  void _handleControllerChange() {
    final next = widget.controller.config.themePreference;
    if (!mounted || next == _themePreference) return;
    setState(() => _themePreference = next);
  }

  ThemeMode get _themeMode => switch (_themePreference) {
    AppThemePreference.light => ThemeMode.light,
    AppThemePreference.dark => ThemeMode.dark,
    AppThemePreference.system => ThemeMode.system,
  };

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'expeneses tracker offline',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _themeMode,
      home: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          if (widget.controller.startupState != StartupState.ready) {
            return StartupPage(controller: widget.controller);
          }
          return AppShell(controller: widget.controller);
        },
      ),
    );
  }
}
