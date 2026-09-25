part of 'local_database.dart';

/// Local budget snapshots, reports and jewelry records. All amounts are integer
/// minor currency units; no market prices or records are fetched from a server.
extension LocalPlanning on LocalDatabase {
  Object? planningRequest(
    String method,
    List<String> path,
    Map<String, Object?> query,
    Map<String, dynamic> body,
  ) {
    if (path.isEmpty) return localUnhandled;
    final resource = path.first;
    if (method == 'GET' &&
        ((resource == 'dashboard' && path.length == 1) ||
            (resource == 'reports' &&
                path.length == 2 &&
                path[1] == 'summary'))) {
      return {'data': _planningReport(query)};
    }
    if (resource == 'cutoff-schedules') {
      _planningEnsureSchedule();
      if (path.length == 1 && method == 'GET') {
        final schedules = [...rows('cutoff_schedules')]
          ..sort(
            (a, b) =>
                '${b['effective_from']}'.compareTo('${a['effective_from']}'),
          );
        return {'data': schedules};
      }
      if (path.length == 1 && method == 'POST') {
        return {'data': _planningCreateSchedule(body)};
      }
      if (path.length == 2 && method == 'GET') {
        return {'data': find('cutoff_schedules', int.tryParse(path[1]) ?? 0)};
      }
    }
    if (resource == 'cutoff-periods') {
      if (method == 'GET' && path.length == 1) {
        final now = clock();
        final from = _planningDate(
          query['from'] ?? date(DateTime(now.year, now.month)),
        );
        final to = _planningDate(
          query['to'] ?? date(DateTime(now.year, now.month + 1, 0)),
        );
        if (to.isBefore(from) ||
            to.year * 12 + to.month - from.year * 12 - from.month > 60) {
          fail(
            'Choose a cutoff range of at most five years, with the end after the start.',
          );
        }
        _planningMaterializeRange(from, to);
        final periods =
            rows('cutoff_periods')
                .where(
                  (p) =>
                      '${p['ends_on']}'.compareTo(date(from)) >= 0 &&
                      '${p['starts_on']}'.compareTo(date(to)) <= 0,
                )
                .toList()
              ..sort(
                (a, b) => '${a['starts_on']}'.compareTo('${b['starts_on']}'),
              );
        return {'data': periods.map(_planningPeriodView).toList()};
      }
      if (path.length == 2 && method == 'GET') {
        final period = path[1] == 'current'
            ? resolveCutoff(_planningDate(query['date'] ?? date(clock())))
            : find('cutoff_periods', int.tryParse(path[1]) ?? 0);
        return {'data': _planningPeriodView(period)};
      }
      if (path.length == 3 && path[2] == 'budget') {
        final period = find('cutoff_periods', int.tryParse(path[1]) ?? 0);
        if (method == 'PUT') {
          final budget = _planningInteger(
            body['total_budget_minor'] ?? body['budget_minor'],
            'Budget',
          );
          final items = _planningBudgetItems(
            body['items'] ?? body['category_budgets'] ?? [],
            budget,
          );
          period.addAll({
            'budget_minor': budget,
            'budget_items': items,
            'is_budget_overridden': true,
          });
          return {'data': _planningPeriodView(period)};
        }
        if (method == 'DELETE') {
          period.addAll({
            'budget_minor': period['default_budget_minor'],
            'budget_items': _planningMaps(period['default_budget_items']),
            'is_budget_overridden': false,
          });
          return {'data': _planningPeriodView(period)};
        }
      }
    }
    if (resource == 'jewelry') {
      if (path.length == 1 && method == 'GET') {
        final search = '${query['search'] ?? ''}'.toLowerCase();
        final items =
            rows('jewelry')
                .where(
                  (item) =>
                      (item['is_archived'] != true ||
                          '${query['include_archived']}' == '1') &&
                      (query['status'] == null ||
                          item['status'] == query['status']) &&
                      '${item['name']} ${item['jewelry_type']} ${item['notes'] ?? ''}'
                          .toLowerCase()
                          .contains(search),
                )
                .toList()
              ..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
        return {'data': items.map(_planningJewelryView).toList()};
      }
      if (path.length == 1 && method == 'POST') {
        final item = _planningJewelryData(body)
          ..addAll({
            'id': nextId('jewelry'),
            'status': 'held',
            'is_archived': false,
            'created_at': clock().toIso8601String(),
            'updated_at': clock().toIso8601String(),
          });
        rows('jewelry').add(item);
        return {'data': _planningJewelryView(item)};
      }
      if (path.length >= 2) {
        final item = find('jewelry', int.tryParse(path[1]) ?? 0);
        if (path.length == 3 && path[2] == 'convert' && method == 'POST') {
          return {'data': _planningConvertJewelry(item, body)};
        }
        if (path.length == 2 && method == 'GET') {
          return {'data': _planningJewelryView(item)};
        }
        if (path.length == 2 && (method == 'PATCH' || method == 'PUT')) {
          final values = _planningJewelryData({...item, ...body});
          if (item['status'] == 'converted' &&
              values['acquired_on'] != null &&
              '${values['acquired_on']}'.compareTo('${item['converted_on']}') >
                  0) {
            fail(
              'The acquisition date must be on or before the conversion date.',
            );
          }
          item.addAll({...values, 'updated_at': clock().toIso8601String()});
          return {'data': _planningJewelryView(item)};
        }
        if (path.length == 2 && method == 'DELETE') {
          item['is_archived'] = true;
          return {'data': null};
        }
      }
    }
    if (resource == 'gold-price') {
      if (path.length == 2 && path[1] == 'manual') {
        if (method == 'PUT') {
          final rates = _planningMaps(body['rates']);
          if (body['rates'] is! List || rates.length > 24) {
            fail('Enter up to 24 gold prices.');
          }
          final karats = <int>{};
          final validated = <Map<String, dynamic>>[];
          for (final rate in rates) {
            final karat = _planningInteger(
              rate['karat'],
              'Karat',
              minimum: 1,
              maximum: 24,
            );
            if (!karats.add(karat)) {
              fail('Enter only one price for each karat.');
            }
            validated.add({
              'karat': karat,
              'price_per_gram_minor': _planningInteger(
                rate['price_per_gram_minor'],
                'Price per gram',
                minimum: 1,
              ),
              'source': 'manual',
              'quoted_at': null,
              'updated_at': clock().toIso8601String(),
            });
          }
          rows('gold_price_rates')
            ..clear()
            ..addAll(validated);
        }
        if (method == 'GET' || method == 'PUT') {
          return {
            'data': {'currency_code': 'PHP', 'rates': rows('gold_price_rates')},
          };
        }
      }
      if (path.length == 1 && method == 'GET') {
        final gold24 = rows('gold_price_rates')
            .where((rate) => rate['karat'] == 24)
            .firstOrNull;
        if (gold24 == null) {
          fail(
            'This app works offline. Add a manual 24K price in Gold Prices to use a gold reference.',
          );
        }
        final updated = DateTime.parse(gold24['updated_at'] as String);
        return {
          'data': {
            'provider': 'Your saved price',
            'currency_code': 'PHP',
            'unit': 'gram',
            'price_24k_per_gram_minor': gold24['price_per_gram_minor'],
            'quoted_at': updated.toIso8601String(),
            'fetched_at': updated.toIso8601String(),
            'age_seconds': clock()
                .difference(updated)
                .inSeconds
                .clamp(0, 2147483647),
            'source': 'manual',
            'is_cached': true,
            'is_stale': false,
            'warning': 'Saved manually on this device. Update prices yourself when needed.',
          },
        };
      }
    }
    return localUnhandled;
  }

  Map<String, dynamic> resolveCutoff(DateTime on) {
    final day = date(on);
    var existing = rows('cutoff_periods')
        .where(
          (p) =>
              '${p['starts_on']}'.compareTo(day) <= 0 &&
              '${p['ends_on']}'.compareTo(day) >= 0,
        )
        .firstOrNull;
    if (existing != null) return existing;
    _planningMaterializeMonth(on);
    existing = rows('cutoff_periods')
        .where(
          (p) =>
              '${p['starts_on']}'.compareTo(day) <= 0 &&
              '${p['ends_on']}'.compareTo(day) >= 0,
        )
        .firstOrNull;
    if (existing == null) fail('No cutoff schedule covers this date.');
    return existing;
  }

  void _planningEnsureSchedule() {
    if (rows('cutoff_schedules').isNotEmpty) return;
    rows('cutoff_schedules').add({
      'id': nextId('cutoff_schedules'),
      'name': 'Semi-monthly',
      'scope': 'personal',
      'effective_from': '1900-01-01',
      'effective_to': null,
      'is_active': true,
      'rules': [
        {
          'id': nextId('cutoff_rules'),
          'label': 'First cutoff',
          'position': 1,
          'start_day': 1,
          'default_budget_minor': 0,
          'category_budgets': <Map<String, dynamic>>[],
        },
        {
          'id': nextId('cutoff_rules'),
          'label': 'Second cutoff',
          'position': 2,
          'start_day': 16,
          'default_budget_minor': 0,
          'category_budgets': <Map<String, dynamic>>[],
        },
      ],
    });
  }

  Map<String, dynamic> _planningCreateSchedule(Map<String, dynamic> body) {
    final start = _planningDate(body['effective_from']);
    if (start.day != 1) {
      fail('A schedule must start on the first day of a month.');
    }
    final name = _planningText(body['name'], 'Schedule name', maximum: 100);
    final inputRules = _planningMaps(body['rules']);
    if (inputRules.isEmpty || inputRules.length > 28) {
      fail('Add at least one cutoff rule.');
    }
    var previousDay = 0;
    final rules = <Map<String, dynamic>>[];
    for (final input in inputRules) {
      final day = _planningInteger(
        input['start_day'],
        'Start day',
        minimum: 1,
        maximum: 28,
      );
      if ((previousDay == 0 && day != 1) || day <= previousDay) {
        fail(
          'Cutoff rules must start on day 1 and be ordered by unique start days.',
        );
      }
      previousDay = day;
      final budget = _planningInteger(
        input['default_budget_minor'],
        'Default budget',
      );
      rules.add({
        'id': nextId('cutoff_rules'),
        'label': _planningText(input['label'], 'Rule label', maximum: 80),
        'position': rules.length + 1,
        'start_day': day,
        'default_budget_minor': budget,
        'category_budgets': _planningBudgetItems(
          input['category_budgets'] ?? [],
          budget,
        ),
      });
    }
    final effective = date(start);
    if (rows('cutoff_schedules')
        .any((s) => '${s['effective_from']}'.compareTo(effective) >= 0)) {
      fail(
        'A schedule already starts on or after this date. Choose a later month.',
      );
    }
    final protected = rows('cutoff_periods').any(
      (p) =>
          '${p['starts_on']}'.compareTo(effective) >= 0 &&
          p['is_budget_overridden'] == true,
    );
    final transactions = rows('transactions').any(
      (t) =>
          t['deleted_at'] == null &&
          t['is_archived'] != true &&
          '${t['occurred_on']}'.compareTo(effective) >= 0,
    );
    if (protected || transactions) {
      fail(
        'This schedule would replace cutoffs containing transactions or budget overrides. Choose a later month.',
      );
    }
    rows('cutoff_periods')
        .removeWhere((p) => '${p['starts_on']}'.compareTo(effective) >= 0);
    final previous = [...rows('cutoff_schedules')]
      ..sort(
        (a, b) => '${b['effective_from']}'.compareTo('${a['effective_from']}'),
      );
    if (previous.isNotEmpty) {
      previous.first.addAll({
        'effective_to': date(start.subtract(const Duration(days: 1))),
        'is_active': false,
      });
    }
    final schedule = <String, dynamic>{
      'id': nextId('cutoff_schedules'),
      'scope': 'personal',
      'name': name,
      'effective_from': effective,
      'effective_to': null,
      'is_active': true,
      'rules': rules,
    };
    rows('cutoff_schedules').add(schedule);
    return schedule;
  }

  void _planningMaterializeRange(DateTime from, DateTime to) {
    var cursor = DateTime(from.year, from.month);
    while (!cursor.isAfter(to)) {
      _planningMaterializeMonth(cursor);
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
  }

  void _planningMaterializeMonth(DateTime month) {
    _planningEnsureSchedule();
    final monthStart = date(DateTime(month.year, month.month));
    final schedules =
        rows('cutoff_schedules')
            .where(
              (s) =>
                  '${s['effective_from']}'.compareTo(monthStart) <= 0 &&
                  (s['effective_to'] == null ||
                      '${s['effective_to']}'.compareTo(monthStart) >= 0),
            )
            .toList()
          ..sort(
            (a, b) =>
                '${b['effective_from']}'.compareTo('${a['effective_from']}'),
          );
    if (schedules.isEmpty) fail('No cutoff schedule covers this date.');
    final schedule = schedules.first;
    final rules = _planningMaps(schedule['rules']);
    for (var i = 0; i < rules.length; i++) {
      final rule = rules[i];
      final from = date(
        DateTime(month.year, month.month, rule['start_day'] as int),
      );
      final to = date(
        i + 1 == rules.length
            ? DateTime(month.year, month.month + 1, 0)
            : DateTime(
                month.year,
                month.month,
                (rules[i + 1]['start_day'] as int) - 1,
              ),
      );
      if (rows('cutoff_periods')
          .any((p) => p['starts_on'] == from && p['ends_on'] == to)) {
        continue;
      }
      rows('cutoff_periods').add({
        'id': nextId('cutoff_periods'),
        'scope': 'personal',
        'starts_on': from,
        'ends_on': to,
        'cutoff_schedule_id': schedule['id'],
        'cutoff_rule_id': rule['id'],
        'label': rule['label'],
        'budget_minor': rule['default_budget_minor'],
        'default_budget_minor': rule['default_budget_minor'],
        'is_budget_overridden': false,
        'budget_items': _planningMaps(rule['category_budgets']),
        'default_budget_items': _planningMaps(rule['category_budgets']),
      });
    }
  }

  List<Map<String, dynamic>> _planningBudgetItems(Object? value, int budget) {
    if (value is! List) fail('Category budgets must be a list.');
    final result = <Map<String, dynamic>>[];
    final ids = <int>{};
    var allocated = 0;
    for (final item in _planningMaps(value)) {
      final id = _planningInteger(item['category_id'], 'Category', minimum: 1);
      final category = find('categories', id);
      if (!ids.add(id) ||
          category['kind'] != 'expense' ||
          category['is_archived'] == true ||
          category['is_active'] == false) {
        fail('Choose a unique, active expense category for each budget.');
      }
      final amount = _planningInteger(item['amount_minor'], 'Category budget');
      allocated += amount;
      result.add({'category_id': id, 'amount_minor': amount});
    }
    if (allocated > budget) {
      fail('Category allocations cannot exceed the cutoff budget.');
    }
    return result;
  }

  Map<String, dynamic> _planningPeriodView(Map<String, dynamic> period) {
    final expenses = _planningTransactions(
      '${period['starts_on']}',
      '${period['ends_on']}',
    ).where((t) => t['kind'] == 'expense').toList();
    return {
      ...period,
      'spent_minor': _planningSum(expenses, 'amount_minor'),
      'budget_items': _planningMaps(period['budget_items']).map((item) {
        final category = rows('categories')
            .where((c) => c['id'] == item['category_id'])
            .firstOrNull;
        return {
          ...item,
          'category': category,
          'category_name': category?['name'] ?? 'Category',
          'spent_minor': _planningSum(
            expenses.where((t) => t['category_id'] == item['category_id']),
            'amount_minor',
          ),
        };
      }).toList(),
    };
  }

  Map<String, dynamic> _planningReport(Map<String, Object?> query) {
    final period = '${query['period'] ?? 'month'}';
    final anchor = _planningDate(query['anchor'] ?? date(clock()));
    late DateTime from;
    late DateTime to;
    late String label;
    Map<String, dynamic>? cutoff;
    switch (period) {
      case 'week':
        final settings = state['settings'];
        final weekStart = settings is Map
            ? (settings['week_starts_on'] as int? ?? 1)
            : 1;
        from = anchor.subtract(
          Duration(days: (anchor.weekday % 7 - weekStart + 7) % 7),
        );
        to = from.add(const Duration(days: 6));
        label = '${date(from)} – ${date(to)}';
      case 'month':
        from = DateTime(anchor.year, anchor.month);
        to = DateTime(anchor.year, anchor.month + 1, 0);
        label = '${_planningMonths[anchor.month - 1]} ${anchor.year}';
      case 'year':
        from = DateTime(anchor.year);
        to = DateTime(anchor.year, 12, 31);
        label = '${anchor.year}';
      case 'cutoff':
        cutoff = resolveCutoff(anchor);
        from = _planningDate(cutoff['starts_on']);
        to = _planningDate(cutoff['ends_on']);
        label = '${cutoff['label']}';
      default:
        fail('Choose week, month, year or cutoff.');
    }
    if (period == 'month' || period == 'year') {
      _planningMaterializeRange(from, to);
    }
    final start = date(from);
    final end = date(to);
    final transactions = _planningTransactions(start, end);
    final income = _planningSum(
      transactions.where((t) => t['kind'] == 'income'),
      'amount_minor',
    );
    final expenses = _planningSum(
      transactions.where((t) => t['kind'] == 'expense'),
      'amount_minor',
    );
    final budgets = cutoff != null
        ? [cutoff]
        : rows('cutoff_periods')
              .where(
                (p) =>
                    '${p['starts_on']}'.compareTo(start) >= 0 &&
                    '${p['ends_on']}'.compareTo(end) <= 0,
              )
              .toList();
    final budget = period == 'week'
        ? null
        : _planningSum(budgets, 'budget_minor');
    final categoryBudgets = <int, int>{};
    if (period != 'week') {
      for (final p in budgets) {
        for (final item in _planningMaps(p['budget_items'])) {
          final id = item['category_id'] as int;
          categoryBudgets[id] =
              (categoryBudgets[id] ?? 0) + (item['amount_minor'] as int);
        }
      }
    }
    final categoryTotals = <int, int>{};
    for (final transaction in transactions.where(
      (t) => t['kind'] == 'expense',
    )) {
      final id = transaction['category_id'] as int;
      categoryTotals[id] =
          (categoryTotals[id] ?? 0) + (transaction['amount_minor'] as int);
    }
    Map<String, dynamic> categoryData(int id) =>
        rows('categories').where((c) => c['id'] == id).firstOrNull ?? {};
    final categories =
        categoryTotals.entries.map((entry) {
          final category = categoryData(entry.key);
          return <String, dynamic>{
            'category_id': entry.key,
            'name': category['name'] ?? 'Uncategorized',
            'color': category['color'] ?? '#43D98B',
            'amount_minor': entry.value,
            'budget_minor': categoryBudgets[entry.key] ?? 0,
            'share_basis_points': _planningRatio(entry.value, expenses),
          };
        }).toList()..sort(
          (a, b) =>
              (b['amount_minor'] as int).compareTo(a['amount_minor'] as int),
        );
    final categoryStatus = categoryBudgets.entries.map((entry) {
      final actual = categoryTotals[entry.key] ?? 0;
      return {
        'category_id': entry.key,
        'name': categoryData(entry.key)['name'],
        'budget_minor': entry.value,
        'expense_minor': actual,
        'remaining_minor': entry.value - actual,
        'utilization_basis_points': _planningRatio(actual, entry.value),
      };
    }).toList();
    final series = <Map<String, dynamic>>[];
    var cursor = from;
    while (!cursor.isAfter(to)) {
      final key = period == 'year'
          ? date(cursor).substring(0, 7)
          : date(cursor);
      final bucket = transactions.where(
        (t) => '${t['occurred_on']}'.startsWith(key),
      );
      final bucketIncome = _planningSum(
        bucket.where((t) => t['kind'] == 'income'),
        'amount_minor',
      );
      final bucketExpenses = _planningSum(
        bucket.where((t) => t['kind'] == 'expense'),
        'amount_minor',
      );
      series.add({
        'date': key,
        'income_minor': bucketIncome,
        'expense_minor': bucketExpenses,
        'net_minor': bucketIncome - bucketExpenses,
      });
      cursor = period == 'year'
          ? DateTime(cursor.year, cursor.month + 1)
          : cursor.add(const Duration(days: 1));
    }
    final accounts = rows('accounts')
        .where((a) => a['is_archived'] != true || a['type'] == 'credit_card')
        .map((a) => {...accountView(a, through: to), 'account_id': a['id']})
        .where((a) => a['is_archived'] != true || a['balance_minor'] != 0)
        .toList();
    final cash = _planningSum(
      accounts.where((a) => a['type'] != 'credit_card'),
      'balance_minor',
    );
    final savings = _planningSum(
      accounts.where((a) => a['type'] == 'savings'),
      'balance_minor',
    );
    final available = _planningSum(
      accounts.where(
        (a) => a['type'] != 'credit_card' && a['type'] != 'savings',
      ),
      'balance_minor',
    );
    final debt = _planningSum(
      accounts.where((a) => a['type'] == 'credit_card'),
      'debt_minor',
    );
    final held = rows('jewelry')
        .where((j) => j['is_archived'] != true && j['status'] == 'held')
        .toList();
    final known = held.where((j) => j['purchase_value_minor'] != null).toList();
    final knownCost = _planningSum(known, 'purchase_value_minor');
    final recent = [...transactions]
      ..sort((a, b) {
        final day = '${b['occurred_on']}'.compareTo('${a['occurred_on']}');
        return day == 0 ? (b['id'] as int).compareTo(a['id'] as int) : day;
      });
    final previousEnd = from.subtract(const Duration(days: 1));
    late DateTime previousStart;
    if (period == 'year') {
      previousStart = DateTime(from.year - 1);
    } else if (period == 'month') {
      previousStart = DateTime(from.year, from.month - 1);
    } else if (period == 'cutoff' && previousEnd.year >= 1900) {
      previousStart = _planningDate(resolveCutoff(previousEnd)['starts_on']);
    } else {
      previousStart = previousEnd.subtract(
        Duration(days: to.difference(from).inDays),
      );
    }
    final previous = _planningTransactions(
      date(previousStart),
      date(previousEnd),
    );
    final previousIncome = _planningSum(
      previous.where((t) => t['kind'] == 'income'),
      'amount_minor',
    );
    final previousExpense = _planningSum(
      previous.where((t) => t['kind'] == 'expense'),
      'amount_minor',
    );
    final utilization = budget == null
        ? null
        : _planningRatio(expenses, budget);
    final savingsRate = _planningRatio(income - expenses, income);
    return {
      'period': period,
      'scope': 'personal',
      'anchor': date(anchor),
      'label': label,
      'range': {'from': start, 'to': end},
      'cutoff_period_id': cutoff?['id'],
      'income_minor': income,
      'expense_minor': expenses,
      'net_cash_flow_minor': income - expenses,
      'budget_minor': budget,
      'budget_source': period == 'week'
          ? null
          : period == 'cutoff'
          ? 'cutoff_period'
          : 'cutoff_periods_sum',
      'remaining_budget_minor': budget == null ? null : budget - expenses,
      'cash_balance_minor': cash,
      'savings_balance_minor': savings,
      'available_money_minor': available,
      'credit_card_debt_minor': debt,
      'net_position_minor': cash - debt,
      'utilization_basis_points': utilization,
      'utilization_percent': utilization == null ? null : utilization / 100,
      'savings_rate_basis_points': savingsRate,
      'savings_rate_percent': savingsRate == null ? null : savingsRate / 100,
      'cash_flow_series': series,
      'expenses_by_category': categories,
      'category_budget_status': categoryStatus,
      'account_balances': accounts,
      'recent_transactions': recent.take(10).map(transactionView).toList(),
      'jewelry_portfolio': {
        'held_count': held.length,
        'cost_known_count': known.length,
        'cost_missing_count': held.length - known.length,
        'total_estimated_value_minor': _planningSum(
          held,
          'estimated_value_minor',
        ),
        'known_purchase_cost_minor': knownCost,
        'unrealized_gain_loss_minor':
            _planningSum(known, 'estimated_value_minor') - knownCost,
      },
      'comparison': {
        'previous_range': {
          'from': date(previousStart),
          'to': date(previousEnd),
        },
        'income_minor': previousIncome,
        'expense_minor': previousExpense,
        'net_cash_flow_minor': previousIncome - previousExpense,
        'income_change_basis_points': _planningRatio(
          income - previousIncome,
          previousIncome.abs(),
        ),
        'expense_change_basis_points': _planningRatio(
          expenses - previousExpense,
          previousExpense.abs(),
        ),
      },
    };
  }

  Map<String, dynamic> _planningJewelryData(Map<String, dynamic> body) {
    final acquired = body['acquired_on'] == null
        ? null
        : _planningDate(body['acquired_on']);
    if (acquired != null && date(acquired).compareTo(date(clock())) > 0) {
      fail('The acquisition date cannot be in the future.');
    }
    return {
      'name': _planningText(body['name'], 'Jewelry name', maximum: 120),
      'jewelry_type': _planningText(
        body['jewelry_type'],
        'Jewelry type',
        maximum: 80,
      ),
      'karat': _planningInteger(
        body['karat'],
        'Karat',
        minimum: 1,
        maximum: 24,
      ),
      'weight_mg': _planningInteger(body['weight_mg'], 'Weight', minimum: 1),
      'acquired_on': acquired == null ? null : date(acquired),
      'purchase_value_minor': body['purchase_value_minor'] == null
          ? null
          : _planningInteger(body['purchase_value_minor'], 'Purchase value'),
      'estimated_value_minor': _planningInteger(
        body['estimated_value_minor'],
        'Estimated value',
      ),
      'notes': body['notes'] == null
          ? null
          : _planningText(
              body['notes'],
              'Notes',
              maximum: 2000,
              allowEmpty: true,
            ),
    };
  }

  Map<String, dynamic> _planningJewelryView(Map<String, dynamic> item) {
    final account = rows('accounts')
        .where((a) => a['id'] == item['conversion_account_id'])
        .firstOrNull;
    return {
      ...item,
      'conversion_account': account == null ? null : accountView(account),
    };
  }

  Map<String, dynamic> _planningConvertJewelry(
    Map<String, dynamic> item,
    Map<String, dynamic> body,
  ) {
    final uuid = _planningText(
      body['client_uuid'],
      'Conversion reference',
      maximum: 100,
    );
    if (item['is_archived'] == true) {
      fail('Restore this jewelry item before converting it.');
    }
    if (item['status'] == 'converted') {
      if (item['conversion_client_uuid'] == uuid) {
        return _planningJewelryView(item);
      }
      fail('This jewelry item has already been converted.');
    }
    if (rows('transactions')
        .any((transaction) => transaction['client_uuid'] == uuid)) {
      fail(
        'This conversion reference has already been used by another transaction.',
      );
    }
    final converted = _planningDate(body['converted_on']);
    if (date(converted).compareTo(date(clock())) > 0) {
      fail('The conversion date cannot be in the future.');
    }
    if (item['acquired_on'] != null &&
        date(converted).compareTo('${item['acquired_on']}') < 0) {
      fail('The conversion date must be on or after the acquisition date.');
    }
    final account = find(
      'accounts',
      _planningInteger(body['account_id'], 'Account', minimum: 1),
    );
    if (account['is_archived'] == true ||
        account['is_active'] == false ||
        account['type'] == 'credit_card' ||
        account['type'] == 'savings') {
      fail('Choose an active cash, bank or e-wallet account for the sale.');
    }
    var category = rows('categories')
        .where((c) => c['kind'] == 'income' && c['name'] == 'Jewelry Sale')
        .firstOrNull;
    if (category == null) {
      category = {
        'id': nextId('categories'),
        'name': 'Jewelry Sale',
        'kind': 'income',
        'is_active': true,
        'is_archived': false,
        'color': '#D4A72C',
        'icon': 'diamond',
      };
      rows('categories').add(category);
    } else {
      category.addAll({'is_archived': false, 'is_active': true});
    }
    final transaction = postLedgerTransaction(
      {
        'client_uuid': uuid,
        'kind': 'income',
        'amount_minor': _planningInteger(
          body['amount_minor'],
          'Sale amount',
          minimum: 1,
        ),
        'occurred_on': date(converted),
        'account_id': account['id'],
        'category_id': category['id'],
        'payee': 'Jewelry sale',
        'note': 'Converted from jewelry item #${item['id']}: ${item['name']}',
      },
      sourceType: 'jewelry_conversion',
      sourceId: item['id'] as int,
    );
    item.addAll({
      'status': 'converted',
      'conversion_client_uuid': uuid,
      'converted_on': date(converted),
      'conversion_amount_minor': transaction['amount_minor'],
      'conversion_account_id': account['id'],
      'conversion_transaction_id': transaction['id'],
      'updated_at': clock().toIso8601String(),
    });
    return _planningJewelryView(item);
  }

  List<Map<String, dynamic>> _planningTransactions(String from, String to) =>
      rows('transactions')
          .where(
            (t) =>
                t['deleted_at'] == null &&
                t['is_archived'] != true &&
                '${t['occurred_on']}'.compareTo(from) >= 0 &&
                '${t['occurred_on']}'.compareTo(to) <= 0,
          )
          .toList();

  int _planningInteger(
    Object? value,
    String label, {
    int minimum = 0,
    int maximum = 999999999999999,
  }) {
    if (value is! int || value < minimum || value > maximum) {
      fail('$label must be a whole number between $minimum and $maximum.');
    }
    return value;
  }

  String _planningText(
    Object? value,
    String label, {
    required int maximum,
    bool allowEmpty = false,
  }) {
    if (value is! String ||
        (!allowEmpty && value.trim().isEmpty) ||
        value.length > maximum) {
      fail('Enter $label using at most $maximum characters.');
    }
    return (value).trim();
  }

  DateTime _planningDate(Object? value) {
    final text = value?.toString() ?? '';
    final parsed = DateTime.tryParse(text);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ||
        parsed == null ||
        date(parsed) != text ||
        parsed.year < 1900 ||
        parsed.year > 9999) {
      fail('Enter a valid date from 1900 onward.');
    }
    return parsed;
  }

  List<Map<String, dynamic>> _planningMaps(Object? value) {
    if (value is! List) return [];
    if (value.any((item) => item is! Map)) {
      fail('Enter a valid list of records.');
    }
    return value.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  int _planningSum(Iterable<Map<String, dynamic>> values, String key) =>
      values.fold(0, (total, value) => total + (value[key] as int? ?? 0));

  int? _planningRatio(int numerator, int denominator) {
    if (denominator <= 0) return null;
    final value = BigInt.from(numerator) * BigInt.from(10000);
    final divisor = BigInt.from(denominator);
    final rounded = (value.abs() + divisor ~/ BigInt.two) ~/ divisor;
    return (value.isNegative ? -rounded : rounded).toInt();
  }
}

const _planningMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
