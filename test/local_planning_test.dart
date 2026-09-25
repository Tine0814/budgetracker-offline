import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:expenses_tracker_offline/core/api_client.dart';
import 'package:expenses_tracker_offline/core/local_database.dart';
import 'package:expenses_tracker_offline/models/domain_models.dart';

void main() {
  late Directory directory;
  late LocalDatabase database;
  var uuid = 0;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('offline_planning_test_');
    database = LocalDatabase(
      file: File('${directory.path}/data.json'),
      clock: () => DateTime(2026, 9, 25, 12),
    );
    uuid = 0;
  });

  tearDown(() async => directory.delete(recursive: true));

  String reference() =>
      '10000000-0000-4000-8000-${(++uuid).toString().padLeft(12, '0')}';

  Future<Map<String, dynamic>> data(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, Object?> query = const {},
  }) async {
    final response = await database.request(
      method,
      path,
      body: body,
      query: query,
    );
    return Map<String, dynamic>.from(response['data'] as Map);
  }

  Future<Map<String, dynamic>> transaction(
    String kind,
    int amount,
    String on, {
    int account = 1,
    int? category,
  }) => data(
    'POST',
    '/transactions',
    body: {
      'client_uuid': reference(),
      'kind': kind,
      'amount_minor': amount,
      'occurred_on': on,
      'account_id': account,
      'category_id': category ?? (kind == 'income' ? 1 : 3),
    },
  );

  Future<Map<String, dynamic>> schedule(
    String from,
    int firstBudget,
    int secondBudget,
  ) => data(
    'POST',
    '/cutoff-schedules',
    body: {
      'name': 'Paydays',
      'effective_from': from,
      'rules': [
        {
          'label': 'First payday',
          'start_day': 1,
          'default_budget_minor': firstBudget,
          'category_budgets': [
            {'category_id': 3, 'amount_minor': firstBudget ~/ 2},
          ],
        },
        {
          'label': 'Second payday',
          'start_day': 16,
          'default_budget_minor': secondBudget,
        },
      ],
    },
  );

  test(
    'reports count expenses and transfer fees but exclude transfer principal',
    () async {
      await schedule('2026-09-01', 100000, 150000);
      final bank = await data(
        'POST',
        '/accounts',
        body: {
          'name': 'Savings',
          'type': 'savings',
          'opening_balance_minor': 0,
          'monthly_interest_rate_basis_points': 0,
          'color': '#008800',
        },
      );
      await transaction('income', 200000, '2026-09-04');
      await transaction('expense', 10000, '2026-09-06');
      await data(
        'POST',
        '/account-transfers',
        body: {
          'client_uuid': reference(),
          'source_account_id': 1,
          'destination_account_id': bank['id'],
          'amount_minor': 10000,
          'service_charge_minor': 500,
          'transferred_on': '2026-09-08',
        },
      );

      final result = await database.request(
        'GET',
        '/reports/summary',
        query: {'period': 'month', 'anchor': '2026-09-25'},
      );
      final report = ReportSummary.fromJson(result, fallbackPeriod: 'month');
      expect(report.incomeMinor, 200000);
      expect(report.expenseMinor, 10500);
      expect(report.netMinor, 189500);
      expect(report.cashBalanceMinor, 189500);
      expect(report.savingsBalanceMinor, 10000);
      expect(report.availableMoneyMinor, 179500);
      expect(report.budgetMinor, 250000);
      expect(report.remainingBudgetMinor, 239500);
      expect(
        report.categories.fold(
          0,
          (sum, category) => sum + category.amountMinor,
        ),
        10500,
      );
      expect(report.buckets.length, 30);
      expect(
        report.buckets.fold(0, (sum, day) => sum + day.expenseMinor),
        10500,
      );

      final previous = await data(
        'GET',
        '/dashboard',
        query: {'period': 'month', 'anchor': '2026-08-15'},
      );
      expect(previous['income_minor'], 0);
      expect(previous['cash_balance_minor'], 0);
      expect(previous['budget_minor'], 0);
      final week = await data(
        'GET',
        '/dashboard',
        query: {'period': 'week', 'anchor': '2026-09-08'},
      );
      expect(week['budget_minor'], isNull);
      expect(week['range'], {'from': '2026-09-07', 'to': '2026-09-13'});
    },
  );

  test('cutoff defaults handle leap months and budget history survives new schedules and restart', () async {
    final leap = await data(
      'GET',
      '/cutoff-periods/current',
      query: {'date': '2024-02-29'},
    );
    expect(leap['starts_on'], '2024-02-16');
    expect(leap['ends_on'], '2024-02-29');
    await schedule('2026-09-01', 100000, 150000);
    final september = await data(
      'GET',
      '/cutoff-periods/current',
      query: {'date': '2026-09-05'},
    );
    await data(
      'PUT',
      '/cutoff-periods/${september['id']}/budget',
      body: {
        'total_budget_minor': 80000,
        'items': [
          {'category_id': 3, 'amount_minor': 70000},
        ],
      },
    );
    await schedule('2026-10-01', 200000, 250000);
    database = LocalDatabase(
      file: File('${directory.path}/data.json'),
      clock: () => DateTime(2026, 9, 25),
    );
    final historic = await data(
      'GET',
      '/cutoff-periods/current',
      query: {'date': '2026-09-05'},
    );
    expect(historic['id'], september['id']);
    expect(historic['budget_minor'], 80000);
    expect(historic['is_budget_overridden'], true);
    final reset = await data(
      'DELETE',
      '/cutoff-periods/${september['id']}/budget',
    );
    expect(reset['budget_minor'], 100000);
    expect(reset['is_budget_overridden'], false);
    expect((reset['budget_items'] as List).single['amount_minor'], 50000);
    final october = await data(
      'GET',
      '/cutoff-periods/current',
      query: {'date': '2026-10-05'},
    );
    expect(october['budget_minor'], 200000);
  });

  test('schedule changes protect existing transactions and invalid budgets roll back', () async {
    await transaction('income', 100000, '2026-09-02');
    expect(
      schedule('2026-09-01', 100000, 100000),
      throwsA(isA<ApiException>()),
    );
    final cutoff = await data(
      'GET',
      '/cutoff-periods/current',
      query: {'date': '2026-09-02'},
    );
    await expectLater(
      database.request(
        'PUT',
        '/cutoff-periods/${cutoff['id']}/budget',
        body: {
          'total_budget_minor': 1000,
          'items': [
            {'category_id': 3, 'amount_minor': 2000},
          ],
        },
      ),
      throwsA(isA<ApiException>()),
    );
    final unchanged = await data(
      'GET',
      '/cutoff-periods/current',
      query: {'date': '2026-09-02'},
    );
    expect(unchanged['budget_minor'], 0);
    expect(unchanged['is_budget_overridden'], false);
  });

  test(
    'jewelry sale is recorded once and leaves a protected income transaction',
    () async {
      final item = await data(
        'POST',
        '/jewelry',
        body: {
          'name': 'Ring',
          'jewelry_type': 'ring',
          'karat': 18,
          'weight_mg': 2000,
          'acquired_on': '2026-06-01',
          'purchase_value_minor': 100000,
          'estimated_value_minor': 125000,
        },
      );
      final before = await data(
        'GET',
        '/dashboard',
        query: {'period': 'month', 'anchor': '2026-09-25'},
      );
      expect(before['cash_balance_minor'], 0);
      expect(before['jewelry_portfolio']['unrealized_gain_loss_minor'], 25000);
      final conversion = <String, dynamic>{
        'client_uuid': reference(),
        'account_id': 1,
        'amount_minor': 120000,
        'converted_on': '2026-09-20',
      };
      final sold = await data(
        'POST',
        '/jewelry/${item['id']}/convert',
        body: conversion,
      );
      final replay = await data(
        'POST',
        '/jewelry/${item['id']}/convert',
        body: conversion,
      );
      expect(sold['status'], 'converted');
      expect(
        replay['conversion_transaction_id'],
        sold['conversion_transaction_id'],
      );
      final after = await data(
        'GET',
        '/dashboard',
        query: {'period': 'month', 'anchor': '2026-09-25'},
      );
      expect(after['cash_balance_minor'], 120000);
      expect(after['income_minor'], 120000);
      expect(after['jewelry_portfolio']['held_count'], 0);
      expect((after['recent_transactions'] as List).length, 1);
      await expectLater(
        database.request(
          'DELETE',
          '/transactions/${sold['conversion_transaction_id']}',
          body: {'version': 1},
        ),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        database.request(
          'POST',
          '/jewelry/${item['id']}/convert',
          body: {...conversion, 'client_uuid': reference()},
        ),
        throwsA(isA<ApiException>()),
      );
      await database.request('DELETE', '/jewelry/${item['id']}');
      final archived = await data(
        'GET',
        '/dashboard',
        query: {'period': 'month', 'anchor': '2026-09-25'},
      );
      expect(archived['cash_balance_minor'], 120000);
    },
  );

  test('manual gold prices persist and estimate integer minor units without a live quote', () async {
    await expectLater(
      database.request('GET', '/gold-price'),
      throwsA(isA<ApiException>()),
    );
    final response = await database.request(
      'PUT',
      '/gold-price/manual',
      body: {
        'rates': [
          {'karat': 18, 'price_per_gram_minor': 375000},
          {'karat': 24, 'price_per_gram_minor': 500000},
        ],
      },
    );
    final manual = ManualGoldPriceList.fromJson(response);
    expect(manual.rateFor(18)!.estimateMinor(weightMg: 2500), 937500);
    final quote = GoldPriceQuote.fromJson(
      await database.request('GET', '/gold-price', query: {'refresh': 1}),
    );
    expect(quote.source, 'manual');
    expect(quote.estimateMinor(weightMg: 2500, karat: 18), 937500);
    database = LocalDatabase(
      file: File('${directory.path}/data.json'),
      clock: () => DateTime(2026, 9, 26),
    );
    final reopened = ManualGoldPriceList.fromJson(
      await database.request('GET', '/gold-price/manual'),
    );
    expect(reopened.rateFor(24)!.pricePerGramMinor, 500000);
    await expectLater(
      database.request(
        'PUT',
        '/gold-price/manual',
        body: {
          'rates': [
            {'karat': 24, 'price_per_gram_minor': 500000},
            {'karat': 24, 'price_per_gram_minor': 600000},
          ],
        },
      ),
      throwsA(isA<ApiException>()),
    );
    final unchanged = ManualGoldPriceList.fromJson(
      await database.request('GET', '/gold-price/manual'),
    );
    expect(unchanged.rateFor(24)!.pricePerGramMinor, 500000);
  });
}
