import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:expenses_tracker_offline/core/api_client.dart';
import 'package:expenses_tracker_offline/core/app_repository.dart';
import 'package:expenses_tracker_offline/core/config_store.dart';
import 'package:expenses_tracker_offline/core/local_database.dart';
import 'package:expenses_tracker_offline/models/domain_models.dart';
import 'package:expenses_tracker_offline/state/app_controller.dart';

void main() {
  late Directory directory;
  late File file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('offline-persistence-');
    file = File('${directory.path}/data.json');
  });
  tearDown(() async => directory.delete(recursive: true));

  AppController controller(LocalDatabase database) {
    final client = ApiClient(database: database);
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

  test(
    'first launch, complete controller writes, and cold restart need no server',
    () async {
      final app = controller(LocalDatabase(file: file));
      addTearDown(app.dispose);
      await app.initialize();
      expect(app.startupState, StartupState.ready, reason: app.errorMessage);
      expect(app.accounts, hasLength(1));
      await app.saveTransaction(
        clientUuid: '10000000-0000-4000-a000-000000000001',
        kind: 'income',
        amountMinor: 100000,
        occurredOn: DateTime.now(),
        accountId: 1,
        categoryId: 1,
      );
      await app.saveTransaction(
        clientUuid: '10000000-0000-4000-a000-000000000002',
        kind: 'expense',
        amountMinor: 10000,
        occurredOn: DateTime.now(),
        accountId: 1,
        categoryId: 3,
      );
      expect(app.accounts.single.balanceMinor, 90000);
      await app.saveAccount(
        name: 'Savings',
        type: 'savings',
        openingBalanceMinor: 0,
        color: '#00AA00',
        scope: FinanceScope.personal,
      );
      final savings = app.accounts.firstWhere((a) => a.isSavingsAccount);
      await app.saveAccountTransfer(
        scope: FinanceScope.personal,
        clientUuid: '10000000-0000-4000-a000-000000000003',
        sourceAccountId: 1,
        destinationAccountId: savings.id,
        amountMinor: 20000,
        transferredOn: DateTime.now(),
        serviceChargeMinor: 500,
      );
      expect(app.accounts.firstWhere((a) => a.id == 1).balanceMinor, 69500);
      expect(
        app.accounts.firstWhere((a) => a.id == savings.id).balanceMinor,
        20000,
      );
      final restarted = controller(LocalDatabase(file: file));
      addTearDown(restarted.dispose);
      await restarted.initialize();
      expect(
        restarted.startupState,
        StartupState.ready,
        reason: restarted.errorMessage,
      );
      expect(
        restarted.accounts.firstWhere((a) => a.id == 1).balanceMinor,
        69500,
      );
      expect(restarted.offlineTransactionsEnabled, isFalse);
      expect(restarted.pendingTransactionCount, 0);
      expect(restarted.isJointScope, isFalse);
    },
  );

  test('serialized parallel writes persist every transaction', () async {
    final db = LocalDatabase(file: file);
    await Future.wait(
      List.generate(
        20,
        (i) => db.request(
          'POST',
          '/transactions',
          body: {
            'client_uuid':
                '20000000-0000-4000-a000-${i.toString().padLeft(12, '0')}',
            'kind': 'income',
            'amount_minor': 100,
            'occurred_on': '2026-09-01',
            'account_id': 1,
            'category_id': 1,
          },
        ),
      ),
    );
    final restarted = LocalDatabase(file: file);
    final accounts = await restarted.request('GET', '/accounts');
    expect(accounts['data'][0]['balance_minor'], 2000);
    expect(
      (jsonDecode(await restarted.exportBackup())['transactions'] as List),
      hasLength(20),
    );
  });

  test(
    'backup round trip and malformed import preserve the current ledger',
    () async {
      final db = LocalDatabase(file: file);
      await db.request(
        'POST',
        '/transactions',
        body: {
          'client_uuid': '30000000-0000-4000-a000-000000000001',
          'kind': 'income',
          'amount_minor': 1500,
          'occurred_on': '2026-09-01',
          'account_id': 1,
          'category_id': 1,
        },
      );
      final backup = await db.exportBackup();
      final copy = LocalDatabase(file: File('${directory.path}/copy.json'));
      await copy.importBackup(backup);
      expect(jsonDecode(await copy.exportBackup()), jsonDecode(backup));
      final broken = jsonDecode(backup) as Map<String, dynamic>;
      (broken['transactions'] as List).first['account_id'] = 999;
      await expectLater(
        copy.importBackup(jsonEncode(broken)),
        throwsFormatException,
      );
      expect(jsonDecode(await copy.exportBackup()), jsonDecode(backup));
      await expectLater(copy.importBackup('{bad json'), throwsFormatException);
      expect(jsonDecode(await copy.exportBackup()), jsonDecode(backup));
    },
  );

  test(
    'joint data and rejected mutations do not change the saved file',
    () async {
      final db = LocalDatabase(file: file);
      await db.request('GET', '/accounts');
      final before = await db.exportBackup();
      await expectLater(
        db.request(
          'POST',
          '/accounts',
          body: {
            'name': 'Joint',
            'type': 'bank',
            'scope': 'joint',
            'opening_balance_minor': 0,
          },
        ),
        throwsA(isA<ApiException>()),
      );
      expect(await db.exportBackup(), before);
      await expectLater(
        db.request(
          'POST',
          '/transactions',
          body: {
            'client_uuid': '40000000-0000-4000-a000-000000000001',
            'kind': 'expense',
            'amount_minor': 500,
            'occurred_on': '2026-09-01',
            'account_id': 1,
            'category_id': 3,
          },
        ),
        throwsA(isA<ApiException>()),
      );
      expect(await db.exportBackup(), before);
    },
  );
}
