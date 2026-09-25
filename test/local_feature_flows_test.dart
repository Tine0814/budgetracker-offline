import 'dart:io';

import 'package:expeneses_tracker_offline/core/api_client.dart';
import 'package:expeneses_tracker_offline/core/app_repository.dart';
import 'package:expeneses_tracker_offline/core/config_store.dart';
import 'package:expeneses_tracker_offline/core/local_database.dart';
import 'package:expeneses_tracker_offline/models/domain_models.dart';
import 'package:expeneses_tracker_offline/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File file;
  late DateTime clock;
  late AppController app;
  var sequence = 0;

  String uuid() =>
      '60000000-0000-4000-a000-${(++sequence).toString().padLeft(12, '0')}';
  Account account(int id) => app.accounts.singleWhere((item) => item.id == id);

  AppController createController() {
    final client = ApiClient(
      database: LocalDatabase(file: file, clock: () => clock),
    );
    return AppController(
      configStore: ConfigStore(
        configFileProvider: () async =>
            File('${directory.path}/preferences.json'),
      ),
      api: client,
      repository: AppRepository(client),
      enableOfflineTransactions: false,
    );
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('offline-feature-flows-');
    file = File('${directory.path}/data.json');
    final now = DateTime.now();
    clock = DateTime(now.year, now.month, now.day);
    app = createController();
    await app.initialize();
    expect(app.startupState, StartupState.ready, reason: app.errorMessage);
  });
  tearDown(() async {
    app.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> fundCash([int amount = 100000]) => app.saveTransaction(
    clientUuid: uuid(),
    kind: 'income',
    amountMinor: amount,
    occurredOn: clock,
    accountId: 1,
    categoryId: 1,
  );

  test('controller creates credit card, purchases, and pays debt with service charge', () async {
    await fundCash();
    await app.saveAccount(
      name: 'Test card',
      type: 'credit_card',
      openingBalanceMinor: 0,
      openingDebtMinor: 10000,
      creditLimitMinor: 200000,
      statementDay: 15,
      dueDay: 25,
      color: '#123456',
      scope: FinanceScope.personal,
    );
    final card = app.creditCardAccounts.single;
    expect(card.debtMinor, 10000);
    await app.saveTransaction(
      clientUuid: uuid(),
      kind: 'expense',
      amountMinor: 20000,
      occurredOn: clock,
      accountId: card.id,
      categoryId: 6,
    );
    expect(account(card.id).debtMinor, 30000);
    expect(account(1).balanceMinor, 100000);
    final payment = await app.saveCreditCardPayment(
      scope: FinanceScope.personal,
      clientUuid: uuid(),
      sourceAccountId: 1,
      creditCardAccountId: card.id,
      amountMinor: 15000,
      paidOn: clock,
      serviceChargeMinor: 500,
      note: 'Card payment with fee',
    );
    expect(payment.amountMinor, 15000);
    expect(payment.serviceChargeMinor, 500);
    expect(account(card.id).debtMinor, 15000);
    expect(account(1).balanceMinor, 84500);
    expect(app.dashboard!.expenseMinor, 20500);
    await app.refreshCreditCardPayments();
    expect(app.creditCardPayments.single.clientUuid, payment.clientUuid);
    expect(app.errorMessage, isNull);
  });

  test(
    'controller manual savings interest updates savings without available cash',
    () async {
      await app.saveAccount(
        name: 'Savings',
        type: 'savings',
        openingBalanceMinor: 100000,
        monthlyInterestRateBasisPoints: 0,
        color: '#00AA00',
        scope: FinanceScope.personal,
      );
      final savings = app.savingsAccounts.single;
      final credit = await app.saveSavingsInterestCredit(
        scope: FinanceScope.personal,
        clientUuid: uuid(),
        savingsAccountId: savings.id,
        amountMinor: 1500,
        creditedOn: clock,
        note: 'Bank interest',
      );
      expect(credit.amountMinor, 1500);
      expect(account(savings.id).balanceMinor, 101500);
      expect(app.dashboard!.availableMoneyMinor, 0);
      expect(app.dashboard!.savingsBalanceMinor, 101500);
      await app.refreshSavingsInterestCredits();
      expect(app.savingsInterestCredits.single.id, credit.id);
      expect(app.errorMessage, isNull);
    },
  );

  test('controller automatic savings accrual accepts complete local metadata and is idempotent', () async {
    await app.saveAccount(
      name: 'Monthly savings',
      type: 'savings',
      openingBalanceMinor: 100000,
      monthlyInterestRateBasisPoints: 100,
      color: '#00AA00',
      scope: FinanceScope.personal,
    );
    final savings = app.savingsAccounts.single;
    expect(savings.nextInterestAccrualOn, isNotNull);
    clock = savings.nextInterestAccrualOn!;
    await app.accrueSavingsInterest();
    expect(account(savings.id).balanceMinor, 101000);
    expect(app.savingsInterestCredits, hasLength(1));
    expect(app.savingsInterestCredits.single.amountMinor, 1000);
    await app.accrueSavingsInterest();
    expect(account(savings.id).balanceMinor, 101000);
    expect(app.savingsInterestCredits, hasLength(1));
    expect(app.errorMessage, isNull);
  });

  test(
    'controller installment down payment and payment each debit cash once',
    () async {
      await fundCash();
      await app.saveInstallmentPlan(
        clientUuid: uuid(),
        accountId: 1,
        categoryId: 6,
        installmentMonthlyMinor: 5000,
        installmentMonths: 3,
        installmentStartOn: clock.add(const Duration(days: 1)),
        downPaymentMinor: 3000,
        payee: 'Phone shop',
        note: 'Phone purchase',
      );
      final plan = app.installmentPlans.single;
      expect(plan.downPaymentMinor, 3000);
      expect(plan.contractTotalMinor, 18000);
      expect(plan.remainingObligationMinor, 15000);
      expect(account(1).balanceMinor, 97000);
      final paymentUuid = uuid();
      await app.recordInstallmentPayment(
        plan: plan,
        clientUuid: paymentUuid,
        paidOn: clock,
        accountId: 1,
      );
      final paid = app.installmentPlans.single;
      expect(paid.paidInstallments, 1);
      expect(paid.remainingInstallments, 2);
      expect(paid.totalPaidMinor, 8000);
      expect(paid.remainingObligationMinor, 10000);
      expect(account(1).balanceMinor, 92000);
      expect(app.dashboard!.expenseMinor, 8000);
      await app.recordInstallmentPayment(
        plan: paid,
        clientUuid: paymentUuid,
        paidOn: clock,
        accountId: 1,
        isIdempotentRetry: true,
      );
      expect(account(1).balanceMinor, 92000);
      expect(app.installmentPlans.single.paidInstallments, 1);
      expect(app.errorMessage, isNull);
    },
  );

  test('controller saved gold references and jewelry conversion persist asset and cash changes', () async {
    await app.saveManualGoldPrices(const [
      ManualGoldPriceRate(karat: 18, pricePerGramMinor: 250000),
    ]);
    final rate = app.manualGoldPrices.rateFor(18)!;
    expect(rate.estimateMinor(weightMg: 2000), 500000);
    await app.saveJewelry(
      name: 'Gold ring',
      jewelryType: 'ring',
      karat: 18,
      weightMg: 2000,
      acquiredOn: clock,
      purchaseValueMinor: 400000,
      estimatedValueMinor: 500000,
    );
    final item = app.jewelryItems.single;
    expect(item.estimatedValueMinor, 500000);
    expect(item.unrealizedGainLossMinor, 100000);
    await app.convertJewelry(
      item: item,
      clientUuid: uuid(),
      accountId: 1,
      amountMinor: 450000,
      convertedOn: clock,
    );
    expect(app.jewelryItems.single.status, 'converted');
    expect(app.jewelryItems.single.conversionAmountMinor, 450000);
    expect(account(1).balanceMinor, 450000);
    await app.refreshJewelry();
    expect(app.manualGoldPrices.rateFor(18)!.pricePerGramMinor, 250000);
    expect(app.errorMessage, isNull);
  });

  test(
    'controller saves currency and cutoff budget overrides across restart',
    () async {
      await fundCash();
      await app.saveSettings(
        app.settings.copyWith(
          currencyCode: 'USD',
          locale: 'en_US',
          weekStartsOn: 0,
        ),
      );
      expect(app.currencyCode, 'USD');
      expect(app.locale, 'en_US');
      expect(app.settings.weekStartsOn, 0);
      expect(
        account(1).balanceMinor,
        100000,
        reason: 'Changing currency must not convert existing amounts.',
      );
      final nextMonth = DateTime(clock.year, clock.month + 1, 1);
      await app.createSchedule(
        name: 'Payday plan',
        effectiveFrom: nextMonth,
        firstBudgetMinor: 20000,
        secondBudgetMinor: 30000,
      );
      await app.setAnchor(nextMonth);
      final first = app.cutoffPeriods.firstWhere(
        (period) => period.startsOn == nextMonth,
      );
      expect(first.budgetMinor, 20000);
      await app.updateCutoffBudget(first, 25000);
      expect(
        app.cutoffPeriods
            .singleWhere((period) => period.id == first.id)
            .budgetMinor,
        25000,
      );
      expect(
        app.cutoffPeriods
            .singleWhere((period) => period.id == first.id)
            .isBudgetOverridden,
        isTrue,
      );
      final restarted = createController();
      addTearDown(restarted.dispose);
      await restarted.initialize();
      expect(
        restarted.startupState,
        StartupState.ready,
        reason: restarted.errorMessage,
      );
      expect(restarted.currencyCode, 'USD');
      expect(restarted.settings.weekStartsOn, 0);
      await restarted.setAnchor(nextMonth);
      final restored = restarted.cutoffPeriods.singleWhere(
        (period) => period.id == first.id,
      );
      expect(restored.budgetMinor, 25000);
      await restarted.resetCutoffBudget(restored);
      expect(
        restarted.cutoffPeriods
            .singleWhere((period) => period.id == first.id)
            .budgetMinor,
        20000,
      );
      expect(restarted.errorMessage, isNull);
    },
  );
}
