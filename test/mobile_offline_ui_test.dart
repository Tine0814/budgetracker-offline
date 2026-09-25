import 'dart:io';

import 'package:expeneses_tracker_offline/core/api_client.dart';
import 'package:expeneses_tracker_offline/core/app_repository.dart';
import 'package:expeneses_tracker_offline/core/config_store.dart';
import 'package:expeneses_tracker_offline/core/local_database.dart';
import 'package:expeneses_tracker_offline/models/domain_models.dart';
import 'package:expeneses_tracker_offline/state/app_controller.dart';
import 'package:expeneses_tracker_offline/theme/app_theme.dart';
import 'package:expeneses_tracker_offline/ui/app_shell.dart';
import 'package:expeneses_tracker_offline/ui/pages/accounts_page.dart';
import 'package:expeneses_tracker_offline/ui/pages/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('phone drawer has personal tracker features and local settings', (
    tester,
  ) async {
    final controller = await _controller(tester);
    await _pump(tester, AppShell(controller: controller));
    expect(find.byKey(const Key('mobile-navigation-bar')), findsOneWidget);
    expect(find.textContaining('Joint'), findsNothing);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('expeneses tracker offline'), findsOneWidget);
    expect(find.text('Deals & penalties'), findsNothing);
    for (final label in [
      'Gold & jewelry',
      'Categories',
      'Reports',
      'Settings',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    final settings = find.text('Settings');
    await tester.ensureVisible(settings);
    await tester.tap(settings);
    await tester.pumpAndSettle();
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('API base URL'), findsNothing);
    expect(find.text('System health'), findsNothing);
    expect(find.byKey(const Key('export-backup-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'account editor cannot create a joint account on a narrow phone',
    (tester) async {
      final controller = await _controller(tester);
      await _pump(tester, AccountsPage(controller: controller));
      final add = find.widgetWithText(FilledButton, 'Add account').first;
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('account-scope-selector')), findsNothing);
      expect(find.text('Joint'), findsNothing);
      expect(find.text('Account name'), findsOneWidget);
      await tester.ensureVisible(find.text('Save account'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings retains valid imported preferences outside the defaults',
    (tester) async {
      final controller = await _controller(tester);
      controller.settings = const AppSettings(
        currencyCode: 'GBP',
        locale: 'en_GB',
        weekStartsOn: 3,
      );
      await _pump(tester, SettingsPage(controller: controller));
      expect(find.text('GBP'), findsOneWidget);
      expect(find.text('en_GB'), findsOneWidget);
      expect(find.text('Wednesday'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('restore requires an explicit replacement confirmation', (
    tester,
  ) async {
    final controller = await _controller(tester);
    await _pump(tester, SettingsPage(controller: controller));
    final restore = find.byKey(const Key('import-backup-button'));
    await tester.ensureVisible(restore);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('restore-backup-text')),
      '{"example":true}',
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Replace this phone’s records?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Replace this phone’s records?'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<AppController> _controller(WidgetTester tester) async {
  final directory = await tester.runAsync(
    () => Directory.systemTemp.createTemp('offline-mobile-ui-'),
  );
  final api = ApiClient(
    database: LocalDatabase(file: File('${directory!.path}/data.json')),
  );
  final controller = AppController(
    configStore: ConfigStore(
      configFileProvider: () async =>
          File('${directory.path}/preferences.json'),
    ),
    api: api,
    repository: AppRepository(api),
    enableOfflineTransactions: false,
  )..dashboard = ReportSummary.empty(DateTime.now(), 'month');
  addTearDown(() async {
    controller.dispose();
    await directory.delete(recursive: true);
  });
  return controller;
}

Future<void> _pump(WidgetTester tester, Widget page) async {
  await tester.binding.setSurfaceSize(const Size(360, 760));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: page),
    ),
  );
  await tester.pumpAndSettle();
}
