import '../core/money.dart';

Map<String, dynamic> jsonMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}

List<dynamic> jsonList(Object? value) => value is List ? value : const [];

Object? dataOf(Object? value) {
  final map = jsonMap(value);
  return map.containsKey('data') ? map['data'] : value;
}

bool jsonBool(Object? value) =>
    value == true || value == 1 || value?.toString().toLowerCase() == 'true';

int jsonInt(Object? value, [int fallback = 0]) =>
    int.tryParse(value?.toString() ?? '') ?? fallback;

enum FinanceScope {
  personal,
  joint;

  factory FinanceScope.fromJson(Object? value) =>
      value?.toString().trim().toLowerCase() == 'joint'
      ? FinanceScope.joint
      : FinanceScope.personal;

  String get apiValue => name;
  String get label => this == FinanceScope.joint ? 'Joint' : 'Personal';
  String get accountLabel =>
      this == FinanceScope.joint ? 'Joint account' : 'Personal account';
}

/// A calendar-based age, avoiding fixed 365-day/30-day approximations.
class CalendarAge {
  const CalendarAge({
    required this.years,
    required this.months,
    required this.days,
    this.isFuture = false,
  });

  factory CalendarAge.between(DateTime acquiredOn, DateTime asOf) {
    final start = DateTime.utc(
      acquiredOn.year,
      acquiredOn.month,
      acquiredOn.day,
    );
    final end = DateTime.utc(asOf.year, asOf.month, asOf.day);
    if (start.isAfter(end)) {
      return const CalendarAge(years: 0, months: 0, days: 0, isFuture: true);
    }

    var years = end.year - start.year;
    var cursor = _addCalendarMonths(start, years * 12);
    if (cursor.isAfter(end)) {
      years--;
      cursor = _addCalendarMonths(start, years * 12);
    }

    var months = (end.year - cursor.year) * 12 + end.month - cursor.month;
    var monthCursor = _addCalendarMonths(cursor, months);
    if (monthCursor.isAfter(end)) {
      months--;
      monthCursor = _addCalendarMonths(cursor, months);
    }

    return CalendarAge(
      years: years,
      months: months,
      days: end.difference(monthCursor).inDays,
    );
  }

  final int years;
  final int months;
  final int days;
  final bool isFuture;

  String get label {
    if (isFuture) return 'Not acquired yet';
    final parts = <String>[
      if (years > 0) '$years ${years == 1 ? 'year' : 'years'}',
      if (months > 0) '$months ${months == 1 ? 'month' : 'months'}',
      if (days > 0) '$days ${days == 1 ? 'day' : 'days'}',
    ];
    return parts.isEmpty ? 'Today' : parts.join(', ');
  }
}

DateTime _addCalendarMonths(DateTime date, int months) {
  final totalMonths = date.year * 12 + date.month - 1 + months;
  final year = totalMonths ~/ 12;
  final month = totalMonths % 12 + 1;
  final lastDay = DateTime.utc(year, month + 1, 0).day;
  return DateTime.utc(year, month, date.day.clamp(1, lastDay));
}

bool _isSameCalendarDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

class HealthStatus {
  const HealthStatus({
    required this.ok,
    required this.apiStatus,
    required this.databaseStatus,
    this.message,
    this.version,
    this.migrationsStatus,
    String? installationId,
  }) : // Public nullable parameter intentionally wraps hot-reload-safe storage.
       // ignore: prefer_initializing_formals
       _installationId = installationId;

  factory HealthStatus.fromJson(Object? value) {
    final map = jsonMap(dataOf(value));
    final overall = map['status']?.toString() ?? 'ok';
    final api = map['api']?.toString();
    final database = map['database'] is Map
        ? jsonMap(map['database'])['status']?.toString()
        : map['database']?.toString();
    final migrations = map['migrations']?.toString();
    final message =
        map['message']?.toString() ??
        _healthMessage(overall, database, migrations);
    return HealthStatus(
      ok: map['ok'] == null
          ? overall == 'ok' || overall == 'healthy'
          : jsonBool(map['ok']),
      apiStatus: api ?? overall,
      databaseStatus:
          database ?? (overall == 'ok' ? 'connected' : 'unavailable'),
      message: message,
      version: map['version']?.toString() ?? map['app_version']?.toString(),
      migrationsStatus: migrations,
      installationId: _nullableTrimmed(map['installation_id']),
    );
  }

  final bool ok;
  final String apiStatus;
  final String databaseStatus;
  final String? message;
  final String? version;
  final String? migrationsStatus;
  // Nullable backing keeps health objects created before hot reload safe.
  final String? _installationId;

  String? get installationId => _installationId;
}

String? _healthMessage(String overall, String? database, String? migrations) {
  if (overall == 'ok' || overall == 'healthy') return null;
  if (database == 'unavailable') {
    return 'The API is available, but its database cannot be reached.';
  }
  if (migrations == 'pending') {
    return 'The API is available, but its database migrations are pending.';
  }
  return 'The local API reported a degraded status.';
}

class AppSettings {
  const AppSettings({
    this.currencyCode = 'PHP',
    this.locale = 'en_PH',
    this.timezone = 'Asia/Manila',
    this.weekStartsOn = 1,
    this.showJewelryInReports = true,
    this.showCreditCardsInReports = true,
  });

  factory AppSettings.fromJson(Object? value) {
    final map = jsonMap(dataOf(value));
    return AppSettings(
      currencyCode: map['currency_code']?.toString() ?? 'PHP',
      locale: map['locale']?.toString() ?? 'en_PH',
      timezone: map['timezone']?.toString() ?? 'Asia/Manila',
      weekStartsOn: jsonInt(map['week_starts_on'], 1),
      showJewelryInReports: jsonBool(map['show_jewelry_in_reports'] ?? true),
      showCreditCardsInReports: jsonBool(
        map['show_credit_cards_in_reports'] ?? true,
      ),
    );
  }

  final String currencyCode;
  final String locale;
  final String timezone;
  final int weekStartsOn;
  final bool showJewelryInReports;
  final bool showCreditCardsInReports;

  Map<String, dynamic> toJson() => {
    'currency_code': currencyCode,
    'locale': locale,
    'timezone': timezone,
    'week_starts_on': weekStartsOn,
    'show_jewelry_in_reports': showJewelryInReports,
    'show_credit_cards_in_reports': showCreditCardsInReports,
  };

  AppSettings copyWith({
    String? currencyCode,
    String? locale,
    String? timezone,
    int? weekStartsOn,
    bool? showJewelryInReports,
    bool? showCreditCardsInReports,
  }) => AppSettings(
    currencyCode: currencyCode ?? this.currencyCode,
    locale: locale ?? this.locale,
    timezone: timezone ?? this.timezone,
    weekStartsOn: weekStartsOn ?? this.weekStartsOn,
    showJewelryInReports: showJewelryInReports ?? this.showJewelryInReports,
    showCreditCardsInReports:
        showCreditCardsInReports ?? this.showCreditCardsInReports,
  );
}

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.type,
    required this.openingBalanceMinor,
    required this.balanceMinor,
    this.color = '#43D98B',
    this.isArchived = false,
    String? cardDesign,
    FinanceScope? scope,
    String? systemKey,
    String? accountRole,
    bool? isSystem,
    bool? isLiability,
    bool? isSavings,
    bool? countsTowardAvailableMoney,
    int? monthlyInterestRateBasisPoints,
    double? monthlyInterestRatePercent,
    DateTime? interestAccrualAnchorOn,
    DateTime? interestLastProcessedOn,
    DateTime? nextInterestAccrualOn,
    int? openingDebtMinor,
    int? creditLimitMinor,
    int? statementDay,
    int? dueDay,
    int? debtMinor,
    int? availableCreditMinor,
  }) : // Public parameter name intentionally differs from nullable storage.
       // ignore: prefer_initializing_formals
       _cardDesign = cardDesign,
       // ignore: prefer_initializing_formals
       _scope = scope,
       // ignore: prefer_initializing_formals
       _systemKey = systemKey,
       // ignore: prefer_initializing_formals
       _accountRole = accountRole,
       // ignore: prefer_initializing_formals
       _isSystem = isSystem,
       // ignore: prefer_initializing_formals
       _isLiability = isLiability,
       // ignore: prefer_initializing_formals
       _isSavings = isSavings,
       // ignore: prefer_initializing_formals
       _countsTowardAvailableMoney = countsTowardAvailableMoney,
       // ignore: prefer_initializing_formals
       _monthlyInterestRateBasisPoints = monthlyInterestRateBasisPoints,
       // ignore: prefer_initializing_formals
       _monthlyInterestRatePercent = monthlyInterestRatePercent,
       // ignore: prefer_initializing_formals
       _interestAccrualAnchorOn = interestAccrualAnchorOn,
       // ignore: prefer_initializing_formals
       _interestLastProcessedOn = interestLastProcessedOn,
       // ignore: prefer_initializing_formals
       _nextInterestAccrualOn = nextInterestAccrualOn,
       // ignore: prefer_initializing_formals
       _openingDebtMinor = openingDebtMinor,
       // ignore: prefer_initializing_formals
       _creditLimitMinor = creditLimitMinor,
       // ignore: prefer_initializing_formals
       _statementDay = statementDay,
       // ignore: prefer_initializing_formals
       _dueDay = dueDay,
       // ignore: prefer_initializing_formals
       _debtMinor = debtMinor,
       // ignore: prefer_initializing_formals
       _availableCreditMinor = availableCreditMinor;

  factory Account.fromJson(Object? value) {
    final map = jsonMap(value);
    return Account(
      id: jsonInt(map['id']),
      name: map['name']?.toString() ?? 'Account',
      type: map['type']?.toString() ?? 'cash',
      openingBalanceMinor: Money.fromJson(
        map['opening_balance_minor'] ??
            map['opening_balance'] ??
            (map['opening_debt_minor'] == null
                ? null
                : -Money.fromJson(map['opening_debt_minor'])),
      ),
      balanceMinor: Money.fromJson(
        map['balance_minor'] ??
            map['current_balance_minor'] ??
            map['balance'] ??
            map['opening_balance_minor'] ??
            (map['opening_debt_minor'] == null
                ? null
                : -Money.fromJson(map['opening_debt_minor'])),
      ),
      color: map['color']?.toString() ?? '#43D98B',
      isArchived: jsonBool(map['is_archived']),
      cardDesign: _nullableTrimmed(map['card_design']),
      scope: FinanceScope.fromJson(map['scope']),
      systemKey: _nullableTrimmed(map['system_key']),
      accountRole: _nullableTrimmed(map['account_role']),
      isSystem: map.containsKey('is_system')
          ? jsonBool(map['is_system'])
          : null,
      isLiability: map.containsKey('is_liability')
          ? jsonBool(map['is_liability'])
          : null,
      isSavings: map.containsKey('is_savings')
          ? jsonBool(map['is_savings'])
          : null,
      countsTowardAvailableMoney:
          map.containsKey('counts_toward_available_money')
          ? jsonBool(map['counts_toward_available_money'])
          : null,
      monthlyInterestRateBasisPoints:
          map.containsKey('monthly_interest_rate_basis_points')
          ? jsonInt(map['monthly_interest_rate_basis_points'], -1)
          : null,
      monthlyInterestRatePercent:
          map.containsKey('monthly_interest_rate_percent')
          ? _nullableDouble(map['monthly_interest_rate_percent']) ?? double.nan
          : null,
      interestAccrualAnchorOn: _nullableDate(map['interest_accrual_anchor_on']),
      interestLastProcessedOn: _nullableDate(map['interest_last_processed_on']),
      nextInterestAccrualOn: _nullableDate(map['next_interest_accrual_on']),
      openingDebtMinor: map.containsKey('opening_debt_minor')
          ? Money.fromJson(map['opening_debt_minor'])
          : null,
      creditLimitMinor: map['credit_limit_minor'] == null
          ? null
          : Money.fromJson(map['credit_limit_minor']),
      statementDay: map['statement_day'] == null
          ? null
          : jsonInt(map['statement_day']),
      dueDay: map['due_day'] == null ? null : jsonInt(map['due_day']),
      debtMinor: map.containsKey('debt_minor')
          ? Money.fromJson(map['debt_minor'])
          : null,
      availableCreditMinor: map['available_credit_minor'] == null
          ? null
          : Money.fromJson(map['available_credit_minor']),
    );
  }

  final int id;
  final String name;
  final String type;
  final int openingBalanceMinor;
  final int balanceMinor;
  final String color;
  final bool isArchived;
  // Nullable backing keeps Account instances created before hot reload safe.
  final String? _cardDesign;
  final FinanceScope? _scope;
  final String? _systemKey;
  final String? _accountRole;
  final bool? _isSystem;
  final bool? _isLiability;
  final bool? _isSavings;
  final bool? _countsTowardAvailableMoney;
  final int? _monthlyInterestRateBasisPoints;
  final double? _monthlyInterestRatePercent;
  final DateTime? _interestAccrualAnchorOn;
  final DateTime? _interestLastProcessedOn;
  final DateTime? _nextInterestAccrualOn;
  final int? _openingDebtMinor;
  final int? _creditLimitMinor;
  final int? _statementDay;
  final int? _dueDay;
  final int? _debtMinor;
  final int? _availableCreditMinor;

  String? get cardDesign => _cardDesign;
  FinanceScope get scope => _scope ?? FinanceScope.personal;
  String? get systemKey => _systemKey;
  String get accountRole =>
      _accountRole ??
      (type == 'credit_card'
          ? 'credit_card'
          : type == 'savings'
          ? 'savings'
          : 'standard');
  bool get isSystem => _isSystem ?? systemKey != null;
  bool get isCreditCard =>
      type == 'credit_card' || _accountRole == 'credit_card';
  bool get isLiability => _isLiability ?? isCreditCard;
  bool get isSavingsAccount =>
      _isSavings ?? (type == 'savings' || accountRole == 'savings');
  bool get countsTowardAvailableMoney =>
      _countsTowardAvailableMoney ?? (!isLiability && !isSavingsAccount);
  int get monthlyInterestRateBasisPoints =>
      _monthlyInterestRateBasisPoints ?? 0;
  double get monthlyInterestRatePercent =>
      _monthlyInterestRatePercent ?? monthlyInterestRateBasisPoints / 100;
  DateTime? get interestAccrualAnchorOn => _interestAccrualAnchorOn;
  DateTime? get interestLastProcessedOn => _interestLastProcessedOn;
  DateTime? get nextInterestAccrualOn => _nextInterestAccrualOn;
  bool get hasAutomaticMonthlyInterest =>
      isSavingsAccount && monthlyInterestRateBasisPoints > 0;
  bool get hasInterestScheduleMetadata =>
      _monthlyInterestRateBasisPoints != null ||
      _monthlyInterestRatePercent != null ||
      interestAccrualAnchorOn != null ||
      interestLastProcessedOn != null ||
      nextInterestAccrualOn != null;
  int get openingDebtMinor {
    final derived = isCreditCard && openingBalanceMinor < 0
        ? -openingBalanceMinor
        : 0;
    assert(_openingDebtMinor == null || _openingDebtMinor == derived);
    return derived;
  }

  int? get creditLimitMinor => _creditLimitMinor;
  int? get statementDay => _statementDay;
  int? get dueDay => _dueDay;
  int get debtMinor {
    final derived = isCreditCard && balanceMinor < 0 ? -balanceMinor : 0;
    assert(_debtMinor == null || _debtMinor == derived);
    return derived;
  }

  int? get availableCreditMinor {
    final limit = creditLimitMinor;
    if (limit == null) return null;
    final available = limit - debtMinor;
    final derived = available < 0 ? 0 : available;
    assert(_availableCreditMinor == null || _availableCreditMinor == derived);
    return derived;
  }

  bool get isDealsPenaltyMoney =>
      systemKey == 'joint_penalty_fund' || accountRole == 'penalty_fund';
  // Legacy domain alias retained for older call sites and API terminology.
  bool get isPenaltyFund => isDealsPenaltyMoney;
  bool get isStandardAccount =>
      !isSystem && !isCreditCard && accountRole == 'standard';
  bool get isTransferAccount =>
      !isSystem && !isCreditCard && (isStandardAccount || isSavingsAccount);
  bool get hasConsistentClassificationMetadata {
    if (!const {
      'cash',
      'bank',
      'ewallet',
      'other',
      'credit_card',
      'savings',
    }.contains(type)) {
      return false;
    }
    final expectedIsSystem = systemKey != null;
    final expectedIsCreditCard = type == 'credit_card';
    final expectedIsSavings = type == 'savings';
    final expectedRole = expectedIsSystem
        ? systemKey == 'joint_penalty_fund'
              ? 'penalty_fund'
              : 'system'
        : expectedIsCreditCard
        ? 'credit_card'
        : expectedIsSavings
        ? 'savings'
        : 'standard';
    return (_isSystem == null || _isSystem == expectedIsSystem) &&
        (_accountRole == null || _accountRole == expectedRole) &&
        (_isLiability == null || _isLiability == expectedIsCreditCard) &&
        (_isSavings == null || _isSavings == expectedIsSavings) &&
        (_countsTowardAvailableMoney == null ||
            _countsTowardAvailableMoney ==
                (!expectedIsCreditCard && !expectedIsSavings));
  }

  bool get hasConsistentInterestScheduleMetadata {
    if (!hasInterestScheduleMetadata) return true;
    final basisPoints = _monthlyInterestRateBasisPoints;
    final percent = _monthlyInterestRatePercent;
    if (basisPoints == null ||
        percent == null ||
        !percent.isFinite ||
        basisPoints < 0 ||
        basisPoints > 10000 ||
        (percent - (basisPoints / 100)).abs() > 0.0000001) {
      return false;
    }
    if (type != 'savings') {
      return basisPoints == 0 &&
          interestAccrualAnchorOn == null &&
          interestLastProcessedOn == null &&
          nextInterestAccrualOn == null;
    }
    if (basisPoints == 0) {
      return interestAccrualAnchorOn == null && nextInterestAccrualOn == null;
    }
    final anchor = interestAccrualAnchorOn;
    final next = nextInterestAccrualOn;
    if (anchor == null || next == null || !next.isAfter(anchor)) return false;
    final last = interestLastProcessedOn;
    if (last?.isBefore(next) == false) return false;
    final nextOffsetMonths =
        (next.year - anchor.year) * 12 + next.month - anchor.month;
    if (nextOffsetMonths < 1 ||
        !_isSameCalendarDay(
          _addCalendarMonths(anchor, nextOffsetMonths),
          next,
        )) {
      return false;
    }
    // A re-enabled schedule can retain an older checkpoint from another user
    // timezone. Before its first new due, only ordering is authoritative.
    if (nextOffsetMonths == 1) return true;
    return last != null &&
        _isSameCalendarDay(
          _addCalendarMonths(anchor, nextOffsetMonths - 1),
          last,
        );
  }

  String get displayName =>
      isDealsPenaltyMoney ? _dealsPenaltyMoneyDisplayName(name) : name;
}

class GoldPriceQuote {
  const GoldPriceQuote({
    required this.provider,
    required this.currencyCode,
    required this.unit,
    required this.price24kPerGramMinor,
    required this.quotedAt,
    required this.fetchedAt,
    required this.ageSeconds,
    required this.source,
    required this.isCached,
    required this.isStale,
    this.warning,
    // Kept public while storing nullable data for pre-hot-reload instances.
    bool? didSynchronize,
    bool? hasSynchronizationMetadata,
    int? ratesUpdated,
    int? jewelryRevalued,
    this.jewelryRevaluationSkippedReason,
  }) : // Public parameter names intentionally differ from nullable storage.
       // ignore: prefer_initializing_formals
       _didSynchronize = didSynchronize,
       // ignore: prefer_initializing_formals
       _hasSynchronizationMetadata = hasSynchronizationMetadata,
       // ignore: prefer_initializing_formals
       _ratesUpdated = ratesUpdated,
       // ignore: prefer_initializing_formals
       _jewelryRevalued = jewelryRevalued;

  factory GoldPriceQuote.fromJson(Object? value) {
    final map = jsonMap(dataOf(value));
    final sync = jsonMap(map['sync']);
    final hasSync = map['sync'] is Map;
    final syncApplied =
        !sync.containsKey('applied') || jsonBool(sync['applied']);
    return GoldPriceQuote(
      provider: map['provider']?.toString() ?? 'Gold price provider',
      currencyCode: map['currency_code']?.toString() ?? 'PHP',
      unit: map['unit']?.toString() ?? 'gram',
      price24kPerGramMinor: Money.fromJson(map['price_24k_per_gram_minor']),
      quotedAt: _timestampFromJson(map['quoted_at'], 'quoted_at'),
      fetchedAt: _timestampFromJson(map['fetched_at'], 'fetched_at'),
      ageSeconds: jsonInt(map['age_seconds']),
      source: map['source']?.toString() ?? 'Market reference',
      isCached: jsonBool(map['is_cached']),
      isStale: jsonBool(map['is_stale']),
      warning: map['warning']?.toString(),
      didSynchronize: hasSync && syncApplied,
      hasSynchronizationMetadata: hasSync,
      ratesUpdated: jsonInt(sync['rates_updated']),
      jewelryRevalued: jsonInt(sync['jewelry_revalued']),
      jewelryRevaluationSkippedReason:
          sync['jewelry_revaluation_skipped_reason']?.toString(),
    );
  }

  final String provider;
  final String currencyCode;
  final String unit;
  final int price24kPerGramMinor;
  final DateTime quotedAt;
  final DateTime fetchedAt;
  final int ageSeconds;
  final String source;
  final bool isCached;
  final bool isStale;
  final String? warning;
  final bool? _didSynchronize;
  final bool? _hasSynchronizationMetadata;
  final int? _ratesUpdated;
  final int? _jewelryRevalued;
  final String? jewelryRevaluationSkippedReason;

  bool get didSynchronize => _didSynchronize ?? false;
  bool get hasSynchronizationMetadata => _hasSynchronizationMetadata ?? false;
  int get ratesUpdated => _ratesUpdated ?? 0;
  int get jewelryRevalued => _jewelryRevalued ?? 0;

  int estimateMinor({required int weightMg, required int karat}) {
    if (weightMg <= 0 || karat <= 0 || price24kPerGramMinor <= 0) return 0;
    final numerator =
        BigInt.from(weightMg) *
        BigInt.from(karat) *
        BigInt.from(price24kPerGramMinor);
    final denominator = BigInt.from(24000);
    final rounded = (numerator + BigInt.from(12000)) ~/ denominator;
    if (rounded > BigInt.from(Money.maxMinorUnits)) {
      return Money.maxMinorUnits + 1;
    }
    return rounded.toInt();
  }
}

class ManualGoldPriceRate {
  const ManualGoldPriceRate({
    required this.karat,
    required this.pricePerGramMinor,
    this.updatedAt,
    // Kept public while storing nullable data for pre-hot-reload instances.
    String? source,
    this.quotedAt,
  }) : // Public parameter name intentionally differs from nullable storage.
       // ignore: prefer_initializing_formals
       _source = source;

  factory ManualGoldPriceRate.fromJson(Object? value) {
    final map = jsonMap(value);
    final updatedAtRaw = map['updated_at']?.toString().trim() ?? '';
    final quotedAtRaw = map['quoted_at']?.toString().trim() ?? '';
    final source = map['source']?.toString().trim() ?? '';
    return ManualGoldPriceRate(
      karat: jsonInt(map['karat']),
      pricePerGramMinor: Money.fromJson(map['price_per_gram_minor']),
      updatedAt: updatedAtRaw.isEmpty ? null : DateTime.tryParse(updatedAtRaw),
      source: source.isEmpty ? 'manual' : source,
      quotedAt: quotedAtRaw.isEmpty ? null : DateTime.tryParse(quotedAtRaw),
    );
  }

  final int karat;
  final int pricePerGramMinor;
  final DateTime? updatedAt;
  final String? _source;
  final DateTime? quotedAt;

  String get source {
    final value = _source?.trim();
    return value == null || value.isEmpty ? 'manual' : value;
  }

  bool get isOnlineReference => source.trim().toLowerCase() != 'manual';

  int estimateMinor({required int weightMg}) {
    if (weightMg <= 0 || pricePerGramMinor <= 0) return 0;
    final numerator = BigInt.from(weightMg) * BigInt.from(pricePerGramMinor);
    final denominator = BigInt.from(1000);
    final rounded =
        (numerator + (denominator ~/ BigInt.from(2))) ~/ denominator;
    if (rounded > BigInt.from(Money.maxMinorUnits)) {
      return Money.maxMinorUnits + 1;
    }
    return rounded.toInt();
  }

  Map<String, int> toJson() => {
    'karat': karat,
    'price_per_gram_minor': pricePerGramMinor,
  };
}

class ManualGoldPriceList {
  const ManualGoldPriceList({this.currencyCode = 'PHP', this.rates = const []});

  factory ManualGoldPriceList.fromJson(Object? value) {
    final map = jsonMap(dataOf(value));
    final rates =
        jsonList(map['rates'])
            .map(ManualGoldPriceRate.fromJson)
            .where((rate) => rate.karat > 0 && rate.pricePerGramMinor > 0)
            .toList()
          ..sort((first, second) => first.karat.compareTo(second.karat));
    return ManualGoldPriceList(
      currencyCode: map['currency_code']?.toString() ?? 'PHP',
      rates: rates,
    );
  }

  final String currencyCode;
  final List<ManualGoldPriceRate> rates;

  ManualGoldPriceRate? rateFor(int karat) {
    for (final rate in rates) {
      if (rate.karat == karat) return rate;
    }
    return null;
  }
}

class JewelryItem {
  const JewelryItem({
    required this.id,
    required this.name,
    required this.jewelryType,
    required this.karat,
    required this.weightMg,
    required this.estimatedValueMinor,
    required this.status,
    this.acquiredOn,
    this.purchaseValueMinor,
    this.notes,
    this.convertedOn,
    this.conversionAmountMinor,
    this.conversionAccountId,
    this.conversionTransactionId,
    this.conversionAccount,
  });

  factory JewelryItem.fromJson(Object? value) {
    final map = jsonMap(value);
    final conversion = jsonMap(map['conversion']);
    final acquired = map['acquired_on'] ?? map['acquisition_date'];
    final converted =
        map['converted_on'] ??
        conversion['converted_on'] ??
        map['conversion_date'];
    final purchase = map['purchase_value_minor'] ?? map['purchase_price_minor'];
    final conversionAmount =
        map['conversion_amount_minor'] ??
        conversion['amount_minor'] ??
        map['converted_amount_minor'];
    final accountValue =
        map['conversion_account'] ?? conversion['account'] ?? map['account'];
    return JewelryItem(
      id: jsonInt(map['id']),
      name: map['name']?.toString() ?? 'Gold jewelry',
      jewelryType:
          map['jewelry_type']?.toString() ?? map['type']?.toString() ?? 'other',
      karat: jsonInt(map['karat'], 24),
      weightMg: jsonInt(map['weight_mg']),
      acquiredOn: acquired == null ? null : dateFromJson(acquired),
      purchaseValueMinor: purchase == null ? null : Money.fromJson(purchase),
      estimatedValueMinor: Money.fromJson(
        map['estimated_value_minor'] ?? map['current_value_minor'],
      ),
      notes: map['notes']?.toString() ?? map['note']?.toString(),
      status: map['status']?.toString() ?? 'held',
      convertedOn: converted == null ? null : dateFromJson(converted),
      conversionAmountMinor: conversionAmount == null
          ? null
          : Money.fromJson(conversionAmount),
      conversionAccountId:
          (map['conversion_account_id'] ?? conversion['account_id']) == null
          ? null
          : jsonInt(map['conversion_account_id'] ?? conversion['account_id']),
      conversionTransactionId:
          (map['conversion_transaction_id'] ?? conversion['transaction_id']) ==
              null
          ? null
          : jsonInt(
              map['conversion_transaction_id'] ?? conversion['transaction_id'],
            ),
      conversionAccount: accountValue is Map
          ? Account.fromJson(accountValue)
          : null,
    );
  }

  final int id;
  final String name;
  final String jewelryType;
  final int karat;
  final int weightMg;
  final DateTime? acquiredOn;
  final int? purchaseValueMinor;
  final int estimatedValueMinor;
  final String? notes;
  final String status;
  final DateTime? convertedOn;
  final int? conversionAmountMinor;
  final int? conversionAccountId;
  final int? conversionTransactionId;
  final Account? conversionAccount;

  bool get isConverted => status == 'converted';
  double get weightGrams => weightMg / 1000;
  double get pureGoldGrams => weightGrams * karat / 24;
  int? get unrealizedGainLossMinor => purchaseValueMinor == null
      ? null
      : estimatedValueMinor - purchaseValueMinor!;
  int? get realizedGainLossMinor =>
      purchaseValueMinor == null || conversionAmountMinor == null
      ? null
      : conversionAmountMinor! - purchaseValueMinor!;

  CalendarAge? ageAt(DateTime asOf) =>
      acquiredOn == null ? null : CalendarAge.between(acquiredOn!, asOf);
}

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.kind,
    this.color = '#43D98B',
    this.icon = 'category',
    this.isArchived = false,
    String? systemKey,
    String? categoryRole,
    bool? isSystem,
  }) : // Nullable backing keeps pre-hot-reload category instances safe.
       // ignore: prefer_initializing_formals
       _systemKey = systemKey,
       // ignore: prefer_initializing_formals
       _categoryRole = categoryRole,
       // ignore: prefer_initializing_formals
       _isSystem = isSystem;

  factory Category.fromJson(Object? value) {
    final map = jsonMap(value);
    return Category(
      id: jsonInt(map['id']),
      name: map['name']?.toString() ?? 'Category',
      kind: map['kind']?.toString() ?? map['type']?.toString() ?? 'expense',
      color: map['color']?.toString() ?? '#43D98B',
      icon: map['icon']?.toString() ?? 'category',
      isArchived: jsonBool(map['is_archived']),
      systemKey: _nullableTrimmed(map['system_key']),
      categoryRole: _nullableTrimmed(map['category_role']),
      isSystem: map.containsKey('is_system')
          ? jsonBool(map['is_system'])
          : null,
    );
  }

  final int id;
  final String name;
  final String kind;
  final String color;
  final String icon;
  final bool isArchived;
  final String? _systemKey;
  final String? _categoryRole;
  final bool? _isSystem;

  String? get systemKey => _systemKey;
  String? get categoryRole => _categoryRole;
  bool get isSystem => _isSystem ?? systemKey != null;
  bool get isTransferFee =>
      systemKey == 'account_transfer_fee' || categoryRole == 'transfer_fee';
  bool get isSavingsInterest =>
      systemKey == 'savings_interest' || categoryRole == 'savings_interest';
}

class TransactionRecord {
  const TransactionRecord({
    required this.id,
    required this.clientUuid,
    required this.kind,
    required this.amountMinor,
    required this.occurredOn,
    required this.version,
    this.accountId,
    this.categoryId,
    this.cutoffPeriodId,
    this.payee,
    this.note,
    this.installmentMonths,
    this.installmentMonthlyMinor,
    this.installmentStartOn,
    this.installmentPlanId,
    this.installmentNumber,
    this.account,
    this.category,
    this.sourceType,
    this.sourceId,
    this.sourceComponent,
    this.jointSplitExpense,
    FinanceScope? scope,
  }) : // Public parameter name intentionally differs from nullable storage.
       // ignore: prefer_initializing_formals
       _scope = scope;

  factory TransactionRecord.fromJson(Object? value) {
    final map = jsonMap(value);
    return TransactionRecord(
      id: jsonInt(map['id']),
      clientUuid: map['client_uuid']?.toString() ?? '',
      kind: map['kind']?.toString() ?? map['type']?.toString() ?? 'expense',
      amountMinor: Money.fromJson(map['amount_minor'] ?? map['amount']),
      occurredOn: dateFromJson(map['occurred_on'] ?? map['transaction_date']),
      version: jsonInt(map['version'], 1),
      accountId: map['account_id'] == null ? null : jsonInt(map['account_id']),
      categoryId: map['category_id'] == null
          ? null
          : jsonInt(map['category_id']),
      cutoffPeriodId: map['cutoff_period_id'] == null
          ? null
          : jsonInt(map['cutoff_period_id']),
      payee: map['payee']?.toString() ?? map['merchant']?.toString(),
      note: map['note']?.toString(),
      installmentMonths: map['installment_months'] == null
          ? null
          : jsonInt(map['installment_months']),
      installmentMonthlyMinor: map['installment_monthly_minor'] == null
          ? null
          : Money.fromJson(map['installment_monthly_minor']),
      installmentStartOn: map['installment_start_on'] == null
          ? null
          : dateFromJson(map['installment_start_on']),
      installmentPlanId: map['installment_plan_id'] == null
          ? null
          : jsonInt(map['installment_plan_id']),
      installmentNumber: map['installment_number'] == null
          ? null
          : jsonInt(map['installment_number']),
      account: map['account'] is Map ? Account.fromJson(map['account']) : null,
      category: map['category'] is Map
          ? Category.fromJson(map['category'])
          : null,
      sourceType: map['source_type']?.toString(),
      sourceId: map['source_id'] == null ? null : jsonInt(map['source_id']),
      sourceComponent: _nullableTrimmed(map['source_component']),
      jointSplitExpense: map['joint_split_expense'] is Map
          ? JointSplitExpense.fromJson(map['joint_split_expense'])
          : null,
      scope: FinanceScope.fromJson(
        map['scope'] ?? jsonMap(map['account'])['scope'],
      ),
    );
  }

  final int id;
  final String clientUuid;
  final String kind;
  final int amountMinor;
  final DateTime occurredOn;
  final int version;
  final int? accountId;
  final int? categoryId;
  final int? cutoffPeriodId;
  final String? payee;
  final String? note;
  final int? installmentMonths;
  final int? installmentMonthlyMinor;
  final DateTime? installmentStartOn;
  final int? installmentPlanId;
  final int? installmentNumber;
  final Account? account;
  final Category? category;
  final String? sourceType;
  final int? sourceId;
  final String? sourceComponent;
  final JointSplitExpense? jointSplitExpense;
  // Nullable backing keeps pre-hot-reload transaction instances safe.
  final FinanceScope? _scope;

  bool get isManagedJewelryConversion => sourceType == 'jewelry_conversion';
  bool get isManagedAccountTransferFee => sourceType == 'account_transfer_fee';
  bool get isManagedCreditCardPaymentFee =>
      sourceType == 'credit_card_payment_fee';
  bool get isManagedSavingsInterest => sourceType == 'savings_interest';
  bool get isManagedJointSplitExpense => sourceType == 'joint_split_expense';
  bool get isManagedInstallmentDownPayment =>
      sourceType == 'installment_plan_down_payment' && installmentNumber == 0;
  bool get isManagedInstallmentPayment =>
      sourceType == 'installment_plan_payment' ||
      (installmentPlanId != null && !isManagedInstallmentDownPayment);
  bool get isJointSplitExpenseAggregate =>
      isManagedJointSplitExpense && sourceComponent == 'group';
  bool get isManagedTransaction =>
      isManagedJewelryConversion ||
      isManagedAccountTransferFee ||
      isManagedCreditCardPaymentFee ||
      isManagedSavingsInterest ||
      isManagedJointSplitExpense ||
      isManagedInstallmentDownPayment ||
      isManagedInstallmentPayment;
  bool get isInstallment =>
      installmentMonths != null && (installmentMonths ?? 0) > 1;
  FinanceScope get scope => _scope ?? account?.scope ?? FinanceScope.personal;
}

class InstallmentPlan {
  const InstallmentPlan({
    required this.id,
    required this.clientUuid,
    required this.scope,
    required this.accountId,
    required this.categoryId,
    required this.installmentMonthlyMinor,
    required this.installmentMonths,
    required this.installmentStartOn,
    required this.status,
    required this.paidInstallments,
    required this.remainingInstallments,
    required this.nextInstallmentNumber,
    required this.version,
    this.nextPaymentOn,
    this.payee,
    this.note,
    this.account,
    this.category,
    this.downPaymentMinor = 0,
    this.downPaymentPaidOn,
    this.downPaymentTransaction,
    this._scheduledTotalMinor,
    this._scheduledRemainingMinor,
    this._contractTotalMinor,
    this._totalPaidMinor,
    this._remainingObligationMinor,
  });

  factory InstallmentPlan.fromJson(Object? value) {
    final map = jsonMap(value);
    return InstallmentPlan(
      id: jsonInt(map['id']),
      clientUuid: map['client_uuid']?.toString() ?? '',
      scope: FinanceScope.fromJson(map['scope']),
      accountId: jsonInt(map['account_id']),
      categoryId: jsonInt(map['category_id']),
      installmentMonthlyMinor: Money.fromJson(map['installment_monthly_minor']),
      installmentMonths: jsonInt(map['installment_months']),
      installmentStartOn: dateFromJson(map['installment_start_on']),
      status: map['status']?.toString() ?? 'active',
      paidInstallments: jsonInt(map['paid_installments']),
      remainingInstallments: jsonInt(map['remaining_installments']),
      nextInstallmentNumber: map['next_installment_number'] == null
          ? null
          : jsonInt(map['next_installment_number']),
      nextPaymentOn: map['next_payment_on'] == null
          ? null
          : dateFromJson(map['next_payment_on']),
      version: jsonInt(map['version'], 1),
      payee: _nullableTrimmed(map['payee']),
      note: _nullableTrimmed(map['note']),
      account: map['account'] is Map ? Account.fromJson(map['account']) : null,
      category: map['category'] is Map
          ? Category.fromJson(map['category'])
          : null,
      downPaymentMinor: map['down_payment_minor'] == null
          ? 0
          : Money.fromJson(map['down_payment_minor']),
      downPaymentPaidOn: map['down_payment_paid_on'] == null
          ? null
          : dateFromJson(map['down_payment_paid_on']),
      downPaymentTransaction: map['down_payment_transaction'] is Map
          ? TransactionRecord.fromJson(map['down_payment_transaction'])
          : null,
      scheduledTotalMinor: map['scheduled_total_minor'] == null
          ? null
          : Money.fromJson(map['scheduled_total_minor']),
      scheduledRemainingMinor: map['scheduled_remaining_minor'] == null
          ? null
          : Money.fromJson(map['scheduled_remaining_minor']),
      contractTotalMinor: map['contract_total_minor'] == null
          ? null
          : Money.fromJson(map['contract_total_minor']),
      totalPaidMinor: map['total_paid_minor'] == null
          ? null
          : Money.fromJson(map['total_paid_minor']),
      remainingObligationMinor: map['remaining_obligation_minor'] == null
          ? null
          : Money.fromJson(map['remaining_obligation_minor']),
    );
  }

  final int id;
  final String clientUuid;
  final FinanceScope scope;
  final int accountId;
  final int categoryId;
  final int installmentMonthlyMinor;
  final int installmentMonths;
  final DateTime installmentStartOn;
  final String status;
  final int paidInstallments;
  final int remainingInstallments;
  final int? nextInstallmentNumber;
  final DateTime? nextPaymentOn;
  final int version;
  final String? payee;
  final String? note;
  final Account? account;
  final Category? category;
  final int downPaymentMinor;
  final DateTime? downPaymentPaidOn;
  final TransactionRecord? downPaymentTransaction;
  final int? _scheduledTotalMinor;
  final int? _scheduledRemainingMinor;
  final int? _contractTotalMinor;
  final int? _totalPaidMinor;
  final int? _remainingObligationMinor;

  bool get isActive => status == 'active';
  bool get isCompleted => status == 'completed';
  bool get isArchived => status == 'archived';
  bool get hasPayments => paidInstallments > 0;
  bool get hasDownPayment => downPaymentMinor > 0;
  int get scheduledTotalMinor =>
      _scheduledTotalMinor ?? installmentMonthlyMinor * installmentMonths;
  int get scheduledRemainingMinor =>
      _scheduledRemainingMinor ??
      installmentMonthlyMinor * remainingInstallments;
  int get contractTotalMinor =>
      _contractTotalMinor ?? downPaymentMinor + scheduledTotalMinor;
  int get totalPaidMinor =>
      _totalPaidMinor ??
      downPaymentMinor + installmentMonthlyMinor * paidInstallments;
  int get remainingObligationMinor =>
      _remainingObligationMinor ?? scheduledRemainingMinor;
}

class InstallmentPaymentResult {
  const InstallmentPaymentResult({
    required this.plan,
    required this.transaction,
  });

  factory InstallmentPaymentResult.fromJson(Object? value) {
    final map = jsonMap(value);
    final data = map['data'] is Map ? jsonMap(map['data']) : map;
    return InstallmentPaymentResult(
      plan: InstallmentPlan.fromJson(data['plan']),
      transaction: TransactionRecord.fromJson(data['transaction']),
    );
  }

  final InstallmentPlan plan;
  final TransactionRecord transaction;
}

class JointSplitExpense {
  const JointSplitExpense({
    required this.id,
    required this.clientUuid,
    required this.amountMinor,
    required this.occurredOn,
    required this.categoryId,
    this.cutoffPeriodId,
    required this.categoryName,
    required this.categoryNameSnapshot,
    required this.firstAccountId,
    required this.firstAccountName,
    required this.firstAccountNameSnapshot,
    required this.firstShareMinor,
    required this.secondAccountId,
    required this.secondAccountName,
    required this.secondAccountNameSnapshot,
    required this.secondShareMinor,
    required this.totalDebitMinor,
    required this.totalCashChangeMinor,
    required this.status,
    required this.version,
    this.payee,
    this.note,
    this.firstAccount,
    this.secondAccount,
    this.category,
    this.firstTransaction,
    this.secondTransaction,
    this.componentTransactions = const [],
    FinanceScope? scope,
    bool? isImmutable,
    int? componentCount,
    bool? affectsAccountBalance,
    bool? affectsIndividualAccountBalances,
    bool? affectsTotalCashBalance,
    bool? affectsIncome,
    bool? affectsExpense,
    bool? affectsCashflow,
    bool? affectsBudget,
    String? splitMethod,
    String? oddMinorRecipient,
    int? expenseCountedMinor,
    bool? hasCutoffPeriodField,
  }) : // Nullable backing keeps future hot-reload additions safe.
       // ignore: prefer_initializing_formals
       _scope = scope,
       // ignore: prefer_initializing_formals
       _isImmutable = isImmutable,
       // ignore: prefer_initializing_formals
       _componentCount = componentCount,
       // ignore: prefer_initializing_formals
       _affectsAccountBalance = affectsAccountBalance,
       // ignore: prefer_initializing_formals
       _affectsIndividualAccountBalances = affectsIndividualAccountBalances,
       // ignore: prefer_initializing_formals
       _affectsTotalCashBalance = affectsTotalCashBalance,
       // ignore: prefer_initializing_formals
       _affectsIncome = affectsIncome,
       // ignore: prefer_initializing_formals
       _affectsExpense = affectsExpense,
       // ignore: prefer_initializing_formals
       _affectsCashflow = affectsCashflow,
       // ignore: prefer_initializing_formals
       _affectsBudget = affectsBudget,
       // ignore: prefer_initializing_formals
       _splitMethod = splitMethod,
       // ignore: prefer_initializing_formals
       _oddMinorRecipient = oddMinorRecipient,
       // ignore: prefer_initializing_formals
       _expenseCountedMinor = expenseCountedMinor,
       // ignore: prefer_initializing_formals
       _hasCutoffPeriodField = hasCutoffPeriodField;

  factory JointSplitExpense.fromJson(Object? value) {
    final map = jsonMap(value);
    final firstTransaction = map['first_transaction'] is Map
        ? TransactionRecord.fromJson(map['first_transaction'])
        : null;
    final secondTransaction = map['second_transaction'] is Map
        ? TransactionRecord.fromJson(map['second_transaction'])
        : null;
    final components = jsonList(map['component_transactions'])
        .map(TransactionRecord.fromJson)
        .toList();
    return JointSplitExpense(
      id: jsonInt(map['id']),
      clientUuid: map['client_uuid']?.toString() ?? '',
      amountMinor: Money.fromJson(map['amount_minor']),
      occurredOn: dateFromJson(map['occurred_on']),
      categoryId: jsonInt(map['category_id']),
      cutoffPeriodId: map['cutoff_period_id'] == null
          ? null
          : jsonInt(map['cutoff_period_id']),
      categoryName: map['category_name']?.toString() ?? '',
      categoryNameSnapshot: map['category_name_snapshot']?.toString() ?? '',
      payee: _nullableTrimmed(map['payee']),
      note: _nullableTrimmed(map['note']),
      firstAccountId: jsonInt(map['first_account_id']),
      firstAccountName: map['first_account_name']?.toString() ?? '',
      firstAccountNameSnapshot:
          map['first_account_name_snapshot']?.toString() ?? '',
      firstShareMinor: Money.fromJson(map['first_share_minor']),
      secondAccountId: jsonInt(map['second_account_id']),
      secondAccountName: map['second_account_name']?.toString() ?? '',
      secondAccountNameSnapshot:
          map['second_account_name_snapshot']?.toString() ?? '',
      secondShareMinor: Money.fromJson(map['second_share_minor']),
      totalDebitMinor: Money.fromJson(map['total_debit_minor']),
      totalCashChangeMinor: Money.fromJson(map['total_cash_change_minor']),
      status: map['status']?.toString() ?? 'posted',
      version: jsonInt(map['version'], 1),
      firstAccount: map['first_account'] is Map
          ? Account.fromJson(map['first_account'])
          : null,
      secondAccount: map['second_account'] is Map
          ? Account.fromJson(map['second_account'])
          : null,
      category: map['category'] is Map
          ? Category.fromJson(map['category'])
          : null,
      firstTransaction: firstTransaction,
      secondTransaction: secondTransaction,
      componentTransactions: components.isEmpty
          ? <TransactionRecord?>[
              firstTransaction,
              secondTransaction,
            ].whereType<TransactionRecord>().toList()
          : components,
      scope: FinanceScope.fromJson(map['scope'] ?? 'joint'),
      isImmutable: map.containsKey('is_immutable')
          ? jsonBool(map['is_immutable'])
          : null,
      componentCount: map.containsKey('component_count')
          ? jsonInt(map['component_count'])
          : null,
      affectsAccountBalance: map.containsKey('affects_account_balance')
          ? jsonBool(map['affects_account_balance'])
          : null,
      affectsIndividualAccountBalances:
          map.containsKey('affects_individual_account_balances')
          ? jsonBool(map['affects_individual_account_balances'])
          : null,
      affectsTotalCashBalance: map.containsKey('affects_total_cash_balance')
          ? jsonBool(map['affects_total_cash_balance'])
          : null,
      affectsIncome: map.containsKey('affects_income')
          ? jsonBool(map['affects_income'])
          : null,
      affectsExpense: map.containsKey('affects_expense')
          ? jsonBool(map['affects_expense'])
          : null,
      affectsCashflow: map.containsKey('affects_cashflow')
          ? jsonBool(map['affects_cashflow'])
          : null,
      affectsBudget: map.containsKey('affects_budget')
          ? jsonBool(map['affects_budget'])
          : null,
      splitMethod: _nullableTrimmed(map['split_method']),
      oddMinorRecipient: _nullableTrimmed(map['odd_minor_recipient']),
      expenseCountedMinor: map.containsKey('expense_counted_minor')
          ? Money.fromJson(map['expense_counted_minor'])
          : null,
      hasCutoffPeriodField: map.containsKey('cutoff_period_id'),
    );
  }

  final int id;
  final String clientUuid;
  final int amountMinor;
  final DateTime occurredOn;
  final int categoryId;
  final int? cutoffPeriodId;
  final String categoryName;
  final String categoryNameSnapshot;
  final String? payee;
  final String? note;
  final int firstAccountId;
  final String firstAccountName;
  final String firstAccountNameSnapshot;
  final int firstShareMinor;
  final int secondAccountId;
  final String secondAccountName;
  final String secondAccountNameSnapshot;
  final int secondShareMinor;
  final int totalDebitMinor;
  final int totalCashChangeMinor;
  final String status;
  final int version;
  final Account? firstAccount;
  final Account? secondAccount;
  final Category? category;
  final TransactionRecord? firstTransaction;
  final TransactionRecord? secondTransaction;
  final List<TransactionRecord> componentTransactions;
  final FinanceScope? _scope;
  final bool? _isImmutable;
  final int? _componentCount;
  final bool? _affectsAccountBalance;
  final bool? _affectsIndividualAccountBalances;
  final bool? _affectsTotalCashBalance;
  final bool? _affectsIncome;
  final bool? _affectsExpense;
  final bool? _affectsCashflow;
  final bool? _affectsBudget;
  final String? _splitMethod;
  final String? _oddMinorRecipient;
  final int? _expenseCountedMinor;
  final bool? _hasCutoffPeriodField;

  FinanceScope get scope => _scope ?? FinanceScope.joint;
  bool get isImmutable => _isImmutable ?? false;
  int get componentCount => _componentCount ?? componentTransactions.length;
  bool get affectsAccountBalance => _affectsAccountBalance ?? false;
  bool get affectsIndividualAccountBalances =>
      _affectsIndividualAccountBalances ?? false;
  bool get affectsTotalCashBalance => _affectsTotalCashBalance ?? false;
  bool get affectsIncome => _affectsIncome ?? false;
  bool get affectsExpense => _affectsExpense ?? false;
  bool get affectsCashflow => _affectsCashflow ?? false;
  bool get affectsBudget => _affectsBudget ?? false;
  String get splitMethod => _splitMethod ?? 'equal';
  String get oddMinorRecipient => _oddMinorRecipient ?? 'first';
  int get expenseCountedMinor => _expenseCountedMinor ?? amountMinor;
  bool get hasEffectMetadata =>
      _isImmutable != null &&
      _componentCount != null &&
      _affectsAccountBalance != null &&
      _affectsIndividualAccountBalances != null &&
      _affectsTotalCashBalance != null &&
      _affectsIncome != null &&
      _affectsExpense != null &&
      _affectsCashflow != null &&
      _affectsBudget != null &&
      _splitMethod != null &&
      _oddMinorRecipient != null &&
      _expenseCountedMinor != null &&
      _hasCutoffPeriodField == true;
  String get firstDisplayName => firstAccountNameSnapshot.isNotEmpty
      ? firstAccountNameSnapshot
      : firstAccount?.displayName ??
            (firstAccountName.isNotEmpty ? firstAccountName : 'First account');
  String get secondDisplayName => secondAccountNameSnapshot.isNotEmpty
      ? secondAccountNameSnapshot
      : secondAccount?.displayName ??
            (secondAccountName.isNotEmpty
                ? secondAccountName
                : 'Second account');
  String get categoryDisplayName => categoryNameSnapshot.isNotEmpty
      ? categoryNameSnapshot
      : category?.name ?? (categoryName.isNotEmpty ? categoryName : 'Expense');
  bool get hasOddCentavo => amountMinor.isOdd;
}

class AccountTransfer {
  const AccountTransfer({
    required this.id,
    required this.clientUuid,
    required this.sourceAccountId,
    required this.sourceAccountName,
    required this.destinationAccountId,
    required this.destinationAccountName,
    required this.amountMinor,
    required this.transferredOn,
    required this.serviceChargeMinor,
    required this.totalSourceDebitMinor,
    required this.destinationCreditMinor,
    required this.totalCashChangeMinor,
    required this.status,
    required this.version,
    this.note,
    this.sourceAccount,
    this.destinationAccount,
    this.feeTransaction,
    FinanceScope? scope,
    bool? isImmutable,
    bool? principalAffectsIndividualAccountBalances,
    bool? principalAffectsTotalCashBalance,
    bool? serviceChargeAffectsAccountBalance,
    bool? affectsTotalCashBalance,
    bool? affectsIncome,
    bool? affectsExpense,
    bool? affectsCashflow,
    bool? affectsBudget,
    int? sourceAvailableMoneyChangeMinor,
    int? destinationAvailableMoneyChangeMinor,
    int? principalAvailableMoneyChangeMinor,
    int? serviceChargeAvailableMoneyChangeMinor,
    int? availableMoneyChangeMinor,
    bool? principalAffectsAvailableMoney,
    bool? serviceChargeAffectsAvailableMoney,
    bool? affectsAvailableMoney,
  }) : // Nullable backing makes future hot-reload additions safe.
       // ignore: prefer_initializing_formals
       _scope = scope,
       // ignore: prefer_initializing_formals
       _isImmutable = isImmutable,
       // ignore: prefer_initializing_formals
       _principalAffectsIndividualAccountBalances =
           principalAffectsIndividualAccountBalances,
       // ignore: prefer_initializing_formals
       _principalAffectsTotalCashBalance = principalAffectsTotalCashBalance,
       // ignore: prefer_initializing_formals
       _serviceChargeAffectsAccountBalance = serviceChargeAffectsAccountBalance,
       // ignore: prefer_initializing_formals
       _affectsTotalCashBalance = affectsTotalCashBalance,
       // ignore: prefer_initializing_formals
       _affectsIncome = affectsIncome,
       // ignore: prefer_initializing_formals
       _affectsExpense = affectsExpense,
       // ignore: prefer_initializing_formals
       _affectsCashflow = affectsCashflow,
       // ignore: prefer_initializing_formals
       _affectsBudget = affectsBudget,
       // ignore: prefer_initializing_formals
       _sourceAvailableMoneyChangeMinor = sourceAvailableMoneyChangeMinor,
       // ignore: prefer_initializing_formals
       _destinationAvailableMoneyChangeMinor =
           destinationAvailableMoneyChangeMinor,
       // ignore: prefer_initializing_formals
       _principalAvailableMoneyChangeMinor = principalAvailableMoneyChangeMinor,
       // ignore: prefer_initializing_formals
       _serviceChargeAvailableMoneyChangeMinor =
           serviceChargeAvailableMoneyChangeMinor,
       // ignore: prefer_initializing_formals
       _availableMoneyChangeMinor = availableMoneyChangeMinor,
       // ignore: prefer_initializing_formals
       _principalAffectsAvailableMoney = principalAffectsAvailableMoney,
       // ignore: prefer_initializing_formals
       _serviceChargeAffectsAvailableMoney = serviceChargeAffectsAvailableMoney,
       // ignore: prefer_initializing_formals
       _affectsAvailableMoney = affectsAvailableMoney;

  factory AccountTransfer.fromJson(Object? value) {
    final map = jsonMap(value);
    return AccountTransfer(
      id: jsonInt(map['id']),
      clientUuid: map['client_uuid']?.toString() ?? '',
      sourceAccountId: jsonInt(map['source_account_id']),
      sourceAccountName:
          map['source_account_name']?.toString() ?? 'Source account',
      destinationAccountId: jsonInt(map['destination_account_id']),
      destinationAccountName:
          map['destination_account_name']?.toString() ?? 'Destination account',
      amountMinor: Money.fromJson(map['amount_minor']),
      transferredOn: dateFromJson(map['transferred_on']),
      serviceChargeMinor: Money.fromJson(map['service_charge_minor']),
      totalSourceDebitMinor: Money.fromJson(map['total_source_debit_minor']),
      destinationCreditMinor: Money.fromJson(map['destination_credit_minor']),
      totalCashChangeMinor: Money.fromJson(map['total_cash_change_minor']),
      status: map['status']?.toString() ?? 'posted',
      version: jsonInt(map['version'], 1),
      note: _nullableTrimmed(map['note']),
      sourceAccount: map['source_account'] is Map
          ? Account.fromJson(map['source_account'])
          : null,
      destinationAccount: map['destination_account'] is Map
          ? Account.fromJson(map['destination_account'])
          : null,
      feeTransaction:
          (map['fee_transaction'] ?? map['service_charge_transaction']) is Map
          ? TransactionRecord.fromJson(
              map['fee_transaction'] ?? map['service_charge_transaction'],
            )
          : null,
      scope: FinanceScope.fromJson(map['scope']),
      isImmutable: map.containsKey('is_immutable')
          ? jsonBool(map['is_immutable'])
          : null,
      principalAffectsIndividualAccountBalances:
          map.containsKey('principal_affects_individual_account_balances')
          ? jsonBool(map['principal_affects_individual_account_balances'])
          : null,
      principalAffectsTotalCashBalance:
          map.containsKey('principal_affects_total_cash_balance')
          ? jsonBool(map['principal_affects_total_cash_balance'])
          : null,
      serviceChargeAffectsAccountBalance:
          map.containsKey('service_charge_affects_account_balance')
          ? jsonBool(map['service_charge_affects_account_balance'])
          : null,
      affectsTotalCashBalance: map.containsKey('affects_total_cash_balance')
          ? jsonBool(map['affects_total_cash_balance'])
          : null,
      affectsIncome: map.containsKey('affects_income')
          ? jsonBool(map['affects_income'])
          : null,
      affectsExpense: map.containsKey('affects_expense')
          ? jsonBool(map['affects_expense'])
          : null,
      affectsCashflow: map.containsKey('affects_cashflow')
          ? jsonBool(map['affects_cashflow'])
          : null,
      affectsBudget: map.containsKey('affects_budget')
          ? jsonBool(map['affects_budget'])
          : null,
      sourceAvailableMoneyChangeMinor:
          map.containsKey('source_available_money_change_minor')
          ? Money.fromJson(map['source_available_money_change_minor'])
          : null,
      destinationAvailableMoneyChangeMinor:
          map.containsKey('destination_available_money_change_minor')
          ? Money.fromJson(map['destination_available_money_change_minor'])
          : null,
      principalAvailableMoneyChangeMinor:
          map.containsKey('principal_available_money_change_minor')
          ? Money.fromJson(map['principal_available_money_change_minor'])
          : null,
      serviceChargeAvailableMoneyChangeMinor:
          map.containsKey('service_charge_available_money_change_minor')
          ? Money.fromJson(map['service_charge_available_money_change_minor'])
          : null,
      availableMoneyChangeMinor: map.containsKey('available_money_change_minor')
          ? Money.fromJson(map['available_money_change_minor'])
          : null,
      principalAffectsAvailableMoney:
          map.containsKey('principal_affects_available_money')
          ? jsonBool(map['principal_affects_available_money'])
          : null,
      serviceChargeAffectsAvailableMoney:
          map.containsKey('service_charge_affects_available_money')
          ? jsonBool(map['service_charge_affects_available_money'])
          : null,
      affectsAvailableMoney: map.containsKey('affects_available_money')
          ? jsonBool(map['affects_available_money'])
          : null,
    );
  }

  final int id;
  final String clientUuid;
  final int sourceAccountId;
  final String sourceAccountName;
  final int destinationAccountId;
  final String destinationAccountName;
  final int amountMinor;
  final DateTime transferredOn;
  final int serviceChargeMinor;
  final int totalSourceDebitMinor;
  final int destinationCreditMinor;
  final int totalCashChangeMinor;
  final String status;
  final int version;
  final String? note;
  final Account? sourceAccount;
  final Account? destinationAccount;
  final TransactionRecord? feeTransaction;
  final FinanceScope? _scope;
  final bool? _isImmutable;
  final bool? _principalAffectsIndividualAccountBalances;
  final bool? _principalAffectsTotalCashBalance;
  final bool? _serviceChargeAffectsAccountBalance;
  final bool? _affectsTotalCashBalance;
  final bool? _affectsIncome;
  final bool? _affectsExpense;
  final bool? _affectsCashflow;
  final bool? _affectsBudget;
  final int? _sourceAvailableMoneyChangeMinor;
  final int? _destinationAvailableMoneyChangeMinor;
  final int? _principalAvailableMoneyChangeMinor;
  final int? _serviceChargeAvailableMoneyChangeMinor;
  final int? _availableMoneyChangeMinor;
  final bool? _principalAffectsAvailableMoney;
  final bool? _serviceChargeAffectsAvailableMoney;
  final bool? _affectsAvailableMoney;

  FinanceScope get scope => _scope ?? FinanceScope.personal;
  bool get isImmutable => _isImmutable ?? false;
  bool get principalAffectsIndividualAccountBalances =>
      _principalAffectsIndividualAccountBalances ?? false;
  bool get principalAffectsTotalCashBalance =>
      _principalAffectsTotalCashBalance ?? false;
  bool get serviceChargeAffectsAccountBalance =>
      _serviceChargeAffectsAccountBalance ?? false;
  bool get affectsTotalCashBalance => _affectsTotalCashBalance ?? false;
  bool get affectsIncome => _affectsIncome ?? false;
  bool get affectsExpense => _affectsExpense ?? false;
  bool get affectsCashflow => _affectsCashflow ?? false;
  bool get affectsBudget => _affectsBudget ?? false;
  int get sourceAvailableMoneyChangeMinor =>
      _sourceAvailableMoneyChangeMinor ??
      (sourceAccount?.countsTowardAvailableMoney == true
          ? -totalSourceDebitMinor
          : 0);
  int get destinationAvailableMoneyChangeMinor =>
      _destinationAvailableMoneyChangeMinor ??
      (destinationAccount?.countsTowardAvailableMoney == true
          ? destinationCreditMinor
          : 0);
  int get principalAvailableMoneyChangeMinor =>
      _principalAvailableMoneyChangeMinor ??
      (sourceAccount?.countsTowardAvailableMoney == true ? -amountMinor : 0) +
          (destinationAccount?.countsTowardAvailableMoney == true
              ? amountMinor
              : 0);
  int get serviceChargeAvailableMoneyChangeMinor =>
      _serviceChargeAvailableMoneyChangeMinor ??
      (sourceAccount?.countsTowardAvailableMoney == true
          ? -serviceChargeMinor
          : 0);
  int get availableMoneyChangeMinor =>
      _availableMoneyChangeMinor ??
      sourceAvailableMoneyChangeMinor + destinationAvailableMoneyChangeMinor;
  bool get principalAffectsAvailableMoney =>
      _principalAffectsAvailableMoney ??
      principalAvailableMoneyChangeMinor != 0;
  bool get serviceChargeAffectsAvailableMoney =>
      _serviceChargeAffectsAvailableMoney ??
      serviceChargeAvailableMoneyChangeMinor != 0;
  bool get affectsAvailableMoney =>
      _affectsAvailableMoney ?? availableMoneyChangeMinor != 0;
  bool get hasAvailableMoneyEffectMetadata =>
      _sourceAvailableMoneyChangeMinor != null &&
      _destinationAvailableMoneyChangeMinor != null &&
      _principalAvailableMoneyChangeMinor != null &&
      _serviceChargeAvailableMoneyChangeMinor != null &&
      _availableMoneyChangeMinor != null &&
      _principalAffectsAvailableMoney != null &&
      _serviceChargeAffectsAvailableMoney != null &&
      _affectsAvailableMoney != null;
  bool get hasEffectMetadata =>
      _isImmutable != null &&
      _principalAffectsIndividualAccountBalances != null &&
      _principalAffectsTotalCashBalance != null &&
      _serviceChargeAffectsAccountBalance != null &&
      _affectsTotalCashBalance != null &&
      _affectsIncome != null &&
      _affectsExpense != null &&
      _affectsCashflow != null &&
      _affectsBudget != null;
  bool get hasServiceCharge => serviceChargeMinor > 0;
  // Immutable history always leads with the posting-time snapshots. Nested
  // accounts may carry a newer name after an edit.
  String get sourceDisplayName => sourceAccountName;
  String get destinationDisplayName => destinationAccountName;
}

class CreditCardPayment {
  const CreditCardPayment({
    required this.id,
    required this.clientUuid,
    required this.sourceAccountId,
    required this.sourceAccountName,
    required this.creditCardAccountId,
    required this.creditCardAccountName,
    required this.amountMinor,
    required this.paidOn,
    required this.sourceCashChangeMinor,
    required this.creditCardDebtChangeMinor,
    required this.debtReductionMinor,
    required this.totalCashChangeMinor,
    required this.netPositionChangeMinor,
    required this.status,
    required this.version,
    this.serviceChargeMinor = 0,
    int? totalSourceDebitMinor,
    this.serviceChargeTransactionId,
    this.sourceAccountNameSnapshot = '',
    this.creditCardAccountNameSnapshot = '',
    this.note,
    this.sourceAccount,
    this.creditCardAccount,
    this.feeTransaction,
    FinanceScope? scope,
    bool? isImmutable,
    bool? affectsAccountBalance,
    bool? affectsIndividualAccountBalances,
    bool? affectsTotalCashBalance,
    bool? affectsCreditCardDebt,
    bool? affectsNetPosition,
    bool? serviceChargeAffectsAccountBalance,
    bool? serviceChargeAffectsExpense,
    bool? affectsIncome,
    bool? affectsExpense,
    bool? affectsCashflow,
    bool? affectsBudget,
    bool? hasNetPositionChangeField,
    bool hasValidServiceChargeMetadata = true,
  }) : // Public parameter names intentionally differ from nullable storage.
       // ignore: prefer_initializing_formals
       _scope = scope,
       // ignore: prefer_initializing_formals
       _isImmutable = isImmutable,
       // ignore: prefer_initializing_formals
       _affectsAccountBalance = affectsAccountBalance,
       // ignore: prefer_initializing_formals
       _affectsIndividualAccountBalances = affectsIndividualAccountBalances,
       // ignore: prefer_initializing_formals
       _affectsTotalCashBalance = affectsTotalCashBalance,
       // ignore: prefer_initializing_formals
       _affectsCreditCardDebt = affectsCreditCardDebt,
       // ignore: prefer_initializing_formals
       _affectsNetPosition = affectsNetPosition,
       // ignore: prefer_initializing_formals
       _serviceChargeAffectsAccountBalance = serviceChargeAffectsAccountBalance,
       // ignore: prefer_initializing_formals
       _serviceChargeAffectsExpense = serviceChargeAffectsExpense,
       // ignore: prefer_initializing_formals
       _affectsIncome = affectsIncome,
       // ignore: prefer_initializing_formals
       _affectsExpense = affectsExpense,
       // ignore: prefer_initializing_formals
       _affectsCashflow = affectsCashflow,
       // ignore: prefer_initializing_formals
       _affectsBudget = affectsBudget,
       // ignore: prefer_initializing_formals
       _hasNetPositionChangeField = hasNetPositionChangeField,
       // ignore: prefer_initializing_formals
       _totalSourceDebitMinor = totalSourceDebitMinor,
       // ignore: prefer_initializing_formals
       _hasValidServiceChargeMetadata = hasValidServiceChargeMetadata;

  factory CreditCardPayment.fromJson(Object? value) {
    final map = jsonMap(value);
    final serviceChargeKeys = [
      'service_charge_minor',
      'service_charge_transaction_id',
      'total_source_debit_minor',
      'service_charge_affects_account_balance',
      'service_charge_affects_expense',
    ];
    final hasAnyServiceChargeMetadata =
        serviceChargeKeys.any(map.containsKey) ||
        map.containsKey('fee_transaction') ||
        map.containsKey('service_charge_transaction');
    final hasCompleteServiceChargeMetadata =
        serviceChargeKeys.every(map.containsKey) &&
        (map.containsKey('fee_transaction') ||
            map.containsKey('service_charge_transaction'));
    return CreditCardPayment(
      id: jsonInt(map['id']),
      clientUuid: map['client_uuid']?.toString() ?? '',
      sourceAccountId: jsonInt(map['source_account_id']),
      sourceAccountName:
          map['source_account_name']?.toString() ?? 'Payment account',
      sourceAccountNameSnapshot:
          map['source_account_name_snapshot']?.toString() ?? '',
      creditCardAccountId: jsonInt(map['credit_card_account_id']),
      creditCardAccountName:
          map['credit_card_account_name']?.toString() ?? 'Credit card',
      creditCardAccountNameSnapshot:
          map['credit_card_account_name_snapshot']?.toString() ?? '',
      amountMinor: Money.fromJson(map['amount_minor']),
      serviceChargeMinor: Money.fromJson(map['service_charge_minor']),
      totalSourceDebitMinor: map.containsKey('total_source_debit_minor')
          ? Money.fromJson(map['total_source_debit_minor'])
          : null,
      serviceChargeTransactionId: map['service_charge_transaction_id'] == null
          ? null
          : jsonInt(map['service_charge_transaction_id']),
      paidOn: dateFromJson(map['paid_on']),
      note: _nullableTrimmed(map['note']),
      status: map['status']?.toString() ?? 'posted',
      version: jsonInt(map['version'], 1),
      sourceCashChangeMinor: Money.fromJson(map['source_cash_change_minor']),
      creditCardDebtChangeMinor: Money.fromJson(
        map['credit_card_debt_change_minor'],
      ),
      debtReductionMinor: Money.fromJson(map['debt_reduction_minor']),
      totalCashChangeMinor: Money.fromJson(map['total_cash_change_minor']),
      netPositionChangeMinor: Money.fromJson(map['net_position_change_minor']),
      sourceAccount: map['source_account'] is Map
          ? Account.fromJson(map['source_account'])
          : null,
      creditCardAccount: map['credit_card_account'] is Map
          ? Account.fromJson(map['credit_card_account'])
          : null,
      feeTransaction:
          (map['fee_transaction'] ?? map['service_charge_transaction']) is Map
          ? TransactionRecord.fromJson(
              map['fee_transaction'] ?? map['service_charge_transaction'],
            )
          : null,
      scope: FinanceScope.fromJson(map['scope']),
      isImmutable: map.containsKey('is_immutable')
          ? jsonBool(map['is_immutable'])
          : null,
      affectsAccountBalance: map.containsKey('affects_account_balance')
          ? jsonBool(map['affects_account_balance'])
          : null,
      affectsIndividualAccountBalances:
          map.containsKey('affects_individual_account_balances')
          ? jsonBool(map['affects_individual_account_balances'])
          : null,
      affectsTotalCashBalance: map.containsKey('affects_total_cash_balance')
          ? jsonBool(map['affects_total_cash_balance'])
          : null,
      affectsCreditCardDebt: map.containsKey('affects_credit_card_debt')
          ? jsonBool(map['affects_credit_card_debt'])
          : null,
      affectsNetPosition: map.containsKey('affects_net_position')
          ? jsonBool(map['affects_net_position'])
          : null,
      serviceChargeAffectsAccountBalance:
          map.containsKey('service_charge_affects_account_balance')
          ? jsonBool(map['service_charge_affects_account_balance'])
          : null,
      serviceChargeAffectsExpense:
          map.containsKey('service_charge_affects_expense')
          ? jsonBool(map['service_charge_affects_expense'])
          : null,
      affectsIncome: map.containsKey('affects_income')
          ? jsonBool(map['affects_income'])
          : null,
      affectsExpense: map.containsKey('affects_expense')
          ? jsonBool(map['affects_expense'])
          : null,
      affectsCashflow: map.containsKey('affects_cashflow')
          ? jsonBool(map['affects_cashflow'])
          : null,
      affectsBudget: map.containsKey('affects_budget')
          ? jsonBool(map['affects_budget'])
          : null,
      hasNetPositionChangeField: map.containsKey('net_position_change_minor'),
      hasValidServiceChargeMetadata:
          !hasAnyServiceChargeMetadata || hasCompleteServiceChargeMetadata,
    );
  }

  final int id;
  final String clientUuid;
  final int sourceAccountId;
  final String sourceAccountName;
  final String sourceAccountNameSnapshot;
  final int creditCardAccountId;
  final String creditCardAccountName;
  final String creditCardAccountNameSnapshot;
  final int amountMinor;
  final int serviceChargeMinor;
  final int? _totalSourceDebitMinor;
  final int? serviceChargeTransactionId;
  final DateTime paidOn;
  final String? note;
  final int sourceCashChangeMinor;
  final int creditCardDebtChangeMinor;
  final int debtReductionMinor;
  final int totalCashChangeMinor;
  final int netPositionChangeMinor;
  final String status;
  final int version;
  final Account? sourceAccount;
  final Account? creditCardAccount;
  final TransactionRecord? feeTransaction;
  final FinanceScope? _scope;
  final bool? _isImmutable;
  final bool? _affectsAccountBalance;
  final bool? _affectsIndividualAccountBalances;
  final bool? _affectsTotalCashBalance;
  final bool? _affectsCreditCardDebt;
  final bool? _affectsNetPosition;
  final bool? _serviceChargeAffectsAccountBalance;
  final bool? _serviceChargeAffectsExpense;
  final bool? _affectsIncome;
  final bool? _affectsExpense;
  final bool? _affectsCashflow;
  final bool? _affectsBudget;
  final bool? _hasNetPositionChangeField;
  final bool _hasValidServiceChargeMetadata;

  FinanceScope get scope => _scope ?? FinanceScope.personal;
  bool get isImmutable => _isImmutable ?? false;
  bool get affectsAccountBalance => _affectsAccountBalance ?? false;
  bool get affectsIndividualAccountBalances =>
      _affectsIndividualAccountBalances ?? false;
  bool get affectsTotalCashBalance => _affectsTotalCashBalance ?? false;
  bool get affectsCreditCardDebt => _affectsCreditCardDebt ?? false;
  bool get affectsNetPosition => _affectsNetPosition ?? false;
  bool get serviceChargeAffectsAccountBalance =>
      _serviceChargeAffectsAccountBalance ?? false;
  bool get serviceChargeAffectsExpense => _serviceChargeAffectsExpense ?? false;
  bool get affectsIncome => _affectsIncome ?? false;
  bool get affectsExpense => _affectsExpense ?? false;
  bool get affectsCashflow => _affectsCashflow ?? false;
  bool get affectsBudget => _affectsBudget ?? false;
  int get totalSourceDebitMinor =>
      _totalSourceDebitMinor ?? amountMinor + serviceChargeMinor;
  bool get hasEffectMetadata =>
      _isImmutable != null &&
      _affectsAccountBalance != null &&
      _affectsIndividualAccountBalances != null &&
      _affectsTotalCashBalance != null &&
      _affectsCreditCardDebt != null &&
      _affectsNetPosition != null &&
      _affectsIncome != null &&
      _affectsExpense != null &&
      _affectsCashflow != null &&
      _affectsBudget != null &&
      _hasNetPositionChangeField == true &&
      _hasValidServiceChargeMetadata;
  bool get hasServiceCharge => serviceChargeMinor > 0;
  String get sourceDisplayName => sourceAccountNameSnapshot.isNotEmpty
      ? sourceAccountNameSnapshot
      : sourceAccountName;
  String get creditCardDisplayName => creditCardAccountNameSnapshot.isNotEmpty
      ? creditCardAccountNameSnapshot
      : creditCardAccountName;
}

class SavingsInterestCredit {
  const SavingsInterestCredit({
    required this.id,
    required this.clientUuid,
    required this.savingsAccountId,
    required this.savingsAccountName,
    required this.amountMinor,
    required this.creditedOn,
    required this.creditedMonth,
    required this.interestTransactionId,
    required this.accountBalanceChangeMinor,
    required this.savingsBalanceChangeMinor,
    required this.totalCashChangeMinor,
    required this.availableMoneyChangeMinor,
    required this.netPositionChangeMinor,
    required this.status,
    required this.version,
    this.savingsAccountNameSnapshot = '',
    this.note,
    this.savingsAccount,
    this.interestTransaction,
    String? creditMethod,
    int? calculationBalanceMinor,
    int? monthlyInterestRateBasisPoints,
    double? monthlyInterestRatePercent,
    int? transactionId,
    TransactionRecord? incomeTransaction,
    this.createdAt,
    this.updatedAt,
    FinanceScope? scope,
    bool? isImmutable,
    bool? affectsAccountBalance,
    bool? affectsIndividualAccountBalances,
    bool? affectsTotalCashBalance,
    bool? affectsAvailableMoney,
    bool? affectsSavingsBalance,
    bool? affectsNetPosition,
    bool? affectsIncome,
    bool? affectsExpense,
    bool? affectsCashflow,
    bool? affectsBudget,
  }) : // Nullable backing keeps hot-reloaded instances safe.
       // ignore: prefer_initializing_formals
       _scope = scope,
       // ignore: prefer_initializing_formals
       _isImmutable = isImmutable,
       // ignore: prefer_initializing_formals
       _affectsAccountBalance = affectsAccountBalance,
       // ignore: prefer_initializing_formals
       _affectsIndividualAccountBalances = affectsIndividualAccountBalances,
       // ignore: prefer_initializing_formals
       _affectsTotalCashBalance = affectsTotalCashBalance,
       // ignore: prefer_initializing_formals
       _affectsAvailableMoney = affectsAvailableMoney,
       // ignore: prefer_initializing_formals
       _affectsSavingsBalance = affectsSavingsBalance,
       // ignore: prefer_initializing_formals
       _affectsNetPosition = affectsNetPosition,
       // ignore: prefer_initializing_formals
       _affectsIncome = affectsIncome,
       // ignore: prefer_initializing_formals
       _affectsExpense = affectsExpense,
       // ignore: prefer_initializing_formals
       _affectsCashflow = affectsCashflow,
       // ignore: prefer_initializing_formals
       _affectsBudget = affectsBudget,
       // ignore: prefer_initializing_formals
       _creditMethod = creditMethod,
       // ignore: prefer_initializing_formals
       _calculationBalanceMinor = calculationBalanceMinor,
       // ignore: prefer_initializing_formals
       _monthlyInterestRateBasisPoints = monthlyInterestRateBasisPoints,
       // ignore: prefer_initializing_formals
       _monthlyInterestRatePercent = monthlyInterestRatePercent,
       // ignore: prefer_initializing_formals
       _transactionId = transactionId,
       // ignore: prefer_initializing_formals
       _incomeTransaction = incomeTransaction;

  factory SavingsInterestCredit.fromJson(Object? value) {
    final map = jsonMap(value);
    return SavingsInterestCredit(
      id: jsonInt(map['id']),
      clientUuid: map['client_uuid']?.toString() ?? '',
      savingsAccountId: jsonInt(map['savings_account_id']),
      savingsAccountName:
          map['savings_account_name']?.toString() ?? 'Savings account',
      savingsAccountNameSnapshot:
          map['savings_account_name_snapshot']?.toString() ?? '',
      amountMinor: Money.fromJson(map['amount_minor']),
      creditedOn: dateFromJson(map['credited_on']),
      creditedMonth: map['credited_month']?.toString() ?? '',
      interestTransactionId: jsonInt(
        map['interest_transaction_id'] ?? map['transaction_id'],
      ),
      transactionId: map.containsKey('transaction_id')
          ? jsonInt(map['transaction_id'])
          : null,
      note: _nullableTrimmed(map['note']),
      creditMethod: _nullableTrimmed(map['credit_method']),
      calculationBalanceMinor: map['calculation_balance_minor'] == null
          ? null
          : Money.fromJson(map['calculation_balance_minor']),
      monthlyInterestRateBasisPoints:
          map['monthly_interest_rate_basis_points'] == null
          ? null
          : jsonInt(map['monthly_interest_rate_basis_points'], -1),
      monthlyInterestRatePercent: map['monthly_interest_rate_percent'] == null
          ? null
          : _nullableDouble(map['monthly_interest_rate_percent']) ?? double.nan,
      status: map['status']?.toString() ?? 'posted',
      version: jsonInt(map['version'], 1),
      accountBalanceChangeMinor: Money.fromJson(
        map['account_balance_change_minor'],
      ),
      savingsBalanceChangeMinor: Money.fromJson(
        map['savings_balance_change_minor'],
      ),
      totalCashChangeMinor: Money.fromJson(map['total_cash_change_minor']),
      availableMoneyChangeMinor: Money.fromJson(
        map['available_money_change_minor'],
      ),
      netPositionChangeMinor: Money.fromJson(map['net_position_change_minor']),
      savingsAccount: map['savings_account'] is Map
          ? Account.fromJson(map['savings_account'])
          : null,
      interestTransaction: map['interest_transaction'] is Map
          ? TransactionRecord.fromJson(map['interest_transaction'])
          : null,
      incomeTransaction: map['income_transaction'] is Map
          ? TransactionRecord.fromJson(map['income_transaction'])
          : null,
      createdAt: _nullableTimestamp(map['created_at']),
      updatedAt: _nullableTimestamp(map['updated_at']),
      scope: FinanceScope.fromJson(map['scope']),
      isImmutable: map.containsKey('is_immutable')
          ? jsonBool(map['is_immutable'])
          : null,
      affectsAccountBalance: map.containsKey('affects_account_balance')
          ? jsonBool(map['affects_account_balance'])
          : null,
      affectsIndividualAccountBalances:
          map.containsKey('affects_individual_account_balances')
          ? jsonBool(map['affects_individual_account_balances'])
          : null,
      affectsTotalCashBalance: map.containsKey('affects_total_cash_balance')
          ? jsonBool(map['affects_total_cash_balance'])
          : null,
      affectsAvailableMoney: map.containsKey('affects_available_money')
          ? jsonBool(map['affects_available_money'])
          : null,
      affectsSavingsBalance: map.containsKey('affects_savings_balance')
          ? jsonBool(map['affects_savings_balance'])
          : null,
      affectsNetPosition: map.containsKey('affects_net_position')
          ? jsonBool(map['affects_net_position'])
          : null,
      affectsIncome: map.containsKey('affects_income')
          ? jsonBool(map['affects_income'])
          : null,
      affectsExpense: map.containsKey('affects_expense')
          ? jsonBool(map['affects_expense'])
          : null,
      affectsCashflow: map.containsKey('affects_cashflow')
          ? jsonBool(map['affects_cashflow'])
          : null,
      affectsBudget: map.containsKey('affects_budget')
          ? jsonBool(map['affects_budget'])
          : null,
    );
  }

  final int id;
  final String clientUuid;
  final int savingsAccountId;
  final String savingsAccountName;
  final String savingsAccountNameSnapshot;
  final int amountMinor;
  final DateTime creditedOn;
  final String creditedMonth;
  final int interestTransactionId;
  final String? note;
  final int accountBalanceChangeMinor;
  final int savingsBalanceChangeMinor;
  final int totalCashChangeMinor;
  final int availableMoneyChangeMinor;
  final int netPositionChangeMinor;
  final String status;
  final int version;
  final Account? savingsAccount;
  final TransactionRecord? interestTransaction;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int? _transactionId;
  final TransactionRecord? _incomeTransaction;
  final FinanceScope? _scope;
  final bool? _isImmutable;
  final bool? _affectsAccountBalance;
  final bool? _affectsIndividualAccountBalances;
  final bool? _affectsTotalCashBalance;
  final bool? _affectsAvailableMoney;
  final bool? _affectsSavingsBalance;
  final bool? _affectsNetPosition;
  final bool? _affectsIncome;
  final bool? _affectsExpense;
  final bool? _affectsCashflow;
  final bool? _affectsBudget;
  final String? _creditMethod;
  final int? _calculationBalanceMinor;
  final int? _monthlyInterestRateBasisPoints;
  final double? _monthlyInterestRatePercent;

  FinanceScope get scope => _scope ?? FinanceScope.personal;
  bool get isImmutable => _isImmutable ?? false;
  bool get affectsAccountBalance => _affectsAccountBalance ?? false;
  bool get affectsIndividualAccountBalances =>
      _affectsIndividualAccountBalances ?? false;
  bool get affectsTotalCashBalance => _affectsTotalCashBalance ?? false;
  bool get affectsAvailableMoney => _affectsAvailableMoney ?? false;
  bool get affectsSavingsBalance => _affectsSavingsBalance ?? false;
  bool get affectsNetPosition => _affectsNetPosition ?? false;
  bool get affectsIncome => _affectsIncome ?? false;
  bool get affectsExpense => _affectsExpense ?? false;
  bool get affectsCashflow => _affectsCashflow ?? false;
  bool get affectsBudget => _affectsBudget ?? false;
  String get creditMethod => _creditMethod ?? 'manual';
  bool get isAutomatic => creditMethod == 'automatic';
  bool get isManual => creditMethod == 'manual';
  int? get calculationBalanceMinor => _calculationBalanceMinor;
  int? get monthlyInterestRateBasisPoints => _monthlyInterestRateBasisPoints;
  double? get monthlyInterestRatePercent => _monthlyInterestRatePercent;
  int get transactionId => _transactionId ?? interestTransactionId;
  TransactionRecord? get incomeTransaction => _incomeTransaction;
  bool get hasAliasMetadata =>
      _transactionId != null && _incomeTransaction != null;
  bool get hasConsistentAliases =>
      transactionId == interestTransactionId &&
      incomeTransaction?.id == interestTransaction?.id &&
      incomeTransaction?.clientUuid.toLowerCase() ==
          interestTransaction?.clientUuid.toLowerCase() &&
      incomeTransaction?.scope == interestTransaction?.scope &&
      incomeTransaction?.kind == interestTransaction?.kind &&
      incomeTransaction?.amountMinor == interestTransaction?.amountMinor &&
      incomeTransaction?.occurredOn == interestTransaction?.occurredOn &&
      incomeTransaction?.accountId == interestTransaction?.accountId &&
      incomeTransaction?.categoryId == interestTransaction?.categoryId &&
      incomeTransaction?.version == interestTransaction?.version &&
      incomeTransaction?.sourceType == interestTransaction?.sourceType &&
      incomeTransaction?.sourceId == interestTransaction?.sourceId;
  bool get hasEffectMetadata =>
      _isImmutable != null &&
      _affectsAccountBalance != null &&
      _affectsIndividualAccountBalances != null &&
      _affectsTotalCashBalance != null &&
      _affectsAvailableMoney != null &&
      _affectsSavingsBalance != null &&
      _affectsNetPosition != null &&
      _affectsIncome != null &&
      _affectsExpense != null &&
      _affectsCashflow != null &&
      _affectsBudget != null;
  bool get hasConsistentCalculationMetadata {
    if (!isAutomatic) {
      return isManual &&
          calculationBalanceMinor == null &&
          monthlyInterestRateBasisPoints == null &&
          monthlyInterestRatePercent == null;
    }
    final balance = calculationBalanceMinor;
    final basisPoints = monthlyInterestRateBasisPoints;
    final percent = monthlyInterestRatePercent;
    if (balance == null ||
        balance <= 0 ||
        basisPoints == null ||
        basisPoints <= 0 ||
        basisPoints > 10000 ||
        percent == null ||
        !percent.isFinite ||
        (percent - (basisPoints / 100)).abs() > 0.0000001) {
      return false;
    }
    final numerator = BigInt.from(balance) * BigInt.from(basisPoints);
    final expectedAmount =
        ((numerator + BigInt.from(5000)) ~/ BigInt.from(10000)).toInt();
    return amountMinor == expectedAmount;
  }

  String get savingsAccountDisplayName => savingsAccountNameSnapshot.isNotEmpty
      ? savingsAccountNameSnapshot
      : savingsAccountName;
}

class SavingsInterestAccrualResult {
  const SavingsInterestAccrualResult({
    required this.scope,
    required this.throughDate,
    required this.processedAccountCount,
    required this.processedDueCount,
    required this.createdCount,
    required this.skippedExistingCount,
    required this.skippedNonpositiveCount,
    required this.skippedZeroAmountCount,
    required this.processedAccounts,
    required this.credits,
  });

  factory SavingsInterestAccrualResult.fromJson(Object? value) {
    final map = jsonMap(dataOf(value));
    return SavingsInterestAccrualResult(
      scope: map['scope']?.toString().trim().toLowerCase() ?? '',
      throughDate: dateFromJson(map['through_date']),
      processedAccountCount: jsonInt(map['processed_account_count'], -1),
      processedDueCount: jsonInt(map['processed_due_count'], -1),
      createdCount: jsonInt(map['created_count'], -1),
      skippedExistingCount: jsonInt(map['skipped_existing_count'], -1),
      skippedNonpositiveCount: jsonInt(map['skipped_nonpositive_count'], -1),
      skippedZeroAmountCount: jsonInt(map['skipped_zero_amount_count'], -1),
      processedAccounts: jsonList(map['processed_accounts'])
          .map(Account.fromJson)
          .toList(growable: false),
      credits: jsonList(map['credits'])
          .map(SavingsInterestCredit.fromJson)
          .toList(growable: false),
    );
  }

  final String scope;
  final DateTime throughDate;
  final int processedAccountCount;
  final int processedDueCount;
  final int createdCount;
  final int skippedExistingCount;
  final int skippedNonpositiveCount;
  final int skippedZeroAmountCount;
  final List<Account> processedAccounts;
  final List<SavingsInterestCredit> credits;

  bool get hasConsistentMetadata {
    if (scope != 'all' ||
        processedAccountCount < 0 ||
        processedDueCount < 0 ||
        createdCount < 0 ||
        skippedExistingCount < 0 ||
        skippedNonpositiveCount < 0 ||
        skippedZeroAmountCount < 0 ||
        processedAccountCount != processedAccounts.length ||
        processedDueCount !=
            createdCount +
                skippedExistingCount +
                skippedNonpositiveCount +
                skippedZeroAmountCount ||
        createdCount != credits.length) {
      return false;
    }
    final accountIds = <int>{};
    for (final account in processedAccounts) {
      if (account.id <= 0 ||
          !accountIds.add(account.id) ||
          account.name.trim().isEmpty ||
          account.isArchived ||
          account.isSystem ||
          !account.isSavingsAccount ||
          !account.hasAutomaticMonthlyInterest ||
          !account.hasConsistentClassificationMetadata ||
          !account.hasConsistentInterestScheduleMetadata ||
          account.balanceMinor.abs() > Money.maxMinorUnits ||
          account.interestAccrualAnchorOn == null ||
          account.nextInterestAccrualOn == null ||
          !account.nextInterestAccrualOn!.isAfter(throughDate)) {
        return false;
      }
    }
    final creditIds = <int>{};
    final creditUuids = <String>{};
    for (final credit in credits) {
      final account = processedAccounts
          .where((item) => item.id == credit.savingsAccountId)
          .firstOrNull;
      if (credit.id <= 0 ||
          !creditIds.add(credit.id) ||
          !creditUuids.add(credit.clientUuid.toLowerCase()) ||
          !credit.isAutomatic ||
          !credit.hasConsistentCalculationMetadata ||
          credit.creditedOn.isAfter(throughDate) ||
          account == null ||
          account.scope != credit.scope) {
        return false;
      }
    }
    return true;
  }
}

class BudgetItem {
  const BudgetItem({
    required this.categoryId,
    required this.categoryName,
    required this.budgetMinor,
    required this.spentMinor,
  });

  factory BudgetItem.fromJson(Object? value) {
    final map = jsonMap(value);
    final category = jsonMap(map['category']);
    return BudgetItem(
      categoryId: jsonInt(map['category_id'] ?? category['id']),
      categoryName:
          map['category_name']?.toString() ??
          category['name']?.toString() ??
          'Category',
      budgetMinor: Money.fromJson(
        map['budget_minor'] ?? map['amount_minor'] ?? map['amount'],
      ),
      spentMinor: Money.fromJson(map['spent_minor'] ?? map['spent']),
    );
  }

  final int categoryId;
  final String categoryName;
  final int budgetMinor;
  final int spentMinor;

  int get remainingMinor => budgetMinor - spentMinor;
}

class CutoffPeriod {
  const CutoffPeriod({
    required this.id,
    required this.label,
    required this.startsOn,
    required this.endsOn,
    required this.budgetMinor,
    required this.spentMinor,
    this.isBudgetOverridden = false,
    this.items = const [],
    FinanceScope? scope,
  }) : // Public parameter name intentionally differs from nullable storage.
       // ignore: prefer_initializing_formals
       _scope = scope;

  factory CutoffPeriod.fromJson(Object? value) {
    final map = jsonMap(value);
    final itemsValue = map['budget_items'] ?? map['items'] ?? map['categories'];
    return CutoffPeriod(
      id: jsonInt(map['id']),
      label:
          map['label']?.toString() ??
          map['label_snapshot']?.toString() ??
          'Cutoff',
      startsOn: dateFromJson(map['starts_on'] ?? map['start_date']),
      endsOn: dateFromJson(map['ends_on'] ?? map['end_date']),
      budgetMinor: Money.fromJson(
        map['budget_minor'] ?? map['total_budget_minor'] ?? map['total_budget'],
      ),
      spentMinor: Money.fromJson(
        map['spent_minor'] ?? map['expense_minor'] ?? map['expenses'],
      ),
      isBudgetOverridden: jsonBool(map['is_budget_overridden']),
      items: jsonList(itemsValue).map(BudgetItem.fromJson).toList(),
      scope: FinanceScope.fromJson(map['scope']),
    );
  }

  final int id;
  final String label;
  final DateTime startsOn;
  final DateTime endsOn;
  final int budgetMinor;
  final int spentMinor;
  final bool isBudgetOverridden;
  final List<BudgetItem> items;
  final FinanceScope? _scope;

  int get remainingMinor => budgetMinor - spentMinor;
  double? get utilization => budgetMinor == 0 ? null : spentMinor / budgetMinor;
  FinanceScope get scope => _scope ?? FinanceScope.personal;
}

class CutoffRule {
  const CutoffRule({
    required this.id,
    required this.label,
    required this.startDay,
    required this.defaultBudgetMinor,
  });

  factory CutoffRule.fromJson(Object? value) {
    final map = jsonMap(value);
    return CutoffRule(
      id: jsonInt(map['id']),
      label: map['label']?.toString() ?? 'Cutoff',
      startDay: jsonInt(map['start_day']),
      defaultBudgetMinor: Money.fromJson(
        map['default_budget_minor'] ?? map['default_budget_amount'],
      ),
    );
  }

  final int id;
  final String label;
  final int startDay;
  final int defaultBudgetMinor;
}

class CutoffSchedule {
  const CutoffSchedule({
    required this.id,
    required this.name,
    required this.effectiveFrom,
    this.effectiveTo,
    this.rules = const [],
    FinanceScope? scope,
  }) : // Public parameter name intentionally differs from nullable storage.
       // ignore: prefer_initializing_formals
       _scope = scope;

  factory CutoffSchedule.fromJson(Object? value) {
    final map = jsonMap(value);
    return CutoffSchedule(
      id: jsonInt(map['id']),
      name: map['name']?.toString() ?? 'Cutoff schedule',
      effectiveFrom: dateFromJson(map['effective_from']),
      effectiveTo: map['effective_to'] == null
          ? null
          : dateFromJson(map['effective_to']),
      rules: jsonList(map['rules']).map(CutoffRule.fromJson).toList(),
      scope: FinanceScope.fromJson(map['scope']),
    );
  }

  final int id;
  final String name;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;
  final List<CutoffRule> rules;
  final FinanceScope? _scope;

  FinanceScope get scope => _scope ?? FinanceScope.personal;
}

class CashflowBucket {
  const CashflowBucket({
    required this.label,
    required this.incomeMinor,
    required this.expenseMinor,
  });

  factory CashflowBucket.fromJson(Object? value) {
    final map = jsonMap(value);
    return CashflowBucket(
      label:
          map['label']?.toString() ??
          map['date']?.toString() ??
          map['month']?.toString() ??
          '',
      incomeMinor: Money.fromJson(map['income_minor'] ?? map['income']),
      expenseMinor: Money.fromJson(
        map['expense_minor'] ?? map['expenses_minor'] ?? map['expenses'],
      ),
    );
  }

  final String label;
  final int incomeMinor;
  final int expenseMinor;
  int get netMinor => incomeMinor - expenseMinor;
}

class CategorySpend {
  const CategorySpend({
    required this.id,
    required this.name,
    required this.amountMinor,
    this.color = '#43D98B',
    this.budgetMinor = 0,
  });

  factory CategorySpend.fromJson(Object? value) {
    final map = jsonMap(value);
    return CategorySpend(
      id: jsonInt(map['category_id'] ?? map['id']),
      name:
          map['category_name']?.toString() ??
          map['name']?.toString() ??
          'Other',
      amountMinor: Money.fromJson(
        map['amount_minor'] ?? map['spent_minor'] ?? map['amount'],
      ),
      budgetMinor: Money.fromJson(map['budget_minor'] ?? map['budget']),
      color: map['color']?.toString() ?? '#43D98B',
    );
  }

  final int id;
  final String name;
  final int amountMinor;
  final int budgetMinor;
  final String color;
}

class JewelryPortfolioSummary {
  const JewelryPortfolioSummary({
    this.heldCount = 0,
    this.costKnownCount = 0,
    this.costMissingCount = 0,
    this.totalEstimatedValueMinor = 0,
    this.knownPurchaseCostMinor = 0,
    this.unrealizedGainLossMinor = 0,
  });

  factory JewelryPortfolioSummary.fromJson(Object? value) {
    final map = jsonMap(value);
    return JewelryPortfolioSummary(
      heldCount: jsonInt(
        map['held_count'] ?? map['items_held'] ?? map['gold_items_count'],
      ),
      costKnownCount: jsonInt(
        map['cost_known_count'] ?? map['purchase_value_known_count'],
      ),
      costMissingCount: jsonInt(
        map['cost_missing_count'] ?? map['purchase_value_missing_count'],
      ),
      totalEstimatedValueMinor: Money.fromJson(
        map['total_estimated_value_minor'] ??
            map['held_gold_value_minor'] ??
            map['total_gold_value_minor'],
      ),
      knownPurchaseCostMinor: Money.fromJson(
        map['known_purchase_cost_minor'] ?? map['gold_purchase_cost_minor'],
      ),
      unrealizedGainLossMinor: Money.fromJson(
        map['unrealized_gain_loss_minor'] ?? map['gold_gain_loss_minor'],
      ),
    );
  }

  final int heldCount;
  final int costKnownCount;
  final int costMissingCount;
  final int totalEstimatedValueMinor;
  final int knownPurchaseCostMinor;
  final int unrealizedGainLossMinor;
}

class JointObligationsSummary {
  const JointObligationsSummary({
    this.outstandingAllTimeMinor = 0,
    this.outstandingAllTimeOccurrences = 0,
    this.outstandingAllTimeEntries = 0,
    this.assessedInPeriodMinor = 0,
    this.topParticipant,
    this.topDeal,
    this.penaltyFundAccount,
    Account? dealsPenaltyMoneyAccount,
    int? penaltyFundBalanceMinor,
    int? dealsPenaltyMoneyBalanceMinor,
    int? externalDepositsInPeriodMinor,
    int? externalDepositReversalsInPeriodMinor,
    int? netExternalDepositAdjustmentInPeriodMinor,
    bool? affectsAccountBalance,
    bool? affectsTotalCashBalance,
    bool? affectsIndividualAccountBalances,
    bool? affectsCashflow,
    bool? affectsBudget,
  }) : // Public parameter names intentionally differ from nullable storage.
       // ignore: prefer_initializing_formals
       _dealsPenaltyMoneyAccount = dealsPenaltyMoneyAccount,
       // ignore: prefer_initializing_formals
       _penaltyFundBalanceMinor = penaltyFundBalanceMinor,
       // ignore: prefer_initializing_formals
       _dealsPenaltyMoneyBalanceMinor = dealsPenaltyMoneyBalanceMinor,
       // ignore: prefer_initializing_formals
       _externalDepositsInPeriodMinor = externalDepositsInPeriodMinor,
       // ignore: prefer_initializing_formals
       _externalDepositReversalsInPeriodMinor =
           externalDepositReversalsInPeriodMinor,
       // ignore: prefer_initializing_formals
       _netExternalDepositAdjustmentInPeriodMinor =
           netExternalDepositAdjustmentInPeriodMinor,
       // ignore: prefer_initializing_formals
       _affectsAccountBalance = affectsAccountBalance,
       // ignore: prefer_initializing_formals
       _affectsTotalCashBalance = affectsTotalCashBalance,
       // ignore: prefer_initializing_formals
       _affectsIndividualAccountBalances = affectsIndividualAccountBalances,
       // ignore: prefer_initializing_formals
       _affectsCashflow = affectsCashflow,
       // ignore: prefer_initializing_formals
       _affectsBudget = affectsBudget;

  factory JointObligationsSummary.fromJson(Object? value) {
    final map = jsonMap(value);
    return JointObligationsSummary(
      outstandingAllTimeMinor: Money.fromJson(
        map['outstanding_all_time_minor'],
      ),
      outstandingAllTimeOccurrences: jsonInt(
        map['outstanding_all_time_occurrences'],
      ),
      outstandingAllTimeEntries: jsonInt(map['outstanding_all_time_entries']),
      assessedInPeriodMinor: Money.fromJson(map['assessed_in_period_minor']),
      topParticipant: map['top_participant'] is Map
          ? JointParticipantSummary.fromJson(map['top_participant'])
          : null,
      topDeal: map['top_deal'] is Map
          ? JointDealSummaryItem.fromJson(map['top_deal'])
          : null,
      penaltyFundAccount: map['penalty_fund_account'] is Map
          ? Account.fromJson(map['penalty_fund_account'])
          : null,
      dealsPenaltyMoneyAccount: map['deals_penalty_money_account'] is Map
          ? Account.fromJson(map['deals_penalty_money_account'])
          : null,
      penaltyFundBalanceMinor: Money.fromJson(
        map['penalty_fund_balance_minor'],
      ),
      dealsPenaltyMoneyBalanceMinor:
          map.containsKey('deals_penalty_money_balance_minor')
          ? Money.fromJson(map['deals_penalty_money_balance_minor'])
          : null,
      externalDepositsInPeriodMinor: Money.fromJson(
        map['external_deposits_in_period_minor'] ??
            map['external_deposits_minor'] ??
            map['external_penalty_deposits_in_period_minor'] ??
            map['external_penalty_deposits_minor'],
      ),
      externalDepositReversalsInPeriodMinor: Money.fromJson(
        map['external_deposit_reversals_in_period_minor'] ??
            map['external_deposit_reversals_minor'] ??
            map['external_penalty_reversals_in_period_minor'] ??
            map['external_penalty_reversals_minor'],
      ),
      netExternalDepositAdjustmentInPeriodMinor: Money.fromJson(
        map['net_external_deposit_adjustment_in_period_minor'] ??
            map['net_external_deposit_adjustment_minor'] ??
            map['external_penalty_cash_adjustment_in_period_minor'] ??
            map['external_penalty_cash_adjustment_minor'],
      ),
      affectsAccountBalance: jsonBool(map['affects_account_balance']),
      affectsTotalCashBalance: map.containsKey('affects_total_cash_balance')
          ? jsonBool(map['affects_total_cash_balance'])
          : null,
      affectsIndividualAccountBalances:
          map.containsKey('affects_individual_account_balances')
          ? jsonBool(map['affects_individual_account_balances'])
          : null,
      affectsCashflow: map.containsKey('affects_cashflow')
          ? jsonBool(map['affects_cashflow'])
          : null,
      affectsBudget: jsonBool(map['affects_budget']),
    );
  }

  final int outstandingAllTimeMinor;
  final int outstandingAllTimeOccurrences;
  final int outstandingAllTimeEntries;
  final int assessedInPeriodMinor;
  final JointParticipantSummary? topParticipant;
  final JointDealSummaryItem? topDeal;
  final Account? penaltyFundAccount;
  final Account? _dealsPenaltyMoneyAccount;
  final int? _penaltyFundBalanceMinor;
  final int? _dealsPenaltyMoneyBalanceMinor;
  final int? _externalDepositsInPeriodMinor;
  final int? _externalDepositReversalsInPeriodMinor;
  final int? _netExternalDepositAdjustmentInPeriodMinor;
  final bool? _affectsAccountBalance;
  final bool? _affectsTotalCashBalance;
  final bool? _affectsIndividualAccountBalances;
  final bool? _affectsCashflow;
  final bool? _affectsBudget;

  Account? get dealsPenaltyMoneyAccount =>
      _dealsPenaltyMoneyAccount ?? penaltyFundAccount;
  int get dealsPenaltyMoneyBalanceMinor =>
      _dealsPenaltyMoneyBalanceMinor ?? _penaltyFundBalanceMinor ?? 0;
  int get penaltyFundBalanceMinor => dealsPenaltyMoneyBalanceMinor;
  int get externalDepositsInPeriodMinor => _externalDepositsInPeriodMinor ?? 0;
  int get externalDepositReversalsInPeriodMinor =>
      _externalDepositReversalsInPeriodMinor ?? 0;
  int get netExternalDepositAdjustmentInPeriodMinor =>
      _netExternalDepositAdjustmentInPeriodMinor ?? 0;
  bool get affectsAccountBalance => _affectsAccountBalance ?? false;
  bool get affectsTotalCashBalance =>
      _affectsTotalCashBalance ?? affectsAccountBalance;
  bool get affectsIndividualAccountBalances =>
      _affectsIndividualAccountBalances ?? false;
  bool get affectsCashflow => _affectsCashflow ?? false;
  bool get affectsBudget => _affectsBudget ?? false;
}

class ReportSummary {
  const ReportSummary({
    required this.period,
    required this.label,
    required this.startsOn,
    required this.endsOn,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.netMinor,
    required this.hasBudget,
    required this.budgetMinor,
    required this.remainingBudgetMinor,
    required this.cashBalanceMinor,
    int? creditCardDebtMinor,
    int? netPositionMinor,
    int? savingsBalanceMinor,
    int? availableMoneyMinor,
    this.utilizationPercent,
    this.savingsRatePercent,
    this.buckets = const [],
    this.categories = const [],
    this.accounts = const [],
    this.recentTransactions = const [],
    FinanceScope? scope,
    // Nullable backing keeps pre-hot-reload instances safe.
    JewelryPortfolioSummary? jewelryPortfolio,
    JointObligationsSummary? jointObligations,
  }) : // Public parameter name intentionally differs from nullable storage.
       // ignore: prefer_initializing_formals
       _jewelryPortfolio = jewelryPortfolio,
       // ignore: prefer_initializing_formals
       _jointObligations = jointObligations,
       // ignore: prefer_initializing_formals
       _scope = scope,
       // ignore: prefer_initializing_formals
       _creditCardDebtMinor = creditCardDebtMinor,
       // ignore: prefer_initializing_formals
       _netPositionMinor = netPositionMinor,
       // ignore: prefer_initializing_formals
       _savingsBalanceMinor = savingsBalanceMinor,
       // ignore: prefer_initializing_formals
       _availableMoneyMinor = availableMoneyMinor;

  factory ReportSummary.empty(
    DateTime anchor,
    String period, {
    FinanceScope scope = FinanceScope.personal,
  }) => ReportSummary(
    period: period,
    label: 'No activity yet',
    startsOn: anchor,
    endsOn: anchor,
    incomeMinor: 0,
    expenseMinor: 0,
    netMinor: 0,
    hasBudget: false,
    budgetMinor: 0,
    remainingBudgetMinor: 0,
    cashBalanceMinor: 0,
    creditCardDebtMinor: 0,
    netPositionMinor: 0,
    savingsBalanceMinor: 0,
    availableMoneyMinor: 0,
    scope: scope,
  );

  factory ReportSummary.fromJson(
    Object? value, {
    required String fallbackPeriod,
  }) {
    final map = jsonMap(dataOf(value));
    final range = jsonMap(map['range']);
    final totals = jsonMap(map['totals']);
    final budget = jsonMap(map['budget']);
    final nestedJewelryPortfolio = jsonMap(map['jewelry_portfolio']);
    final jewelryPortfolio = nestedJewelryPortfolio.isNotEmpty
        ? nestedJewelryPortfolio
        : <String, Object?>{
            'held_count':
                totals['held_gold_count'] ??
                map['held_gold_count'] ??
                map['gold_items_count'],
            'cost_known_count':
                totals['gold_cost_known_count'] ?? map['gold_cost_known_count'],
            'cost_missing_count':
                totals['gold_cost_missing_count'] ??
                map['gold_cost_missing_count'],
            'total_estimated_value_minor':
                totals['held_gold_value_minor'] ??
                map['held_gold_value_minor'] ??
                map['total_gold_value_minor'],
            'known_purchase_cost_minor':
                totals['gold_purchase_cost_minor'] ??
                map['gold_purchase_cost_minor'],
            'unrealized_gain_loss_minor':
                totals['gold_gain_loss_minor'] ?? map['gold_gain_loss_minor'],
          };
    final start =
        map['starts_on'] ??
        map['start_date'] ??
        range['from'] ??
        range['start'];
    final end =
        map['ends_on'] ?? map['end_date'] ?? range['to'] ?? range['end'];
    final income =
        totals['income_minor'] ?? map['income_minor'] ?? map['income'];
    final expenses =
        totals['expense_minor'] ??
        totals['expenses_minor'] ??
        map['expense_minor'] ??
        map['expenses_minor'] ??
        map['expenses'];
    final net =
        totals['net_minor'] ??
        map['net_minor'] ??
        map['net_cash_flow_minor'] ??
        map['net_cash_flow'];
    final budgetAmount =
        budget['amount_minor'] ??
        budget['total_minor'] ??
        map['budget_minor'] ??
        map['total_budget_minor'] ??
        map['budget_amount'];
    final remaining =
        budget['remaining_minor'] ??
        map['remaining_budget_minor'] ??
        map['budget_remaining_minor'];

    return ReportSummary(
      period: map['period']?.toString() ?? fallbackPeriod,
      label:
          map['label']?.toString() ?? range['label']?.toString() ?? 'Summary',
      startsOn: dateFromJson(start),
      endsOn: dateFromJson(end),
      incomeMinor: Money.fromJson(income),
      expenseMinor: Money.fromJson(expenses),
      netMinor: Money.fromJson(net),
      hasBudget: budgetAmount != null,
      budgetMinor: Money.fromJson(budgetAmount),
      remainingBudgetMinor: Money.fromJson(remaining),
      cashBalanceMinor: Money.fromJson(
        totals['cash_balance_minor'] ??
            map['cash_balance_minor'] ??
            map['total_balance_minor'],
      ),
      creditCardDebtMinor:
          totals.containsKey('credit_card_debt_minor') ||
              map.containsKey('credit_card_debt_minor')
          ? Money.fromJson(
              totals['credit_card_debt_minor'] ?? map['credit_card_debt_minor'],
            )
          : null,
      netPositionMinor:
          totals.containsKey('net_position_minor') ||
              map.containsKey('net_position_minor')
          ? Money.fromJson(
              totals['net_position_minor'] ?? map['net_position_minor'],
            )
          : null,
      savingsBalanceMinor:
          totals.containsKey('savings_balance_minor') ||
              map.containsKey('savings_balance_minor')
          ? Money.fromJson(
              totals['savings_balance_minor'] ?? map['savings_balance_minor'],
            )
          : null,
      availableMoneyMinor:
          totals.containsKey('available_money_minor') ||
              map.containsKey('available_money_minor')
          ? Money.fromJson(
              totals['available_money_minor'] ?? map['available_money_minor'],
            )
          : null,
      utilizationPercent: _nullableDouble(
        budget['utilization_percent'] ??
            map['utilization_percent'] ??
            map['utilization_pct'],
      ),
      savingsRatePercent: _nullableDouble(
        totals['savings_rate_percent'] ??
            map['savings_rate_percent'] ??
            map['savings_rate'],
      ),
      buckets: jsonList(
        map['cash_flow_series'] ??
            map['cashflow_series'] ??
            map['series'] ??
            map['buckets'],
      ).map(CashflowBucket.fromJson).toList(),
      categories: jsonList(
        map['expenses_by_category'] ??
            map['expense_by_category'] ??
            map['categories'] ??
            map['category_breakdown'],
      ).map(CategorySpend.fromJson).toList(),
      accounts: jsonList(map['accounts'] ?? map['account_balances'])
          .map(Account.fromJson)
          .toList(),
      recentTransactions: jsonList(map['recent_transactions'])
          .map(TransactionRecord.fromJson)
          .toList(),
      scope: FinanceScope.fromJson(map['scope']),
      jewelryPortfolio: JewelryPortfolioSummary.fromJson(jewelryPortfolio),
      jointObligations: map['joint_obligations'] is Map
          ? JointObligationsSummary.fromJson(map['joint_obligations'])
          : null,
    );
  }

  final String period;
  final String label;
  final DateTime startsOn;
  final DateTime endsOn;
  final int incomeMinor;
  final int expenseMinor;
  final int netMinor;
  final bool hasBudget;
  final int budgetMinor;
  final int remainingBudgetMinor;
  final int cashBalanceMinor;
  final int? _creditCardDebtMinor;
  final int? _netPositionMinor;
  final int? _savingsBalanceMinor;
  final int? _availableMoneyMinor;
  final double? utilizationPercent;
  final double? savingsRatePercent;
  final List<CashflowBucket> buckets;
  final List<CategorySpend> categories;
  final List<Account> accounts;
  final List<TransactionRecord> recentTransactions;
  final JewelryPortfolioSummary? _jewelryPortfolio;
  final JointObligationsSummary? _jointObligations;
  final FinanceScope? _scope;

  JewelryPortfolioSummary get jewelryPortfolio =>
      _jewelryPortfolio ?? const JewelryPortfolioSummary();
  JointObligationsSummary get jointObligations =>
      _jointObligations ?? const JointObligationsSummary();
  bool get hasJointObligations => _jointObligations != null;
  FinanceScope get scope => _scope ?? FinanceScope.personal;
  int get creditCardDebtMinor =>
      _creditCardDebtMinor ??
      accounts
          .where((account) => account.isCreditCard)
          .fold<int>(0, (sum, account) => sum + account.debtMinor);
  int get netPositionMinor =>
      _netPositionMinor ?? cashBalanceMinor - creditCardDebtMinor;
  int get savingsBalanceMinor =>
      _savingsBalanceMinor ??
      accounts
          .where(
            (account) => account.scope == scope && account.isSavingsAccount,
          )
          .fold<int>(0, (sum, account) => sum + account.balanceMinor);
  int get availableMoneyMinor =>
      _availableMoneyMinor ??
      (accounts.isEmpty
          ? cashBalanceMinor
          : accounts
                .where(
                  (account) =>
                      account.scope == scope &&
                      account.countsTowardAvailableMoney,
                )
                .fold<int>(0, (sum, account) => sum + account.balanceMinor));
  bool get hasSavingsBalanceMetadata => _savingsBalanceMinor != null;
  bool get hasAvailableMoneyMetadata => _availableMoneyMinor != null;
  bool get hasConsistentAccountMoneyMetadata {
    if (accounts.any(
      (account) => !account.hasConsistentClassificationMetadata,
    )) {
      return false;
    }
    final derivedSavings = accounts
        .where((account) => account.scope == scope && account.isSavingsAccount)
        .fold<int>(0, (sum, account) => sum + account.balanceMinor);
    final derivedAvailable = accounts
        .where(
          (account) =>
              account.scope == scope && account.countsTowardAvailableMoney,
        )
        .fold<int>(0, (sum, account) => sum + account.balanceMinor);
    return (_savingsBalanceMinor == null ||
            _savingsBalanceMinor == derivedSavings) &&
        (_availableMoneyMinor == null ||
            _availableMoneyMinor == derivedAvailable);
  }
}

class JointParticipant {
  const JointParticipant({
    required this.id,
    required this.name,
    bool? isArchived,
    this.createdAt,
    this.updatedAt,
  }) : // Public parameter name intentionally differs from nullable storage.
       // ignore: prefer_initializing_formals
       _isArchived = isArchived;

  factory JointParticipant.fromJson(Object? value) {
    final map = jsonMap(value);
    return JointParticipant(
      id: jsonInt(map['id']),
      name: map['name']?.toString().trim().isNotEmpty == true
          ? map['name'].toString().trim()
          : 'Participant',
      isArchived: map.containsKey('is_archived')
          ? jsonBool(map['is_archived'])
          : map.containsKey('is_active')
          ? !jsonBool(map['is_active'])
          : false,
      createdAt: _nullableTimestamp(map['created_at']),
      updatedAt: _nullableTimestamp(map['updated_at']),
    );
  }

  final int id;
  final String name;
  final bool? _isArchived;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isArchived => _isArchived ?? false;
  bool get isActive => !isArchived;

  JointParticipant copyWith({String? name, bool? isArchived}) =>
      JointParticipant(
        id: id,
        name: name ?? this.name,
        isArchived: isArchived ?? this.isArchived,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

class JointDeal {
  const JointDeal({
    required this.id,
    required this.title,
    required this.amountPerOccurrenceMinor,
    this.description,
    bool? isArchived,
    this.createdAt,
    this.updatedAt,
  }) : // Public parameter name intentionally differs from nullable storage.
       // ignore: prefer_initializing_formals
       _isArchived = isArchived;

  factory JointDeal.fromJson(Object? value) {
    final map = jsonMap(value);
    return JointDeal(
      id: jsonInt(map['id']),
      title: map['title']?.toString().trim().isNotEmpty == true
          ? map['title'].toString().trim()
          : 'Joint deal',
      description: _nullableTrimmed(map['description']),
      amountPerOccurrenceMinor: Money.fromJson(
        map['amount_per_occurrence_minor'] ?? map['unit_amount_minor'],
      ),
      isArchived: map.containsKey('is_archived')
          ? jsonBool(map['is_archived'])
          : map.containsKey('is_active')
          ? !jsonBool(map['is_active'])
          : false,
      createdAt: _nullableTimestamp(map['created_at']),
      updatedAt: _nullableTimestamp(map['updated_at']),
    );
  }

  final int id;
  final String title;
  final String? description;
  final int amountPerOccurrenceMinor;
  final bool? _isArchived;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isArchived => _isArchived ?? false;
  bool get isActive => !isArchived;

  JointDeal copyWith({
    String? title,
    String? description,
    int? amountPerOccurrenceMinor,
    bool? isArchived,
  }) => JointDeal(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    amountPerOccurrenceMinor:
        amountPerOccurrenceMinor ?? this.amountPerOccurrenceMinor,
    isArchived: isArchived ?? this.isArchived,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

class JointPenaltyPayment {
  const JointPenaltyPayment({
    required this.id,
    required this.mode,
    required this.amountMinor,
    required this.status,
    this.clientUuid,
    this.paidOn,
    this.sourceAccountId,
    this.destinationAccountId,
    this.sourceAccount,
    this.destinationAccount,
    this.participantNameSnapshot,
    this.sourceAccountNameSnapshot,
    this.destinationAccountNameSnapshot,
    bool? isPaidOnly,
    bool? isExternalDeposit,
    bool? financiallyRecorded,
    bool? affectsTotalCashBalance,
    bool? affectsIndividualAccountBalances,
    bool? affectsCashflow,
    bool? affectsBudget,
    bool? sourceAccountIsArchived,
    this.reversedAt,
    this.reversalReason,
    this.createdAt,
    this.updatedAt,
  }) : // Public parameter names intentionally differ from nullable storage.
       // ignore: prefer_initializing_formals
       _isPaidOnly = isPaidOnly,
       // ignore: prefer_initializing_formals
       _isExternalDeposit = isExternalDeposit,
       // ignore: prefer_initializing_formals
       _financiallyRecorded = financiallyRecorded,
       // ignore: prefer_initializing_formals
       _affectsTotalCashBalance = affectsTotalCashBalance,
       // ignore: prefer_initializing_formals
       _affectsIndividualAccountBalances = affectsIndividualAccountBalances,
       // ignore: prefer_initializing_formals
       _affectsCashflow = affectsCashflow,
       // ignore: prefer_initializing_formals
       _affectsBudget = affectsBudget,
       // ignore: prefer_initializing_formals
       _sourceAccountIsArchived = sourceAccountIsArchived;

  factory JointPenaltyPayment.fromJson(Object? value) {
    final map = jsonMap(value);
    return JointPenaltyPayment(
      id: jsonInt(map['id']),
      clientUuid: _nullableTrimmed(map['client_uuid']),
      mode: switch (map['mode']?.toString()) {
        'external_deposit' => 'external_deposit',
        'account_transfer' => 'account_transfer',
        _ => 'tracking',
      },
      amountMinor: Money.fromJson(map['amount_minor']),
      paidOn: _nullableDate(map['paid_on']),
      status: map['status']?.toString() == 'reversed' ? 'reversed' : 'posted',
      isPaidOnly: map.containsKey('is_paid_only')
          ? jsonBool(map['is_paid_only'])
          : null,
      isExternalDeposit: map.containsKey('is_external_deposit')
          ? jsonBool(map['is_external_deposit'])
          : null,
      financiallyRecorded: map.containsKey('financially_recorded')
          ? jsonBool(map['financially_recorded'])
          : null,
      sourceAccountId: map['source_account_id'] == null
          ? null
          : jsonInt(map['source_account_id']),
      destinationAccountId: map['destination_account_id'] == null
          ? null
          : jsonInt(map['destination_account_id']),
      sourceAccount: map['source_account'] is Map
          ? Account.fromJson(map['source_account'])
          : null,
      destinationAccount: map['destination_account'] is Map
          ? Account.fromJson(map['destination_account'])
          : null,
      participantNameSnapshot: _nullableTrimmed(
        map['participant_name_snapshot'] ?? map['participant_name'],
      ),
      sourceAccountNameSnapshot: _nullableTrimmed(
        map['source_account_name_snapshot'] ?? map['source_account_name'],
      ),
      destinationAccountNameSnapshot: _nullableTrimmed(
        map['destination_account_name_snapshot'] ??
            map['destination_account_name'] ??
            map['fund_account_name'] ??
            map['penalty_fund_name'],
      ),
      affectsTotalCashBalance: jsonBool(
        map['affects_total_cash_balance'] ??
            map['affects_joint_total'] ??
            map['affects_account_balance'],
      ),
      affectsIndividualAccountBalances:
          map.containsKey('affects_individual_account_balances')
          ? jsonBool(map['affects_individual_account_balances'])
          : null,
      affectsCashflow: map.containsKey('affects_cashflow')
          ? jsonBool(map['affects_cashflow'])
          : null,
      affectsBudget: map.containsKey('affects_budget')
          ? jsonBool(map['affects_budget'])
          : null,
      sourceAccountIsArchived: map.containsKey('source_account_is_archived')
          ? jsonBool(map['source_account_is_archived'])
          : null,
      reversedAt: _nullableTimestamp(map['reversed_at']),
      reversalReason: _nullableTrimmed(map['reversal_reason']),
      createdAt: _nullableTimestamp(map['created_at']),
      updatedAt: _nullableTimestamp(map['updated_at']),
    );
  }

  final int id;
  final String? clientUuid;
  final String mode;
  final int amountMinor;
  final DateTime? paidOn;
  final String status;
  final bool? _isPaidOnly;
  final bool? _isExternalDeposit;
  final bool? _financiallyRecorded;
  final int? sourceAccountId;
  final int? destinationAccountId;
  final Account? sourceAccount;
  final Account? destinationAccount;
  final String? participantNameSnapshot;
  final String? sourceAccountNameSnapshot;
  final String? destinationAccountNameSnapshot;
  final bool? _affectsTotalCashBalance;
  final bool? _affectsIndividualAccountBalances;
  final bool? _affectsCashflow;
  final bool? _affectsBudget;
  final bool? _sourceAccountIsArchived;
  final DateTime? reversedAt;
  final String? reversalReason;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isPosted => status == 'posted';
  bool get isReversed => status == 'reversed';
  bool get isAccountTransfer => mode == 'account_transfer';
  bool get isExternalDeposit =>
      _isExternalDeposit ?? mode == 'external_deposit';
  // `is_paid_only` is a compatibility flag for the historical tracking mode.
  // Direct deposits are financially recorded and must never inherit it.
  bool get isPaidOnly => _isPaidOnly ?? mode == 'tracking';
  bool get financiallyRecorded =>
      _financiallyRecorded ??
      ((isAccountTransfer || isExternalDeposit) && isPosted);
  bool get affectsTotalCashBalance => _affectsTotalCashBalance ?? false;
  bool get affectsIndividualAccountBalances =>
      _affectsIndividualAccountBalances ??
      ((isAccountTransfer || isExternalDeposit) && isPosted);
  bool get affectsCashflow => _affectsCashflow ?? false;
  bool get affectsBudget => _affectsBudget ?? false;
  bool get sourceAccountIsArchived =>
      _sourceAccountIsArchived ?? sourceAccount?.isArchived ?? false;
  String get sourceName =>
      sourceAccountNameSnapshot ??
      sourceAccount?.displayName ??
      'Joint account';
  String get destinationName {
    final current = destinationAccount;
    if (current?.isDealsPenaltyMoney == true) return current!.displayName;
    final snapshot = destinationAccountNameSnapshot;
    return snapshot == null
        ? current?.displayName ?? 'Deals Penalty Money'
        : _dealsPenaltyMoneyDisplayName(snapshot);
  }
}

class JointPenalty {
  const JointPenalty({
    required this.id,
    this.clientUuid,
    required this.dealId,
    this.dealTitleSnapshot,
    required this.participantId,
    required this.participantName,
    required this.occurredOn,
    required this.quantity,
    required this.amountPerOccurrenceMinor,
    required this.totalAmountMinor,
    String? status,
    this.notes,
    this.settledOn,
    this.lastSettledOn,
    this.voidedAt,
    this.voidReason,
    this.reopenedAt,
    this.reopenReason,
    String? paymentStatus,
    String? settlementMode,
    bool? isPaidOnly,
    bool? isExternalDeposit,
    bool? financiallyRecorded,
    this.currentPayment,
    this.penaltyFundAccount,
    Account? dealsPenaltyMoneyAccount,
    bool? affectsAccountBalance,
    bool? affectsTotalCashBalance,
    bool? affectsIndividualAccountBalances,
    bool? affectsCashflow,
    bool? affectsBudget,
    bool? participantWasCreated,
    int? version,
    bool? isArchived,
    this.deal,
    this.participant,
    this.createdAt,
    this.updatedAt,
  }) : // Public parameter names intentionally differ from nullable storage.
       // ignore: prefer_initializing_formals
       _status = status,
       // ignore: prefer_initializing_formals
       _paymentStatus = paymentStatus,
       // ignore: prefer_initializing_formals
       _settlementMode = settlementMode,
       // ignore: prefer_initializing_formals
       _isPaidOnly = isPaidOnly,
       // ignore: prefer_initializing_formals
       _isExternalDeposit = isExternalDeposit,
       // ignore: prefer_initializing_formals
       _financiallyRecorded = financiallyRecorded,
       // ignore: prefer_initializing_formals
       _dealsPenaltyMoneyAccount = dealsPenaltyMoneyAccount,
       // ignore: prefer_initializing_formals
       _affectsAccountBalance = affectsAccountBalance,
       // ignore: prefer_initializing_formals
       _affectsTotalCashBalance = affectsTotalCashBalance,
       // ignore: prefer_initializing_formals
       _affectsIndividualAccountBalances = affectsIndividualAccountBalances,
       // ignore: prefer_initializing_formals
       _affectsCashflow = affectsCashflow,
       // ignore: prefer_initializing_formals
       _affectsBudget = affectsBudget,
       // ignore: prefer_initializing_formals
       _participantWasCreated = participantWasCreated,
       // ignore: prefer_initializing_formals
       _version = version,
       // ignore: prefer_initializing_formals
       _isArchived = isArchived;

  factory JointPenalty.fromJson(Object? value) {
    final map = jsonMap(value);
    final participantMap = jsonMap(map['participant']);
    final participantIdValue = map['participant_id'] ?? participantMap['id'];
    final participantName =
        _nullableTrimmed(map['participant_name']) ??
        _nullableTrimmed(participantMap['name']) ??
        'Participant';
    final settledOn = map['settled_on'];
    return JointPenalty(
      id: jsonInt(map['id']),
      clientUuid: _nullableTrimmed(map['client_uuid']),
      dealId: jsonInt(map['deal_id'] ?? jsonMap(map['deal'])['id']),
      dealTitleSnapshot: _nullableTrimmed(map['deal_title']),
      participantId: jsonInt(participantIdValue),
      participantName: participantName,
      occurredOn: dateFromJson(map['occurred_on']),
      quantity: jsonInt(map['quantity'], 1),
      amountPerOccurrenceMinor: Money.fromJson(
        map['amount_per_occurrence_minor'] ?? map['unit_amount_minor'],
      ),
      totalAmountMinor: Money.fromJson(map['total_amount_minor']),
      notes: _nullableTrimmed(map['notes'] ?? map['note']),
      status: switch (map['status']?.toString().toLowerCase()) {
        'settled' => 'settled',
        'void' => 'void',
        _ => 'outstanding',
      },
      paymentStatus: switch (map['payment_status']?.toString().toLowerCase()) {
        'paid' => 'paid',
        'void' => 'void',
        'unpaid' => 'unpaid',
        _ => null,
      },
      settlementMode: switch (map['settlement_mode']?.toString()) {
        'external_deposit' => 'external_deposit',
        'tracking' => 'tracking',
        'account_transfer' => 'account_transfer',
        _ => null,
      },
      isPaidOnly: map.containsKey('is_paid_only')
          ? jsonBool(map['is_paid_only'])
          : null,
      isExternalDeposit: map.containsKey('is_external_deposit')
          ? jsonBool(map['is_external_deposit'])
          : null,
      financiallyRecorded: map.containsKey('financially_recorded')
          ? jsonBool(map['financially_recorded'])
          : null,
      currentPayment: map['current_payment'] is Map
          ? JointPenaltyPayment.fromJson(map['current_payment'])
          : null,
      penaltyFundAccount: map['penalty_fund_account'] is Map
          ? Account.fromJson(map['penalty_fund_account'])
          : null,
      dealsPenaltyMoneyAccount: map['deals_penalty_money_account'] is Map
          ? Account.fromJson(map['deals_penalty_money_account'])
          : null,
      settledOn: settledOn == null ? null : dateFromJson(settledOn),
      lastSettledOn: _nullableDate(map['last_settled_on']),
      voidedAt: _nullableTimestamp(map['voided_at']),
      voidReason: _nullableTrimmed(map['void_reason']),
      reopenedAt: _nullableTimestamp(map['reopened_at']),
      reopenReason: _nullableTrimmed(map['reopen_reason']),
      affectsAccountBalance: jsonBool(map['affects_account_balance']),
      affectsTotalCashBalance: map.containsKey('affects_total_cash_balance')
          ? jsonBool(map['affects_total_cash_balance'])
          : null,
      affectsIndividualAccountBalances:
          map.containsKey('affects_individual_account_balances')
          ? jsonBool(map['affects_individual_account_balances'])
          : null,
      affectsCashflow: map.containsKey('affects_cashflow')
          ? jsonBool(map['affects_cashflow'])
          : null,
      affectsBudget: jsonBool(map['affects_budget']),
      participantWasCreated: map['participant_was_created'] == null
          ? null
          : jsonBool(map['participant_was_created']),
      version: jsonInt(map['version'], 1),
      isArchived: jsonBool(map['is_archived']),
      deal: map['deal'] is Map ? JointDeal.fromJson(map['deal']) : null,
      participant: map['participant'] is Map
          ? JointParticipant.fromJson(map['participant'])
          : null,
      createdAt: _nullableTimestamp(map['created_at']),
      updatedAt: _nullableTimestamp(map['updated_at']),
    );
  }

  final int id;
  final String? clientUuid;
  final int dealId;
  final String? dealTitleSnapshot;
  final int participantId;
  final String participantName;
  final DateTime occurredOn;
  final int quantity;
  final int amountPerOccurrenceMinor;
  final int totalAmountMinor;
  final String? notes;
  final String? _status;
  final String? _paymentStatus;
  final String? _settlementMode;
  final bool? _isPaidOnly;
  final bool? _isExternalDeposit;
  final bool? _financiallyRecorded;
  final DateTime? settledOn;
  final DateTime? lastSettledOn;
  final DateTime? voidedAt;
  final String? voidReason;
  final DateTime? reopenedAt;
  final String? reopenReason;
  final JointPenaltyPayment? currentPayment;
  final Account? penaltyFundAccount;
  final Account? _dealsPenaltyMoneyAccount;
  final bool? _affectsAccountBalance;
  final bool? _affectsTotalCashBalance;
  final bool? _affectsIndividualAccountBalances;
  final bool? _affectsCashflow;
  final bool? _affectsBudget;
  final bool? _participantWasCreated;
  final int? _version;
  final bool? _isArchived;
  final JointDeal? deal;
  final JointParticipant? participant;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get status => _status ?? 'outstanding';
  String get paymentStatus =>
      _paymentStatus ??
      (isVoided
          ? 'void'
          : isSettled
          ? 'paid'
          : 'unpaid');
  String? get settlementMode => _settlementMode ?? currentPayment?.mode;
  bool get isPaid => paymentStatus == 'paid';
  bool get isUnpaid => paymentStatus == 'unpaid';
  bool get isExternalDeposit =>
      _isExternalDeposit ??
      currentPayment?.isExternalDeposit ??
      settlementMode == 'external_deposit';
  bool get isPaidOnly =>
      _isPaidOnly ??
      currentPayment?.isPaidOnly ??
      (isPaid && settlementMode == 'tracking');
  bool get financiallyRecorded =>
      _financiallyRecorded ?? currentPayment?.financiallyRecorded ?? false;
  Account? get dealsPenaltyMoneyAccount =>
      _dealsPenaltyMoneyAccount ?? penaltyFundAccount;
  bool get isSettled => status == 'settled';
  bool get isOutstanding => status == 'outstanding';
  bool get isVoided => status == 'void';
  bool get affectsAccountBalance => _affectsAccountBalance ?? false;
  bool get affectsTotalCashBalance =>
      _affectsTotalCashBalance ?? affectsAccountBalance;
  bool get affectsIndividualAccountBalances =>
      _affectsIndividualAccountBalances ?? false;
  bool get affectsCashflow => _affectsCashflow ?? false;
  bool get affectsBudget => _affectsBudget ?? false;
  bool get participantWasCreated => _participantWasCreated ?? false;
  int get version => _version ?? 1;
  bool get isArchived => _isArchived ?? false;
  String get dealTitle => dealTitleSnapshot ?? deal?.title ?? 'Deal #$dealId';
}

class JointParticipantSummary {
  const JointParticipantSummary({
    required this.participantId,
    required this.name,
    this.outstandingMinor = 0,
    this.settledMinor = 0,
    this.outstandingOccurrences = 0,
    this.settledOccurrences = 0,
    this.outstandingEntries = 0,
    this.settledEntries = 0,
    int? trackingPaidMinor,
    int? legacyTrackingPaidMinor,
    int? externalDepositPaidMinor,
    int? externalDepositPaidOccurrences,
    int? externalDepositPaidEntries,
    int? paidOnlyOccurrences,
    int? paidOnlyEntries,
    int? legacyTrackingPaidOccurrences,
    int? legacyTrackingPaidEntries,
    int? financiallyRecordedPaidMinor,
  }) : // Public parameter names intentionally differ from nullable storage.
       // ignore: prefer_initializing_formals
       _trackingPaidMinor = trackingPaidMinor,
       // ignore: prefer_initializing_formals
       _legacyTrackingPaidMinor = legacyTrackingPaidMinor,
       // ignore: prefer_initializing_formals
       _externalDepositPaidMinor = externalDepositPaidMinor,
       // ignore: prefer_initializing_formals
       _externalDepositPaidOccurrences = externalDepositPaidOccurrences,
       // ignore: prefer_initializing_formals
       _externalDepositPaidEntries = externalDepositPaidEntries,
       // ignore: prefer_initializing_formals
       _paidOnlyOccurrences = paidOnlyOccurrences,
       // ignore: prefer_initializing_formals
       _paidOnlyEntries = paidOnlyEntries,
       // ignore: prefer_initializing_formals
       _legacyTrackingPaidOccurrences = legacyTrackingPaidOccurrences,
       // ignore: prefer_initializing_formals
       _legacyTrackingPaidEntries = legacyTrackingPaidEntries,
       // ignore: prefer_initializing_formals
       _financiallyRecordedPaidMinor = financiallyRecordedPaidMinor;

  factory JointParticipantSummary.fromJson(Object? value) {
    final map = jsonMap(value);
    return JointParticipantSummary(
      participantId: jsonInt(map['participant_id'] ?? map['id']),
      name:
          _nullableTrimmed(map['name'] ?? map['participant_name']) ??
          'Participant',
      outstandingMinor: Money.fromJson(
        map['unpaid_minor'] ?? map['outstanding_minor'] ?? map['owed_minor'],
      ),
      settledMinor: Money.fromJson(map['paid_minor'] ?? map['settled_minor']),
      outstandingOccurrences: jsonInt(
        map['unpaid_occurrences'] ?? map['outstanding_occurrences'],
      ),
      settledOccurrences: jsonInt(
        map['paid_occurrences'] ?? map['settled_occurrences'],
      ),
      outstandingEntries: jsonInt(map['outstanding_entries']),
      settledEntries: jsonInt(map['settled_entries']),
      trackingPaidMinor: Money.fromJson(
        map['paid_only_minor'] ?? map['tracking_paid_minor'],
      ),
      legacyTrackingPaidMinor: Money.fromJson(
        map['legacy_tracking_paid_minor'],
      ),
      externalDepositPaidMinor: Money.fromJson(
        map['external_deposit_paid_minor'] ?? map['direct_deposit_paid_minor'],
      ),
      externalDepositPaidOccurrences: jsonInt(
        map['external_deposit_paid_occurrences'] ??
            map['direct_deposit_paid_occurrences'],
      ),
      externalDepositPaidEntries: jsonInt(
        map['external_deposit_paid_entries'] ??
            map['direct_deposit_paid_entries'],
      ),
      paidOnlyOccurrences: jsonInt(
        map['paid_only_occurrences'] ?? map['tracking_paid_occurrences'],
      ),
      paidOnlyEntries: jsonInt(
        map['paid_only_entries'] ?? map['tracking_paid_entries'],
      ),
      legacyTrackingPaidOccurrences: jsonInt(
        map['legacy_tracking_paid_occurrences'],
      ),
      legacyTrackingPaidEntries: jsonInt(map['legacy_tracking_paid_entries']),
      financiallyRecordedPaidMinor: Money.fromJson(
        map['financially_recorded_paid_minor'] ?? map['transferred_paid_minor'],
      ),
    );
  }

  final int participantId;
  final String name;
  final int outstandingMinor;
  final int settledMinor;
  final int outstandingOccurrences;
  final int settledOccurrences;
  final int outstandingEntries;
  final int settledEntries;
  final int? _trackingPaidMinor;
  final int? _legacyTrackingPaidMinor;
  final int? _externalDepositPaidMinor;
  final int? _externalDepositPaidOccurrences;
  final int? _externalDepositPaidEntries;
  final int? _paidOnlyOccurrences;
  final int? _paidOnlyEntries;
  final int? _legacyTrackingPaidOccurrences;
  final int? _legacyTrackingPaidEntries;
  final int? _financiallyRecordedPaidMinor;

  int get trackingPaidMinor => _trackingPaidMinor ?? 0;
  int get externalDepositPaidMinor => _externalDepositPaidMinor ?? 0;
  int get externalDepositPaidOccurrences =>
      _externalDepositPaidOccurrences ?? 0;
  int get externalDepositPaidEntries => _externalDepositPaidEntries ?? 0;
  int get paidOnlyMinor => trackingPaidMinor;
  int get legacyTrackingPaidMinor => _legacyTrackingPaidMinor ?? 0;
  int get paidOnlyOccurrences => _paidOnlyOccurrences ?? 0;
  int get paidOnlyEntries => _paidOnlyEntries ?? 0;
  int get legacyTrackingPaidOccurrences => _legacyTrackingPaidOccurrences ?? 0;
  int get legacyTrackingPaidEntries => _legacyTrackingPaidEntries ?? 0;
  int get financiallyRecordedPaidMinor => _financiallyRecordedPaidMinor ?? 0;
  int get assessedMinor => outstandingMinor + settledMinor;
  int get unpaidMinor => outstandingMinor;
  int get paidMinor => settledMinor;
  int get unpaidOccurrences => outstandingOccurrences;
  int get paidOccurrences => settledOccurrences;
  int get occurrences => outstandingOccurrences + settledOccurrences;
}

class JointDealSummaryItem {
  const JointDealSummaryItem({
    required this.dealId,
    required this.title,
    this.outstandingMinor = 0,
    this.settledMinor = 0,
    this.outstandingOccurrences = 0,
    this.settledOccurrences = 0,
    this.outstandingEntries = 0,
    this.settledEntries = 0,
  });

  factory JointDealSummaryItem.fromJson(Object? value) {
    final map = jsonMap(value);
    return JointDealSummaryItem(
      dealId: jsonInt(map['deal_id'] ?? map['id']),
      title: _nullableTrimmed(map['title']) ?? 'Joint deal',
      outstandingMinor: Money.fromJson(
        map['unpaid_minor'] ?? map['outstanding_minor'] ?? map['owed_minor'],
      ),
      settledMinor: Money.fromJson(map['paid_minor'] ?? map['settled_minor']),
      outstandingOccurrences: jsonInt(
        map['unpaid_occurrences'] ?? map['outstanding_occurrences'],
      ),
      settledOccurrences: jsonInt(
        map['paid_occurrences'] ?? map['settled_occurrences'],
      ),
      outstandingEntries: jsonInt(map['outstanding_entries']),
      settledEntries: jsonInt(map['settled_entries']),
    );
  }

  final int dealId;
  final String title;
  final int outstandingMinor;
  final int settledMinor;
  final int outstandingOccurrences;
  final int settledOccurrences;
  final int outstandingEntries;
  final int settledEntries;

  int get assessedMinor => outstandingMinor + settledMinor;
  int get unpaidMinor => outstandingMinor;
  int get paidMinor => settledMinor;
  int get unpaidOccurrences => outstandingOccurrences;
  int get paidOccurrences => settledOccurrences;
  int get occurrences => outstandingOccurrences + settledOccurrences;
}

class JointDealsSummary {
  const JointDealsSummary({
    this.from,
    this.to,
    this.activeDeals = 0,
    this.outstandingMinor = 0,
    this.settledMinor = 0,
    this.outstandingOccurrences = 0,
    this.settledOccurrences = 0,
    this.outstandingEntries = 0,
    this.settledEntries = 0,
    int? trackingPaidMinor,
    int? legacyTrackingPaidMinor,
    int? externalDepositPaidMinor,
    int? externalDepositPaidOccurrences,
    int? externalDepositPaidEntries,
    int? paidOnlyOccurrences,
    int? paidOnlyEntries,
    int? legacyTrackingPaidOccurrences,
    int? legacyTrackingPaidEntries,
    int? financiallyRecordedPaidMinor,
    int? transferredPaidMinor,
    int? transferredPaidOccurrences,
    int? transferredPaidEntries,
    int? balanceRecordedPaidMinor,
    int? balanceRecordedPaidOccurrences,
    int? balanceRecordedPaidEntries,
    Account? dealsPenaltyMoneyAccount,
    Account? penaltyFundAccount,
    int? dealsPenaltyMoneyBalanceMinor,
    int? penaltyFundBalanceMinor,
    bool? hasDealsPenaltyMoneyData,
    this.participants = const [],
    this.deals = const [],
    FinanceScope? scope,
    bool? affectsAccountBalance,
    bool? affectsTotalCashBalance,
    bool? affectsIndividualAccountBalances,
    bool? affectsCashflow,
    bool? affectsBudget,
  }) : // Public parameter names intentionally differ from nullable storage.
       // ignore: prefer_initializing_formals
       _trackingPaidMinor = trackingPaidMinor,
       // ignore: prefer_initializing_formals
       _legacyTrackingPaidMinor = legacyTrackingPaidMinor,
       // ignore: prefer_initializing_formals
       _externalDepositPaidMinor = externalDepositPaidMinor,
       // ignore: prefer_initializing_formals
       _externalDepositPaidOccurrences = externalDepositPaidOccurrences,
       // ignore: prefer_initializing_formals
       _externalDepositPaidEntries = externalDepositPaidEntries,
       // ignore: prefer_initializing_formals
       _paidOnlyOccurrences = paidOnlyOccurrences,
       // ignore: prefer_initializing_formals
       _paidOnlyEntries = paidOnlyEntries,
       // ignore: prefer_initializing_formals
       _legacyTrackingPaidOccurrences = legacyTrackingPaidOccurrences,
       // ignore: prefer_initializing_formals
       _legacyTrackingPaidEntries = legacyTrackingPaidEntries,
       // ignore: prefer_initializing_formals
       _financiallyRecordedPaidMinor = financiallyRecordedPaidMinor,
       // ignore: prefer_initializing_formals
       _transferredPaidMinor = transferredPaidMinor,
       // ignore: prefer_initializing_formals
       _transferredPaidOccurrences = transferredPaidOccurrences,
       // ignore: prefer_initializing_formals
       _transferredPaidEntries = transferredPaidEntries,
       // ignore: prefer_initializing_formals
       _balanceRecordedPaidMinor = balanceRecordedPaidMinor,
       // ignore: prefer_initializing_formals
       _balanceRecordedPaidOccurrences = balanceRecordedPaidOccurrences,
       // ignore: prefer_initializing_formals
       _balanceRecordedPaidEntries = balanceRecordedPaidEntries,
       // ignore: prefer_initializing_formals
       _dealsPenaltyMoneyAccount = dealsPenaltyMoneyAccount,
       // ignore: prefer_initializing_formals
       _penaltyFundAccount = penaltyFundAccount,
       // ignore: prefer_initializing_formals
       _dealsPenaltyMoneyBalanceMinor = dealsPenaltyMoneyBalanceMinor,
       // ignore: prefer_initializing_formals
       _penaltyFundBalanceMinor = penaltyFundBalanceMinor,
       // ignore: prefer_initializing_formals
       _hasDealsPenaltyMoneyData = hasDealsPenaltyMoneyData,
       // ignore: prefer_initializing_formals
       _scope = scope,
       // ignore: prefer_initializing_formals
       _affectsAccountBalance = affectsAccountBalance,
       // ignore: prefer_initializing_formals
       _affectsTotalCashBalance = affectsTotalCashBalance,
       // ignore: prefer_initializing_formals
       _affectsIndividualAccountBalances = affectsIndividualAccountBalances,
       // ignore: prefer_initializing_formals
       _affectsCashflow = affectsCashflow,
       // ignore: prefer_initializing_formals
       _affectsBudget = affectsBudget;

  factory JointDealsSummary.fromJson(Object? value) {
    final map = jsonMap(dataOf(value));
    final range = jsonMap(map['range']);
    return JointDealsSummary(
      from: _nullableDate(range['from'] ?? map['from']),
      to: _nullableDate(range['to'] ?? map['to']),
      activeDeals: jsonInt(map['active_deals']),
      outstandingMinor: Money.fromJson(
        map['unpaid_minor'] ?? map['outstanding_minor'] ?? map['owed_minor'],
      ),
      settledMinor: Money.fromJson(map['paid_minor'] ?? map['settled_minor']),
      outstandingOccurrences: jsonInt(
        map['unpaid_occurrences'] ?? map['outstanding_occurrences'],
      ),
      settledOccurrences: jsonInt(
        map['paid_occurrences'] ?? map['settled_occurrences'],
      ),
      outstandingEntries: jsonInt(map['outstanding_entries']),
      settledEntries: jsonInt(map['settled_entries']),
      trackingPaidMinor: Money.fromJson(
        map['paid_only_minor'] ?? map['tracking_paid_minor'],
      ),
      legacyTrackingPaidMinor: Money.fromJson(
        map['legacy_tracking_paid_minor'],
      ),
      externalDepositPaidMinor: Money.fromJson(
        map['external_deposit_paid_minor'] ?? map['direct_deposit_paid_minor'],
      ),
      externalDepositPaidOccurrences: jsonInt(
        map['external_deposit_paid_occurrences'] ??
            map['direct_deposit_paid_occurrences'],
      ),
      externalDepositPaidEntries: jsonInt(
        map['external_deposit_paid_entries'] ??
            map['direct_deposit_paid_entries'],
      ),
      paidOnlyOccurrences: jsonInt(
        map['paid_only_occurrences'] ?? map['tracking_paid_occurrences'],
      ),
      paidOnlyEntries: jsonInt(
        map['paid_only_entries'] ?? map['tracking_paid_entries'],
      ),
      legacyTrackingPaidOccurrences: jsonInt(
        map['legacy_tracking_paid_occurrences'],
      ),
      legacyTrackingPaidEntries: jsonInt(map['legacy_tracking_paid_entries']),
      financiallyRecordedPaidMinor: Money.fromJson(
        map['financially_recorded_paid_minor'] ?? map['transferred_paid_minor'],
      ),
      transferredPaidMinor: Money.fromJson(
        map['transferred_paid_minor'] ?? map['financially_recorded_paid_minor'],
      ),
      transferredPaidOccurrences: jsonInt(
        map['transferred_paid_occurrences'] ??
            map['financially_recorded_paid_occurrences'],
      ),
      transferredPaidEntries: jsonInt(
        map['transferred_paid_entries'] ??
            map['financially_recorded_paid_entries'],
      ),
      balanceRecordedPaidMinor: Money.fromJson(
        map['balance_recorded_paid_minor'],
      ),
      balanceRecordedPaidOccurrences: jsonInt(
        map['balance_recorded_paid_occurrences'],
      ),
      balanceRecordedPaidEntries: jsonInt(map['balance_recorded_paid_entries']),
      dealsPenaltyMoneyAccount: map['deals_penalty_money_account'] is Map
          ? Account.fromJson(map['deals_penalty_money_account'])
          : null,
      penaltyFundAccount: map['penalty_fund_account'] is Map
          ? Account.fromJson(map['penalty_fund_account'])
          : null,
      dealsPenaltyMoneyBalanceMinor:
          map.containsKey('deals_penalty_money_balance_minor')
          ? Money.fromJson(map['deals_penalty_money_balance_minor'])
          : null,
      penaltyFundBalanceMinor: map.containsKey('penalty_fund_balance_minor')
          ? Money.fromJson(map['penalty_fund_balance_minor'])
          : null,
      hasDealsPenaltyMoneyData:
          map.containsKey('deals_penalty_money_account') ||
          map.containsKey('deals_penalty_money_balance_minor') ||
          map.containsKey('penalty_fund_account') ||
          map.containsKey('penalty_fund_balance_minor'),
      participants: jsonList(map['participants'])
          .map(JointParticipantSummary.fromJson)
          .toList(),
      deals: jsonList(map['deals']).map(JointDealSummaryItem.fromJson).toList(),
      scope: FinanceScope.fromJson(map['scope'] ?? 'joint'),
      affectsAccountBalance: jsonBool(map['affects_account_balance']),
      affectsTotalCashBalance: map.containsKey('affects_total_cash_balance')
          ? jsonBool(map['affects_total_cash_balance'])
          : null,
      affectsIndividualAccountBalances:
          map.containsKey('affects_individual_account_balances')
          ? jsonBool(map['affects_individual_account_balances'])
          : null,
      affectsCashflow: map.containsKey('affects_cashflow')
          ? jsonBool(map['affects_cashflow'])
          : null,
      affectsBudget: jsonBool(map['affects_budget']),
    );
  }

  final DateTime? from;
  final DateTime? to;
  final int activeDeals;
  final int outstandingMinor;
  final int settledMinor;
  final int outstandingOccurrences;
  final int settledOccurrences;
  final int outstandingEntries;
  final int settledEntries;
  final int? _trackingPaidMinor;
  final int? _legacyTrackingPaidMinor;
  final int? _externalDepositPaidMinor;
  final int? _externalDepositPaidOccurrences;
  final int? _externalDepositPaidEntries;
  final int? _paidOnlyOccurrences;
  final int? _paidOnlyEntries;
  final int? _legacyTrackingPaidOccurrences;
  final int? _legacyTrackingPaidEntries;
  final int? _financiallyRecordedPaidMinor;
  final int? _transferredPaidMinor;
  final int? _transferredPaidOccurrences;
  final int? _transferredPaidEntries;
  final int? _balanceRecordedPaidMinor;
  final int? _balanceRecordedPaidOccurrences;
  final int? _balanceRecordedPaidEntries;
  final Account? _dealsPenaltyMoneyAccount;
  final Account? _penaltyFundAccount;
  final int? _dealsPenaltyMoneyBalanceMinor;
  final int? _penaltyFundBalanceMinor;
  final bool? _hasDealsPenaltyMoneyData;
  final List<JointParticipantSummary> participants;
  final List<JointDealSummaryItem> deals;
  final FinanceScope? _scope;
  final bool? _affectsAccountBalance;
  final bool? _affectsTotalCashBalance;
  final bool? _affectsIndividualAccountBalances;
  final bool? _affectsCashflow;
  final bool? _affectsBudget;

  FinanceScope get scope => _scope ?? FinanceScope.joint;
  bool get affectsAccountBalance => _affectsAccountBalance ?? false;
  bool get affectsTotalCashBalance =>
      _affectsTotalCashBalance ?? affectsAccountBalance;
  bool get affectsIndividualAccountBalances =>
      _affectsIndividualAccountBalances ?? false;
  bool get affectsCashflow => _affectsCashflow ?? false;
  bool get affectsBudget => _affectsBudget ?? false;
  int get trackingPaidMinor => _trackingPaidMinor ?? 0;
  int get externalDepositPaidMinor => _externalDepositPaidMinor ?? 0;
  int get externalDepositPaidOccurrences =>
      _externalDepositPaidOccurrences ?? 0;
  int get externalDepositPaidEntries => _externalDepositPaidEntries ?? 0;
  int get paidOnlyMinor => trackingPaidMinor;
  int get legacyTrackingPaidMinor => _legacyTrackingPaidMinor ?? 0;
  int get paidOnlyOccurrences => _paidOnlyOccurrences ?? 0;
  int get paidOnlyEntries => _paidOnlyEntries ?? 0;
  int get legacyTrackingPaidOccurrences => _legacyTrackingPaidOccurrences ?? 0;
  int get legacyTrackingPaidEntries => _legacyTrackingPaidEntries ?? 0;
  int get financiallyRecordedPaidMinor => _financiallyRecordedPaidMinor ?? 0;
  int get transferredPaidMinor =>
      _transferredPaidMinor ?? financiallyRecordedPaidMinor;
  int get transferredPaidOccurrences => _transferredPaidOccurrences ?? 0;
  int get transferredPaidEntries => _transferredPaidEntries ?? 0;
  int get balanceRecordedPaidMinor =>
      _balanceRecordedPaidMinor ??
      externalDepositPaidMinor + transferredPaidMinor;
  int get balanceRecordedPaidOccurrences =>
      _balanceRecordedPaidOccurrences ??
      externalDepositPaidOccurrences + transferredPaidOccurrences;
  int get balanceRecordedPaidEntries =>
      _balanceRecordedPaidEntries ??
      externalDepositPaidEntries + transferredPaidEntries;
  Account? get dealsPenaltyMoneyAccount =>
      _dealsPenaltyMoneyAccount ?? _penaltyFundAccount;
  Account? get penaltyFundAccount => dealsPenaltyMoneyAccount;
  int get dealsPenaltyMoneyBalanceMinor =>
      _dealsPenaltyMoneyBalanceMinor ?? _penaltyFundBalanceMinor ?? 0;
  int get penaltyFundBalanceMinor => dealsPenaltyMoneyBalanceMinor;
  bool get hasDealsPenaltyMoneyData => _hasDealsPenaltyMoneyData ?? false;
  int get assessedMinor => outstandingMinor + settledMinor;
  int get unpaidMinor => outstandingMinor;
  int get paidMinor => settledMinor;
  int get unpaidOccurrences => outstandingOccurrences;
  int get paidOccurrences => settledOccurrences;
  int get occurrences => outstandingOccurrences + settledOccurrences;
  int get entries => outstandingEntries + settledEntries;
}

String? _nullableTrimmed(Object? value) {
  final result = value?.toString().trim() ?? '';
  return result.isEmpty ? null : result;
}

String _dealsPenaltyMoneyDisplayName(String value) {
  final trimmed = value.trim();
  final legacy = RegExp(
    r'^penalty fund(\s*\(\d+\))?$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  return legacy == null ? value : 'Deals Penalty Money${legacy.group(1) ?? ''}';
}

DateTime? _nullableTimestamp(Object? value) {
  final raw = value?.toString().trim() ?? '';
  return raw.isEmpty ? null : DateTime.tryParse(raw);
}

DateTime? _nullableDate(Object? value) {
  if (value == null || value.toString().trim().isEmpty) return null;
  return dateFromJson(value);
}

double? _nullableDouble(Object? value) =>
    value == null ? null : double.tryParse(value.toString());

DateTime _timestampFromJson(Object? value, String field) {
  final raw = value?.toString() ?? '';
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw FormatException('Expected $field to be an ISO-8601 timestamp.', raw);
  }
  return parsed;
}

class PageResult<T> {
  const PageResult({
    required this.items,
    this.currentPage = 1,
    this.lastPage = 1,
    this.total = 0,
    Object? rawResponse,
  }) : // Public nullable parameter wraps hot-reload-safe storage.
       // ignore: prefer_initializing_formals
       _rawResponse = rawResponse;

  final List<T> items;
  final int currentPage;
  final int lastPage;
  final int total;
  // Nullable backing keeps page objects created before hot reload safe.
  final Object? _rawResponse;

  Object? get rawResponse => _rawResponse;
}
