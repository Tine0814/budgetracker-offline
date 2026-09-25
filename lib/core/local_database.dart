import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import 'api_client.dart' show ApiException;
import 'money.dart';

part 'local_ledger.dart';
part 'local_backup.dart';
part 'local_planning.dart';

const localUnhandled = Object();

/// The authoritative, phone-local database. No socket or HTTP client is used.
/// Commands are serialized, committed by atomic rename, and rolled back on error.
class LocalDatabase {
  LocalDatabase({File? file, DateTime Function()? clock})
    : // Public injection name intentionally differs from private storage.
      // ignore: prefer_initializing_formals
      _file = file,
      clock = clock ?? DateTime.now;

  File? _file;
  final DateTime Function() clock;
  Map<String, dynamic> state = {};
  bool _loaded = false;
  Future<void> _tail = Future.value();

  List<Map<String, dynamic>> rows(String name) {
    final list =
        state.putIfAbsent(name, () => <Map<String, dynamic>>[]) as List;
    if (list is List<Map<String, dynamic>>) return list;
    final normalized = list
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    state[name] = normalized;
    return normalized;
  }

  int nextId(String table) {
    final counters =
        state.putIfAbsent('sequences', () => <String, dynamic>{}) as Map;
    final largest = rows(table)
        .fold<int>(0, (a, r) => max(a, (r['id'] as int?) ?? 0));
    final next = max(largest, (counters[table] as int?) ?? 0) + 1;
    counters[table] = next;
    return next;
  }

  Map<String, dynamic> find(String table, int id) => rows(table).firstWhere(
    (r) => r['id'] == id,
    orElse: () => fail('This record no longer exists.'),
  );

  Never fail(String message) => throw ApiException(message: message);

  String date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<File> _resolveFile() async {
    if (_file != null) return _file!;
    final support = await getApplicationSupportDirectory();
    return _file = File('${support.path}/expenses_tracker_offline/data.json');
  }

  Future<void> _load() async {
    if (_loaded) return;
    final file = await _resolveFile();
    if (await file.exists()) {
      try {
        state = _validateDocument(jsonDecode(await file.readAsString()));
      } catch (error) {
        throw const ApiException(
          message: 'The saved data could not be opened. Your file has been preserved. Restore a valid backup from Settings or keep the app data for recovery.',
        );
      }
    } else {
      state = _seed();
      await _persist();
    }
    _loaded = true;
  }

  Map<String, dynamic> _seed() {
    final now = clock().toIso8601String();
    final random = Random.secure();
    String hex(int n) =>
        List.generate(n, (_) => random.nextInt(16).toRadixString(16)).join();
    return {
      'format': 'expenses_tracker_offline',
      'schema_version': 1,
      'installation_id': '${hex(8)}-${hex(4)}-4${hex(3)}-a${hex(3)}-${hex(12)}',
      'created_at': now,
      'settings': {
        'currency_code': 'PHP',
        'locale': 'en_PH',
        'timezone': 'Asia/Manila',
        'week_starts_on': 1,
      },
      'sequences': <String, dynamic>{},
      'accounts': <Map<String, dynamic>>[
        {
          'id': 1,
          'name': 'Cash',
          'type': 'cash',
          'scope': 'personal',
          'opening_balance_minor': 0,
          'color': '#4F8F68',
          'is_archived': false,
          'created_at': now,
        },
      ],
      'categories': <Map<String, dynamic>>[
        for (final entry in [
          [1, 'Salary', 'income', '#4F8F68', 'payments'],
          [2, 'Other income', 'income', '#3A8C9B', 'add_circle'],
          [3, 'Food', 'expense', '#D8944D', 'restaurant'],
          [4, 'Transport', 'expense', '#688EB1', 'directions_car'],
          [5, 'Bills', 'expense', '#9A7BB5', 'receipt_long'],
          [6, 'Shopping', 'expense', '#CE8396', 'shopping_bag'],
          [7, 'Other expenses', 'expense', '#8B918C', 'category'],
          [8, 'Transfer Fees', 'expense', '#8B918C', 'swap_horiz'],
          [9, 'Savings Interest', 'income', '#4F8F68', 'savings'],
        ])
          {
            'id': entry[0],
            'name': entry[1],
            'kind': entry[2],
            'color': entry[3],
            'icon': entry[4],
            'is_archived': false,
            if (entry[0] == 8) 'system_key': 'account_transfer_fee',
            if (entry[0] == 9) 'system_key': 'savings_interest',
          },
      ],
      for (final table in [
        'transactions',
        'account_transfers',
        'credit_card_payments',
        'savings_interest_credits',
        'installment_plans',
        'jewelry',
        'gold_price_rates',
        'cutoff_schedules',
        'cutoff_periods',
      ])
        table: <Map<String, dynamic>>[],
    };
  }

  Future<void> _persist() async {
    final file = await _resolveFile();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    try {
      await temporary.writeAsString(jsonEncode(state), flush: true);
      if (await file.exists()) await file.copy('${file.path}.previous');
      await temporary.rename(file.path);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<dynamic> request(
    String method,
    String path, {
    Map<String, Object?> query = const {},
    Object? body,
  }) => _serial(() async {
    await _load();
    final before = jsonEncode(state);
    try {
      final payload = body == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(body as Map);
      if (query['scope'] == 'joint' ||
          payload['scope'] == 'joint' ||
          path.contains('joint')) {
        fail('This app supports personal accounts only.');
      }
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();
      if (path != '/savings-interest-credits/accrue') accrueSavingsInterest();
      Object? result;
      if (path == '/health') {
        result = {
          'data': {
            'ok': true,
            'status': 'ok',
            'api': 'local',
            'database': 'connected',
            'migrations': 'current',
            'version': '1.0.0',
            'installation_id': state['installation_id'],
          },
        };
      } else if (path == '/settings') {
        if (method != 'GET') {
          final currency = payload['currency_code']?.toString() ?? '';
          if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
            fail('Enter a three-letter currency code.');
          }
          final locale = payload['locale'];
          if (locale is! String || locale.trim().isEmpty) {
            fail('Choose a valid number format.');
          }
          try {
            Money.format(0, currencyCode: currency, locale: locale);
          } catch (_) {
            fail('This number format is not supported.');
          }
          final week = payload['week_starts_on'];
          if (week is! int || week < 0 || week > 6) {
            fail('Choose a valid start of the week.');
          }
          state['settings'] = {...state['settings'] as Map, ...payload};
        }
        result = {'data': state['settings']};
      } else {
        result = ledgerRequest(method, segments, query, payload);
        if (identical(result, localUnhandled)) {
          result = planningRequest(method, segments, query, payload);
        }
        if (identical(result, localUnhandled)) {
          fail('This action is not supported in this app.');
        }
      }
      if (jsonEncode(state) != before) await _persist();
      return result == null ? null : jsonDecode(jsonEncode(result));
    } catch (_) {
      state = Map<String, dynamic>.from(jsonDecode(before) as Map);
      rethrow;
    }
  });

  Future<String> exportBackup() => _serial(() async {
    await _load();
    return const JsonEncoder.withIndent('  ').convert(state);
  });

  Future<void> importBackup(String text) => _serial(() async {
    final replacement = _validateDocument(jsonDecode(text));
    final previous = state;
    state = replacement;
    try {
      await _persist();
      _loaded = true;
    } catch (_) {
      state = previous;
      rethrow;
    }
  });

  Map<String, dynamic> _validateDocument(Object? document) =>
      validateBackupDocument(document);
}
