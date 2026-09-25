part of 'local_database.dart';

extension LocalBackupValidation on LocalDatabase {
  /// Validate before replacing the current file or making restored rows live.
  Map<String, dynamic> validateBackupDocument(Object? document) =>
      _LocalBackupValidator(document).validate();
}

class _LocalBackupValidator {
  _LocalBackupValidator(this.document);

  final Object? document;
  late Map<String, dynamic> result;
  final tables = <String, Map<int, Map<String, dynamic>>>{};
  final balances = <int, BigInt>{};
  final managedTransactions = <int>{};
  static const tableNames = [
    'accounts',
    'categories',
    'transactions',
    'account_transfers',
    'credit_card_payments',
    'savings_interest_credits',
    'installment_plans',
    'jewelry',
    'cutoff_schedules',
    'cutoff_periods',
  ];

  Never invalid(String detail) =>
      throw FormatException('Invalid backup: $detail.');

  Map<String, dynamic> map(Object? value, String label) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      invalid('$label must be an object');
    }
    return Map<String, dynamic>.from(value);
  }

  List<Map<String, dynamic>> list(Object? value, String label) {
    if (value is! List) invalid('$label must be a list');
    return value.map((item) => map(item, label)).toList();
  }

  int integer(
    Object? value,
    String label, {
    int min = 0,
    int max = Money.maxMinorUnits,
  }) {
    if (value is! int || value < min || value > max) {
      invalid('$label must be an integer from $min to $max');
    }
    return value;
  }

  String text(Object? value, String label) {
    if (value is! String || value.trim().isEmpty) invalid('$label is required');
    return value;
  }

  void optionalText(Object? value, String label) {
    if (value != null && value is! String) invalid('$label must be text');
  }

  String choice(Object? value, List<String> choices, String label) {
    if (value is! String || !choices.contains(value)) {
      invalid('unsupported $label');
    }
    return value;
  }

  String day(Object? value, String label) {
    final raw = text(value, label);
    final parsed = DateTime.tryParse(raw);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw) ||
        parsed == null ||
        parsed.year < 1900 ||
        parsed.year > 9999 ||
        '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}' !=
            raw) {
      invalid('$label must be a valid calendar date');
    }
    return raw;
  }

  void timestamp(Object? value, String label) {
    if (value != null &&
        (value is! String || DateTime.tryParse(value) == null)) {
      invalid('$label must be a timestamp');
    }
  }

  Map<String, dynamic> reference(String table, Object? id, String label) {
    final value = integer(id, label, min: 1);
    final found = tables[table]?[value];
    if (found == null) invalid('$label references a missing $table record');
    return found;
  }

  Iterable<Map<String, dynamic>> rows(String table) => tables[table]!.values;

  void common(Map<String, dynamic> row, String table) {
    if (row['scope'] != null && row['scope'] != 'personal') {
      invalid('only personal records are supported');
    }
    for (final flag in [
      'is_archived',
      'is_active',
      'is_system',
      'is_budget_overridden',
    ]) {
      if (row[flag] != null && row[flag] is! bool) {
        invalid('$table.$flag must be true or false');
      }
    }
    if (row['version'] != null) {
      integer(row['version'], '$table version', min: 1);
    }
    for (final field in ['created_at', 'updated_at']) {
      timestamp(row[field], '$table.$field');
    }
    for (final field in [
      'name',
      'color',
      'icon',
      'note',
      'notes',
      'payee',
      'system_key',
    ]) {
      optionalText(row[field], '$table.$field');
    }
    if (row['_request_payload'] != null) {
      map(row['_request_payload'], 'Original request');
    }
    for (final entry in row.entries) {
      if (entry.key.endsWith('_minor') && entry.value != null) {
        integer(entry.value, '$table.${entry.key}', min: -Money.maxMinorUnits);
      }
    }
  }

  Map<String, dynamic> validate() {
    result = map(document, 'Backup');
    // Accept backups exported before the app-name correction.
    const legacyFormat = 'expeneses_tracker_offline';
    if ((result['format'] != 'expenses_tracker_offline' &&
            result['format'] != legacyFormat) ||
        result['schema_version'] != 1) {
      invalid('unsupported format or version');
    }
    result['format'] = 'expenses_tracker_offline';
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(text(result['installation_id'], 'Installation ID'))) {
      invalid('invalid installation ID');
    }
    final settings = map(result['settings'], 'Settings');
    if (!RegExp(r'^[A-Z]{3}$')
        .hasMatch(text(settings['currency_code'], 'Currency'))) {
      invalid('invalid currency');
    }
    final locale = text(settings['locale'], 'Locale');
    try {
      Money.format(
        0,
        locale: locale,
        currencyCode: settings['currency_code'] as String,
      );
    } catch (_) {
      invalid('unsupported number format locale');
    }
    text(settings['timezone'], 'Timezone');
    integer(settings['week_starts_on'], 'Week start', max: 6);
    for (final flag in [
      'show_jewelry_in_reports',
      'show_credit_cards_in_reports',
    ]) {
      if (settings.containsKey(flag) && settings[flag] is! bool) {
        invalid('Settings.$flag must be true or false');
      }
      settings.putIfAbsent(flag, () => true);
    }
    result['settings'] = settings;
    final sequences = map(result['sequences'], 'Sequences');
    for (final entry in sequences.entries) {
      integer(entry.value, 'Sequence ${entry.key}');
    }
    for (final table in tableNames) {
      final indexed = <int, Map<String, dynamic>>{};
      final uuids = <String>{};
      for (final row in list(result[table], table)) {
        final id = integer(row['id'], '$table ID', min: 1);
        if (indexed.containsKey(id)) invalid('duplicate $table ID');
        common(row, table);
        if (row['client_uuid'] != null &&
            !uuids.add(text(row['client_uuid'], '$table reference'))) {
          invalid('duplicate $table reference');
        }
        indexed[id] = row;
      }
      tables[table] = indexed;
    }
    if (rows('accounts').isEmpty) invalid('at least one account is required');
    _accounts();
    _categories();
    _schedules();
    _transactions();
    _movements('account_transfers');
    _movements('credit_card_payments');
    _interest();
    _plans();
    _jewelry();
    _gold();
    for (final row in rows('transactions')) {
      if (row['source_type'] != null &&
          !managedTransactions.contains(row['id'])) {
        invalid('a managed transaction has no matching source');
      }
    }
    for (final account in rows('accounts')) {
      final balance = balances[account['id']]!;
      if (balance.abs() > BigInt.from(Money.maxMinorUnits)) {
        invalid('account balance exceeds the supported amount');
      }
      final card = account['type'] == 'credit_card';
      if ((card && balance > BigInt.zero) || (!card && balance < BigInt.zero)) {
        invalid('account balance has an invalid sign');
      }
      if (card &&
          account['credit_limit_minor'] != null &&
          -balance > BigInt.from(account['credit_limit_minor'] as int)) {
        invalid('credit card debt exceeds its limit');
      }
      if (account['is_archived'] == true &&
          ['savings', 'credit_card'].contains(account['type']) &&
          balance != BigInt.zero) {
        invalid(
          'an archived savings or credit card account has an unsettled balance',
        );
      }
    }
    return result;
  }

  void _accounts() {
    final names = <String>{};
    for (final account in rows('accounts')) {
      if (!names.add(text(account['name'], 'Account name').toLowerCase())) {
        invalid('duplicate account name');
      }
      final type = choice(account['type'], [
        'cash',
        'bank',
        'ewallet',
        'other',
        'savings',
        'credit_card',
      ], 'account type');
      final opening = integer(
        account['opening_balance_minor'],
        'Opening balance',
        min: type == 'credit_card' ? -Money.maxMinorUnits : 0,
        max: type == 'credit_card' ? 0 : Money.maxMinorUnits,
      );
      balances[account['id'] as int] = BigInt.from(opening);
      if (account['credit_limit_minor'] != null) {
        integer(account['credit_limit_minor'], 'Credit limit', min: 1);
      }
      for (final key in ['statement_day', 'due_day']) {
        if (account[key] != null) integer(account[key], key, min: 1, max: 31);
      }
      final rate = integer(
        account['monthly_interest_rate_basis_points'] ?? 0,
        'Monthly interest rate',
        max: 10000,
      );
      if (type != 'savings' && rate != 0) {
        invalid('only savings accounts can accrue interest');
      }
      for (final field in [
        'interest_accrual_anchor_on',
        'next_interest_accrual_on',
        'interest_last_processed_on',
      ]) {
        if (account[field] != null) day(account[field], field);
      }
      if (type == 'savings' && rate > 0) {
        final anchor = day(
          account['interest_accrual_anchor_on'],
          'Interest anchor',
        );
        final next = day(
          account['next_interest_accrual_on'],
          'Next interest date',
        );
        if (next.compareTo(anchor) <= 0) {
          invalid('the next interest date must follow the anchor');
        }
        final a = DateTime.parse(anchor);
        final n = DateTime.parse(next);
        final lastDay = DateTime(n.year, n.month + 1, 0).day;
        if (n.day != min(a.day, lastDay) ||
            n.year * 12 + n.month <= a.year * 12 + a.month) {
          invalid('invalid monthly interest schedule');
        }
      }
    }
  }

  void _categories() {
    final names = <String>{};
    final system = <String>{};
    for (final category in rows('categories')) {
      final kind = choice(category['kind'], [
        'income',
        'expense',
      ], 'category kind');
      if (!names.add(
        '$kind:${text(category['name'], 'Category name').toLowerCase()}',
      )) {
        invalid('duplicate category name');
      }
      final key = category['system_key'];
      if (key != null) {
        choice(key, [
          'account_transfer_fee',
          'savings_interest',
        ], 'system category');
        if (!system.add(key as String)) invalid('duplicate system category');
        if (kind != (key == 'savings_interest' ? 'income' : 'expense') ||
            category['is_archived'] == true) {
          invalid('invalid built-in category');
        }
      }
    }
    if (!system.containsAll(['account_transfer_fee', 'savings_interest'])) {
      invalid('required built-in categories are missing');
    }
  }

  List<Map<String, dynamic>> budgetItems(Object? value, int budget) {
    final items = list(value, 'Category budgets');
    final ids = <int>{};
    var total = BigInt.zero;
    for (final item in items) {
      final category = reference(
        'categories',
        item['category_id'],
        'Budget category',
      );
      if (category['kind'] != 'expense' || !ids.add(category['id'] as int)) {
        invalid('budget categories must be unique expense categories');
      }
      total += BigInt.from(integer(item['amount_minor'], 'Category budget'));
    }
    if (total > BigInt.from(budget)) {
      invalid('category budgets exceed the total');
    }
    return items;
  }

  void _schedules() {
    final ruleIds = <int>{};
    final ruleById = <int, Map<String, dynamic>>{};
    final ruleSchedule = <int, int>{};
    final schedules = rows('cutoff_schedules').toList();
    for (final schedule in schedules) {
      text(schedule['name'], 'Schedule name');
      final start = day(schedule['effective_from'], 'Schedule start');
      if (!start.endsWith('-01')) {
        invalid('schedule must start on the first day of a month');
      }
      if (schedule['effective_to'] != null &&
          day(schedule['effective_to'], 'Schedule end').compareTo(start) < 0) {
        invalid('schedule ends before it starts');
      }
      final rules = list(schedule['rules'], 'Cutoff rules');
      if (rules.isEmpty || rules.length > 28) {
        invalid('schedule needs 1 to 28 cutoff rules');
      }
      var previousDay = 0;
      for (final rule in rules) {
        final id = integer(rule['id'], 'Rule ID', min: 1);
        if (!ruleIds.add(id)) invalid('duplicate cutoff rule ID');
        ruleById[id] = rule;
        ruleSchedule[id] = schedule['id'] as int;
        text(rule['label'], 'Rule label');
        final startDay = integer(
          rule['start_day'],
          'Rule day',
          min: 1,
          max: 28,
        );
        if ((previousDay == 0 && startDay != 1) || startDay <= previousDay) {
          invalid('rules must be ordered and start on day 1');
        }
        previousDay = startDay;
        budgetItems(
          rule['category_budgets'],
          integer(rule['default_budget_minor'], 'Rule budget'),
        );
      }
    }
    schedules.sort(
      (a, b) => (a['effective_from'] as String).compareTo(
        b['effective_from'] as String,
      ),
    );
    for (var i = 0; i < schedules.length; i++) {
      final schedule = schedules[i];
      if (i + 1 < schedules.length) {
        final next = DateTime.parse(
          schedules[i + 1]['effective_from'] as String,
        );
        final expected = next.subtract(const Duration(days: 1));
        final end = schedule['effective_to'];
        if (end == null || DateTime.parse(end as String) != expected) {
          invalid('cutoff schedules overlap or leave a gap');
        }
      } else if (schedule['effective_to'] != null) {
        invalid('the latest cutoff schedule must remain open');
      }
    }
    final ruleCounter =
        (result['sequences'] as Map)['cutoff_rules'] as int? ?? 0;
    if (ruleIds.any((id) => id > ruleCounter)) {
      invalid('cutoff rule sequence is behind the saved rules');
    }
    final periods = rows('cutoff_periods').toList();
    for (final period in periods) {
      final from = day(period['starts_on'], 'Cutoff start');
      final to = day(period['ends_on'], 'Cutoff end');
      if (to.compareTo(from) < 0 ||
          from.substring(0, 7) != to.substring(0, 7)) {
        invalid('invalid cutoff date range');
      }
      text(period['label'], 'Cutoff label');
      final schedule = reference(
        'cutoff_schedules',
        period['cutoff_schedule_id'],
        'Cutoff schedule',
      );
      final ruleId = integer(period['cutoff_rule_id'], 'Cutoff rule', min: 1);
      final rule = ruleById[ruleId];
      if (rule == null || ruleSchedule[ruleId] != schedule['id']) {
        invalid('cutoff rule is missing or belongs to a different schedule');
      }
      if (from.compareTo(schedule['effective_from'] as String) < 0 ||
          (schedule['effective_to'] != null &&
              to.compareTo(schedule['effective_to'] as String) > 0)) {
        invalid('cutoff is outside its schedule');
      }
      final parsed = DateTime.parse(from);
      final rules = list(schedule['rules'], 'Rules');
      final index = rules.indexWhere((r) => r['id'] == ruleId);
      final expectedEnd = index == rules.length - 1
          ? DateTime(parsed.year, parsed.month + 1, 0).day
          : (rules[index + 1]['start_day'] as int) - 1;
      if (parsed.day != rule['start_day'] ||
          DateTime.parse(to).day != expectedEnd) {
        invalid('cutoff dates disagree with its rule');
      }
      final budget = integer(period['budget_minor'], 'Cutoff budget');
      final defaultBudget = integer(
        period['default_budget_minor'],
        'Default cutoff budget',
      );
      final items = budgetItems(period['budget_items'], budget);
      final defaults = budgetItems(
        period['default_budget_items'],
        defaultBudget,
      );
      if (defaultBudget != rule['default_budget_minor'] ||
          !_sameBudgets(
            defaults,
            list(rule['category_budgets'], 'Rule budgets'),
          )) {
        invalid('cutoff defaults differ from its historical rule');
      }
      if (period['is_budget_overridden'] is! bool) {
        invalid('cutoff override flag is missing');
      }
      if (period['is_budget_overridden'] == false &&
          (budget != defaultBudget || !_sameBudgets(items, defaults))) {
        invalid('unmodified cutoff differs from its defaults');
      }
    }
    periods.sort(
      (a, b) => (a['starts_on'] as String).compareTo(b['starts_on'] as String),
    );
    for (var i = 1; i < periods.length; i++) {
      if ((periods[i - 1]['ends_on'] as String).compareTo(
            periods[i]['starts_on'] as String,
          ) >=
          0) {
        invalid('overlapping cutoff periods');
      }
    }
  }

  bool _sameBudgets(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    final first = {
      for (final item in a) item['category_id']: item['amount_minor'],
    };
    final second = {
      for (final item in b) item['category_id']: item['amount_minor'],
    };
    return first.length == second.length &&
        first.entries.every((entry) => second[entry.key] == entry.value);
  }

  void _transactions() {
    for (final transaction in rows('transactions')) {
      integer(transaction['version'], 'Transaction version', min: 1);
      text(transaction['client_uuid'], 'Transaction reference');
      final kind = choice(transaction['kind'], [
        'income',
        'expense',
      ], 'transaction kind');
      final amount = integer(
        transaction['amount_minor'],
        'Transaction amount',
        min: 1,
      );
      final on = day(transaction['occurred_on'], 'Transaction date');
      final account = reference(
        'accounts',
        transaction['account_id'],
        'Transaction account',
      );
      final category = reference(
        'categories',
        transaction['category_id'],
        'Transaction category',
      );
      if (category['kind'] != kind) {
        invalid('transaction and category kinds do not match');
      }
      final cutoff = reference(
        'cutoff_periods',
        transaction['cutoff_period_id'],
        'Transaction cutoff',
      );
      if (on.compareTo(cutoff['starts_on'] as String) < 0 ||
          on.compareTo(cutoff['ends_on'] as String) > 0) {
        invalid('transaction is outside its cutoff');
      }
      if (transaction['deleted_at'] != null ||
          transaction['is_archived'] == true) {
        invalid('deleted transactions must not remain in the ledger');
      }
      final source = transaction['source_type'];
      if (source != null) {
        choice(source, [
          'account_transfer_fee',
          'credit_card_payment_fee',
          'savings_interest',
          'jewelry_conversion',
          'installment_plan_payment',
          'installment_plan_down_payment',
        ], 'transaction source');
        integer(transaction['source_id'], 'Transaction source ID', min: 1);
      } else if (transaction['source_id'] != null ||
          transaction['system_source'] != null ||
          transaction['installment_plan_id'] != null ||
          transaction['installment_number'] != null) {
        invalid('transaction source metadata is incomplete');
      }
      if (transaction['installment_months'] != null) {
        final months = integer(
          transaction['installment_months'],
          'Installment months',
          min: 2,
          max: 120,
        );
        final monthly = integer(
          transaction['installment_monthly_minor'],
          'Monthly installment',
          min: 1,
        );
        final start = day(
          transaction['installment_start_on'],
          'Installment start',
        );
        if (kind != 'expense' ||
            monthly !=
                (account['type'] == 'credit_card'
                    ? (amount + months - 1) ~/ months
                    : amount) ||
            start.compareTo(on) < 0) {
          invalid('invalid transaction installment terms');
        }
      } else if (transaction['installment_monthly_minor'] != null ||
          transaction['installment_start_on'] != null) {
        invalid('incomplete installment terms');
      }
      final id = account['id'] as int;
      balances[id] =
          balances[id]! + BigInt.from(kind == 'income' ? amount : -amount);
    }
  }

  void linkedTransaction(
    Object? id, {
    required String source,
    required int sourceId,
    required String kind,
    required int amount,
    required Object? accountId,
    required String on,
  }) {
    final transaction = reference('transactions', id, 'Linked transaction');
    if (!managedTransactions.add(transaction['id'] as int) ||
        transaction['source_type'] != source ||
        transaction['source_id'] != sourceId ||
        transaction['kind'] != kind ||
        transaction['amount_minor'] != amount ||
        transaction['account_id'] != accountId ||
        transaction['occurred_on'] != on) {
      invalid('linked financial records do not agree');
    }
  }

  void _movements(String table) {
    final transfer = table == 'account_transfers';
    for (final movement in rows(table)) {
      text(movement['client_uuid'], 'Movement reference');
      choice(movement['status'], ['posted'], 'movement status');
      final source = reference(
        'accounts',
        movement['source_account_id'],
        'Source account',
      );
      final destination = reference(
        'accounts',
        movement[transfer
            ? 'destination_account_id'
            : 'credit_card_account_id'],
        'Destination account',
      );
      if (source['id'] == destination['id'] ||
          source['type'] == 'credit_card' ||
          (transfer
              ? destination['type'] == 'credit_card'
              : destination['type'] != 'credit_card' ||
                    source['type'] == 'savings')) {
        invalid('invalid movement account types');
      }
      final amount = integer(
        movement['amount_minor'],
        'Movement amount',
        min: 1,
      );
      final fee = integer(movement['service_charge_minor'], 'Service charge');
      if (BigInt.from(amount) + BigInt.from(fee) >
          BigInt.from(Money.maxMinorUnits)) {
        invalid('movement debit exceeds the limit');
      }
      final on = day(
        movement[transfer ? 'transferred_on' : 'paid_on'],
        'Movement date',
      );
      if (fee == 0) {
        if (movement['service_charge_transaction_id'] != null) {
          invalid('a zero service charge has a fee transaction');
        }
      } else {
        linkedTransaction(
          movement['service_charge_transaction_id'],
          source: transfer ? 'account_transfer_fee' : 'credit_card_payment_fee',
          sourceId: movement['id'] as int,
          kind: 'expense',
          amount: fee,
          accountId: source['id'],
          on: on,
        );
      }
      balances[source['id'] as int] =
          balances[source['id']]! - BigInt.from(amount);
      balances[destination['id'] as int] =
          balances[destination['id']]! + BigInt.from(amount);
    }
  }

  void _interest() {
    final months = <String>{};
    for (final credit in rows('savings_interest_credits')) {
      text(credit['client_uuid'], 'Interest reference');
      choice(credit['status'], ['posted'], 'interest status');
      final account = reference(
        'accounts',
        credit['savings_account_id'],
        'Savings account',
      );
      if (account['type'] != 'savings') {
        invalid('interest belongs to a non-savings account');
      }
      final amount = integer(credit['amount_minor'], 'Interest amount', min: 1);
      final on = day(credit['credited_on'], 'Interest date');
      if (credit['credited_month'] != on.substring(0, 7) ||
          !months.add('${account['id']}:${credit['credited_month']}')) {
        invalid('duplicate or invalid interest month');
      }
      final method = choice(credit['credit_method'], [
        'manual',
        'automatic',
      ], 'interest method');
      if (method == 'automatic') {
        final balance = integer(
          credit['calculation_balance_minor'],
          'Interest calculation balance',
          min: 1,
        );
        final rate = integer(
          credit['monthly_interest_rate_basis_points'],
          'Interest rate',
          min: 1,
          max: 10000,
        );
        final expected =
            (BigInt.from(balance) * BigInt.from(rate) + BigInt.from(5000)) ~/
            BigInt.from(10000);
        if (expected != BigInt.from(amount)) {
          invalid('automatic interest amount differs from its calculation');
        }
      }
      linkedTransaction(
        credit['interest_transaction_id'],
        source: 'savings_interest',
        sourceId: credit['id'] as int,
        kind: 'income',
        amount: amount,
        accountId: account['id'],
        on: on,
      );
    }
  }

  void _plans() {
    for (final plan in rows('installment_plans')) {
      text(plan['client_uuid'], 'Installment reference');
      integer(plan['version'], 'Installment version', min: 1);
      final account = reference(
        'accounts',
        plan['account_id'],
        'Installment account',
      );
      final category = reference(
        'categories',
        plan['category_id'],
        'Installment category',
      );
      if (['credit_card', 'savings'].contains(account['type']) ||
          category['kind'] != 'expense') {
        invalid('invalid installment account or category');
      }
      final months = integer(
        plan['installment_months'],
        'Installment months',
        min: 2,
        max: 120,
      );
      final monthly = integer(
        plan['installment_monthly_minor'],
        'Monthly installment',
        min: 1,
      );
      final down = integer(plan['down_payment_minor'], 'Down payment');
      day(plan['installment_start_on'], 'Installment start');
      if (BigInt.from(monthly) * BigInt.from(months) + BigInt.from(down) >
          BigInt.from(Money.maxMinorUnits)) {
        invalid('installment contract exceeds the limit');
      }
      final payments = rows('transactions')
          .where((t) => t['installment_plan_id'] == plan['id'])
          .toList();
      final numbers = <int>{};
      for (final payment in payments) {
        final number = integer(
          payment['installment_number'],
          'Installment number',
          max: months,
        );
        if (!numbers.add(number) || (number == 0 && down == 0)) {
          invalid('duplicate or unexpected installment payment');
        }
        if (number != 0 && payment['category_id'] != plan['category_id']) {
          invalid('installment payment category differs from the plan');
        }
        if (['credit_card', 'savings'].contains(
          reference(
            'accounts',
            payment['account_id'],
            'Payment account',
          )['type'],
        )) {
          invalid('invalid installment payment account');
        }
        linkedTransaction(
          payment['id'],
          source: number == 0
              ? 'installment_plan_down_payment'
              : 'installment_plan_payment',
          sourceId: plan['id'] as int,
          kind: 'expense',
          amount: number == 0 ? down : monthly,
          accountId: payment['account_id'],
          on: payment['occurred_on'] as String,
        );
      }
      if ((down > 0) != numbers.contains(0)) {
        invalid('installment down payment is missing');
      }
      final paid = numbers.where((n) => n > 0).length;
      for (var i = 1; i <= paid; i++) {
        if (!numbers.contains(i)) invalid('installment payments have a gap');
      }
    }
  }

  void _jewelry() {
    for (final jewelry in rows('jewelry')) {
      text(jewelry['name'], 'Jewelry name');
      text(jewelry['jewelry_type'], 'Jewelry type');
      integer(jewelry['karat'], 'Karat', min: 1, max: 24);
      integer(jewelry['weight_mg'], 'Weight', min: 1);
      integer(jewelry['estimated_value_minor'], 'Jewelry value');
      if (jewelry['purchase_value_minor'] != null) {
        integer(jewelry['purchase_value_minor'], 'Purchase value');
      }
      if (jewelry['acquired_on'] != null) {
        day(jewelry['acquired_on'], 'Acquisition date');
      }
      final status = choice(jewelry['status'], [
        'held',
        'converted',
      ], 'jewelry status');
      final fields = [
        'conversion_client_uuid',
        'conversion_amount_minor',
        'converted_on',
        'conversion_account_id',
        'conversion_transaction_id',
      ];
      if (status == 'held') {
        if (fields.any((field) => jewelry[field] != null)) {
          invalid('held jewelry has sale records');
        }
      } else {
        final uuid = text(
          jewelry['conversion_client_uuid'],
          'Jewelry sale reference',
        );
        final amount = integer(
          jewelry['conversion_amount_minor'],
          'Jewelry sale amount',
          min: 1,
        );
        final on = day(jewelry['converted_on'], 'Jewelry sale date');
        if (jewelry['acquired_on'] != null &&
            on.compareTo(jewelry['acquired_on'] as String) < 0) {
          invalid('jewelry was sold before acquisition');
        }
        final account = reference(
          'accounts',
          jewelry['conversion_account_id'],
          'Jewelry sale account',
        );
        if (['savings', 'credit_card'].contains(account['type'])) {
          invalid('invalid jewelry sale account');
        }
        final transaction = reference(
          'transactions',
          jewelry['conversion_transaction_id'],
          'Jewelry sale transaction',
        );
        if (transaction['client_uuid'] != uuid) {
          invalid('jewelry sale reference differs from its transaction');
        }
        linkedTransaction(
          transaction['id'],
          source: 'jewelry_conversion',
          sourceId: jewelry['id'] as int,
          kind: 'income',
          amount: amount,
          accountId: account['id'],
          on: on,
        );
      }
    }
  }

  void _gold() {
    final karats = <int>{};
    for (final rate in list(result['gold_price_rates'], 'Gold prices')) {
      if (!karats.add(integer(rate['karat'], 'Gold karat', min: 1, max: 24))) {
        invalid('duplicate gold karat');
      }
      integer(rate['price_per_gram_minor'], 'Gold price', min: 1);
      choice(rate['source'], ['manual'], 'gold price source');
      timestamp(
        text(rate['updated_at'], 'Gold price timestamp'),
        'Gold price timestamp',
      );
      timestamp(rate['quoted_at'], 'Gold quote timestamp');
    }
  }
}
