import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:expenses_tracker_offline/core/api_client.dart';
import 'package:expenses_tracker_offline/core/local_database.dart';
import 'package:expenses_tracker_offline/models/domain_models.dart';

void main() {
  late Directory directory;
  late File file;
  late LocalDatabase db;
  late DateTime now;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('offline-ledger-');
    file = File('${directory.path}/data.json');
    now = DateTime(2026, 1, 31, 12);
    db = LocalDatabase(file: file, clock: () => now);
  });
  tearDown(() async => directory.delete(recursive: true));

  Future<Map<String, dynamic>> data(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final response = await db.request(method, path, body: body);
    return Map<String, dynamic>.from(response['data'] as Map);
  }

  Future<Map<String, dynamic>> account(
    String name,
    int opening, {
    String type = 'bank',
    int rate = 0,
    int? limit,
  }) => data('POST', '/accounts', {
    'name': name,
    'type': type,
    'scope': 'personal',
    if (type == 'credit_card')
      'opening_debt_minor': opening
    else
      'opening_balance_minor': opening,
    if (type == 'credit_card') 'credit_limit_minor': limit,
    if (type == 'savings') 'monthly_interest_rate_basis_points': rate,
  });

  test('transactions survive restart, update balances, filter and reject stale writes', () async {
    final wallet = await account('Wallet', 10000);
    final tx = await data('POST', '/transactions', {
      'client_uuid': 'lunch',
      'kind': 'expense',
      'amount_minor': 2500,
      'occurred_on': '2026-01-31',
      'account_id': wallet['id'],
      'category_id': 3,
      'payee': 'Lunch',
    });
    expect(TransactionRecord.fromJson(tx).amountMinor, 2500);
    expect(
      (await data('GET', '/accounts/${wallet['id']}'))['balance_minor'],
      7500,
    );
    await data('PATCH', '/transactions/${tx['id']}', {
      'version': 1,
      'amount_minor': 3000,
    });
    await expectLater(
      data('PATCH', '/transactions/${tx['id']}', {
        'version': 1,
        'amount_minor': 4000,
      }),
      throwsA(isA<ApiException>()),
    );
    db = LocalDatabase(file: file, clock: () => now);
    expect(
      (await data('GET', '/accounts/${wallet['id']}'))['balance_minor'],
      7000,
    );
    final found = await db.request(
      'GET',
      '/transactions',
      query: {'search': 'lunch', 'account_id': wallet['id'], 'per_page': 1},
    );
    expect(found['meta']['total'], 1);
    expect(found['data'][0]['amount_minor'], 3000);
    await db.request(
      'DELETE',
      '/transactions/${tx['id']}',
      body: {'version': 2},
    );
    expect(
      (await data('GET', '/accounts/${wallet['id']}'))['balance_minor'],
      10000,
    );
  });

  test(
    'transfer principal is not income or expense and fee posts exactly once',
    () async {
      final source = await account('Bank', 10000);
      final destination = await account('Savings', 0, type: 'savings');
      final payload = {
        'client_uuid': 'move-1',
        'source_account_id': source['id'],
        'destination_account_id': destination['id'],
        'amount_minor': 4000,
        'service_charge_minor': 100,
        'transferred_on': '2026-01-31',
      };
      final first = await data('POST', '/account-transfers', payload);
      final second = await data('POST', '/account-transfers', payload);
      final transfer = AccountTransfer.fromJson(first);
      expect(first['id'], second['id']);
      expect(transfer.hasEffectMetadata, isTrue);
      expect(transfer.hasAvailableMoneyEffectMetadata, isTrue);
      expect(transfer.availableMoneyChangeMinor, -4100);
      expect(
        (await data('GET', '/accounts/${source['id']}'))['balance_minor'],
        5900,
      );
      expect(
        (await data('GET', '/accounts/${destination['id']}'))['balance_minor'],
        4000,
      );
      final history = await db.request('GET', '/transactions');
      expect(history['meta']['total'], 1);
      expect(history['data'][0]['amount_minor'], 100);
      expect(history['data'][0]['source_type'], 'account_transfer_fee');
      await expectLater(
        db.request(
          'DELETE',
          '/transactions/${history['data'][0]['id']}',
          body: {'version': 1},
        ),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        data('POST', '/account-transfers', {...payload, 'amount_minor': 5000}),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test('concurrent debits serialize and a failed transfer leaves no partial posting', () async {
    final source = await account('Source', 10000);
    final destination = await account('Destination', 0);
    Future<Object?> transfer(String uuid) async {
      try {
        return await data('POST', '/account-transfers', {
          'client_uuid': uuid,
          'source_account_id': source['id'],
          'destination_account_id': destination['id'],
          'amount_minor': 6000,
          'service_charge_minor': 100,
          'transferred_on': '2026-01-31',
        });
      } catch (error) {
        return error;
      }
    }

    final results = await Future.wait([transfer('first'), transfer('second')]);
    expect(results.whereType<ApiException>().length, 1);
    expect(
      (await data('GET', '/accounts/${source['id']}'))['balance_minor'],
      3900,
    );
    expect(
      (await data('GET', '/accounts/${destination['id']}'))['balance_minor'],
      6000,
    );
    final transfers = await db.request('GET', '/account-transfers');
    final transactions = await db.request('GET', '/transactions');
    expect(transfers['meta']['total'], 1);
    expect(transactions['meta']['total'], 1);
  });

  test('credit card expenses increase debt and payments reduce debt without double expenses', () async {
    final source = await account('Bank', 20000);
    final card = await account('Card', 2000, type: 'credit_card', limit: 10000);
    await data('POST', '/transactions', {
      'client_uuid': 'card-purchase',
      'kind': 'expense',
      'amount_minor': 3000,
      'occurred_on': '2026-01-31',
      'account_id': card['id'],
      'category_id': 6,
    });
    expect((await data('GET', '/accounts/${card['id']}'))['debt_minor'], 5000);
    final payment = await data('POST', '/credit-card-payments', {
      'client_uuid': 'pay-card',
      'source_account_id': source['id'],
      'credit_card_account_id': card['id'],
      'amount_minor': 4000,
      'service_charge_minor': 50,
      'paid_on': '2026-01-31',
    });
    final parsed = CreditCardPayment.fromJson(payment);
    expect(parsed.debtReductionMinor, 4000);
    expect(parsed.netPositionChangeMinor, -50);
    expect((await data('GET', '/accounts/${card['id']}'))['debt_minor'], 1000);
    expect(
      (await data('GET', '/accounts/${source['id']}'))['balance_minor'],
      15950,
    );
    await expectLater(
      data('POST', '/credit-card-payments', {
        'client_uuid': 'overpay',
        'source_account_id': source['id'],
        'credit_card_account_id': card['id'],
        'amount_minor': 1001,
        'paid_on': '2026-01-31',
      }),
      throwsA(isA<ApiException>()),
    );
    await expectLater(
      data('POST', '/transactions', {
        'client_uuid': 'over-limit',
        'kind': 'expense',
        'amount_minor': 10000,
        'occurred_on': '2026-01-31',
        'account_id': card['id'],
        'category_id': 6,
      }),
      throwsA(isA<ApiException>()),
    );
    final history = await db.request('GET', '/transactions');
    expect(
      (history['data'] as List).fold<int>(
        0,
        (sum, tx) => sum + tx['amount_minor'] as int,
      ),
      3050,
    );
  });

  test('monthly interest catches up, compounds with integer rounding, and remains idempotent', () async {
    final savings = await account(
      'Savings',
      100005,
      type: 'savings',
      rate: 100,
    );
    expect(savings['next_interest_accrual_on'], '2026-02-28');
    now = DateTime(2026, 3, 31, 12);
    final result = await data('POST', '/savings-interest-credits/accrue', {});
    expect(result['created_count'], 2);
    expect(
      SavingsInterestAccrualResult.fromJson(result).hasConsistentMetadata,
      isTrue,
    );
    expect(
      (await data('GET', '/accounts/${savings['id']}'))['balance_minor'],
      102015,
    );
    expect(
      (await data(
        'GET',
        '/accounts/${savings['id']}',
      ))['next_interest_accrual_on'],
      '2026-04-30',
    );
    expect(
      (await data(
        'POST',
        '/savings-interest-credits/accrue',
        {},
      ))['created_count'],
      0,
    );
    final credits = await db.request('GET', '/savings-interest-credits');
    expect(credits['meta']['total'], 2);
    final parsed = SavingsInterestCredit.fromJson(credits['data'][0]);
    expect(parsed.creditMethod, 'automatic');
    expect(parsed.calculationBalanceMinor, 101005);
    expect(
      parsed.interestTransaction!.category!.categoryRole,
      'savings_interest',
    );
    expect(parsed.interestTransaction!.clientUuid, parsed.clientUuid);
    await expectLater(
      data('POST', '/transactions', {
        'client_uuid': 'historical-edit',
        'kind': 'income',
        'amount_minor': 1000,
        'occurred_on': '2026-02-01',
        'account_id': savings['id'],
        'category_id': 2,
      }),
      throwsA(isA<ApiException>()),
    );
    db = LocalDatabase(file: file, clock: () => now);
    expect(
      (await data('GET', '/accounts/${savings['id']}'))['balance_minor'],
      102015,
    );
  });

  test(
    'manual interest prevents an automatic duplicate for the same month',
    () async {
      final savings = await account(
        'Savings',
        10000,
        type: 'savings',
        rate: 100,
      );
      now = DateTime(2026, 2, 15);
      await data('POST', '/savings-interest-credits', {
        'client_uuid': 'manual-interest',
        'savings_account_id': savings['id'],
        'amount_minor': 90,
        'credited_on': '2026-02-15',
      });
      now = DateTime(2026, 2, 28);
      final accrued = await data(
        'POST',
        '/savings-interest-credits/accrue',
        {},
      );
      expect(accrued['created_count'], 0);
      expect(accrued['skipped_existing_count'], 1);
      expect(
        (await data('GET', '/accounts/${savings['id']}'))['balance_minor'],
        10090,
      );
    },
  );

  test(
    'installment plan posts only down payment and explicitly recorded payments',
    () async {
      final source = await account('Bank', 10000);
      final plan = await data('POST', '/installment-plans', {
        'client_uuid': 'phone-plan',
        'account_id': source['id'],
        'category_id': 6,
        'installment_monthly_minor': 1000,
        'installment_months': 2,
        'installment_start_on': '2026-01-31',
        'down_payment_minor': 500,
        'payee': 'Phone',
      });
      expect(InstallmentPlan.fromJson(plan).contractTotalMinor, 2500);
      expect(plan['paid_installments'], 0);
      expect(
        (await data('GET', '/accounts/${source['id']}'))['balance_minor'],
        9500,
      );
      final firstPayload = {
        'client_uuid': 'payment-1',
        'version': 1,
        'paid_on': '2026-01-31',
      };
      final payment = await data(
        'POST',
        '/installment-plans/${plan['id']}/payments',
        firstPayload,
      );
      expect(payment['plan']['paid_installments'], 1);
      expect(payment['plan']['next_payment_on'], '2026-02-28');
      await data(
        'POST',
        '/installment-plans/${plan['id']}/payments',
        firstPayload,
      );
      expect(
        (await data('GET', '/accounts/${source['id']}'))['balance_minor'],
        8500,
      );
      now = DateTime(2026, 2, 28);
      await db.request('DELETE', '/categories/6');
      // Archiving prevents new expenses while preserving existing obligations.
      await expectLater(
        data('POST', '/transactions', {
          'client_uuid': 'new-archived-category-expense',
          'kind': 'expense',
          'amount_minor': 100,
          'occurred_on': '2026-02-28',
          'account_id': source['id'],
          'category_id': 6,
        }),
        throwsA(isA<ApiException>()),
      );
      final completed = await data(
        'POST',
        '/installment-plans/${plan['id']}/payments',
        {'client_uuid': 'payment-2', 'version': 2, 'paid_on': '2026-02-28'},
      );
      expect(completed['plan']['status'], 'completed');
      expect(completed['transaction']['category']['is_archived'], isTrue);
      expect(completed['plan']['remaining_obligation_minor'], 0);
      expect(
        (await data('GET', '/accounts/${source['id']}'))['balance_minor'],
        7500,
      );
      await expectLater(
        data('POST', '/installment-plans/${plan['id']}/payments', {
          'client_uuid': 'payment-3',
          'version': 3,
          'paid_on': '2026-02-28',
        }),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'joint accounts and fractional amounts cannot enter the local ledger',
    () async {
      await expectLater(
        data('POST', '/accounts', {
          'name': 'Shared',
          'type': 'cash',
          'scope': 'joint',
          'opening_balance_minor': 10,
        }),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        data('POST', '/transactions', {
          'client_uuid': 'fraction',
          'kind': 'income',
          'amount_minor': 1.5,
          'occurred_on': '2026-01-31',
          'account_id': 1,
          'category_id': 1,
        }),
        throwsA(isA<ApiException>()),
      );
    },
  );
}
