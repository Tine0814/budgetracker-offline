part of 'local_database.dart';

/// Personal finance postings. All amounts are integer minor units. The database
/// runs these synchronous operations atomically and persists the whole commit.
extension LocalLedger on LocalDatabase {
  static const int _moneyLimit = 999999999999999;

  Object? ledgerRequest(
    String method,
    List<String> path,
    Map<String, Object?> query,
    Map<String, dynamic> body,
  ) {
    if (path.isEmpty) return localUnhandled;
    if ((query['scope'] != null &&
            !['personal', 'all'].contains(query['scope'])) ||
        (body['scope'] != null && body['scope'] != 'personal')) {
      fail('Only personal accounts are available in this offline app.');
    }
    final table = switch (path.first) {
      'accounts' => 'accounts',
      'categories' => 'categories',
      'transactions' => 'transactions',
      'account-transfers' => 'account_transfers',
      'credit-card-payments' => 'credit_card_payments',
      'savings-interest-credits' => 'savings_interest_credits',
      'installment-plans' => 'installment_plans',
      _ => null,
    };
    if (table == null) return localUnhandled;
    if (path.length == 2 &&
        path[1] == 'accrue' &&
        table == 'savings_interest_credits' &&
        method == 'POST') {
      return {'data': accrueSavingsInterest()};
    }
    final id = path.length > 1 ? int.tryParse(path[1]) : null;
    if (path.length > 1 && id == null) return localUnhandled;
    if (path.length == 3 &&
        table == 'installment_plans' &&
        path[2] == 'payments' &&
        method == 'POST') {
      return {'data': _ledgerPayInstallment(find(table, id!), body)};
    }
    if (path.length > 2) return localUnhandled;
    if (method == 'GET') {
      if (id != null) return {'data': _ledgerView(table, find(table, id))};
      var result = rows(table).where((row) {
        if (['accounts', 'categories'].contains(table) &&
            query['include_archived'] != 1 &&
            query['include_archived'] != '1' &&
            query['include_archived'] != true &&
            row['is_archived'] == true) {
          return false;
        }
        if (table == 'installment_plans') {
          final status = installmentView(row)['status'];
          final filter = query['status'];
          if (filter != null && filter != 'all' && status != filter) {
            return false;
          }
          if (filter == null && status == 'archived') return false;
        }
        for (final key in [
          'kind',
          'category_id',
          'cutoff_period_id',
          'source_account_id',
          'credit_card_account_id',
          'savings_account_id',
        ]) {
          if (query[key] != null &&
              query[key].toString().isNotEmpty &&
              query[key].toString() != row[key]?.toString()) {
            return false;
          }
        }
        if (query['account_id'] != null) {
          final wanted = query['account_id'].toString();
          if (table == 'account_transfers') {
            if (row['source_account_id'].toString() != wanted &&
                row['destination_account_id'].toString() != wanted) {
              return false;
            }
          } else if (row['account_id'].toString() != wanted) {
            return false;
          }
        }
        final on =
            (row['occurred_on'] ??
                    row['transferred_on'] ??
                    row['paid_on'] ??
                    row['credited_on'])
                ?.toString();
        if (on != null &&
            query['from'] != null &&
            on.compareTo(query['from'].toString()) < 0) {
          return false;
        }
        if (on != null &&
            query['to'] != null &&
            on.compareTo(query['to'].toString()) > 0) {
          return false;
        }
        final search = query['search']?.toString().trim().toLowerCase() ?? '';
        if (search.isNotEmpty) {
          final text = [
            row['name'],
            row['payee'],
            row['note'],
            row['source_account_name'],
            row['destination_account_name'],
            row['credit_card_account_name'],
            if (row['account_id'] != null)
              find('accounts', row['account_id'] as int)['name'],
            if (row['category_id'] != null)
              find('categories', row['category_id'] as int)['name'],
          ].join(' ').toLowerCase();
          if (!text.contains(search)) return false;
        }
        return true;
      }).toList();
      if (['accounts', 'categories'].contains(table)) {
        result.sort(
          (a, b) => a['name'].toString().toLowerCase().compareTo(
            b['name'].toString().toLowerCase(),
          ),
        );
        return {'data': result.map((r) => _ledgerView(table, r)).toList()};
      }
      result.sort((a, b) {
        final ad =
            (a['occurred_on'] ??
                    a['transferred_on'] ??
                    a['paid_on'] ??
                    a['credited_on'] ??
                    a['created_at'])
                .toString();
        final bd =
            (b['occurred_on'] ??
                    b['transferred_on'] ??
                    b['paid_on'] ??
                    b['credited_on'] ??
                    b['created_at'])
                .toString();
        final order = bd.compareTo(ad);
        return order == 0 ? (b['id'] as int).compareTo(a['id'] as int) : order;
      });
      final page = _ledgerQueryInt(query['page'], 1).clamp(1, 1000000);
      final size = _ledgerQueryInt(query['per_page'], 50).clamp(1, 1000);
      return {
        'data': result
            .skip((page - 1) * size)
            .take(size)
            .map((r) => _ledgerView(table, r))
            .toList(),
        'meta': {
          'current_page': page,
          'last_page': ((result.length + size - 1) ~/ size).clamp(1, 1000000),
          'per_page': size,
          'total': result.length,
        },
      };
    }
    if (method == 'POST' && id == null) {
      if (table == 'accounts') {
        return {'data': accountView(_ledgerSaveAccount(body))};
      }
      if (table == 'categories') return {'data': _ledgerSaveCategory(body)};
      if (table == 'transactions') {
        return {'data': transactionView(postLedgerTransaction(body))};
      }
      if (table == 'account_transfers' || table == 'credit_card_payments') {
        return {'data': _ledgerView(table, _ledgerPostMovement(table, body))};
      }
      if (table == 'savings_interest_credits') {
        return {'data': _ledgerInterestView(_ledgerPostInterest(body))};
      }
      if (table == 'installment_plans') {
        return {'data': installmentView(_ledgerSavePlan(body))};
      }
    }
    if (id != null && (method == 'PATCH' || method == 'PUT')) {
      final row = find(table, id);
      if (table == 'accounts') {
        return {'data': accountView(_ledgerSaveAccount(body, row))};
      }
      if (table == 'categories') {
        return {'data': _ledgerSaveCategory(body, row)};
      }
      if (table == 'transactions') {
        _ledgerMutableTransaction(row, body);
        final oldAccount = row['account_id'] as int;
        final candidate = _ledgerTransactionValues({
          ...row,
          ...body,
        }, managed: false);
        row.addAll(candidate);
        row['version'] = (row['version'] as int) + 1;
        row['updated_at'] = clock().toIso8601String();
        _ledgerCheckBalance(find('accounts', oldAccount));
        _ledgerCheckBalance(find('accounts', row['account_id'] as int));
        return {'data': transactionView(row)};
      }
      if (table == 'installment_plans') {
        return {'data': installmentView(_ledgerSavePlan(body, row))};
      }
      fail(
        'Posted transfers, payments, and interest credits cannot be edited.',
      );
    }
    if (id != null && method == 'DELETE') {
      final row = find(table, id);
      if (table == 'transactions') {
        _ledgerMutableTransaction(row, body);
        final account = find('accounts', row['account_id'] as int);
        rows(table).remove(row);
        _ledgerCheckBalance(account);
      } else if (table == 'accounts') {
        if (accountBalance(row) != 0 &&
            ['savings', 'credit_card'].contains(row['type'])) {
          fail(
            'Move the savings balance or pay the card debt before archiving this account.',
          );
        }
        row['is_archived'] = true;
      } else if (table == 'categories') {
        if (row['is_system'] == true || row['system_key'] != null) {
          fail('This built-in category is required by account activity.');
        }
        row['is_archived'] = true;
      } else if (table == 'installment_plans') {
        _ledgerVersion(row, body);
        row['is_archived'] = true;
        row['version'] = (row['version'] as int) + 1;
        return {'data': installmentView(row)};
      } else {
        fail(
          'Posted transfers, payments, and interest credits cannot be deleted.',
        );
      }
      return {'data': null};
    }
    return localUnhandled;
  }

  int _ledgerQueryInt(Object? value, int fallback) =>
      int.tryParse('$value') ?? fallback;
  int _ledgerInt(
    Object? value,
    String label, {
    int min = 0,
    int max = _moneyLimit,
  }) {
    if (value is! int || value < min || value > max) {
      fail('$label must be a whole number between $min and $max.');
    }
    return value;
  }

  String _ledgerName(Object? value, String label, {int max = 100}) {
    final result = value?.toString().trim() ?? '';
    if (result.isEmpty || result.length > max) {
      fail('$label is required and must be at most $max characters.');
    }
    return result;
  }

  String _ledgerDate(Object? value, {bool allowFuture = false}) {
    final raw = value?.toString() ?? '';
    final parsed = DateTime.tryParse(raw);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw) ||
        parsed == null ||
        date(parsed) != raw) {
      fail('Enter a valid date.');
    }
    if (!allowFuture && raw.compareTo(date(clock())) > 0) {
      fail('Posted activity cannot be dated in the future.');
    }
    return raw;
  }

  DateTime _ledgerAddMonths(DateTime anchor, int months) {
    final first = DateTime(anchor.year, anchor.month + months);
    final days = DateTime(first.year, first.month + 1, 0).day;
    return DateTime(first.year, first.month, anchor.day.clamp(1, days));
  }

  void _ledgerVersion(Map<String, dynamic> row, Map<String, dynamic> body) {
    if (body['version'] != row['version']) {
      fail('This record changed. Refresh it before saving.');
    }
  }

  Map<String, dynamic>? _ledgerReplay(String table, Map<String, dynamic> body) {
    final uuid = body['client_uuid'];
    if (uuid == null || uuid.toString().trim().isEmpty) return null;
    for (final row in rows(table)) {
      if (row['client_uuid'] != uuid) continue;
      final previous = row['_request_payload'];
      if (previous is Map &&
          body.entries.any(
            (e) => e.key != 'version' && previous[e.key] != e.value,
          )) {
        fail(
          'This payment reference has already been used with different details.',
        );
      }
      return row;
    }
    return null;
  }

  String _ledgerUuid() {
    final random = Random.secure();
    String hex(int count) => List.generate(
      count,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-a${hex(3)}-${hex(12)}';
  }

  Map<String, dynamic> _ledgerBase(String table, Map<String, dynamic> body) {
    final id = nextId(table);
    return {
      'id': id,
      'client_uuid': body['client_uuid'] ?? _ledgerUuid(),
      'scope': 'personal',
      'version': 1,
      'created_at': clock().toIso8601String(),
      'updated_at': clock().toIso8601String(),
      '_request_payload': Map<String, dynamic>.from(body),
    };
  }

  Map<String, dynamic> _ledgerPublic(Map<String, dynamic> row) =>
      Map<String, dynamic>.fromEntries(
        row.entries.where((e) => !e.key.startsWith('_')),
      );

  Map<String, dynamic> _ledgerActiveAccount(Object? value) {
    final account = find('accounts', _ledgerInt(value, 'Account', min: 1));
    if (account['is_archived'] == true) fail('Choose an active account.');
    if (account['scope'] != null && account['scope'] != 'personal') {
      fail('Only personal accounts are supported.');
    }
    return account;
  }

  Map<String, dynamic> _ledgerCategory(
    Object? value,
    String kind, {
    bool managed = false,
    bool allowArchived = false,
  }) {
    final category = find('categories', _ledgerInt(value, 'Category', min: 1));
    if ((!allowArchived && category['is_archived'] == true) ||
        category['kind'] != kind) {
      fail('Choose an active $kind category.');
    }
    if (!managed &&
        (category['is_system'] == true || category['system_key'] != null)) {
      fail('This category is reserved for account activity.');
    }
    return category;
  }

  void _ledgerHistoryDate(Map<String, dynamic> account, String on) {
    final finalized = account['interest_last_processed_on']?.toString();
    if (account['type'] == 'savings' &&
        finalized != null &&
        on.compareTo(finalized) < 0) {
      fail(
        'This savings date has already been finalized by monthly interest. Choose $finalized or later.',
      );
    }
  }

  int accountBalance(Map<String, dynamic> account, {DateTime? through}) {
    var balance = (account['opening_balance_minor'] as int?) ?? 0;
    final id = account['id'];
    final end = through == null ? null : date(through);
    bool included(Map<String, dynamic> row, String field) =>
        end == null || row[field].toString().compareTo(end) <= 0;
    for (final tx in rows('transactions')) {
      if (tx['account_id'] == id && included(tx, 'occurred_on')) {
        balance +=
            (tx['kind'] == 'income' ? 1 : -1) * (tx['amount_minor'] as int);
      }
    }
    for (final transfer in rows('account_transfers')) {
      if (!included(transfer, 'transferred_on')) continue;
      if (transfer['source_account_id'] == id) {
        balance -= transfer['amount_minor'] as int;
      }
      if (transfer['destination_account_id'] == id) {
        balance += transfer['amount_minor'] as int;
      }
    }
    for (final payment in rows('credit_card_payments')) {
      if (!included(payment, 'paid_on')) continue;
      if (payment['source_account_id'] == id) {
        balance -= payment['amount_minor'] as int;
      }
      if (payment['credit_card_account_id'] == id) {
        balance += payment['amount_minor'] as int;
      }
    }
    return balance;
  }

  void _ledgerCheckBalance(Map<String, dynamic> account) {
    final balance = accountBalance(account);
    if (balance.abs() > _moneyLimit) {
      fail('The account balance exceeds the supported amount.');
    }
    if (account['type'] == 'credit_card') {
      if (balance > 0) {
        fail('A card payment or refund cannot exceed the outstanding debt.');
      }
      final limit = account['credit_limit_minor'] as int?;
      if (limit != null && -balance > limit) {
        fail('This purchase exceeds the available credit.');
      }
    } else if (balance < 0) {
      fail('There is not enough money in ${account['name']}.');
    }
  }

  Map<String, dynamic> accountView(
    Map<String, dynamic> row, {
    DateTime? through,
  }) {
    final card = row['type'] == 'credit_card';
    final savings = row['type'] == 'savings';
    final balance = accountBalance(row, through: through);
    final rate = (row['monthly_interest_rate_basis_points'] as int?) ?? 0;
    final limit = row['credit_limit_minor'] as int?;
    return {
      ..._ledgerPublic(row),
      'scope': 'personal',
      'balance_minor': balance,
      'is_liability': card,
      'is_savings': savings,
      'is_system': row['system_key'] != null,
      'counts_toward_available_money': !card && !savings,
      'opening_debt_minor': card ? -(row['opening_balance_minor'] as int) : 0,
      'debt_minor': card ? -balance : 0,
      'available_credit_minor': card && limit != null ? limit + balance : null,
      'monthly_interest_rate_basis_points': savings ? rate : 0,
      'monthly_interest_rate_percent': savings ? rate / 100 : 0,
    };
  }

  Map<String, dynamic> _ledgerCategoryView(Map<String, dynamic> row) => {
    ..._ledgerPublic(row),
    'is_system': row['system_key'] != null,
    'category_role': switch (row['system_key']) {
      'savings_interest' => 'savings_interest',
      'account_transfer_fee' => 'transfer_fee',
      _ => 'standard',
    },
  };

  Map<String, dynamic> transactionView(Map<String, dynamic> row) => {
    ..._ledgerPublic(row),
    'scope': 'personal',
    'account': accountView(find('accounts', row['account_id'] as int)),
    'category': _ledgerCategoryView(
      find('categories', row['category_id'] as int),
    ),
    if (row['source_type'] == null && row['system_source'] != null)
      'source_type': row['system_source'],
  };

  Map<String, dynamic> _ledgerSaveAccount(
    Map<String, dynamic> body, [
    Map<String, dynamic>? existing,
  ]) {
    final values = {...?existing, ...body};
    final name = _ledgerName(values['name'], 'Account name');
    final type = values['type'];
    if (![
      'cash',
      'bank',
      'ewallet',
      'other',
      'credit_card',
      'savings',
    ].contains(type)) {
      fail('Choose a valid account type.');
    }
    if (rows('accounts').any(
      (r) =>
          r['id'] != existing?['id'] &&
          r['name'].toString().toLowerCase() == name.toLowerCase(),
    )) {
      fail('An account with this name already exists.');
    }
    if (existing != null &&
        type != existing['type'] &&
        ([
          type,
          existing['type'],
        ].any((t) => ['savings', 'credit_card'].contains(t)))) {
      fail('Savings and credit card account types cannot be changed.');
    }
    final opening = type == 'credit_card'
        ? -_ledgerInt(
            body['opening_debt_minor'] ??
                existing?['opening_debt_minor'] ??
                -(existing?['opening_balance_minor'] as int? ?? 0),
            'Opening debt',
          )
        : _ledgerInt(values['opening_balance_minor'] ?? 0, 'Opening balance');
    final rate = type == 'savings'
        ? _ledgerInt(
            values['monthly_interest_rate_basis_points'] ?? 0,
            'Monthly interest rate',
            max: 10000,
          )
        : 0;
    final row = existing ?? _ledgerBase('accounts', body);
    if (existing != null &&
        existing['type'] == 'savings' &&
        opening != existing['opening_balance_minor'] &&
        (rows('transactions').any((r) => r['account_id'] == row['id']) ||
            rows('account_transfers').any(
              (r) =>
                  r['source_account_id'] == row['id'] ||
                  r['destination_account_id'] == row['id'],
            ))) {
      fail(
        'The opening balance cannot change after savings activity has been recorded.',
      );
    }
    if (type == 'savings' &&
        rate != (existing?['monthly_interest_rate_basis_points'] ?? 0)) {
      row['interest_accrual_anchor_on'] = rate > 0 ? date(clock()) : null;
      row['next_interest_accrual_on'] = rate > 0
          ? date(_ledgerAddMonths(clock(), 1))
          : null;
    }
    row.addAll({
      'name': name,
      'type': type,
      'scope': 'personal',
      'opening_balance_minor': opening,
      'color': values['color'] ?? '#43D98B',
      'icon': values['icon'] ?? 'wallet',
      'card_design': values['card_design'],
      'is_archived': values['is_archived'] == true,
      'monthly_interest_rate_basis_points': rate,
      'credit_limit_minor':
          type == 'credit_card' && values['credit_limit_minor'] != null
          ? _ledgerInt(values['credit_limit_minor'], 'Credit limit', min: 1)
          : null,
      'statement_day': type == 'credit_card' && values['statement_day'] != null
          ? _ledgerInt(
              values['statement_day'],
              'Statement day',
              min: 1,
              max: 31,
            )
          : null,
      'due_day': type == 'credit_card' && values['due_day'] != null
          ? _ledgerInt(values['due_day'], 'Due day', min: 1, max: 31)
          : null,
      'updated_at': clock().toIso8601String(),
    });
    if (existing == null) rows('accounts').add(row);
    _ledgerCheckBalance(row);
    if (row['is_archived'] == true &&
        accountBalance(row) != 0 &&
        ['savings', 'credit_card'].contains(type)) {
      fail('Settle the account balance before archiving it.');
    }
    return row;
  }

  Map<String, dynamic> _ledgerSaveCategory(
    Map<String, dynamic> body, [
    Map<String, dynamic>? existing,
  ]) {
    final values = {...?existing, ...body};
    final name = _ledgerName(values['name'], 'Category name');
    final kind = values['kind'];
    if (!['income', 'expense'].contains(kind)) {
      fail('Choose income or expense.');
    }
    if (existing != null &&
        (existing['is_system'] == true || existing['system_key'] != null)) {
      fail('This built-in category is managed by account activity.');
    }
    if (existing != null && kind != existing['kind']) {
      final id = existing['id'];
      bool containsBudget(Object? items) =>
          items is List &&
          items.any((item) => item is Map && item['category_id'] == id);
      final used =
          rows('transactions').any((r) => r['category_id'] == id) ||
          rows('installment_plans').any((r) => r['category_id'] == id) ||
          rows('cutoff_periods').any(
            (r) =>
                containsBudget(r['budget_items']) ||
                containsBudget(r['default_budget_items']),
          ) ||
          rows('cutoff_schedules').any(
            (r) =>
                r['rules'] is List &&
                (r['rules'] as List).any(
                  (rule) =>
                      rule is Map && containsBudget(rule['category_budgets']),
                ),
          );
      if (used) {
        fail(
          'A category used by transactions, installments, or budgets cannot change between income and expense.',
        );
      }
    }
    if (rows('categories').any(
      (r) =>
          r['id'] != existing?['id'] &&
          r['kind'] == kind &&
          r['name'].toString().toLowerCase() == name.toLowerCase(),
    )) {
      fail('A category with this name already exists.');
    }
    final row = existing ?? _ledgerBase('categories', body);
    row.addAll({
      'name': name,
      'kind': kind,
      'color': values['color'] ?? '#43D98B',
      'icon': values['icon'] ?? 'category',
      'is_archived': values['is_archived'] == true,
    });
    if (existing == null) rows('categories').add(row);
    return _ledgerPublic(row);
  }

  Map<String, dynamic> _ledgerTransactionValues(
    Map<String, dynamic> body, {
    required bool managed,
    bool allowArchivedCategory = false,
  }) {
    final kind = body['kind'];
    if (!['income', 'expense'].contains(kind)) {
      fail('Choose income or expense.');
    }
    final account = _ledgerActiveAccount(body['account_id']);
    final category = _ledgerCategory(
      body['category_id'],
      kind as String,
      managed: managed,
      allowArchived: allowArchivedCategory,
    );
    final amount = _ledgerInt(body['amount_minor'], 'Amount', min: 1);
    final on = _ledgerDate(body['occurred_on']);
    if (!managed) _ledgerHistoryDate(account, on);
    final months = body['installment_months'] == null
        ? null
        : _ledgerInt(
            body['installment_months'],
            'Installment months',
            min: 2,
            max: 120,
          );
    int? monthly;
    String? start;
    if (months != null) {
      if (kind != 'expense') {
        fail('Installments are only available for expenses.');
      }
      monthly = account['type'] == 'credit_card'
          ? (amount + months - 1) ~/ months
          : amount;
      if (body['installment_monthly_minor'] != null &&
          body['installment_monthly_minor'] != monthly) {
        fail('The monthly amount does not match this installment purchase.');
      }
      start = _ledgerDate(
        body['installment_start_on'] ?? on,
        allowFuture: true,
      );
      if (start.compareTo(on) < 0 ||
          (account['type'] != 'credit_card' && start != on)) {
        fail('Choose a valid first installment date.');
      }
    }
    return {
      'kind': kind,
      'amount_minor': amount,
      'occurred_on': on,
      'account_id': account['id'],
      'category_id': category['id'],
      'cutoff_period_id': resolveCutoff(DateTime.parse(on))['id'],
      'payee': body['payee']?.toString().trim(),
      'note': body['note']?.toString().trim(),
      'installment_months': months,
      'installment_monthly_minor': monthly,
      'installment_start_on': start,
    };
  }

  Map<String, dynamic> postLedgerTransaction(
    Map<String, dynamic> body, {
    String? sourceType,
    int? sourceId,
    int? installmentNumber,
    int? installmentPlanId,
  }) {
    final replay = _ledgerReplay('transactions', body);
    if (replay != null) return replay;
    final values = _ledgerTransactionValues(
      body,
      managed: sourceType != null,
      // Existing plans keep their historical category after it is archived.
      allowArchivedCategory: sourceType == 'installment_plan_payment',
    );
    if (sourceType != 'savings_interest') {
      _ledgerHistoryDate(
        find('accounts', values['account_id'] as int),
        values['occurred_on'] as String,
      );
    }
    final row = {
      ..._ledgerBase('transactions', body),
      ...values,
      'source_type': sourceType,
      'source_id': sourceId,
      'installment_number': installmentNumber,
      'installment_plan_id': installmentPlanId,
    };
    rows('transactions').add(row);
    _ledgerCheckBalance(find('accounts', row['account_id'] as int));
    return row;
  }

  void _ledgerMutableTransaction(
    Map<String, dynamic> row,
    Map<String, dynamic> body,
  ) {
    _ledgerVersion(row, body);
    if (row['source_type'] != null ||
        row['system_source'] != null ||
        row['installment_plan_id'] != null) {
      fail(
        'This transaction is managed by its account activity and cannot be changed here.',
      );
    }
    _ledgerHistoryDate(
      find('accounts', row['account_id'] as int),
      row['occurred_on'] as String,
    );
  }

  Map<String, dynamic> _ledgerPostMovement(
    String table,
    Map<String, dynamic> body,
  ) {
    final replay = _ledgerReplay(table, body);
    if (replay != null) return replay;
    final transfer = table == 'account_transfers';
    final destinationKey = transfer
        ? 'destination_account_id'
        : 'credit_card_account_id';
    final onKey = transfer ? 'transferred_on' : 'paid_on';
    final source = _ledgerActiveAccount(body['source_account_id']);
    final destination = _ledgerActiveAccount(body[destinationKey]);
    if (source['id'] == destination['id']) {
      fail('Choose two different accounts.');
    }
    if (source['type'] == 'credit_card') {
      fail('Choose a cash, bank, wallet, or savings account as the source.');
    }
    if (transfer && destination['type'] == 'credit_card') {
      fail('Use Pay credit card to pay a credit card.');
    }
    if (!transfer && source['type'] == 'savings') {
      fail(
        'Transfer savings to a cash, bank, or wallet account before paying a card.',
      );
    }
    if (!transfer && destination['type'] != 'credit_card') {
      fail('Choose a credit card to pay.');
    }
    final amount = _ledgerInt(body['amount_minor'], 'Amount', min: 1);
    final fee = _ledgerInt(body['service_charge_minor'] ?? 0, 'Service charge');
    if (amount + fee > _moneyLimit) {
      fail('The total debit exceeds the supported amount.');
    }
    final on = _ledgerDate(body[onKey]);
    _ledgerHistoryDate(source, on);
    _ledgerHistoryDate(destination, on);
    if (accountBalance(source) < amount + fee) {
      fail('There is not enough money to cover the amount and service charge.');
    }
    if (!transfer && amount > -accountBalance(destination)) {
      fail('The payment cannot exceed the outstanding card debt.');
    }
    final row = {
      ..._ledgerBase(table, body),
      'source_account_id': source['id'],
      destinationKey: destination['id'],
      'source_account_name': source['name'],
      'source_account_name_snapshot': source['name'],
      transfer ? 'destination_account_name' : 'credit_card_account_name':
          destination['name'],
      transfer
              ? 'destination_account_name_snapshot'
              : 'credit_card_account_name_snapshot':
          destination['name'],
      'amount_minor': amount,
      'service_charge_minor': fee,
      onKey: on,
      'note': body['note'],
      'status': 'posted',
      'service_charge_transaction_id': null,
    };
    rows(table).add(row);
    if (fee > 0) {
      final tx = postLedgerTransaction(
        {
          'client_uuid': _ledgerUuid(),
          'kind': 'expense',
          'amount_minor': fee,
          'occurred_on': on,
          'account_id': source['id'],
          'category_id': _ledgerSystemCategory('account_transfer_fee', 8)['id'],
          'payee': transfer
              ? 'Transfer service charge'
              : 'Credit card payment service charge',
          'note': body['note'],
        },
        sourceType: transfer
            ? 'account_transfer_fee'
            : 'credit_card_payment_fee',
        sourceId: row['id'] as int,
      );
      row['service_charge_transaction_id'] = tx['id'];
    }
    _ledgerCheckBalance(source);
    _ledgerCheckBalance(destination);
    return row;
  }

  Map<String, dynamic> _ledgerSystemCategory(String key, int fallbackId) {
    for (final category in rows('categories')) {
      if (category['system_key'] == key) return category;
    }
    return find('categories', fallbackId);
  }

  Map<String, dynamic> _ledgerMovementView(
    String table,
    Map<String, dynamic> row,
  ) {
    final transfer = table == 'account_transfers';
    final amount = row['amount_minor'] as int;
    final fee = row['service_charge_minor'] as int;
    final source = accountView(
      find('accounts', row['source_account_id'] as int),
    );
    final destination = accountView(
      find(
        'accounts',
        row[transfer ? 'destination_account_id' : 'credit_card_account_id']
            as int,
      ),
    );
    final txId = row['service_charge_transaction_id'];
    final tx = txId == null
        ? null
        : transactionView(find('transactions', txId as int));
    final sourceAvailable = source['counts_toward_available_money'] == true;
    final destinationAvailable =
        destination['counts_toward_available_money'] == true;
    final principalAvailable =
        (sourceAvailable ? -amount : 0) + (destinationAvailable ? amount : 0);
    final feeAvailable = sourceAvailable ? -fee : 0;
    return {
      ..._ledgerPublic(row),
      'is_immutable': true,
      'total_source_debit_minor': amount + fee,
      'total_cash_change_minor': transfer ? -fee : -(amount + fee),
      'affects_account_balance': !transfer || fee > 0,
      'affects_total_cash_balance': !transfer || fee > 0,
      'affects_individual_account_balances': true,
      'affects_income': false,
      'affects_expense': fee > 0,
      'affects_cashflow': fee > 0,
      'affects_budget': fee > 0,
      'service_charge_affects_account_balance': fee > 0,
      'service_charge_affects_expense': fee > 0,
      'source_account': source,
      transfer ? 'destination_account' : 'credit_card_account': destination,
      'fee_transaction': tx,
      'service_charge_transaction': tx,
      if (transfer) ...{
        'destination_credit_minor': amount,
        'principal_affects_individual_account_balances': true,
        'principal_affects_total_cash_balance': false,
        'source_available_money_change_minor': sourceAvailable
            ? -(amount + fee)
            : 0,
        'destination_available_money_change_minor': destinationAvailable
            ? amount
            : 0,
        'principal_available_money_change_minor': principalAvailable,
        'service_charge_available_money_change_minor': feeAvailable,
        'available_money_change_minor': principalAvailable + feeAvailable,
        'principal_affects_available_money': principalAvailable != 0,
        'service_charge_affects_available_money': feeAvailable != 0,
        'affects_available_money': principalAvailable + feeAvailable != 0,
      } else ...{
        'source_cash_change_minor': -(amount + fee),
        'credit_card_debt_change_minor': -amount,
        'debt_reduction_minor': amount,
        'net_position_change_minor': -fee,
        'affects_credit_card_debt': true,
        'affects_net_position': fee > 0,
      },
    };
  }

  Map<String, dynamic> _ledgerPostInterest(
    Map<String, dynamic> body, {
    bool automatic = false,
    int? calculationBalance,
    int? rate,
  }) {
    final replay = _ledgerReplay('savings_interest_credits', body);
    if (replay != null) return replay;
    final account = _ledgerActiveAccount(body['savings_account_id']);
    if (account['type'] != 'savings') fail('Choose a savings account.');
    final amount = _ledgerInt(body['amount_minor'], 'Interest amount', min: 1);
    final on = _ledgerDate(body['credited_on']);
    final month = on.substring(0, 7);
    if (!automatic) _ledgerHistoryDate(account, on);
    if (rows('savings_interest_credits').any(
      (r) =>
          r['savings_account_id'] == account['id'] &&
          r['credited_month'] == month,
    )) {
      fail('Interest has already been credited for this account and month.');
    }
    final row = {
      ..._ledgerBase('savings_interest_credits', body),
      'savings_account_id': account['id'],
      'savings_account_name': account['name'],
      'savings_account_name_snapshot': account['name'],
      'amount_minor': amount,
      'credited_on': on,
      'credited_month': month,
      'credit_method': automatic ? 'automatic' : 'manual',
      'calculation_balance_minor': calculationBalance,
      'monthly_interest_rate_basis_points': rate,
      'monthly_interest_rate_percent': rate == null ? null : rate / 100,
      'note': body['note'],
      'status': 'posted',
    };
    rows('savings_interest_credits').add(row);
    final tx = postLedgerTransaction(
      {
        'client_uuid': row['client_uuid'],
        'kind': 'income',
        'amount_minor': amount,
        'occurred_on': on,
        'account_id': account['id'],
        'category_id': _ledgerSystemCategory('savings_interest', 9)['id'],
        'payee': 'Savings interest',
        'note': body['note'],
      },
      sourceType: 'savings_interest',
      sourceId: row['id'] as int,
    );
    row['interest_transaction_id'] = tx['id'];
    return row;
  }

  Map<String, dynamic> _ledgerInterestView(Map<String, dynamic> row) {
    final amount = row['amount_minor'] as int;
    final tx = transactionView(
      find('transactions', row['interest_transaction_id'] as int),
    );
    return {
      ..._ledgerPublic(row),
      'transaction_id': row['interest_transaction_id'],
      'is_immutable': true,
      'account_balance_change_minor': amount,
      'savings_balance_change_minor': amount,
      'total_cash_change_minor': amount,
      'available_money_change_minor': 0,
      'net_position_change_minor': amount,
      'affects_account_balance': true,
      'affects_individual_account_balances': true,
      'affects_total_cash_balance': true,
      'affects_available_money': false,
      'affects_savings_balance': true,
      'affects_net_position': true,
      'affects_income': true,
      'affects_expense': false,
      'affects_cashflow': true,
      'affects_budget': false,
      'savings_account': accountView(
        find('accounts', row['savings_account_id'] as int),
      ),
      'income_transaction': tx,
      'interest_transaction': tx,
    };
  }

  Map<String, dynamic> accrueSavingsInterest() {
    final today = date(clock());
    final result = <String, dynamic>{
      'scope': 'all',
      'through_date': today,
      'processed_account_ids': <int>[],
      'credit_ids': <int>[],
      'processed_due_count': 0,
      'created_count': 0,
      'skipped_existing_count': 0,
      'skipped_nonpositive_count': 0,
      'skipped_zero_amount_count': 0,
    };
    for (final account in rows('accounts')) {
      final rate = account['monthly_interest_rate_basis_points'] as int? ?? 0;
      if (account['type'] != 'savings' ||
          account['is_archived'] == true ||
          rate <= 0) {
        continue;
      }
      final anchor = DateTime.tryParse(
        account['interest_accrual_anchor_on']?.toString() ?? '',
      );
      var next = DateTime.tryParse(
        account['next_interest_accrual_on']?.toString() ?? '',
      );
      if (anchor == null || next == null || !next.isAfter(anchor)) {
        fail('The savings interest schedule is invalid.');
      }
      (result['processed_account_ids'] as List<int>).add(account['id'] as int);
      var count = 0;
      while (date(next!).compareTo(today) <= 0) {
        if (++count > 1200) {
          fail('The savings interest catch-up period is too large.');
        }
        result['processed_due_count'] =
            (result['processed_due_count'] as int) + 1;
        final month = date(next).substring(0, 7);
        final exists = rows('savings_interest_credits').any(
          (r) =>
              r['savings_account_id'] == account['id'] &&
              r['credited_month'] == month,
        );
        if (exists) {
          result['skipped_existing_count'] =
              (result['skipped_existing_count'] as int) + 1;
        } else {
          final balance = accountBalance(
            account,
            through: next.subtract(const Duration(days: 1)),
          );
          final amount = balance <= 0
              ? 0
              : (balance ~/ 10000) * rate +
                    ((balance % 10000) * rate + 5000) ~/ 10000;
          if (balance <= 0) {
            result['skipped_nonpositive_count'] =
                (result['skipped_nonpositive_count'] as int) + 1;
          } else if (amount == 0) {
            result['skipped_zero_amount_count'] =
                (result['skipped_zero_amount_count'] as int) + 1;
          } else {
            final credit = _ledgerPostInterest(
              {
                'client_uuid': _ledgerUuid(),
                'savings_account_id': account['id'],
                'amount_minor': amount,
                'credited_on': date(next),
                'note': 'Automatic monthly savings interest.',
              },
              automatic: true,
              calculationBalance: balance,
              rate: rate,
            );
            (result['credit_ids'] as List<int>).add(credit['id'] as int);
            result['created_count'] = (result['created_count'] as int) + 1;
          }
        }
        account['interest_last_processed_on'] = date(next);
        final elapsedMonths =
            (next.year - anchor.year) * 12 + next.month - anchor.month;
        next = _ledgerAddMonths(anchor, elapsedMonths + 1);
        account['next_interest_accrual_on'] = date(next);
      }
    }
    result['processed_account_count'] =
        (result['processed_account_ids'] as List).length;
    result['processed_accounts'] =
        (result['processed_account_ids'] as List<int>)
            .map((id) => accountView(find('accounts', id)))
            .toList();
    result['credits'] = (result['credit_ids'] as List<int>)
        .map((id) => _ledgerInterestView(find('savings_interest_credits', id)))
        .toList();
    return result;
  }

  Map<String, dynamic> installmentView(Map<String, dynamic> row) {
    final payments = rows('transactions')
        .where(
          (t) =>
              t['installment_plan_id'] == row['id'] &&
              (t['installment_number'] as int? ?? 0) > 0,
        )
        .toList();
    final down = rows('transactions')
        .where(
          (t) =>
              t['installment_plan_id'] == row['id'] &&
              t['installment_number'] == 0,
        )
        .firstOrNull;
    final months = row['installment_months'] as int;
    final remaining = (months - payments.length).clamp(0, months);
    final monthly = row['installment_monthly_minor'] as int;
    final downAmount = row['down_payment_minor'] as int? ?? 0;
    final status = row['is_archived'] == true
        ? 'archived'
        : remaining == 0
        ? 'completed'
        : 'active';
    return {
      ..._ledgerPublic(row),
      'status': status,
      'paid_installments': payments.length,
      'remaining_installments': remaining,
      'next_installment_number': status == 'active'
          ? payments.length + 1
          : null,
      'next_payment_on': status == 'active'
          ? date(
              _ledgerAddMonths(
                DateTime.parse(row['installment_start_on'] as String),
                payments.length,
              ),
            )
          : null,
      'scheduled_total_minor': monthly * months,
      'installment_total_minor': monthly * months,
      'scheduled_remaining_minor': monthly * remaining,
      'contract_total_minor': downAmount + monthly * months,
      'total_paid_minor': downAmount + monthly * payments.length,
      'remaining_obligation_minor': monthly * remaining,
      'down_payment_paid_on': down?['occurred_on'],
      'down_payment_transaction': down == null ? null : transactionView(down),
      'account': accountView(find('accounts', row['account_id'] as int)),
      'category': _ledgerCategoryView(
        find('categories', row['category_id'] as int),
      ),
      'payments': payments.map(transactionView).toList(),
      'affects_account_balance': false,
      'affects_income': false,
      'affects_expense': false,
      'affects_cashflow': false,
      'affects_budget': false,
    };
  }

  Map<String, dynamic> _ledgerSavePlan(
    Map<String, dynamic> body, [
    Map<String, dynamic>? existing,
  ]) {
    if (existing == null) {
      final replay = _ledgerReplay('installment_plans', body);
      if (replay != null) return replay;
    } else {
      _ledgerVersion(existing, body);
      if (installmentView(existing)['status'] != 'active') {
        fail('Only active installment plans can be edited.');
      }
      if ((installmentView(existing)['paid_installments'] as int) > 0) {
        for (final key in [
          'category_id',
          'installment_monthly_minor',
          'installment_months',
          'installment_start_on',
        ]) {
          if (body.containsKey(key) && body[key] != existing[key]) {
            fail(
              'The payment schedule cannot change after a payment has been recorded.',
            );
          }
        }
      }
      if (body.containsKey('down_payment_minor') &&
          body['down_payment_minor'] != existing['down_payment_minor']) {
        fail('A recorded down payment cannot be changed.');
      }
    }
    final values = {...?existing, ...body};
    final account = _ledgerActiveAccount(values['account_id']);
    if (['credit_card', 'savings'].contains(account['type'])) {
      fail('Choose a cash, bank, or wallet account for installment payments.');
    }
    final category = _ledgerCategory(values['category_id'], 'expense');
    final monthly = _ledgerInt(
      values['installment_monthly_minor'],
      'Monthly payment',
      min: 1,
    );
    final months = _ledgerInt(
      values['installment_months'],
      'Installment months',
      min: 2,
      max: 120,
    );
    final down = _ledgerInt(values['down_payment_minor'] ?? 0, 'Down payment');
    if (monthly * months + down > _moneyLimit) {
      fail('The installment total exceeds the supported amount.');
    }
    final start = _ledgerDate(
      values['installment_start_on'],
      allowFuture: true,
    );
    if (existing == null && start.compareTo(date(clock())) < 0) {
      fail('A new installment plan must start today or later.');
    }
    final row = existing ?? _ledgerBase('installment_plans', body);
    row.addAll({
      'account_id': account['id'],
      'category_id': category['id'],
      'account_name_snapshot': account['name'],
      'category_name_snapshot': category['name'],
      'installment_monthly_minor': monthly,
      'installment_months': months,
      'installment_start_on': start,
      'down_payment_minor': down,
      'payee': values['payee'],
      'note': values['note'],
      'is_archived': false,
    });
    if (existing == null) {
      rows('installment_plans').add(row);
      if (down > 0) {
        postLedgerTransaction(
          {
            'client_uuid': _ledgerUuid(),
            'kind': 'expense',
            'amount_minor': down,
            'occurred_on': date(clock()),
            'account_id': account['id'],
            'category_id': category['id'],
            'payee': row['payee'],
            'note': row['note'],
          },
          sourceType: 'installment_plan_down_payment',
          sourceId: row['id'] as int,
          installmentPlanId: row['id'] as int,
          installmentNumber: 0,
        );
      }
    } else {
      row['version'] = (row['version'] as int) + 1;
    }
    return row;
  }

  Map<String, dynamic> _ledgerPayInstallment(
    Map<String, dynamic> plan,
    Map<String, dynamic> body,
  ) {
    final uuid = body['client_uuid'];
    if (uuid == null || uuid.toString().trim().isEmpty) {
      fail('A payment reference is required.');
    }
    final existing = rows('transactions')
        .where((t) => t['client_uuid'] == uuid)
        .firstOrNull;
    if (existing != null) {
      if (existing['installment_plan_id'] != plan['id'] ||
          existing['occurred_on'] != body['paid_on'] ||
          (body['account_id'] != null &&
              existing['account_id'] != body['account_id'])) {
        fail('This payment reference was already used with different details.');
      }
      return {
        'plan': installmentView(plan),
        'transaction': transactionView(existing),
      };
    }
    _ledgerVersion(plan, body);
    final view = installmentView(plan);
    if (view['status'] != 'active') {
      fail('This installment plan has no remaining payments.');
    }
    final account = _ledgerActiveAccount(
      body['account_id'] ?? plan['account_id'],
    );
    if (['credit_card', 'savings'].contains(account['type'])) {
      fail('Choose a cash, bank, or wallet account for the payment.');
    }
    final tx = postLedgerTransaction(
      {
        'client_uuid': uuid,
        'kind': 'expense',
        'amount_minor': plan['installment_monthly_minor'],
        'occurred_on': _ledgerDate(body['paid_on']),
        'account_id': account['id'],
        'category_id': plan['category_id'],
        'payee': plan['payee'],
        'note': plan['note'],
      },
      sourceType: 'installment_plan_payment',
      sourceId: plan['id'] as int,
      installmentPlanId: plan['id'] as int,
      installmentNumber: view['next_installment_number'] as int,
    );
    plan['version'] = (plan['version'] as int) + 1;
    return {'plan': installmentView(plan), 'transaction': transactionView(tx)};
  }

  Map<String, dynamic> _ledgerView(String table, Map<String, dynamic> row) =>
      switch (table) {
        'accounts' => accountView(row),
        'categories' => _ledgerCategoryView(row),
        'transactions' => transactionView(row),
        'account_transfers' ||
        'credit_card_payments' => _ledgerMovementView(table, row),
        'savings_interest_credits' => _ledgerInterestView(row),
        'installment_plans' => installmentView(row),
        _ => _ledgerPublic(row),
      };
}
