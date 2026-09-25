import 'api_client.dart';
import 'money.dart';
import 'offline_transactions.dart';
import '../models/domain_models.dart';

class AppRepository {
  AppRepository(this.api);

  final ApiClient api;

  Future<HealthStatus> health() async => HealthStatus.fromJson(
    await api.networkGet('/health', additionalSuccessStatusCodes: const {503}),
  );

  Future<TransactionSyncBatch> syncTransactions({
    required String installationId,
    required List<OfflineTransactionOperation> operations,
  }) async {
    final normalizedInstallationId = installationId.trim().toLowerCase();
    if (!_isUuid(normalizedInstallationId)) {
      throw const FormatException('A verified installation ID is required.');
    }
    if (operations.isEmpty || operations.length > 100) {
      throw const FormatException(
        'Transaction sync requires between 1 and 100 operations.',
      );
    }
    final batch = TransactionSyncBatch.fromJson(
      await api.post(
        '/transactions/sync',
        body: {
          'installation_id': normalizedInstallationId,
          'operations': operations
              .map((operation) => operation.toSyncEnvelope())
              .toList(),
        },
      ),
    );
    if (batch.installationId != normalizedInstallationId ||
        !batch.requiresRefresh) {
      throw const FormatException(
        'The transaction sync response came from an unexpected installation.',
      );
    }
    if (batch.results.length != operations.length) {
      throw const FormatException(
        'The transaction sync response did not include every queued operation.',
      );
    }
    final remaining = [...batch.results];
    for (final operation in operations) {
      final matches = remaining
          .where(
            (result) =>
                result.operationUuid == operation.operationUuid &&
                result.localId == operation.localId &&
                result.action == operation.action &&
                result.queuedAt.toUtc() == operation.queuedAt.toUtc(),
          )
          .toList();
      if (matches.length != 1) {
        throw const FormatException(
          'A transaction sync result did not match its frozen operation.',
        );
      }
      final result = matches.single;
      _validateSyncResult(operation, result);
      remaining.remove(result);
    }
    if (remaining.isNotEmpty) {
      throw const FormatException(
        'The transaction sync response contained an unknown operation.',
      );
    }
    return batch;
  }

  Future<AppSettings> settings() async =>
      AppSettings.fromJson(await api.get('/settings'));

  Future<AppSettings> updateSettings(AppSettings settings) async =>
      AppSettings.fromJson(
        await api.patch('/settings', body: settings.toJson()),
      );

  Future<List<Account>> accounts({
    bool includeArchived = false,
    FinanceScope scope = FinanceScope.personal,
    bool networkOnly = false,
  }) async {
    final query = {
      'include_archived': includeArchived ? 1 : 0,
      'scope': scope.apiValue,
    };
    final response = networkOnly
        ? await api.networkGet('/accounts', query: query)
        : await api.get('/accounts', query: query);
    return _items(response).map(Account.fromJson).toList();
  }

  Future<Account> createAccount({
    required String name,
    required String type,
    required int openingBalanceMinor,
    required String color,
    required FinanceScope scope,
    int openingDebtMinor = 0,
    int? creditLimitMinor,
    int? statementDay,
    int? dueDay,
    String? cardDesign,
    int? monthlyInterestRateBasisPoints,
  }) async => Account.fromJson(
    dataOf(
      await api.post(
        '/accounts',
        body: {
          'name': name,
          'type': type,
          if (type == 'credit_card')
            'opening_debt_minor': openingDebtMinor
          else
            'opening_balance_minor': openingBalanceMinor,
          if (type == 'credit_card') 'credit_limit_minor': creditLimitMinor,
          if (type == 'credit_card') 'statement_day': statementDay,
          if (type == 'credit_card') 'due_day': dueDay,
          if (type == 'savings')
            'monthly_interest_rate_basis_points':
                monthlyInterestRateBasisPoints ?? 0,
          'card_design': ?cardDesign,
          'color': color,
          'scope': scope.apiValue,
        },
      ),
    ),
  );

  Future<Account> updateAccount(
    int id, {
    required String name,
    required String type,
    required int openingBalanceMinor,
    required String color,
    int openingDebtMinor = 0,
    int? creditLimitMinor,
    int? statementDay,
    int? dueDay,
    String? cardDesign,
    int? monthlyInterestRateBasisPoints,
  }) async => Account.fromJson(
    dataOf(
      await api.patch(
        '/accounts/$id',
        body: {
          'name': name,
          'type': type,
          if (type == 'credit_card')
            'opening_debt_minor': openingDebtMinor
          else
            'opening_balance_minor': openingBalanceMinor,
          if (type == 'credit_card') 'credit_limit_minor': creditLimitMinor,
          if (type == 'credit_card') 'statement_day': statementDay,
          if (type == 'credit_card') 'due_day': dueDay,
          if (type == 'savings')
            'monthly_interest_rate_basis_points':
                monthlyInterestRateBasisPoints ?? 0,
          'card_design': ?cardDesign,
          'color': color,
        },
      ),
    ),
  );

  Future<void> deleteAccount(int id) => api.delete('/accounts/$id');

  Future<PageResult<AccountTransfer>> accountTransfers({
    FinanceScope scope = FinanceScope.personal,
    DateTime? from,
    DateTime? to,
    int? accountId,
    String? search,
    int page = 1,
    int perPage = 20,
    bool networkOnly = false,
  }) async {
    final query = <String, Object?>{
      'scope': scope.apiValue,
      'from': from == null ? null : apiDate(from),
      'to': to == null ? null : apiDate(to),
      'account_id': accountId,
      'search': _emptyToNull(search),
      'page': page,
      'per_page': perPage,
    };
    final response = networkOnly
        ? await api.networkGet('/account-transfers', query: query)
        : await api.get('/account-transfers', query: query);
    return accountTransfersFromResponse(response, fallbackPage: page);
  }

  PageResult<AccountTransfer> accountTransfersFromResponse(
    Object? response, {
    int fallbackPage = 1,
  }) {
    final map = jsonMap(response);
    final meta = jsonMap(map['meta']);
    return PageResult(
      items: _items(response).map(AccountTransfer.fromJson).toList(),
      currentPage: jsonInt(meta['current_page'], fallbackPage),
      lastPage: jsonInt(meta['last_page'], 1),
      total: jsonInt(meta['total']),
      rawResponse: response,
    );
  }

  Future<AccountTransfer> accountTransfer(int id) async =>
      AccountTransfer.fromJson(dataOf(await api.get('/account-transfers/$id')));

  Future<AccountTransfer> createAccountTransfer({
    required String clientUuid,
    required int sourceAccountId,
    required int destinationAccountId,
    required int amountMinor,
    required DateTime transferredOn,
    int serviceChargeMinor = 0,
    String? note,
  }) async => AccountTransfer.fromJson(
    dataOf(
      await api.post(
        '/account-transfers',
        body: {
          'client_uuid': clientUuid,
          'source_account_id': sourceAccountId,
          'destination_account_id': destinationAccountId,
          'amount_minor': amountMinor,
          'transferred_on': apiDate(transferredOn),
          'service_charge_minor': serviceChargeMinor,
          'note': _emptyToNull(note),
        },
      ),
    ),
  );

  Future<PageResult<CreditCardPayment>> creditCardPayments({
    FinanceScope scope = FinanceScope.personal,
    DateTime? from,
    DateTime? to,
    int? sourceAccountId,
    int? creditCardAccountId,
    String? search,
    int page = 1,
    int perPage = 20,
    bool networkOnly = false,
  }) async {
    final query = {
      'scope': scope.apiValue,
      'from': from == null ? null : apiDate(from),
      'to': to == null ? null : apiDate(to),
      'source_account_id': sourceAccountId,
      'credit_card_account_id': creditCardAccountId,
      'search': _emptyToNull(search),
      'page': page,
      'per_page': perPage,
    };
    final response = networkOnly
        ? await api.networkGet('/credit-card-payments', query: query)
        : await api.get('/credit-card-payments', query: query);
    final map = jsonMap(response);
    final meta = jsonMap(map['meta']);
    return PageResult(
      items: _items(response).map(CreditCardPayment.fromJson).toList(),
      currentPage: jsonInt(meta['current_page'], page),
      lastPage: jsonInt(meta['last_page'], 1),
      total: jsonInt(meta['total']),
      rawResponse: response,
    );
  }

  Future<CreditCardPayment> creditCardPayment(int id) async =>
      CreditCardPayment.fromJson(
        dataOf(await api.get('/credit-card-payments/$id')),
      );

  Future<CreditCardPayment> createCreditCardPayment({
    required String clientUuid,
    required int sourceAccountId,
    required int creditCardAccountId,
    required int amountMinor,
    required DateTime paidOn,
    int serviceChargeMinor = 0,
    String? note,
  }) async => CreditCardPayment.fromJson(
    dataOf(
      await api.post(
        '/credit-card-payments',
        body: {
          'client_uuid': clientUuid,
          'source_account_id': sourceAccountId,
          'credit_card_account_id': creditCardAccountId,
          'amount_minor': amountMinor,
          'service_charge_minor': serviceChargeMinor,
          'paid_on': apiDate(paidOn),
          'note': _emptyToNull(note),
        },
      ),
    ),
  );

  Future<PageResult<SavingsInterestCredit>> savingsInterestCredits({
    FinanceScope scope = FinanceScope.personal,
    DateTime? from,
    DateTime? to,
    int? savingsAccountId,
    int page = 1,
    int perPage = 20,
    bool networkOnly = false,
  }) async {
    final query = {
      'scope': scope.apiValue,
      'from': from == null ? null : apiDate(from),
      'to': to == null ? null : apiDate(to),
      'savings_account_id': savingsAccountId,
      'page': page,
      'per_page': perPage,
    };
    final response = networkOnly
        ? await api.networkGet('/savings-interest-credits', query: query)
        : await api.get('/savings-interest-credits', query: query);
    final map = jsonMap(response);
    final meta = jsonMap(map['meta']);
    return PageResult(
      items: _items(response).map(SavingsInterestCredit.fromJson).toList(),
      currentPage: jsonInt(meta['current_page'], page),
      lastPage: jsonInt(meta['last_page'], 1),
      total: jsonInt(meta['total']),
      rawResponse: response,
    );
  }

  Future<SavingsInterestCredit> savingsInterestCredit(int id) async =>
      SavingsInterestCredit.fromJson(
        dataOf(await api.get('/savings-interest-credits/$id')),
      );

  Future<SavingsInterestCredit> createSavingsInterestCredit({
    required String clientUuid,
    required int savingsAccountId,
    required int amountMinor,
    required DateTime creditedOn,
    String? note,
  }) async => SavingsInterestCredit.fromJson(
    dataOf(
      await api.post(
        '/savings-interest-credits',
        body: {
          'client_uuid': clientUuid,
          'savings_account_id': savingsAccountId,
          'amount_minor': amountMinor,
          'credited_on': apiDate(creditedOn),
          'note': _emptyToNull(note),
        },
      ),
    ),
  );

  Future<SavingsInterestAccrualResult> accrueSavingsInterest() async =>
      SavingsInterestAccrualResult.fromJson(
        await api.post('/savings-interest-credits/accrue', body: const {}),
      );

  Future<List<JointParticipant>> jointParticipants({
    bool includeArchived = false,
  }) async => _items(
    await api.get(
      '/joint-participants',
      query: {'include_archived': includeArchived ? 1 : 0},
    ),
  ).map(JointParticipant.fromJson).toList();

  Future<JointParticipant> createJointParticipant({
    required String name,
  }) async => JointParticipant.fromJson(
    dataOf(await api.post('/joint-participants', body: {'name': name.trim()})),
  );

  Future<JointParticipant> updateJointParticipant(
    int id, {
    required String name,
    bool? isArchived,
  }) async => JointParticipant.fromJson(
    dataOf(
      await api.patch(
        '/joint-participants/$id',
        body: {'name': name.trim(), 'is_archived': ?isArchived},
      ),
    ),
  );

  Future<void> deleteJointParticipant(int id) =>
      api.delete('/joint-participants/$id');

  Future<List<JointDeal>> jointDeals({bool includeArchived = false}) async =>
      _items(
        await api.get(
          '/joint-deals',
          query: {'include_archived': includeArchived ? 1 : 0},
        ),
      ).map(JointDeal.fromJson).toList();

  Future<JointDeal> createJointDeal({
    required String title,
    String? description,
    required int amountPerOccurrenceMinor,
  }) async => JointDeal.fromJson(
    dataOf(
      await api.post(
        '/joint-deals',
        body: {
          'title': title.trim(),
          'description': _emptyToNull(description),
          'amount_per_occurrence_minor': amountPerOccurrenceMinor,
        },
      ),
    ),
  );

  Future<JointDeal> updateJointDeal(
    int id, {
    required String title,
    String? description,
    required int amountPerOccurrenceMinor,
    bool? isArchived,
  }) async => JointDeal.fromJson(
    dataOf(
      await api.patch(
        '/joint-deals/$id',
        body: {
          'title': title.trim(),
          'description': _emptyToNull(description),
          'amount_per_occurrence_minor': amountPerOccurrenceMinor,
          'is_archived': ?isArchived,
        },
      ),
    ),
  );

  Future<void> deleteJointDeal(int id) => api.delete('/joint-deals/$id');

  Future<PageResult<JointPenalty>> jointPenalties({
    String? status,
    int? dealId,
    int? participantId,
    String? search,
    DateTime? from,
    DateTime? to,
    bool includeArchived = false,
    int page = 1,
    int perPage = 100,
    bool networkOnly = false,
  }) async {
    final query = <String, Object?>{
      'status': status,
      'deal_id': dealId,
      'participant_id': participantId,
      'search': _emptyToNull(search),
      'from': from == null ? null : apiDate(from),
      'to': to == null ? null : apiDate(to),
      'include_archived': includeArchived ? 1 : 0,
      'page': page,
      'per_page': perPage,
    };
    final response = networkOnly
        ? await api.networkGet('/joint-penalties', query: query)
        : await api.get('/joint-penalties', query: query);
    return jointPenaltiesFromResponse(response, fallbackPage: page);
  }

  PageResult<JointPenalty> jointPenaltiesFromResponse(
    Object? response, {
    int fallbackPage = 1,
  }) {
    final map = jsonMap(response);
    final meta = jsonMap(map['meta']);
    return PageResult(
      items: _items(response).map(JointPenalty.fromJson).toList(),
      currentPage: jsonInt(meta['current_page'], fallbackPage),
      lastPage: jsonInt(meta['last_page'], 1),
      total: jsonInt(meta['total']),
      rawResponse: response,
    );
  }

  Future<JointPenalty> createJointPenalty({
    required String clientUuid,
    required int dealId,
    int? participantId,
    String? participantName,
    required DateTime occurredOn,
    required int quantity,
    String? notes,
  }) async => JointPenalty.fromJson(
    dataOf(
      await api.post(
        '/joint-penalties',
        body: {
          'client_uuid': clientUuid,
          'deal_id': dealId,
          ...participantId != null
              ? {'participant_id': participantId}
              : {'participant_name': _emptyToNull(participantName)},
          'occurred_on': apiDate(occurredOn),
          'quantity': quantity,
          'notes': _emptyToNull(notes),
        },
      ),
    ),
  );

  Future<JointPenalty> updateJointPenalty(
    int id, {
    required int version,
    required int dealId,
    int? participantId,
    String? participantName,
    required DateTime occurredOn,
    required int quantity,
    String? notes,
  }) async => JointPenalty.fromJson(
    dataOf(
      await api.patch(
        '/joint-penalties/$id',
        body: {
          'version': version,
          'deal_id': dealId,
          ...participantId != null
              ? {'participant_id': participantId}
              : {'participant_name': _emptyToNull(participantName)},
          'occurred_on': apiDate(occurredOn),
          'quantity': quantity,
          'notes': _emptyToNull(notes),
        },
      ),
    ),
  );

  Future<JointPenalty> settleJointPenalty(
    int id, {
    required int version,
    DateTime? settledOn,
    required String paymentMode,
    required String paymentClientUuid,
    int? sourceAccountId,
  }) async {
    if (paymentMode != 'external_deposit' &&
        paymentMode != 'account_transfer') {
      throw const FormatException('Choose a valid payment method.');
    }
    if (paymentClientUuid.trim().isEmpty) {
      throw const FormatException('A stable payment reference is required.');
    }
    if (paymentMode == 'external_deposit' && sourceAccountId != null) {
      throw const FormatException(
        'A direct payment cannot include a source account.',
      );
    }
    if (paymentMode == 'account_transfer' && sourceAccountId == null) {
      throw const FormatException(
        'Choose a Joint source account for the payment.',
      );
    }
    return JointPenalty.fromJson(
      dataOf(
        await api.post(
          '/joint-penalties/$id/settle',
          body: {
            'version': version,
            if (settledOn != null) 'settled_on': apiDate(settledOn),
            'payment_mode': paymentMode,
            'payment_client_uuid': paymentClientUuid,
            if (paymentMode == 'account_transfer')
              'source_account_id': sourceAccountId,
          },
        ),
      ),
    );
  }

  Future<JointPenalty> reopenJointPenalty(
    int id, {
    required int version,
    String? reason,
  }) async => JointPenalty.fromJson(
    dataOf(
      await api.post(
        '/joint-penalties/$id/reopen',
        body: {'version': version, 'reason': _emptyToNull(reason)},
      ),
    ),
  );

  Future<void> deleteJointPenalty(
    int id, {
    required int version,
    String? reason,
  }) => api.delete(
    '/joint-penalties/$id',
    body: {'version': version, 'reason': _emptyToNull(reason)},
  );

  Future<JointDealsSummary> jointDealsSummary({
    DateTime? from,
    DateTime? to,
  }) async => JointDealsSummary.fromJson(
    await api.get(
      '/joint-deals/summary',
      query: {
        'from': from == null ? null : apiDate(from),
        'to': to == null ? null : apiDate(to),
      },
    ),
  );

  Future<List<JewelryItem>> jewelry() async =>
      _items(await api.get('/jewelry')).map(JewelryItem.fromJson).toList();

  Future<GoldPriceQuote> goldPrice({bool refresh = false}) async =>
      GoldPriceQuote.fromJson(
        await api.get(
          '/gold-price',
          query: refresh ? const {'refresh': 1} : const {},
        ),
      );

  Future<ManualGoldPriceList> manualGoldPrices() async =>
      ManualGoldPriceList.fromJson(await api.get('/gold-price/manual'));

  Future<ManualGoldPriceList> updateManualGoldPrices(
    List<ManualGoldPriceRate> rates,
  ) async => ManualGoldPriceList.fromJson(
    await api.put(
      '/gold-price/manual',
      body: {'rates': rates.map((rate) => rate.toJson()).toList()},
    ),
  );

  Future<JewelryItem> createJewelry({
    required String name,
    required String jewelryType,
    required int karat,
    required int weightMg,
    DateTime? acquiredOn,
    int? purchaseValueMinor,
    required int estimatedValueMinor,
    String? notes,
  }) async => JewelryItem.fromJson(
    dataOf(
      await api.post(
        '/jewelry',
        body: {
          'name': name.trim(),
          'jewelry_type': jewelryType,
          'karat': karat,
          'weight_mg': weightMg,
          'acquired_on': acquiredOn == null ? null : apiDate(acquiredOn),
          'purchase_value_minor': purchaseValueMinor,
          'estimated_value_minor': estimatedValueMinor,
          'notes': _emptyToNull(notes),
        },
      ),
    ),
  );

  Future<JewelryItem> updateJewelry(
    int id, {
    required String name,
    required String jewelryType,
    required int karat,
    required int weightMg,
    DateTime? acquiredOn,
    int? purchaseValueMinor,
    required int estimatedValueMinor,
    String? notes,
  }) async => JewelryItem.fromJson(
    dataOf(
      await api.patch(
        '/jewelry/$id',
        body: {
          'name': name.trim(),
          'jewelry_type': jewelryType,
          'karat': karat,
          'weight_mg': weightMg,
          'acquired_on': acquiredOn == null ? null : apiDate(acquiredOn),
          'purchase_value_minor': purchaseValueMinor,
          'estimated_value_minor': estimatedValueMinor,
          'notes': _emptyToNull(notes),
        },
      ),
    ),
  );

  Future<void> deleteJewelry(int id) => api.delete('/jewelry/$id');

  Future<JewelryItem> convertJewelry(
    int id, {
    required String clientUuid,
    required int accountId,
    required int amountMinor,
    required DateTime convertedOn,
  }) async {
    final response = dataOf(
      await api.post(
        '/jewelry/$id/convert',
        body: {
          'client_uuid': clientUuid,
          'account_id': accountId,
          'amount_minor': amountMinor,
          'converted_on': apiDate(convertedOn),
        },
      ),
    );
    final map = jsonMap(response);
    return JewelryItem.fromJson(map['jewelry'] ?? map['item'] ?? response);
  }

  Future<List<Category>> categories({bool includeArchived = false}) async {
    final response = await api.get(
      '/categories',
      query: {'include_archived': includeArchived ? 1 : 0},
    );
    return _items(response).map(Category.fromJson).toList();
  }

  Future<Category> createCategory({
    required String name,
    required String kind,
    required String color,
    required String icon,
  }) async => Category.fromJson(
    dataOf(
      await api.post(
        '/categories',
        body: {'name': name, 'kind': kind, 'color': color, 'icon': icon},
      ),
    ),
  );

  Future<Category> updateCategory(
    int id, {
    required String name,
    required String kind,
    required String color,
    required String icon,
  }) async => Category.fromJson(
    dataOf(
      await api.patch(
        '/categories/$id',
        body: {'name': name, 'kind': kind, 'color': color, 'icon': icon},
      ),
    ),
  );

  Future<void> deleteCategory(int id) => api.delete('/categories/$id');

  Future<PageResult<TransactionRecord>> transactions({
    DateTime? from,
    DateTime? to,
    String? kind,
    int? accountId,
    int? categoryId,
    int? cutoffPeriodId,
    String? search,
    FinanceScope scope = FinanceScope.personal,
    int page = 1,
    int perPage = 50,
    bool networkOnly = false,
  }) async {
    final query = <String, Object?>{
      'from': from == null ? null : apiDate(from),
      'to': to == null ? null : apiDate(to),
      'kind': kind,
      'account_id': accountId,
      'category_id': categoryId,
      'cutoff_period_id': cutoffPeriodId,
      'search': search,
      'scope': scope.apiValue,
      'page': page,
      'per_page': perPage,
    };
    final response = networkOnly
        ? await api.networkGet('/transactions', query: query)
        : await api.get('/transactions', query: query);
    return transactionsFromResponse(response, fallbackPage: page);
  }

  Future<PageResult<InstallmentPlan>> installmentPlans({
    FinanceScope scope = FinanceScope.personal,
    bool networkOnly = false,
    String? status,
    int page = 1,
    int perPage = 100,
  }) async {
    final query = {
      'scope': scope.apiValue,
      'status': ?status,
      'page': page,
      'per_page': perPage,
    };
    final response = networkOnly
        ? await api.networkGet('/installment-plans', query: query)
        : await api.get('/installment-plans', query: query);
    final map = jsonMap(response);
    final meta = jsonMap(map['meta']);
    final items = _items(response).map(InstallmentPlan.fromJson).toList();
    return PageResult(
      items: items,
      currentPage: jsonInt(meta['current_page'], page),
      lastPage: jsonInt(meta['last_page'], 1),
      total: jsonInt(meta['total'], items.length),
      rawResponse: response,
    );
  }

  Future<InstallmentPlan> createInstallmentPlan({
    required String clientUuid,
    required int accountId,
    required int categoryId,
    required int installmentMonthlyMinor,
    required int installmentMonths,
    required DateTime installmentStartOn,
    int downPaymentMinor = 0,
    String? payee,
    String? note,
  }) async => InstallmentPlan.fromJson(
    dataOf(
      await api.post(
        '/installment-plans',
        body: {
          'client_uuid': clientUuid,
          'account_id': accountId,
          'category_id': categoryId,
          'installment_monthly_minor': installmentMonthlyMinor,
          'installment_months': installmentMonths,
          'installment_start_on': apiDate(installmentStartOn),
          'down_payment_minor': downPaymentMinor,
          'payee': _emptyToNull(payee),
          'note': _emptyToNull(note),
        },
      ),
    ),
  );

  Future<InstallmentPlan> updateInstallmentPlan(
    int id, {
    required int version,
    int? accountId,
    required String? payee,
    required String? note,
    int? categoryId,
    int? installmentMonthlyMinor,
    int? installmentMonths,
    DateTime? installmentStartOn,
  }) async => InstallmentPlan.fromJson(
    dataOf(
      await api.patch(
        '/installment-plans/$id',
        body: {
          'version': version,
          'account_id': ?accountId,
          'category_id': ?categoryId,
          'installment_monthly_minor': ?installmentMonthlyMinor,
          'installment_months': ?installmentMonths,
          if (installmentStartOn != null)
            'installment_start_on': apiDate(installmentStartOn),
          'payee': _emptyToNull(payee),
          'note': _emptyToNull(note),
        },
      ),
    ),
  );

  Future<InstallmentPlan> archiveInstallmentPlan(
    int id, {
    required int version,
  }) async => InstallmentPlan.fromJson(
    dataOf(
      await api.delete('/installment-plans/$id', body: {'version': version}),
    ),
  );

  Future<InstallmentPaymentResult> recordInstallmentPayment(
    int id, {
    required String clientUuid,
    required int version,
    required DateTime paidOn,
    int? accountId,
  }) async => InstallmentPaymentResult.fromJson(
    await api.post(
      '/installment-plans/$id/payments',
      body: {
        'client_uuid': clientUuid,
        'version': version,
        'paid_on': apiDate(paidOn),
        'account_id': ?accountId,
      },
    ),
  );

  PageResult<TransactionRecord> transactionsFromResponse(
    Object? response, {
    int fallbackPage = 1,
  }) {
    final map = jsonMap(response);
    final meta = jsonMap(map['meta']);
    return PageResult(
      items: _items(response).map(TransactionRecord.fromJson).toList(),
      currentPage: jsonInt(meta['current_page'], fallbackPage),
      lastPage: jsonInt(meta['last_page'], 1),
      total: jsonInt(meta['total']),
      rawResponse: response,
    );
  }

  Future<PageResult<JointSplitExpense>> jointSplitExpenses({
    DateTime? from,
    DateTime? to,
    int? accountId,
    int? categoryId,
    String? search,
    int page = 1,
    int perPage = 50,
  }) async {
    final response = await api.get(
      '/joint-split-expenses',
      query: {
        'from': from == null ? null : apiDate(from),
        'to': to == null ? null : apiDate(to),
        'account_id': accountId,
        'category_id': categoryId,
        'search': _emptyToNull(search),
        'page': page,
        'per_page': perPage,
      },
    );
    final map = jsonMap(response);
    final meta = jsonMap(map['meta']);
    return PageResult(
      items: _items(response).map(JointSplitExpense.fromJson).toList(),
      currentPage: jsonInt(meta['current_page'], page),
      lastPage: jsonInt(meta['last_page'], 1),
      total: jsonInt(meta['total']),
    );
  }

  Future<JointSplitExpense> jointSplitExpense(int id) async =>
      JointSplitExpense.fromJson(
        dataOf(await api.get('/joint-split-expenses/$id')),
      );

  Future<JointSplitExpense> createJointSplitExpense({
    required String clientUuid,
    required int firstAccountId,
    required int secondAccountId,
    required int amountMinor,
    required DateTime occurredOn,
    required int categoryId,
    String? payee,
    String? note,
  }) async => JointSplitExpense.fromJson(
    dataOf(
      await api.post(
        '/joint-split-expenses',
        body: {
          'client_uuid': clientUuid,
          'first_account_id': firstAccountId,
          'second_account_id': secondAccountId,
          'amount_minor': amountMinor,
          'occurred_on': apiDate(occurredOn),
          'category_id': categoryId,
          'payee': _emptyToNull(payee),
          'note': _emptyToNull(note),
        },
      ),
    ),
  );

  Future<TransactionRecord> createTransaction({
    required String clientUuid,
    required String kind,
    required int amountMinor,
    required DateTime occurredOn,
    required int accountId,
    required int categoryId,
    String? payee,
    String? note,
    int? installmentMonths,
    int? installmentMonthlyMinor,
    DateTime? installmentStartOn,
  }) async => TransactionRecord.fromJson(
    dataOf(
      await api.post(
        '/transactions',
        body: {
          'client_uuid': clientUuid,
          'kind': kind,
          'amount_minor': amountMinor,
          'occurred_on': apiDate(occurredOn),
          'account_id': accountId,
          'category_id': categoryId,
          'payee': _emptyToNull(payee),
          'note': _emptyToNull(note),
          'installment_months': installmentMonths,
          'installment_monthly_minor': installmentMonthlyMinor,
          'installment_start_on': installmentStartOn == null
              ? null
              : apiDate(installmentStartOn),
        },
      ),
    ),
  );

  Future<TransactionRecord> updateTransaction(
    int id, {
    required int version,
    required String kind,
    required int amountMinor,
    required DateTime occurredOn,
    required int accountId,
    required int categoryId,
    String? payee,
    String? note,
    int? installmentMonths,
    int? installmentMonthlyMinor,
    DateTime? installmentStartOn,
  }) async => TransactionRecord.fromJson(
    dataOf(
      await api.patch(
        '/transactions/$id',
        body: {
          'version': version,
          'kind': kind,
          'amount_minor': amountMinor,
          'occurred_on': apiDate(occurredOn),
          'account_id': accountId,
          'category_id': categoryId,
          'payee': _emptyToNull(payee),
          'note': _emptyToNull(note),
          'installment_months': installmentMonths,
          'installment_monthly_minor': installmentMonthlyMinor,
          'installment_start_on': installmentStartOn == null
              ? null
              : apiDate(installmentStartOn),
        },
      ),
    ),
  );

  Future<void> deleteTransaction(int id, int version) =>
      api.delete('/transactions/$id', body: {'version': version});

  Future<ReportSummary> dashboard({
    required String period,
    required DateTime anchor,
    FinanceScope scope = FinanceScope.personal,
    bool networkOnly = false,
  }) async => ReportSummary.fromJson(
    await (networkOnly ? api.networkGet : api.get)(
      '/dashboard',
      query: {
        'period': period,
        'anchor': apiDate(anchor),
        'scope': scope.apiValue,
      },
    ),
    fallbackPeriod: period,
  );

  Future<ReportSummary> report({
    required String period,
    required DateTime anchor,
    FinanceScope scope = FinanceScope.personal,
    bool networkOnly = false,
  }) async => ReportSummary.fromJson(
    await (networkOnly ? api.networkGet : api.get)(
      '/reports/summary',
      query: {
        'period': period,
        'anchor': apiDate(anchor),
        'scope': scope.apiValue,
      },
    ),
    fallbackPeriod: period,
  );

  Future<List<CutoffPeriod>> cutoffPeriods({
    required DateTime from,
    required DateTime to,
    FinanceScope scope = FinanceScope.personal,
  }) async {
    final response = await api.get(
      '/cutoff-periods',
      query: {
        'from': apiDate(from),
        'to': apiDate(to),
        'scope': scope.apiValue,
      },
    );
    return _items(response).map(CutoffPeriod.fromJson).toList();
  }

  Future<CutoffPeriod> currentCutoff(
    DateTime date, {
    FinanceScope scope = FinanceScope.personal,
  }) async => CutoffPeriod.fromJson(
    dataOf(
      await api.get(
        '/cutoff-periods/current',
        query: {'date': apiDate(date), 'scope': scope.apiValue},
      ),
    ),
  );

  Future<CutoffPeriod> updateCutoffBudget(
    int periodId, {
    required int totalBudgetMinor,
    List<Map<String, int>> items = const [],
  }) async => CutoffPeriod.fromJson(
    dataOf(
      await api.put(
        '/cutoff-periods/$periodId/budget',
        body: {'total_budget_minor': totalBudgetMinor, 'items': items},
      ),
    ),
  );

  Future<CutoffPeriod> resetCutoffBudget(int periodId) async =>
      CutoffPeriod.fromJson(
        dataOf(await api.delete('/cutoff-periods/$periodId/budget')),
      );

  Future<List<CutoffSchedule>> cutoffSchedules({
    FinanceScope scope = FinanceScope.personal,
  }) async => _items(
    await api.get('/cutoff-schedules', query: {'scope': scope.apiValue}),
  ).map(CutoffSchedule.fromJson).toList();

  Future<CutoffSchedule> createCutoffSchedule({
    required String name,
    required DateTime effectiveFrom,
    required List<Map<String, Object?>> rules,
    FinanceScope scope = FinanceScope.personal,
  }) async => CutoffSchedule.fromJson(
    dataOf(
      await api.post(
        '/cutoff-schedules',
        body: {
          'name': name,
          'effective_from': apiDate(effectiveFrom),
          'scope': scope.apiValue,
          'rules': rules,
        },
      ),
    ),
  );

  static List<dynamic> _items(Object? response) {
    final data = dataOf(response);
    if (data is List) return data;
    final map = jsonMap(data);
    final nested = map['items'] ?? map['data'];
    return nested is List ? nested : const [];
  }

  static String? _emptyToNull(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}

void _validateSyncResult(
  OfflineTransactionOperation operation,
  TransactionSyncResult result,
) {
  if (result.localId >= 0 || !_isUuid(result.operationUuid)) {
    throw const FormatException(
      'Transaction sync returned an invalid identity.',
    );
  }
  if (result.status == 'applied') {
    if (result.code != null ||
        result.message != null ||
        result.retryable ||
        result.errors.isNotEmpty ||
        result.currentServerTransaction != null ||
        (result.serverId ?? 0) <= 0) {
      throw const FormatException(
        'Transaction sync returned an invalid applied receipt.',
      );
    }
    if (operation.action == OfflineTransactionAction.delete) {
      final base = TransactionRecord.fromJson(operation.baseSnapshot);
      if (result.httpStatus != 204 ||
          result.transaction != null ||
          result.serverId != operation.serverId ||
          result.currentState != 'deleted' ||
          !_validTombstone(
            result.tombstone,
            expectedId: operation.serverId!,
            expectedClientUuid: base.clientUuid,
            expectedScope: operation.scope,
            minimumVersion: operation.baseVersion!,
          )) {
        throw const FormatException(
          'Transaction sync returned an invalid delete receipt.',
        );
      }
      return;
    }
    final expectedStatus = operation.action == OfflineTransactionAction.create
        ? const {200, 201}
        : const {200};
    if (!expectedStatus.contains(result.httpStatus) ||
        result.transaction == null ||
        result.tombstone != null ||
        result.currentState != 'active') {
      throw const FormatException(
        'Transaction sync did not return the applied transaction.',
      );
    }
    final desired = TransactionRecord.fromJson(operation.desiredSnapshot);
    if (!_validTransactionResource(
      result.transaction!,
      expectedScope: operation.scope,
      expectedClientUuid: desired.clientUuid,
      expectedId: operation.action == OfflineTransactionAction.update
          ? operation.serverId
          : null,
      requireOrdinary: true,
    )) {
      throw const FormatException(
        'The applied transaction resource was malformed.',
      );
    }
    final transaction = TransactionRecord.fromJson(result.transaction);
    if (transaction.id <= 0 ||
        transaction.isManagedTransaction ||
        transaction.scope != operation.scope ||
        (operation.action == OfflineTransactionAction.create &&
            transaction.version < 1) ||
        (operation.action == OfflineTransactionAction.update &&
            transaction.version != operation.baseVersion! + 1) ||
        (operation.action == OfflineTransactionAction.update &&
            transaction.id != operation.serverId) ||
        result.serverId != transaction.id ||
        !_sameTransactionIntent(transaction, desired)) {
      throw const FormatException(
        'The applied transaction did not match its queued intent.',
      );
    }
    return;
  }
  if (result.status == 'conflict') {
    if (result.httpStatus != 409 ||
        result.retryable ||
        result.errors.isNotEmpty ||
        result.transaction != null ||
        result.code == null ||
        result.message == null) {
      throw const FormatException(
        'Transaction sync returned an invalid conflict receipt.',
      );
    }
    if (result.code == 'OPERATION_UUID_IN_USE') {
      if (result.replayed ||
          result.serverId != null ||
          result.currentServerTransaction != null ||
          result.tombstone != null ||
          result.currentState != null) {
        throw const FormatException(
          'The operation UUID conflict contained unexpected state.',
        );
      }
      return;
    }
    if (operation.action == OfflineTransactionAction.create) {
      if (result.code == 'CLIENT_UUID_IN_USE' &&
          (result.serverId ?? 0) > 0 &&
          result.currentServerTransaction == null &&
          result.tombstone == null &&
          result.currentState == null) {
        return;
      }
      if (result.code == 'CLIENT_UUID_DELETED') {
        final expected = TransactionRecord.fromJson(operation.desiredSnapshot);
        if ((result.serverId ?? 0) > 0 &&
            result.currentServerTransaction == null &&
            result.currentState == 'deleted' &&
            _validTombstone(
              result.tombstone,
              expectedId: result.serverId!,
              expectedClientUuid: expected.clientUuid,
              expectedScope: operation.scope,
              minimumVersion: 1,
            )) {
          return;
        }
      }
      throw const FormatException(
        'The queued create conflict did not include its current identity.',
      );
    }
    final base = TransactionRecord.fromJson(operation.baseSnapshot);
    if (result.code == 'STALE_VERSION' || _isManagedConflictCode(result.code)) {
      if (result.currentServerTransaction == null ||
          result.tombstone != null ||
          result.currentState != 'active' ||
          result.serverId != operation.serverId ||
          !_validTransactionResource(
            result.currentServerTransaction!,
            expectedScope: operation.scope,
            expectedClientUuid: base.clientUuid,
            expectedId: operation.serverId,
            requireOrdinary: result.code == 'STALE_VERSION',
          )) {
        throw const FormatException(
          'The transaction conflict belongs to another record.',
        );
      }
      final current = TransactionRecord.fromJson(
        result.currentServerTransaction,
      );
      if (current.version < operation.baseVersion! ||
          (result.code == 'STALE_VERSION' &&
              (current.version == operation.baseVersion ||
                  current.isManagedTransaction)) ||
          (_isManagedConflictCode(result.code) &&
              !_managedConflictMatches(result.code, current.sourceType))) {
        throw const FormatException(
          'The transaction conflict belongs to another record.',
        );
      }
      return;
    }
    if (result.code == 'TRANSACTION_DELETED' &&
        result.currentServerTransaction == null &&
        result.serverId == operation.serverId &&
        result.currentState == 'deleted' &&
        _validTombstone(
          result.tombstone,
          expectedId: operation.serverId!,
          expectedClientUuid: base.clientUuid,
          expectedScope: operation.scope,
          minimumVersion: operation.baseVersion!,
        )) {
      return;
    }
    throw const FormatException(
      'The transaction conflict did not include its current state.',
    );
  }
  if (result.status == 'rejected') {
    if (result.message == null ||
        result.transaction != null ||
        result.currentServerTransaction != null ||
        result.tombstone != null ||
        result.currentState != null ||
        result.serverId != operation.serverId) {
      throw const FormatException(
        'Transaction sync returned an invalid rejected receipt.',
      );
    }
    final valid = switch (result.code) {
      'VALIDATION_ERROR' =>
        result.httpStatus == 422 &&
            !result.retryable &&
            result.errors.isNotEmpty,
      'TRANSACTION_NOT_FOUND' =>
        operation.action != OfflineTransactionAction.create &&
            result.httpStatus == 404 &&
            !result.retryable &&
            result.errors.isEmpty,
      'SYNC_OPERATION_FAILED' =>
        result.httpStatus == 500 &&
            result.retryable &&
            !result.replayed &&
            result.errors.isEmpty,
      'SYNC_SERVER_ERROR' =>
        result.httpStatus == 500 &&
            !result.retryable &&
            !result.replayed &&
            result.errors.isEmpty,
      _ => false,
    };
    if (!valid) {
      throw const FormatException(
        'Transaction sync returned an unsupported rejection.',
      );
    }
    return;
  }
  throw const FormatException('Unsupported transaction sync result status.');
}

bool _validTransactionResource(
  Map<String, Object?> raw, {
  required FinanceScope expectedScope,
  required String expectedClientUuid,
  int? expectedId,
  required bool requireOrdinary,
}) {
  final id = raw['id'];
  final version = raw['version'];
  final accountId = raw['account_id'];
  final categoryId = raw['category_id'];
  final cutoffPeriodId = raw['cutoff_period_id'];
  final kind = raw['kind'];
  final amountMinor = raw['amount_minor'];
  final occurredOn = raw['occurred_on'];
  final payee = raw['payee'];
  final note = raw['note'];
  final clientUuid = raw['client_uuid']?.toString().trim().toLowerCase();
  if (id is! int ||
      id <= 0 ||
      expectedId != null && id != expectedId ||
      version is! int ||
      version <= 0 ||
      accountId is! int ||
      accountId <= 0 ||
      categoryId is! int ||
      categoryId <= 0 ||
      cutoffPeriodId is! int ||
      cutoffPeriodId <= 0 ||
      (kind != 'income' && kind != 'expense') ||
      amountMinor is! int ||
      amountMinor < 1 ||
      amountMinor > Money.maxMinorUnits ||
      occurredOn is! String ||
      !_isExactApiDate(occurredOn) ||
      payee != null && (payee is! String || payee.runes.length > 150) ||
      note != null && (note is! String || note.runes.length > 2000) ||
      raw['scope'] != expectedScope.apiValue ||
      clientUuid != expectedClientUuid.trim().toLowerCase() ||
      !_isUuid(clientUuid ?? '')) {
    return false;
  }
  final account = raw['account'];
  final category = raw['category'];
  if (account is! Map || category is! Map) return false;
  final accountMap = jsonMap(account);
  final categoryMap = jsonMap(category);
  if (accountMap['id'] is! int ||
      accountMap['id'] != accountId ||
      accountMap['scope'] != expectedScope.apiValue ||
      categoryMap['id'] is! int ||
      categoryMap['id'] != categoryId ||
      categoryMap['kind'] != raw['kind']) {
    return false;
  }
  if (requireOrdinary &&
      (raw['source_type'] != null ||
          raw['source_id'] != null ||
          raw['source_component'] != null ||
          categoryMap['is_system'] == true)) {
    return false;
  }
  return true;
}

bool _isExactApiDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final parsed = DateTime.tryParse(value);
  return parsed != null && apiDate(parsed) == value;
}

bool _validTombstone(
  Map<String, Object?>? raw, {
  required int expectedId,
  required String expectedClientUuid,
  required FinanceScope expectedScope,
  required int minimumVersion,
}) {
  if (raw == null ||
      raw['id'] is! int ||
      raw['id'] != expectedId ||
      raw['client_uuid']?.toString().trim().toLowerCase() !=
          expectedClientUuid.trim().toLowerCase() ||
      !_isUuid(raw['client_uuid']?.toString().trim().toLowerCase() ?? '') ||
      raw['scope'] != expectedScope.apiValue ||
      raw['version'] is! int ||
      (raw['version'] as int) < minimumVersion ||
      DateTime.tryParse(raw['deleted_at']?.toString() ?? '') == null) {
    return false;
  }
  return true;
}

bool _isManagedConflictCode(String? code) => const {
  'JEWELRY_TRANSACTION_MANAGED',
  'ACCOUNT_TRANSFER_FEE_MANAGED',
  'CREDIT_CARD_PAYMENT_FEE_MANAGED',
  'SAVINGS_INTEREST_MANAGED',
  'JOINT_SPLIT_EXPENSE_MANAGED',
}.contains(code);

bool _managedConflictMatches(String? code, String? sourceType) =>
    switch (code) {
      'JEWELRY_TRANSACTION_MANAGED' => sourceType == 'jewelry_conversion',
      'ACCOUNT_TRANSFER_FEE_MANAGED' => sourceType == 'account_transfer_fee',
      'CREDIT_CARD_PAYMENT_FEE_MANAGED' =>
        sourceType == 'credit_card_payment_fee',
      'SAVINGS_INTEREST_MANAGED' => sourceType == 'savings_interest',
      'JOINT_SPLIT_EXPENSE_MANAGED' => sourceType == 'joint_split_expense',
      _ => false,
    };

bool _sameTransactionIntent(
  TransactionRecord actual,
  TransactionRecord desired,
) =>
    actual.clientUuid == desired.clientUuid &&
    actual.kind == desired.kind &&
    actual.amountMinor == desired.amountMinor &&
    actual.occurredOn == desired.occurredOn &&
    actual.accountId == desired.accountId &&
    actual.categoryId == desired.categoryId &&
    _normalized(actual.payee) == _normalized(desired.payee) &&
    _normalized(actual.note) == _normalized(desired.note);

String? _normalized(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}

bool _isUuid(String value) => RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
).hasMatch(value);
