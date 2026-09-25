import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:expeneses_tracker_offline/core/api_client.dart';
import 'package:expeneses_tracker_offline/core/local_database.dart';

void main() {
  late Directory directory;
  late File file;
  late LocalDatabase db;
  late DateTime now;
  var counter = 0;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'offline-backup-validation-',
    );
    file = File('${directory.path}/data.json');
    now = DateTime(2026, 8, 25, 12);
    db = LocalDatabase(file: file, clock: () => now);
    counter = 0;
  });
  tearDown(() => directory.delete(recursive: true));

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await db.request(
      'POST',
      path,
      body: {'client_uuid': 'backup-fixture-${++counter}', ...body},
    );
    return Map<String, dynamic>.from(response['data'] as Map);
  }

  Future<String> completeBackup() async {
    await post('/cutoff-schedules', {
      'name': 'Paydays',
      'effective_from': '2026-08-01',
      'rules': [
        {
          'label': 'First',
          'start_day': 1,
          'default_budget_minor': 100000,
          'category_budgets': [
            {'category_id': 3, 'amount_minor': 50000},
          ],
        },
        {'label': 'Second', 'start_day': 16, 'default_budget_minor': 100000},
      ],
    });
    await post('/transactions', {
      'kind': 'income',
      'amount_minor': 1000000,
      'occurred_on': '2026-08-25',
      'account_id': 1,
      'category_id': 1,
    });
    final savings = await post('/accounts', {
      'name': 'Savings',
      'type': 'savings',
      'opening_balance_minor': 0,
      'monthly_interest_rate_basis_points': 100,
    });
    final card = await post('/accounts', {
      'name': 'Card',
      'type': 'credit_card',
      'opening_debt_minor': 5000,
      'credit_limit_minor': 20000,
    });
    await post('/account-transfers', {
      'source_account_id': 1,
      'destination_account_id': savings['id'],
      'amount_minor': 50000,
      'service_charge_minor': 100,
      'transferred_on': '2026-08-25',
    });
    await post('/credit-card-payments', {
      'source_account_id': 1,
      'credit_card_account_id': card['id'],
      'amount_minor': 1000,
      'service_charge_minor': 50,
      'paid_on': '2026-08-25',
    });
    await post('/savings-interest-credits', {
      'savings_account_id': savings['id'],
      'amount_minor': 100,
      'credited_on': '2026-08-25',
    });
    final plan = await post('/installment-plans', {
      'account_id': 1,
      'category_id': 6,
      'installment_months': 2,
      'installment_monthly_minor': 1000,
      'installment_start_on': '2026-08-25',
      'down_payment_minor': 500,
    });
    await post('/installment-plans/${plan['id']}/payments', {
      'version': 1,
      'paid_on': '2026-08-25',
    });
    final jewelry = await post('/jewelry', {
      'name': 'Ring',
      'jewelry_type': 'ring',
      'karat': 18,
      'weight_mg': 2500,
      'estimated_value_minor': 100000,
      'purchase_value_minor': 80000,
      'acquired_on': '2026-01-01',
    });
    await post('/jewelry/${jewelry['id']}/convert', {
      'account_id': 1,
      'amount_minor': 110000,
      'converted_on': '2026-08-25',
    });
    await db.request(
      'PUT',
      '/gold-price/manual',
      body: {
        'rates': [
          {'karat': 24, 'price_per_gram_minor': 500000},
        ],
      },
    );
    final cutoff = await db.request(
      'GET',
      '/cutoff-periods/current',
      query: {'date': '2026-08-25'},
    );
    await db.request(
      'PUT',
      '/cutoff-periods/${cutoff['data']['id']}/budget',
      body: {
        'total_budget_minor': 125000,
        'items': [
          {'category_id': 3, 'amount_minor': 60000},
        ],
      },
    );
    now = DateTime(2026, 9, 25, 12);
    await db.request('POST', '/savings-interest-credits/accrue');
    return db.exportBackup();
  }

  test('seed and complete exported ledger validate and preserve every balance on restart', () async {
    await db.request('GET', '/accounts');
    final seed = await db.exportBackup();
    final seedCopy = LocalDatabase(
      file: File('${directory.path}/seed.json'),
      clock: () => now,
    );
    await seedCopy.importBackup(seed);
    expect(await seedCopy.exportBackup(), seed);
    final backup = await completeBackup();
    final originalAccounts = await db.request(
      'GET',
      '/accounts',
      query: {'include_archived': 1},
    );
    final copy = LocalDatabase(
      file: File('${directory.path}/copy.json'),
      clock: () => now,
    );
    await copy.importBackup(backup);
    expect(await copy.exportBackup(), backup);
    expect(
      await copy.request('GET', '/accounts', query: {'include_archived': 1}),
      originalAccounts,
    );
    final restarted = LocalDatabase(file: file, clock: () => now);
    expect(
      await restarted.request(
        'GET',
        '/accounts',
        query: {'include_archived': 1},
      ),
      originalAccounts,
    );
    final report = await restarted.request(
      'GET',
      '/reports/summary',
      query: {'period': 'year', 'anchor': '2026-09-25'},
    );
    expect(report['data']['income_minor'], 1110601);
  });

  test('malformed financial records and broken links cannot replace a valid ledger', () async {
    final original = await completeBackup();
    final bytes = await file.readAsString();
    final corruptions = <String, void Function(Map<String, dynamic>)>{
      'negative income': (d) => d['transactions'][0]['amount_minor'] = -100,
      'missing amount': (d) =>
          (d['transactions'][0] as Map).remove('amount_minor'),
      'missing kind': (d) => (d['transactions'][0] as Map).remove('kind'),
      'non-calendar date': (d) =>
          d['transactions'][0]['occurred_on'] = '2026-02-31',
      'missing account': (d) =>
          (d['transactions'][0] as Map).remove('account_id'),
      'kind mismatch': (d) => d['transactions'][0]['category_id'] = 3,
      'duplicate transaction': (d) => (d['transactions'] as List).add(
        Map<String, dynamic>.from(d['transactions'][0] as Map),
      ),
      'missing fee': (d) =>
          d['account_transfers'][0]['service_charge_transaction_id'] = 99999,
      'mismatched fee': (d) =>
          d['account_transfers'][0]['service_charge_minor'] = 101,
      'mismatched card payment': (d) =>
          d['credit_card_payments'][0]['credit_card_account_id'] = 1,
      'missing interest transaction': (d) =>
          d['savings_interest_credits'][0]['interest_transaction_id'] = null,
      'bad automatic interest arithmetic': (d) =>
          (d['savings_interest_credits'] as List)
                  .last['calculation_balance_minor'] =
              100,
      'duplicate installment number': (d) =>
          (d['transactions'] as List).firstWhere(
            (t) => t['source_type'] == 'installment_plan_payment',
          )['installment_number'] = 0,
      'missing down payment': (d) => (d['transactions'] as List).removeWhere(
        (t) => t['source_type'] == 'installment_plan_down_payment',
      ),
      'sale amount mismatch': (d) =>
          d['jewelry'][0]['conversion_amount_minor'] = 1,
      'wrong savings schedule': (d) => (d['accounts'] as List).firstWhere(
        (a) => a['type'] == 'savings',
      )['next_interest_accrual_on'] = '2026-08-01',
      'budget overallocation': (d) =>
          (d['cutoff_periods'] as List).first['budget_items'] = [
            {'category_id': 3, 'amount_minor': 999999},
          ],
      'non-monthly schedule': (d) =>
          d['cutoff_schedules'][0]['rules'][0]['start_day'] = 2,
      'overlapping periods': (d) => (d['cutoff_periods'] as List).add({
        ...Map<String, dynamic>.from(d['cutoff_periods'][0] as Map),
        'id': 999,
      }),
      'unsupported week start': (d) =>
          d['settings']['week_starts_on'] = 'Monday',
      'unsupported locale': (d) =>
          d['settings']['locale'] = 'not_a_real_locale',
      'negative asset opening balance': (d) =>
          d['accounts'][0]['opening_balance_minor'] = -1,
      'duplicate gold price': (d) => (d['gold_price_rates'] as List).add(
        Map<String, dynamic>.from(d['gold_price_rates'][0] as Map),
      ),
    };
    for (final corruption in corruptions.entries) {
      final altered = jsonDecode(original) as Map<String, dynamic>;
      corruption.value(altered);
      await expectLater(
        db.importBackup(jsonEncode(altered)),
        throwsFormatException,
        reason: corruption.key,
      );
      expect(await db.exportBackup(), original, reason: corruption.key);
      expect(await file.readAsString(), bytes, reason: corruption.key);
    }
  });

  test('a corrupt primary file is preserved and can be restored without loading it', () async {
    final backup = await completeBackup();
    await file.writeAsString('{corrupt');
    final restarted = LocalDatabase(file: file, clock: () => now);
    await expectLater(
      restarted.request('GET', '/health'),
      throwsA(isA<ApiException>()),
    );
    expect(await file.readAsString(), '{corrupt');
    await restarted.importBackup(backup);
    final accounts = await restarted.request('GET', '/accounts');
    expect(accounts['data'], hasLength(3));
    expect(await restarted.exportBackup(), backup);
  });
}
