import 'dart:io';

import 'package:expenses_tracker_offline/core/api_client.dart';
import 'package:expenses_tracker_offline/core/app_repository.dart';
import 'package:expenses_tracker_offline/core/config_store.dart';
import 'package:expenses_tracker_offline/core/local_database.dart';
import 'package:expenses_tracker_offline/models/domain_models.dart';
import 'package:expenses_tracker_offline/state/app_controller.dart';
import 'package:expenses_tracker_offline/theme/app_theme.dart';
import 'package:expenses_tracker_offline/ui/pages/dashboard_page.dart';
import 'package:expenses_tracker_offline/ui/pages/reports_page.dart';
import 'package:expenses_tracker_offline/ui/pages/settings_page.dart';
import 'package:expenses_tracker_offline/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _jewelrySwitch = Key('settings-show-jewelry-in-reports');
const _creditCardsSwitch = Key('settings-show-credit-cards-in-reports');

void main() {
  for (final width in <double>[320, 1280]) {
    testWidgets(
      'report visibility is independent and reversible at ${width.toInt()}px',
      (tester) async {
        final controller = _ReportController();
        addTearDown(controller.dispose);
        await _setSize(tester, Size(width, 760));

        // Start with the defaults, exercise each combination, then show both
        // again. The same financial summary survives every display change.
        for (final visibility in [
          (true, true),
          (false, true),
          (true, false),
          (false, false),
          (true, true),
        ]) {
          controller.settings = controller.settings.copyWith(
            showJewelryInReports: visibility.$1,
            showCreditCardsInReports: visibility.$2,
          );
          await _pump(
            tester,
            DashboardPage(controller: controller, onOpenTransactions: () {}),
          );
          expect(
            find.byKey(const Key('dashboard-gold-position-card')),
            visibility.$1 ? findsOneWidget : findsNothing,
          );
          for (final key in [
            'dashboard-credit-card-debt-card',
            'dashboard-next-month-credit-card-billing-panel',
          ]) {
            expect(
              find.byKey(Key(key)),
              visibility.$2 ? findsOneWidget : findsNothing,
            );
          }
          _expectAmount(tester, 'dashboard-income-metric', 120000);
          _expectAmount(tester, 'dashboard-expenses-metric', 35000);
          _expectAmount(tester, 'dashboard-net-cashflow-metric', 85000);
          expect(
            find.byKey(const Key('dashboard-budget-panel')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);

          await _pump(tester, ReportsPage(controller: controller));
          for (final key in ['credit-debt', 'net-position']) {
            expect(
              find.byKey(Key('reports-personal-kpi-$key')),
              visibility.$2 ? findsOneWidget : findsNothing,
            );
          }
          _expectAmount(tester, 'reports-personal-kpi-income', 120000);
          _expectAmount(tester, 'reports-personal-kpi-expenses', 35000);
          _expectAmount(tester, 'reports-personal-kpi-net', 85000);
          _expectAmount(tester, 'reports-personal-kpi-budget', 65000);
          expect(controller.dashboard, same(controller.reportSummary));
          expect(controller.reportSummary!.creditCardDebtMinor, 25000);
          expect(
            controller.reportSummary!.jewelryPortfolio.totalEstimatedValueMinor,
            150000,
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets('report preferences save locally and reopen on a narrow phone', (
    tester,
  ) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('report-visibility-ui-'),
    ))!;
    addTearDown(() => directory.delete(recursive: true));
    final dataFile = File('${directory.path}/data.json');
    final controller = (await tester.runAsync(
      () async => _ReportController(dataFile: dataFile),
    ))!;
    addTearDown(controller.dispose);
    await _setSize(tester, const Size(320, 760));
    await _pump(tester, SettingsPage(controller: controller));

    _expectSwitch(tester, _jewelrySwitch, true);
    _expectSwitch(tester, _creditCardsSwitch, true);
    await _toggle(tester, _jewelrySwitch);
    await _toggle(tester, _creditCardsSwitch);
    // Editing preferences takes effect only after the existing save action.
    expect(controller.settings.showJewelryInReports, isTrue);
    expect(controller.settings.showCreditCardsInReports, isTrue);
    await _save(tester, controller);
    expect(controller.settings.showJewelryInReports, isFalse);
    expect(controller.settings.showCreditCardsInReports, isFalse);

    // Construct the database in the same real-async zone as its first read:
    // its initial request queue must not wait for a fake-async microtask.
    final reopened = (await tester.runAsync(() async {
      final next = _ReportController(dataFile: dataFile);
      next.settings = await next.repository.settings();
      return next;
    }))!;
    addTearDown(reopened.dispose);
    await _pump(tester, const SizedBox.shrink());
    await _pump(tester, SettingsPage(controller: reopened));
    _expectSwitch(tester, _jewelrySwitch, false);
    _expectSwitch(tester, _creditCardsSwitch, false);

    await _toggle(tester, _jewelrySwitch);
    await _save(tester, reopened);
    expect(reopened.settings.showJewelryInReports, isTrue);
    expect(reopened.settings.showCreditCardsInReports, isFalse);

    final persisted = (await tester.runAsync(
      () =>
          AppRepository(ApiClient(database: LocalDatabase(file: dataFile)))
              .settings(),
    ))!;
    expect(persisted.showJewelryInReports, isTrue);
    expect(persisted.showCreditCardsInReports, isFalse);
    expect(persisted.currencyCode, controller.settings.currencyCode);
    expect(persisted.locale, controller.settings.locale);
    expect(persisted.weekStartsOn, controller.settings.weekStartsOn);
    expect(tester.takeException(), isNull);
  });
}

void _expectAmount(WidgetTester tester, String key, int amount) {
  final money = find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byType(MoneyLabel),
  );
  expect(money, findsOneWidget);
  expect(tester.widget<MoneyLabel>(money).minorUnits, amount);
}

void _expectSwitch(WidgetTester tester, Key key, bool value) {
  expect(tester.widget<SwitchListTile>(find.byKey(key)).value, value);
}

Future<void> _toggle(WidgetTester tester, Key key) async {
  final toggle = find.byKey(key);
  await tester.ensureVisible(toggle);
  await tester.tap(toggle);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _save(WidgetTester tester, _ReportController controller) async {
  final save = find.text('Save preferences');
  await tester.ensureVisible(save);
  await tester.runAsync(() async {
    await tester.tap(save);
    await controller.settingsSave;
  });
  await tester.pumpAndSettle();
  expect(controller.errorMessage, isNull);
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _pump(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: page),
    ),
  );
  await tester.pumpAndSettle();
}

class _ReportController extends AppController {
  factory _ReportController({File? dataFile}) =>
      _ReportController._(ApiClient(database: LocalDatabase(file: dataFile)));

  _ReportController._(ApiClient api)
    : super(
        configStore: ConfigStore(),
        api: api,
        repository: AppRepository(api),
        enableOfflineTransactions: false,
      ) {
    accounts = const [
      Account(
        id: 1,
        name: 'Cash',
        type: 'cash',
        openingBalanceMinor: 200000,
        balanceMinor: 285000,
      ),
      Account(
        id: 2,
        name: 'Credit card',
        type: 'credit_card',
        openingBalanceMinor: 0,
        balanceMinor: -25000,
        creditLimitMinor: 500000,
        statementDay: 15,
        dueDay: 5,
      ),
    ];
    dashboard = ReportSummary(
      period: 'month',
      label: 'September 2026',
      startsOn: DateTime(2026, 9, 1),
      endsOn: DateTime(2026, 9, 30),
      incomeMinor: 120000,
      expenseMinor: 35000,
      netMinor: 85000,
      hasBudget: true,
      budgetMinor: 100000,
      remainingBudgetMinor: 65000,
      cashBalanceMinor: 285000,
      creditCardDebtMinor: 25000,
      netPositionMinor: 260000,
      accounts: accounts,
      jewelryPortfolio: const JewelryPortfolioSummary(
        heldCount: 1,
        costKnownCount: 1,
        totalEstimatedValueMinor: 150000,
        knownPurchaseCostMinor: 100000,
        unrealizedGainLossMinor: 50000,
      ),
    );
    reportSummary = dashboard;
  }

  Future<void>? settingsSave;

  @override
  Future<void> saveSettings(AppSettings next) =>
      settingsSave = super.saveSettings(next);

  @override
  Future<void> loadReport(
    String period, {
    bool propagateError = false,
    bool networkOnly = false,
  }) async {}
}
