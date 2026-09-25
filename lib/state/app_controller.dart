import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' hide Category;

import '../core/api_client.dart';
import '../core/app_repository.dart';
import '../core/config_store.dart';
import '../core/money.dart';
import '../core/offline_store.dart';
import '../core/offline_transactions.dart';
import '../models/domain_models.dart';

enum StartupState { connecting, ready, error }

class AppController extends ChangeNotifier {
  static final Object _financialBaselineZoneKey = Object();
  AppController({
    required this.configStore,
    required this.api,
    required this.repository,
    this.offlineStore,
    bool? enableOfflineTransactions,
    int? syncBatchSizeOverride,
    AppConfig? initialConfig,
  }) : config =
           initialConfig ??
           AppConfig(apiBaseUrl: AppConfig.validatedDefaultApiBaseUrl),
       // Public injectable names intentionally differ from private storage.
       // ignore: prefer_initializing_formals
       _enableOfflineTransactions = enableOfflineTransactions,
       // ignore: prefer_initializing_formals
       // ignore: prefer_initializing_formals
       // ignore: prefer_initializing_formals
       _syncBatchSizeOverride = syncBatchSizeOverride;

  final ConfigStore configStore;
  final ApiClient api;
  final AppRepository repository;
  final OfflineStore? offlineStore;
  // Nullable override keeps controllers created before hot reload safe.
  final bool? _enableOfflineTransactions;
  final int? _syncBatchSizeOverride;

  int get _syncBatchSize {
    final override = _syncBatchSizeOverride;
    return override == null ? 100 : override.clamp(1, 100).toInt();
  }

  StartupState startupState = StartupState.connecting;
  AppConfig config;
  HealthStatus? health;
  AppSettings settings = const AppSettings();
  GoldPriceQuote? goldPriceQuote;
  ManualGoldPriceList manualGoldPrices = const ManualGoldPriceList();
  List<Account> accounts = const [];
  List<JewelryItem> jewelryItems = const [];
  List<Category> categories = const [];
  List<TransactionRecord> transactions = const [];
  List<InstallmentPlan> installmentPlans = const [];
  List<CutoffPeriod> cutoffPeriods = const [];
  List<CutoffSchedule> cutoffSchedules = const [];
  ReportSummary? dashboard;
  ReportSummary? reportSummary;
  String selectedPeriod = 'month';
  DateTime anchor = DateTime.now();
  bool isBusy = false;
  bool isRefreshing = false;
  bool isGoldPriceRefreshing = false;
  bool isManualGoldPriceRefreshing = false;
  bool manualGoldPricesLoaded = false;
  String? errorMessage;
  String? goldPriceError;
  String? goldPriceRefreshNotice;
  String? manualGoldPriceError;
  // Nullable so AppController instances created before a hot reload can safely
  // initialize the newly added request sequence on first use.
  int? _dashboardRequestToken;
  // A depth instead of a boolean keeps the loading surface stable when a full
  // refresh owns a nested dashboard request or filters change in quick
  // succession. Nullable backing keeps hot-reloaded controllers safe.
  int? _dashboardRefreshDepth;
  // Nullable backing keeps controllers created before hot reload safe.
  int? _financeScopeRequestToken;
  int? _reportRequestToken;
  int? _transactionsRequestToken;
  int? _installmentPlansRequestToken;
  int? _accountsRequestToken;
  // Nullable backing keeps controllers created before hot reload safe.
  List<AccountTransfer>? _accountTransfers;
  int? _accountTransfersRequestToken;
  List<CreditCardPayment>? _creditCardPayments;
  int? _creditCardPaymentsRequestToken;
  List<SavingsInterestCredit>? _savingsInterestCredits;
  int? _savingsInterestCreditsRequestToken;
  List<JointSplitExpense>? _jointSplitExpenses;
  // Nullable backing keeps controllers created before hot reload safe.
  List<JointParticipant>? _jointParticipants;
  List<JointParticipant>? _archivedJointParticipants;
  List<JointDeal>? _jointDeals;
  List<JointDeal>? _archivedJointDeals;
  List<JointPenalty>? _jointPenalties;
  JointDealsSummary? _jointDealsSummary;
  int? _jointDealsRequestToken;
  String? _lastJointDealsRefreshError;
  Account? _dealsPenaltyMoneyAccountSnapshot;
  int? _dealsPenaltyMoneyBalanceSnapshot;
  bool? _hasDealsPenaltyMoneySnapshot;
  TransactionOutbox? _transactionOutbox;
  bool? _isOffline;
  bool? _isSyncingTransactions;
  String? _offlineBlockingMessage;
  DateTime? _lastSuccessfulSyncAt;
  DateTime? _lastSavedDataAt;
  DateTime? _lastVerifiedInstallationAt;
  Future<bool>? _installationVerification;
  List<TransactionRecord>? _serverTransactions;
  List<Account>? _serverAccounts;
  ReportSummary? _serverDashboard;
  ReportSummary? _serverReportSummary;
  List<CutoffPeriod>? _serverCutoffPeriods;
  int? _offlineSyncRequestToken;
  Future<void>? _outboxMutationQueue;
  Future<void>? _financialBaselineQueue;
  Future<void>? _configMutationQueue;
  bool _disposed = false;
  Map<FinanceScope, Set<String>>? _includedFinancialOperationUuids;
  bool? _settingsBaselineLoaded;
  bool? _accountsBaselineLoaded;
  bool? _categoriesBaselineLoaded;
  bool? _transactionsBaselineLoaded;
  bool? _installmentPlansBaselineLoaded;
  bool? _dashboardBaselineLoaded;
  bool? _cutoffsBaselineLoaded;
  bool? _goldPriceBaselineLoaded;
  bool? _jewelryBaselineLoaded;
  bool? _manualGoldPricesBaselineLoaded;
  bool? _schedulesBaselineLoaded;
  bool? _accountTransfersBaselineLoaded;
  bool? _creditCardPaymentsBaselineLoaded;
  bool? _savingsInterestCreditsBaselineLoaded;
  bool? _jointDealsBaselineLoaded;

  String get currencyCode => settings.currencyCode;
  String get locale => settings.locale;
  FinanceScope get selectedFinanceScope => FinanceScope.personal;
  bool get isJointScope => false;
  List<AccountTransfer> get accountTransfers => _accountTransfers ?? const [];
  List<CreditCardPayment> get creditCardPayments =>
      _creditCardPayments ?? const [];
  List<SavingsInterestCredit> get savingsInterestCredits =>
      _savingsInterestCredits ?? const [];
  List<JointSplitExpense> get jointSplitExpenses =>
      _jointSplitExpenses ?? const [];
  List<Account> get accountTransferAccounts => accounts
      .where(
        (account) =>
            account.scope == selectedFinanceScope &&
            !account.isArchived &&
            account.isTransferAccount &&
            !account.isCreditCard,
      )
      .toList();
  List<Account> get savingsAccounts => accounts
      .where(
        (account) =>
            account.scope == selectedFinanceScope &&
            !account.isArchived &&
            account.isSavingsAccount &&
            !account.isSystem,
      )
      .toList();
  List<Account> get jointSplitExpenseAccounts => accounts
      .where(
        (account) =>
            account.scope == FinanceScope.joint &&
            !account.isArchived &&
            account.isStandardAccount &&
            !account.isCreditCard,
      )
      .toList();
  List<JointParticipant> get jointParticipants =>
      _jointParticipants ?? const [];
  List<JointParticipant> get archivedJointParticipants =>
      _archivedJointParticipants ?? const [];
  List<JointDeal> get jointDeals => _jointDeals ?? const [];
  List<JointDeal> get archivedJointDeals => _archivedJointDeals ?? const [];
  List<JointPenalty> get jointPenalties => _jointPenalties ?? const [];
  Account? get dealsPenaltyMoneyAccount {
    final projectedAccount = accounts
        .where((account) => account.isDealsPenaltyMoney)
        .firstOrNull;
    if (projectedAccount != null &&
        _hasPendingAccountProjection(projectedAccount.id)) {
      return projectedAccount;
    }
    if (_hasDealsPenaltyMoneySnapshot ?? false) {
      return _dealsPenaltyMoneyAccountSnapshot;
    }
    return projectedAccount ?? jointDealsSummary.dealsPenaltyMoneyAccount;
  }

  int get dealsPenaltyMoneyBalanceMinor {
    final projectedAccount = accounts
        .where((account) => account.isDealsPenaltyMoney)
        .firstOrNull;
    if (projectedAccount != null &&
        _hasPendingAccountProjection(projectedAccount.id)) {
      return projectedAccount.balanceMinor;
    }
    if (_hasDealsPenaltyMoneySnapshot ?? false) {
      return _dealsPenaltyMoneyBalanceSnapshot ?? 0;
    }
    return projectedAccount?.balanceMinor ??
        dealsPenaltyMoneyAccount?.balanceMinor ??
        jointDealsSummary.dealsPenaltyMoneyBalanceMinor;
  }

  bool _hasPendingAccountProjection(int accountId) =>
      _projectedOperations(FinanceScope.joint).any(
        (operation) =>
            operation.baseTransaction?.accountId == accountId ||
            operation.desiredTransaction?.accountId == accountId,
      );

  List<Account> get penaltyPaymentSourceAccounts => accounts
      .where(
        (account) =>
            account.scope == FinanceScope.joint &&
            !account.isArchived &&
            account.isStandardAccount &&
            !account.isCreditCard,
      )
      .toList();
  List<Account> get creditCardAccounts => accounts
      .where(
        (account) =>
            account.scope == selectedFinanceScope &&
            !account.isArchived &&
            account.isCreditCard,
      )
      .toList();
  List<Account> get creditCardPaymentSourceAccounts => accounts
      .where(
        (account) =>
            account.scope == selectedFinanceScope &&
            !account.isArchived &&
            account.isStandardAccount &&
            !account.isCreditCard,
      )
      .toList();
  JointDealsSummary get jointDealsSummary =>
      _jointDealsSummary ?? const JointDealsSummary();
  List<Category> get expenseCategories => categories
      .where((category) => category.kind == 'expense' && !category.isArchived)
      .toList();
  List<Category> get standardTransactionExpenseCategories =>
      expenseCategories.where((category) => !category.isSystem).toList();
  List<Category> get incomeCategories => categories
      .where((category) => category.kind == 'income' && !category.isArchived)
      .toList();
  List<Category> get standardTransactionIncomeCategories =>
      incomeCategories.where((category) => !category.isSystem).toList();
  bool get offlineTransactionsEnabled =>
      _enableOfflineTransactions ??
      (offlineStore != null &&
          !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android));
  bool get isOffline => _isOffline ?? api.isOffline;
  bool get hasLiveConnection => !isOffline && !api.cacheOnlyReads;
  bool get isSyncingTransactions => _isSyncingTransactions ?? false;
  String? get offlineBlockingMessage => _offlineBlockingMessage;
  DateTime? get lastSuccessfulSyncAt => _lastSuccessfulSyncAt;
  DateTime? get lastSavedDataAt =>
      _lastSavedDataAt ?? api.lastCachedResponseSavedAt;
  List<OfflineTransactionOperation> get offlineTransactionOperations =>
      _transactionOutbox?.operations ?? const [];
  int get pendingTransactionCount => _transactionOutbox?.pendingCount ?? 0;
  int get transactionConflictCount => _transactionOutbox?.conflictCount ?? 0;
  OfflineTransactionOperation? get firstAttentionTransaction =>
      offlineTransactionOperations
          .where((operation) => operation.needsAttention)
          .firstOrNull;
  int get pendingProjectionCount =>
      _projectedOperations(selectedFinanceScope).length;
  List<OfflineTransactionOperation> get unallocatedCutoffOperations {
    final periods = _serverCutoffPeriods ?? const <CutoffPeriod>[];
    return _projectedOperations(selectedFinanceScope).where((operation) {
      final desired = operation.desiredTransaction;
      if (desired == null || desired.kind != 'expense') return false;
      return !periods.any(
        (period) =>
            period.scope == desired.scope &&
            _within(desired.occurredOn, period.startsOn, period.endsOn),
      );
    }).toList();
  }

  int get unallocatedCutoffPendingMinor => unallocatedCutoffOperations.fold(
    0,
    (total, operation) => total + operation.desiredTransaction!.amountMinor,
  );
  OfflineTransactionOperation? offlineOperationFor(
    TransactionRecord transaction,
  ) => offlineTransactionOperations.where((operation) {
    if (operation.scope != transaction.scope) return false;
    if (transaction.id < 0) {
      return operation.desiredTransaction?.id == transaction.id;
    }
    return operation.serverId == transaction.id ||
        operation.resultTransaction?['id'] == transaction.id;
  }).firstOrNull;
  TransactionRecord? rebasedRetryPreview(
    OfflineTransactionOperation operation,
  ) {
    if (operation.serverTransaction?.isManagedTransaction == true) return null;
    final snapshot = _rebasedRetrySnapshot(operation);
    return snapshot == null ? null : TransactionRecord.fromJson(snapshot);
  }

  bool get offlineCoreReady =>
      (_settingsBaselineLoaded ?? false) &&
      (_accountsBaselineLoaded ?? false) &&
      (_categoriesBaselineLoaded ?? false) &&
      (_transactionsBaselineLoaded ?? false) &&
      (_dashboardBaselineLoaded ?? false) &&
      (_cutoffsBaselineLoaded ?? false);
  bool get offlineTransactionBaselineReady =>
      (_settingsBaselineLoaded ?? false) &&
      (_accountsBaselineLoaded ?? false) &&
      (_categoriesBaselineLoaded ?? false) &&
      (_transactionsBaselineLoaded ?? false);
  bool get canSaveOfflineTransactions =>
      offlineTransactionsEnabled &&
      offlineCoreReady &&
      _offlineBlockingMessage == null &&
      _looksLikeUuid(_transactionOutbox?.installationId ?? '');
  bool _availableBaseline(bool? loaded) =>
      (loaded ?? false) ||
      (offlineStore == null && startupState == StartupState.connecting);
  bool get hasSavedSettings => _availableBaseline(_settingsBaselineLoaded);
  bool get hasSavedAccounts =>
      hasSavedSettings && _availableBaseline(_accountsBaselineLoaded);
  bool get hasSavedCategories => _availableBaseline(_categoriesBaselineLoaded);
  bool get hasSavedTransactions =>
      hasSavedSettings && _availableBaseline(_transactionsBaselineLoaded);
  bool get hasSavedInstallmentPlans =>
      hasSavedSettings && _availableBaseline(_installmentPlansBaselineLoaded);
  bool get hasSavedDashboard =>
      hasSavedSettings && _availableBaseline(_dashboardBaselineLoaded);
  bool get isDashboardRefreshing => (_dashboardRefreshDepth ?? 0) > 0;
  bool get hasSavedCutoffs =>
      hasSavedSettings && _availableBaseline(_cutoffsBaselineLoaded);
  bool get hasSavedGoldPrice =>
      hasSavedSettings && _availableBaseline(_goldPriceBaselineLoaded);
  bool get hasSavedJewelry =>
      hasSavedSettings && _availableBaseline(_jewelryBaselineLoaded);
  bool get hasSavedManualGoldPrices =>
      hasSavedSettings && _availableBaseline(_manualGoldPricesBaselineLoaded);
  bool get hasSavedSchedules =>
      hasSavedSettings && _availableBaseline(_schedulesBaselineLoaded);
  bool get hasSavedAccountTransfers =>
      hasSavedSettings && _availableBaseline(_accountTransfersBaselineLoaded);
  bool get hasSavedCreditCardPayments =>
      hasSavedSettings && _availableBaseline(_creditCardPaymentsBaselineLoaded);
  bool get hasSavedSavingsInterestCredits =>
      hasSavedSettings &&
      _availableBaseline(_savingsInterestCreditsBaselineLoaded);
  bool get hasSavedJointDeals =>
      hasSavedSettings && _availableBaseline(_jointDealsBaselineLoaded);

  Future<void> initialize() async {
    startupState = StartupState.connecting;
    errorMessage = null;
    _resetLoadedStateForReconnect();
    notifyListeners();
    try {
      config = await configStore.load();
      health = await repository.health();
      await _accrueSavingsInterestUnlocked(refreshSnapshots: false);
      await _loadSettings();
      await Future.wait([
        _loadAccounts(),
        _loadCategories(),
        _loadJewelry(),
        _loadManualGoldPrices(),
        _loadSchedules(),
        refreshInstallmentPlans(silent: true),
        refreshTransactions(silent: true, propagateError: true),
        refreshCutoffs(silent: true, propagateError: true),
        refreshDashboard(silent: true, propagateError: true),
        _loadGoldPrice(),
      ]);
      startupState = StartupState.ready;
    } catch (error) {
      startupState = StartupState.error;
      errorMessage = _message(error);
    }
    notifyListeners();
  }

  Future<void> reconnect() => initialize();

  Future<String> exportBackup() => api.database.exportBackup();

  Future<void> importBackup(String data) async {
    if (isBusy || isRefreshing) {
      throw const FormatException(
        'Wait for the current action to finish before restoring.',
      );
    }
    await api.database.importBackup(data);
    await initialize();
    if (startupState == StartupState.error) {
      throw FormatException(
        errorMessage ?? 'Unable to read the restored data.',
      );
    }
  }

  Future<void> clearSavedOfflineData() async {
    final store = offlineStore;
    if (store == null) return;
    if (_transactionOutbox?.hasOperations == true) {
      throw const FormatException(
        'Sync or resolve pending transaction changes before clearing saved responses. Pending changes were not deleted.',
      );
    }
    await store.clearCachedResponses();
    _lastSavedDataAt = null;
    notifyListeners();
  }

  Future<void> discardAllOfflineChanges(String confirmation) async {
    if (confirmation.trim() != 'DISCARD') {
      throw const FormatException('Type DISCARD to confirm this action.');
    }
    final store = offlineStore;
    if (store == null) return;
    final cacheId = await store.cacheInstallationId();
    final empty = TransactionOutbox(
      installationId: cacheId != null && _looksLikeUuid(cacheId)
          ? cacheId.toLowerCase()
          : null,
    );
    await store.clearCachedResponses();
    // The cache is disposable; the outbox is not. Clear cached responses first
    // so a cache write failure can never discard a pending financial intent.
    await store.saveOutbox(empty.toSnapshot());
    _transactionOutbox = empty;
    _offlineBlockingMessage = null;
    _resetLoadedStateForReconnect();
    errorMessage = 'Saved offline changes and cached responses were discarded from this device. Reconnect to reload data.';
    notifyListeners();
  }

  Future<void> _captureOptional(Future<void> operation) async {
    try {
      await operation;
    } catch (_) {
      // A missing optional cache keeps only that screen unavailable.
    }
  }

  void _resetLoadedStateForReconnect() {
    _settingsBaselineLoaded = false;
    _accountsBaselineLoaded = false;
    _categoriesBaselineLoaded = false;
    _transactionsBaselineLoaded = false;
    _installmentPlansBaselineLoaded = false;
    _dashboardBaselineLoaded = false;
    _cutoffsBaselineLoaded = false;
    _goldPriceBaselineLoaded = false;
    _jewelryBaselineLoaded = false;
    _manualGoldPricesBaselineLoaded = false;
    _schedulesBaselineLoaded = false;
    _accountTransfersBaselineLoaded = false;
    _creditCardPaymentsBaselineLoaded = false;
    _savingsInterestCreditsBaselineLoaded = false;
    _jointDealsBaselineLoaded = false;
    _serverAccounts = null;
    _serverTransactions = null;
    _serverDashboard = null;
    _serverReportSummary = null;
    _serverCutoffPeriods = null;
    health = null;
    settings = const AppSettings();
    goldPriceQuote = null;
    manualGoldPrices = const ManualGoldPriceList();
    manualGoldPricesLoaded = false;
    accounts = const [];
    jewelryItems = const [];
    categories = const [];
    transactions = const [];
    installmentPlans = const [];
    dashboard = null;
    reportSummary = null;
    cutoffPeriods = const [];
    cutoffSchedules = const [];
    _accountTransfers = const [];
    _creditCardPayments = const [];
    _savingsInterestCredits = const [];
    _jointSplitExpenses = const [];
    _jointParticipants = const [];
    _archivedJointParticipants = const [];
    _jointDeals = const [];
    _archivedJointDeals = const [];
    _jointPenalties = const [];
    _jointDealsSummary = null;
    _clearDealsPenaltyMoneySnapshot();
    _includedFinancialOperationUuids = null;
    _lastSavedDataAt = null;
    _lastVerifiedInstallationAt = null;
    _installationVerification = null;
    _dashboardRequestToken = (_dashboardRequestToken ?? 0) + 1;
    _transactionsRequestToken = (_transactionsRequestToken ?? 0) + 1;
    _installmentPlansRequestToken = (_installmentPlansRequestToken ?? 0) + 1;
    _accountsRequestToken = (_accountsRequestToken ?? 0) + 1;
    _savingsInterestCreditsRequestToken =
        (_savingsInterestCreditsRequestToken ?? 0) + 1;
    _reportRequestToken = (_reportRequestToken ?? 0) + 1;
    _jointDealsRequestToken = (_jointDealsRequestToken ?? 0) + 1;
  }

  Future<void> _acceptVerifiedInstallation(String? installationId) async {
    final normalized = installationId?.trim().toLowerCase();
    if (normalized == null || !_looksLikeUuid(normalized)) {
      if (offlineTransactionsEnabled) {
        throw const ApiException(
          message: 'This API does not expose an installation identity required for safe offline transactions.',
        );
      }
      return;
    }
    final store = offlineStore;
    final outbox = _transactionOutbox;
    final previous = outbox?.installationId;
    final previousCacheIdentity = api.cacheNamespace?.trim().toLowerCase();
    final identityChanged =
        (previous ?? previousCacheIdentity) != null &&
        (previous ?? previousCacheIdentity) != normalized;
    if (outbox != null &&
        outbox.hasOperations &&
        (previous == null || previous != normalized)) {
      _offlineBlockingMessage = previous == null
          ? 'Pending transactions are not bound to a verified Budget Flow database. They were kept and will not be sent automatically.'
          : 'This address now points to a different Budget Flow database. Pending transactions were kept and will not be sent.';
      throw ApiException(
        message: _offlineBlockingMessage!,
        statusCode: 409,
        code: 'INSTANCE_MISMATCH',
      );
    }
    if (store != null) {
      await store.bindCacheInstallation(normalized);
    }
    api.cacheNamespace = normalized;
    if (outbox != null && previous != normalized) {
      final next = TransactionOutbox.fromSnapshot(
        outbox.toSnapshot(),
        recoverInFlight: false,
      )..installationId = normalized;
      await store?.saveOutbox(next.toSnapshot());
      _transactionOutbox = next;
    }
    if (identityChanged) {
      _resetLoadedStateForReconnect();
    }
    _lastVerifiedInstallationAt = DateTime.now().toUtc();
    _offlineBlockingMessage = null;
  }

  Future<void> updateThemePreference(AppThemePreference value) =>
      _withConfigLock(() async {
        if (value == config.themePreference) return;
        final nextConfig = config.copyWith(themePreference: value);
        await configStore.save(nextConfig);
        config = nextConfig;
        notifyListeners();
      });

  void _beginDashboardRefresh() {
    _dashboardRefreshDepth = (_dashboardRefreshDepth ?? 0) + 1;
  }

  void _endDashboardRefresh() {
    _dashboardRefreshDepth = max(0, (_dashboardRefreshDepth ?? 0) - 1);
  }

  Future<void> setPeriod(String value) async {
    if (value == selectedPeriod) return;
    selectedPeriod = value;
    _dashboardBaselineLoaded = false;
    reportSummary = null;
    _serverReportSummary = null;
    errorMessage = null;
    await refreshDashboard();
  }

  Future<void> setFinanceScope(FinanceScope value) async {
    if (value != FinanceScope.personal) {
      throw const FormatException('Only personal accounts are supported.');
    }
  }

  Future<void> setAnchor(DateTime value) async {
    final nextAnchor = DateTime(value.year, value.month, value.day);
    if (nextAnchor == DateTime(anchor.year, anchor.month, anchor.day)) return;
    anchor = nextAnchor;
    _dashboardBaselineLoaded = false;
    _cutoffsBaselineLoaded = false;
    reportSummary = null;
    cutoffPeriods = const [];
    _serverReportSummary = null;
    _serverCutoffPeriods = const [];
    errorMessage = null;
    await Future.wait([refreshDashboard(), refreshCutoffs(silent: true)]);
  }

  Future<void> moveAnchor(int direction) {
    final next = switch (selectedPeriod) {
      'week' => anchor.add(Duration(days: 7 * direction)),
      'year' => DateTime(anchor.year + direction, anchor.month, anchor.day),
      'cutoff' when dashboard != null && hasSavedDashboard =>
        direction < 0
            ? dashboard!.startsOn.subtract(const Duration(days: 1))
            : dashboard!.endsOn.add(const Duration(days: 1)),
      'cutoff' => anchor.add(Duration(days: 15 * direction)),
      _ => DateTime(anchor.year, anchor.month + direction, 1),
    };
    return setAnchor(next);
  }

  Future<void> goToToday() => setAnchor(DateTime.now());

  Future<void> refreshAll() async {
    final scopeGeneration = _financeScopeRequestToken ?? 0;
    isRefreshing = true;
    _beginDashboardRefresh();
    errorMessage = null;
    goldPriceRefreshNotice = null;
    notifyListeners();
    try {
      await _withFinancialBaselineLock(() async {
        await _restoreNetworkReadsIfNeeded();
        await _verifyBoundInstallation(force: true);
        String? automaticInterestWarning;
        try {
          await _accrueSavingsInterestUnlocked(refreshSnapshots: false);
        } catch (error) {
          automaticInterestWarning = _automaticInterestWarning(error);
        }
        await _loadGoldPrice();
        final tasks = <Future<void>>[
          _loadAccounts(),
          _loadJewelry(),
          _loadManualGoldPrices(),
          _loadCategories(),
          _loadSchedules(),
          refreshDashboard(silent: true),
          refreshTransactions(silent: true),
          _captureOptional(refreshInstallmentPlans(silent: true)),
          refreshCutoffs(silent: true),
        ];
        if (isJointScope) tasks.add(refreshJointDeals(silent: true));
        if (_accountTransfers != null) {
          tasks.add(refreshAccountTransfers(silent: true));
        }
        if (_creditCardPayments != null) {
          tasks.add(refreshCreditCardPayments(silent: true));
        }
        if (_savingsInterestCredits != null) {
          tasks.add(refreshSavingsInterestCredits(silent: true));
        }
        await Future.wait(tasks);
        if (automaticInterestWarning != null &&
            _isCurrentScopeGeneration(scopeGeneration)) {
          errorMessage = automaticInterestWarning;
        }
      });
    } catch (error) {
      if (_isCurrentScopeGeneration(scopeGeneration)) {
        errorMessage = _message(error);
      }
    } finally {
      _endDashboardRefresh();
      if (_isCurrentScopeGeneration(scopeGeneration)) {
        isRefreshing = false;
      }
      notifyListeners();
    }
  }

  Future<void> refreshHealth() =>
      _withFinancialBaselineLock(_refreshHealthUnlocked);

  Future<void> _refreshHealthUnlocked() async {
    isRefreshing = true;
    notifyListeners();
    try {
      await _loadHealth();
      final checked = health;
      if (checked?.ok == true) {
        await _acceptVerifiedInstallation(checked?.installationId);
        // Accepting a new empty installation resets all loaded domains. Keep
        // the health result that authorized that reset visible to the user.
        health = checked;
        api.cacheOnlyReads = false;
        _isOffline = false;
      } else {
        // A reachable API with an unavailable database is still offline for
        // financial reads. Keep exact cached data isolated until a later
        // healthy identity probe succeeds.
        api.cacheOnlyReads = true;
        _isOffline = true;
      }
      errorMessage = health?.ok == true ? null : health?.message;
    } catch (error) {
      errorMessage = _message(error);
    } finally {
      isRefreshing = false;
      notifyListeners();
    }
  }

  Future<void> refreshDashboard({
    bool silent = false,
    bool propagateError = false,
  }) async {
    final scopeGeneration = _financeScopeRequestToken ?? 0;
    _beginDashboardRefresh();
    if (!silent) {
      isRefreshing = true;
    }
    notifyListeners();
    try {
      final applied = await _loadDashboard();
      if (applied) {
        _dashboardBaselineLoaded = true;
        errorMessage = null;
      }
    } catch (error) {
      if (_isCurrentScopeGeneration(scopeGeneration)) {
        errorMessage = _message(error);
        if (!silent || propagateError) rethrow;
      }
    } finally {
      _endDashboardRefresh();
      if (!silent && _isCurrentScopeGeneration(scopeGeneration)) {
        isRefreshing = false;
      }
      notifyListeners();
    }
  }

  Future<void> loadReport(
    String period, {
    bool propagateError = false,
    bool networkOnly = false,
  }) => _withFinancialBaselineLock(
    () => _loadReportUnlocked(
      period,
      propagateError: propagateError,
      networkOnly: networkOnly,
    ),
  );

  Future<void> _loadReportUnlocked(
    String period, {
    bool propagateError = false,
    bool networkOnly = false,
  }) async {
    final requestedScope = selectedFinanceScope;
    await _verifyBoundInstallation(force: true);
    _requireSafeFinancialBaselineRead(requestedScope);
    final requestedAnchor = DateTime(anchor.year, anchor.month, anchor.day);
    final scopeGeneration = _financeScopeRequestToken ?? 0;
    final requestToken = (_reportRequestToken ?? 0) + 1;
    _reportRequestToken = requestToken;
    reportSummary = null;
    isRefreshing = true;
    notifyListeners();
    try {
      final loaded = await repository.report(
        period: period,
        anchor: requestedAnchor,
        scope: requestedScope,
        networkOnly: networkOnly,
      );
      if (loaded.scope != requestedScope ||
          !loaded.hasConsistentAccountMoneyMetadata ||
          loaded.recentTransactions.any(
            (transaction) =>
                transaction.account?.hasConsistentClassificationMetadata ==
                false,
          )) {
        throw ApiException(
          message: 'The report returned inconsistent account or savings totals. Refresh and try again.',
        );
      }
      if (requestedScope == FinanceScope.joint &&
          loaded.hasJointObligations &&
          _hasUnsafeJointObligations(loaded.jointObligations)) {
        throw ApiException(
          message: 'The report returned inconsistent penalty cash effects. Refresh and try again.',
        );
      }
      if (_hasUnsafeJointSplitProjections(loaded.recentTransactions)) {
        throw ApiException(
          message: 'The report returned an unsafe split-expense component or total. Refresh and try again.',
        );
      }
      if (_isCurrentReportRequest(
        requestToken,
        period,
        requestedAnchor,
        requestedScope,
        scopeGeneration,
      )) {
        _serverReportSummary = loaded;
        reportSummary = _projectReportSummary(loaded);
        errorMessage = null;
      }
    } catch (error) {
      if (_isCurrentReportRequest(
        requestToken,
        period,
        requestedAnchor,
        requestedScope,
        scopeGeneration,
      )) {
        errorMessage = _message(error);
        if (propagateError) rethrow;
      }
    } finally {
      if (_isCurrentReportRequest(
        requestToken,
        period,
        requestedAnchor,
        requestedScope,
        scopeGeneration,
      )) {
        isRefreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshTransactions({
    bool silent = false,
    bool propagateError = false,
    bool networkOnly = false,
  }) => _withFinancialBaselineLock(
    () => _refreshTransactionsUnlocked(
      silent: silent,
      propagateError: propagateError,
      networkOnly: networkOnly,
    ),
  );

  Future<void> refreshInstallmentPlans({
    bool silent = false,
    bool propagateError = false,
  }) async {
    final requestedScope = selectedFinanceScope;
    final scopeGeneration = _financeScopeRequestToken ?? 0;
    final requestToken = (_installmentPlansRequestToken ?? 0) + 1;
    _installmentPlansRequestToken = requestToken;
    if (!silent) {
      isRefreshing = true;
      notifyListeners();
    }
    try {
      await _verifyBoundInstallation(force: true);
      final loaded = <InstallmentPlan>[];
      var page = 1;
      var lastPage = 1;
      int? expectedTotal;
      do {
        final result = await repository.installmentPlans(
          scope: requestedScope,
          page: page,
          perPage: 100,
        );
        if (result.currentPage != page ||
            result.lastPage < page ||
              (page > 1 && result.lastPage != lastPage) ||
            (expectedTotal != null && result.total != expectedTotal)) {
          throw const FormatException(
            'Installment plans changed while their pages were loading.',
          );
        }
        loaded.addAll(result.items);
        lastPage = result.lastPage;
        expectedTotal ??= result.total;
        page += 1;
      } while (page <= lastPage);
      final ids = <int>{};
      if (loaded.length != expectedTotal ||
          loaded.length > 10000 ||
          loaded.any(
            (plan) =>
                !ids.add(plan.id) ||
                _invalidInstallmentPlan(plan, requestedScope),
          )) {
        throw const FormatException(
          'Installment plans were incomplete or inconsistent.',
        );
      }
      if (requestToken == (_installmentPlansRequestToken ?? 0) &&
          _isCurrentScopedRequest(requestedScope, scopeGeneration)) {
        installmentPlans = loaded
          ..sort((first, second) {
            final firstDate = first.nextPaymentOn ?? first.installmentStartOn;
            final secondDate =
                second.nextPaymentOn ?? second.installmentStartOn;
            final byDate = firstDate.compareTo(secondDate);
            return byDate != 0 ? byDate : first.id.compareTo(second.id);
          });
        _installmentPlansBaselineLoaded = true;
        errorMessage = null;
      }
    } catch (error) {
      if (requestToken == (_installmentPlansRequestToken ?? 0) &&
          _isCurrentScopedRequest(requestedScope, scopeGeneration)) {
        _installmentPlansBaselineLoaded = false;
        if (!silent || propagateError) {
          errorMessage = _message(error);
          if (propagateError) rethrow;
        }
      }
    } finally {
      if (!silent &&
          requestToken == (_installmentPlansRequestToken ?? 0) &&
          _isCurrentScopedRequest(requestedScope, scopeGeneration)) {
        isRefreshing = false;
        notifyListeners();
      }
    }
  }

  bool _invalidInstallmentPlan(
    InstallmentPlan plan,
    FinanceScope expectedScope,
  ) =>
      plan.id <= 0 ||
      plan.clientUuid.trim().isEmpty ||
      plan.scope != expectedScope ||
      plan.accountId <= 0 ||
      plan.categoryId <= 0 ||
      plan.installmentMonthlyMinor <= 0 ||
      plan.installmentMonths < 2 ||
      plan.installmentMonths > 120 ||
      plan.downPaymentMinor < 0 ||
      plan.downPaymentMinor > Money.maxMinorUnits ||
      plan.scheduledTotalMinor !=
          plan.installmentMonthlyMinor * plan.installmentMonths ||
      plan.scheduledRemainingMinor !=
          plan.installmentMonthlyMinor * plan.remainingInstallments ||
      plan.contractTotalMinor !=
          plan.downPaymentMinor + plan.scheduledTotalMinor ||
      plan.totalPaidMinor !=
          plan.downPaymentMinor +
              plan.installmentMonthlyMinor * plan.paidInstallments ||
      plan.remainingObligationMinor != plan.scheduledRemainingMinor ||
      (plan.hasDownPayment &&
          (plan.downPaymentPaidOn == null ||
              plan.downPaymentTransaction == null ||
              !plan.downPaymentTransaction!.isManagedInstallmentDownPayment ||
              plan.downPaymentTransaction!.installmentPlanId != plan.id ||
              plan.downPaymentTransaction!.scope != plan.scope ||
              plan.downPaymentTransaction!.amountMinor !=
                  plan.downPaymentMinor)) ||
      (!plan.hasDownPayment &&
          (plan.downPaymentPaidOn != null ||
              plan.downPaymentTransaction != null)) ||
      plan.version <= 0 ||
      plan.paidInstallments < 0 ||
      plan.paidInstallments > plan.installmentMonths ||
      plan.remainingInstallments !=
          plan.installmentMonths - plan.paidInstallments ||
      !const {'active', 'completed', 'archived'}.contains(plan.status) ||
      (plan.isActive &&
          (plan.remainingInstallments <= 0 ||
              plan.nextInstallmentNumber == null ||
              plan.nextInstallmentNumber != plan.paidInstallments + 1 ||
              plan.nextPaymentOn == null));

  Future<void> _refreshTransactionsUnlocked({
    required bool silent,
    required bool propagateError,
    required bool networkOnly,
  }) async {
    final requestedScope = selectedFinanceScope;
    await _verifyBoundInstallation(force: true);
    _requireSafeFinancialBaselineRead(requestedScope);
    final scopeGeneration = _financeScopeRequestToken ?? 0;
    final requestToken = (_transactionsRequestToken ?? 0) + 1;
    _transactionsRequestToken = requestToken;
    if (!silent) {
      isRefreshing = true;
      notifyListeners();
    }
    try {
      final loadedTransactions = await _loadAllTransactions(
        requestedScope,
        networkOnly: networkOnly,
      );
      if (_hasUnsafeJointSplitProjections(loadedTransactions)) {
        throw ApiException(
          message: 'Split expense history returned a component or inconsistent logical expense. Refresh and try again.',
        );
      }
      if (requestToken == (_transactionsRequestToken ?? 0) &&
          _isCurrentScopedRequest(requestedScope, scopeGeneration)) {
        final seenSplitIds = <int>{};
        final serverTransactions = loadedTransactions.where((transaction) {
          if (transaction.scope != requestedScope) return false;
          if (!transaction.isManagedJointSplitExpense) return true;
          return seenSplitIds.add(transaction.sourceId!);
        }).toList();
        _serverTransactions = serverTransactions;
        transactions = _projectTransactionHistory(
          serverTransactions,
          requestedScope,
        );
        _jointSplitExpenses = [
          for (final transaction in transactions)
            if (transaction.isJointSplitExpenseAggregate &&
                transaction.jointSplitExpense != null)
              transaction.jointSplitExpense!,
        ];
        _transactionsBaselineLoaded = true;
        errorMessage = null;
      }
    } catch (error) {
      if (requestToken == (_transactionsRequestToken ?? 0) &&
          _isCurrentScopedRequest(requestedScope, scopeGeneration)) {
        errorMessage = _message(error);
        if (!silent || propagateError) rethrow;
      }
    } finally {
      if (!silent &&
          requestToken == (_transactionsRequestToken ?? 0) &&
          _isCurrentScopedRequest(requestedScope, scopeGeneration)) {
        isRefreshing = false;
        notifyListeners();
      }
    }
  }

  Future<List<TransactionRecord>> _loadAllTransactions(
    FinanceScope scope, {
    bool networkOnly = false,
  }) async {
    final store = offlineStore;
    if (networkOnly) {
      final loaded = await _loadTransactionPages(
        scope,
        networkOnly: true,
        savePages: store == null
            ? null
            : (pages) => store.saveDataset(
                _offlineDatasetKey('transactions', scope),
                pages: pages,
                scope: scope.apiValue,
              ),
      );
      _lastSavedDataAt = DateTime.now().toUtc();
      return loaded;
    }
    if (store == null) return _loadTransactionPages(scope, networkOnly: false);
    final included = await store.includedFinancialOperationUuids(
      scope.apiValue,
    );
    (_includedFinancialOperationUuids ??=
            <FinanceScope, Set<String>>{})[scope] =
        included;
    final key = _offlineDatasetKey('transactions', scope);
    if (api.cacheOnlyReads) {
      final cached = await store.cachedDataset(key);
      if (cached == null || cached.scope != scope.apiValue) {
        throw const ApiException(
          message: 'Transaction history has not been saved on this device.',
          isConnectionError: true,
        );
      }
      final loaded = _parseTransactionPages(cached.pages, scope);
      _lastSavedDataAt = cached.savedAt;
      return loaded;
    }
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final loaded = await _loadTransactionPages(
          scope,
          networkOnly: true,
          savePages: (pages) async {
            await store.saveDataset(key, pages: pages, scope: scope.apiValue);
          },
        );
        _lastSavedDataAt = DateTime.now().toUtc();
        return loaded;
      } catch (error) {
        lastError = error;
        if (error is ApiException && !error.isConnectionError) rethrow;
        if (error is ApiException && error.isConnectionError) break;
        if (error is! ApiException && error is! FormatException) rethrow;
      }
    }
    final cached = await store.cachedDataset(key);
    if (cached == null || cached.scope != scope.apiValue) {
      throw lastError ??
          const ApiException(
            message: 'No saved transaction history is available offline.',
            isConnectionError: true,
          );
    }
    final loaded = _parseTransactionPages(cached.pages, scope);
    _lastSavedDataAt = cached.savedAt;
    _isOffline = true;
    return loaded;
  }

  Future<List<TransactionRecord>> _loadTransactionPages(
    FinanceScope scope, {
    required bool networkOnly,
    Future<void> Function(List<Object?> pages)? savePages,
  }) async {
    final loaded = <TransactionRecord>[];
    final pages = <Object?>[];
    var page = 1;
    var lastPage = 1;
    int? expectedTotal;
    do {
      final result = await repository.transactions(
        scope: scope,
        page: page,
        perPage: 100,
        networkOnly: networkOnly,
      );
      if (result.currentPage != page ||
          result.lastPage < page ||
          (page > 1 && result.lastPage != lastPage) ||
          (expectedTotal != null && result.total != expectedTotal)) {
        throw const FormatException(
          'Transaction history changed while its pages were loading.',
        );
      }
      loaded.addAll(result.items);
      lastPage = result.lastPage;
      expectedTotal ??= result.total;
      if (result.rawResponse != null) pages.add(result.rawResponse);
      page += 1;
    } while (page <= lastPage);
    _validateCompleteTransactions(loaded, expectedTotal, scope);
    if (savePages != null) await savePages(pages);
    return loaded;
  }

  List<TransactionRecord> _parseTransactionPages(
    List<Object?> pages,
    FinanceScope scope,
  ) {
    if (pages.isEmpty) {
      throw const FormatException('Saved transaction history is incomplete.');
    }
    final loaded = <TransactionRecord>[];
    int? expectedTotal;
    for (var index = 0; index < pages.length; index++) {
      final result = repository.transactionsFromResponse(
        pages[index],
        fallbackPage: index + 1,
      );
      if (result.currentPage != index + 1 ||
          result.lastPage != pages.length ||
          (expectedTotal != null && result.total != expectedTotal)) {
        throw const FormatException('Saved transaction pages do not match.');
      }
      expectedTotal ??= result.total;
      loaded.addAll(result.items);
    }
    _validateCompleteTransactions(
      loaded,
      expectedTotal ?? loaded.length,
      scope,
    );
    return loaded;
  }

  void _validateCompleteTransactions(
    List<TransactionRecord> loaded,
    int expectedTotal,
    FinanceScope scope,
  ) {
    final ids = <int>{};
    if (loaded.length != expectedTotal ||
        loaded.length > 10000 ||
        loaded.any(
          (item) =>
              item.id <= 0 ||
              item.scope != scope ||
              item.account?.hasConsistentClassificationMetadata == false ||
              !ids.add(item.id),
        )) {
      throw const FormatException(
        'Transaction history was incomplete or inconsistent.',
      );
    }
  }

  String _offlineDatasetKey(String name, FinanceScope scope) =>
      '${_transactionOutbox?.installationId ?? api.cacheNamespace ?? 'unbound'}|$name|${scope.apiValue}';

  List<TransactionRecord> _projectTransactionHistory(
    List<TransactionRecord> server,
    FinanceScope scope,
  ) {
    final projected = <int, TransactionRecord>{
      for (final transaction in server) transaction.id: transaction,
    };
    for (final operation in offlineTransactionOperations.where(
      (item) => item.scope == scope && item.isPendingProjection,
    )) {
      if (operation.status == OfflineOperationStatus.applied &&
          (_includedFinancialOperationUuids?[scope] ?? const <String>{})
              .contains(operation.operationUuid)) {
        continue;
      }
      switch (operation.action) {
        case OfflineTransactionAction.create:
          final desired = operation.desiredTransaction;
          if (desired != null) projected[desired.id] = desired;
        case OfflineTransactionAction.update:
          final desired = operation.desiredTransaction;
          if (desired != null) projected[operation.serverId!] = desired;
        case OfflineTransactionAction.delete:
          projected.remove(operation.serverId);
      }
    }
    final result = projected.values.toList()
      ..sort((first, second) {
        final date = second.occurredOn.compareTo(first.occurredOn);
        return date != 0 ? date : second.id.compareTo(first.id);
      });
    return result;
  }

  List<OfflineTransactionOperation> _projectedOperations(FinanceScope scope) =>
      offlineTransactionOperations.where((operation) {
        if (operation.scope != scope || !operation.isPendingProjection) {
          return false;
        }
        return operation.status != OfflineOperationStatus.applied ||
            !(_includedFinancialOperationUuids?[scope] ?? const <String>{})
                .contains(operation.operationUuid);
      }).toList();

  List<Account> _projectAccounts(
    List<Account> server,
    FinanceScope scope, {
    DateTime? through,
  }) {
    if (!offlineTransactionsEnabled) return [...server];
    final deltas = <int, int>{};
    for (final operation in _projectedOperations(scope)) {
      final base = operation.baseTransaction;
      final desired = operation.desiredTransaction;
      if (base != null &&
          base.accountId != null &&
          (through == null || !base.occurredOn.isAfter(through))) {
        deltas.update(
          base.accountId!,
          (value) => value - _cashEffect(base),
          ifAbsent: () => -_cashEffect(base),
        );
      }
      if (desired != null &&
          desired.accountId != null &&
          (through == null || !desired.occurredOn.isAfter(through))) {
        deltas.update(
          desired.accountId!,
          (value) => value + _cashEffect(desired),
          ifAbsent: () => _cashEffect(desired),
        );
      }
    }
    return server
        .map(
          (account) => Account(
            id: account.id,
            name: account.name,
            type: account.type,
            openingBalanceMinor: account.openingBalanceMinor,
            balanceMinor: account.balanceMinor + (deltas[account.id] ?? 0),
            color: account.color,
            isArchived: account.isArchived,
            cardDesign: account.cardDesign,
            scope: account.scope,
            systemKey: account.systemKey,
            accountRole: account.accountRole,
            isSystem: account.isSystem,
            isLiability: account.isLiability,
            isSavings: account.isSavingsAccount,
            countsTowardAvailableMoney: account.countsTowardAvailableMoney,
            openingDebtMinor: account.openingDebtMinor,
            creditLimitMinor: account.creditLimitMinor,
            statementDay: account.statementDay,
            dueDay: account.dueDay,
            debtMinor: account.isCreditCard
                ? (-(account.balanceMinor + (deltas[account.id] ?? 0))).clamp(
                    0,
                    Money.maxMinorUnits,
                  )
                : 0,
            availableCreditMinor: account.creditLimitMinor == null
                ? null
                : max(
                    0,
                    account.creditLimitMinor! -
                        (account.isCreditCard
                            ? (-(account.balanceMinor +
                                      (deltas[account.id] ?? 0)))
                                  .clamp(0, Money.maxMinorUnits)
                            : 0),
                  ),
          ),
        )
        .toList();
  }

  ReportSummary _projectReportSummary(ReportSummary server) {
    if (!offlineTransactionsEnabled) return server;
    var incomeDelta = 0;
    var expenseDelta = 0;
    var cashDelta = 0;
    var availableMoneyDelta = 0;
    final activeAccounts = {
      for (final account in server.accounts) account.id: account,
    };
    for (final operation in _projectedOperations(server.scope)) {
      final base = operation.baseTransaction;
      final desired = operation.desiredTransaction;
      if (base != null) {
        if (!base.occurredOn.isAfter(server.endsOn) &&
            activeAccounts.containsKey(base.accountId) &&
            activeAccounts[base.accountId]?.isCreditCard != true) {
          cashDelta -= _cashEffect(base);
          if (activeAccounts[base.accountId]?.countsTowardAvailableMoney ==
              true) {
            availableMoneyDelta -= _cashEffect(base);
          }
        }
        if (_within(base.occurredOn, server.startsOn, server.endsOn)) {
          if (base.kind == 'income') {
            incomeDelta -= base.amountMinor;
          } else {
            expenseDelta -= base.amountMinor;
          }
        }
      }
      if (desired != null) {
        if (!desired.occurredOn.isAfter(server.endsOn) &&
            activeAccounts.containsKey(desired.accountId) &&
            activeAccounts[desired.accountId]?.isCreditCard != true) {
          cashDelta += _cashEffect(desired);
          if (activeAccounts[desired.accountId]?.countsTowardAvailableMoney ==
              true) {
            availableMoneyDelta += _cashEffect(desired);
          }
        }
        if (_within(desired.occurredOn, server.startsOn, server.endsOn)) {
          if (desired.kind == 'income') {
            incomeDelta += desired.amountMinor;
          } else {
            expenseDelta += desired.amountMinor;
          }
        }
      }
    }
    final income = server.incomeMinor + incomeDelta;
    final expense = server.expenseMinor + expenseDelta;
    final remaining = server.hasBudget
        ? server.remainingBudgetMinor - expenseDelta
        : server.remainingBudgetMinor;
    final projectedAccounts = _projectAccounts(
      server.accounts,
      server.scope,
      through: server.endsOn,
    );
    final projectedRecent =
        _projectTransactionHistory(
              _serverTransactions ?? server.recentTransactions,
              server.scope,
            )
            .where(
              (item) =>
                  _within(item.occurredOn, server.startsOn, server.endsOn),
            )
            .take(10)
            .toList();
    final projectedDebt = projectedAccounts
        .where((account) => account.isCreditCard)
        .fold<int>(0, (sum, account) => sum + account.debtMinor);
    final serverObligations = server.hasJointObligations
        ? server.jointObligations
        : null;
    final projectedFund = projectedAccounts
        .where((account) => account.isDealsPenaltyMoney)
        .firstOrNull;
    final projectedObligations = serverObligations == null
        ? null
        : JointObligationsSummary(
            outstandingAllTimeMinor: serverObligations.outstandingAllTimeMinor,
            outstandingAllTimeOccurrences:
                serverObligations.outstandingAllTimeOccurrences,
            outstandingAllTimeEntries:
                serverObligations.outstandingAllTimeEntries,
            assessedInPeriodMinor: serverObligations.assessedInPeriodMinor,
            topParticipant: serverObligations.topParticipant,
            topDeal: serverObligations.topDeal,
            penaltyFundAccount:
                projectedFund ?? serverObligations.penaltyFundAccount,
            dealsPenaltyMoneyAccount:
                projectedFund ?? serverObligations.dealsPenaltyMoneyAccount,
            penaltyFundBalanceMinor:
                projectedFund?.balanceMinor ??
                serverObligations.penaltyFundBalanceMinor,
            dealsPenaltyMoneyBalanceMinor:
                projectedFund?.balanceMinor ??
                serverObligations.dealsPenaltyMoneyBalanceMinor,
            externalDepositsInPeriodMinor:
                serverObligations.externalDepositsInPeriodMinor,
            externalDepositReversalsInPeriodMinor:
                serverObligations.externalDepositReversalsInPeriodMinor,
            netExternalDepositAdjustmentInPeriodMinor:
                serverObligations.netExternalDepositAdjustmentInPeriodMinor,
            affectsAccountBalance: serverObligations.affectsAccountBalance,
            affectsTotalCashBalance: serverObligations.affectsTotalCashBalance,
            affectsIndividualAccountBalances:
                serverObligations.affectsIndividualAccountBalances,
            affectsCashflow: serverObligations.affectsCashflow,
            affectsBudget: serverObligations.affectsBudget,
          );
    return ReportSummary(
      period: server.period,
      label: server.label,
      startsOn: server.startsOn,
      endsOn: server.endsOn,
      incomeMinor: income,
      expenseMinor: expense,
      netMinor: income - expense,
      hasBudget: server.hasBudget,
      budgetMinor: server.budgetMinor,
      remainingBudgetMinor: remaining,
      cashBalanceMinor: server.cashBalanceMinor + cashDelta,
      availableMoneyMinor: server.availableMoneyMinor + availableMoneyDelta,
      savingsBalanceMinor: projectedAccounts
          .where((account) => account.isSavingsAccount)
          .fold<int>(0, (sum, account) => sum + account.balanceMinor),
      creditCardDebtMinor: projectedDebt,
      netPositionMinor: server.cashBalanceMinor + cashDelta - projectedDebt,
      utilizationPercent: server.hasBudget && server.budgetMinor > 0
          ? expense / server.budgetMinor * 100
          : server.utilizationPercent,
      savingsRatePercent: income > 0 ? (income - expense) / income * 100 : null,
      buckets: server.buckets,
      categories: server.categories,
      accounts: projectedAccounts,
      recentTransactions: projectedRecent,
      scope: server.scope,
      jewelryPortfolio: server.jewelryPortfolio,
      jointObligations: projectedObligations,
    );
  }

  List<CutoffPeriod> _projectCutoffPeriods(
    List<CutoffPeriod> server,
    FinanceScope scope,
  ) {
    if (!offlineTransactionsEnabled) return [...server];
    final operations = _projectedOperations(scope);
    return server.map((period) {
      var spentDelta = 0;
      final categoryDeltas = <int, int>{};
      for (final operation in operations) {
        final base = operation.baseTransaction;
        final desired = operation.desiredTransaction;
        if (base != null &&
            base.kind == 'expense' &&
            base.cutoffPeriodId == period.id) {
          spentDelta -= base.amountMinor;
          if (base.categoryId != null) {
            categoryDeltas.update(
              base.categoryId!,
              (value) => value - base.amountMinor,
              ifAbsent: () => -base.amountMinor,
            );
          }
        }
        if (desired != null &&
            desired.kind == 'expense' &&
            _within(desired.occurredOn, period.startsOn, period.endsOn) &&
            (desired.cutoffPeriodId == null ||
                desired.cutoffPeriodId == period.id)) {
          spentDelta += desired.amountMinor;
          if (desired.categoryId != null) {
            categoryDeltas.update(
              desired.categoryId!,
              (value) => value + desired.amountMinor,
              ifAbsent: () => desired.amountMinor,
            );
          }
        }
      }
      final projectedItems = period.items
          .map(
            (item) => BudgetItem(
              categoryId: item.categoryId,
              categoryName: item.categoryName,
              budgetMinor: item.budgetMinor,
              spentMinor:
                  item.spentMinor + (categoryDeltas[item.categoryId] ?? 0),
            ),
          )
          .toList();
      final existingCategoryIds = projectedItems
          .map((item) => item.categoryId)
          .toSet();
      for (final entry in categoryDeltas.entries) {
        if (entry.value == 0 || existingCategoryIds.contains(entry.key)) {
          continue;
        }
        final categoryName = categories
            .where((category) => category.id == entry.key)
            .firstOrNull
            ?.name;
        projectedItems.add(
          BudgetItem(
            categoryId: entry.key,
            categoryName:
                '${categoryName ?? 'Category #${entry.key}'} · pending',
            budgetMinor: 0,
            spentMinor: entry.value,
          ),
        );
      }
      return CutoffPeriod(
        id: period.id,
        label: period.label,
        startsOn: period.startsOn,
        endsOn: period.endsOn,
        budgetMinor: period.budgetMinor,
        spentMinor: period.spentMinor + spentDelta,
        isBudgetOverridden: period.isBudgetOverridden,
        items: projectedItems,
        scope: period.scope,
      );
    }).toList();
  }

  int _cashEffect(TransactionRecord transaction) => transaction.kind == 'income'
      ? transaction.amountMinor
      : -transaction.amountMinor;

  bool _within(DateTime value, DateTime start, DateTime end) =>
      !value.isBefore(start) && !value.isAfter(end);

  Future<void> refreshAccountTransfers({bool silent = false}) =>
      _withFinancialBaselineLock(
        () => _refreshAccountTransfersUnlocked(silent: silent),
      );

  Future<void> _refreshAccountTransfersUnlocked({required bool silent}) async {
    final requestedScope = selectedFinanceScope;
    final scopeGeneration = _financeScopeRequestToken ?? 0;
    if (!silent) {
      isRefreshing = true;
      notifyListeners();
    }
    try {
      final applied = await _loadAccountTransfers(scope: requestedScope);
      if (applied) errorMessage = null;
    } catch (error) {
      if (_isCurrentScopedRequest(requestedScope, scopeGeneration)) {
        errorMessage = _message(error);
        if (!silent) rethrow;
      }
    } finally {
      if (!silent && _isCurrentScopedRequest(requestedScope, scopeGeneration)) {
        isRefreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshCreditCardPayments({bool silent = false}) =>
      _withFinancialBaselineLock(
        () => _refreshCreditCardPaymentsUnlocked(silent: silent),
      );

  Future<void> _refreshCreditCardPaymentsUnlocked({
    required bool silent,
  }) async {
    final requestedScope = selectedFinanceScope;
    final scopeGeneration = _financeScopeRequestToken ?? 0;
    if (!silent) {
      isRefreshing = true;
      notifyListeners();
    }
    try {
      final applied = await _loadCreditCardPayments(scope: requestedScope);
      if (applied) errorMessage = null;
    } catch (error) {
      if (_isCurrentScopedRequest(requestedScope, scopeGeneration)) {
        errorMessage = _message(error);
        if (!silent) rethrow;
      }
    } finally {
      if (!silent && _isCurrentScopedRequest(requestedScope, scopeGeneration)) {
        isRefreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshSavingsInterestCredits({bool silent = false}) =>
      _withFinancialBaselineLock(
        () => _refreshSavingsInterestCreditsUnlocked(silent: silent),
      );

  Future<SavingsInterestAccrualResult?> accrueSavingsInterest({
    bool silent = false,
  }) => _withFinancialBaselineLock(() async {
    final requestedScope = selectedFinanceScope;
    final scopeGeneration = _financeScopeRequestToken ?? 0;
    if (!silent) {
      isRefreshing = true;
      errorMessage = null;
      notifyListeners();
    }
    try {
      return await _accrueSavingsInterestUnlocked(refreshSnapshots: true);
    } catch (error, stackTrace) {
      final originalMessage = _message(error);
      try {
        await _refreshAfterCommittedSavingsInterest(
          scope: requestedScope,
          scopeGeneration: scopeGeneration,
        );
      } catch (_) {
        // The POST may have committed before its response was lost or rejected.
        // Reconciliation is best effort here; preserve the original failure.
      }
      errorMessage = originalMessage;
      if (!silent) Error.throwWithStackTrace(error, stackTrace);
      return null;
    } finally {
      if (!silent) {
        isRefreshing = false;
        notifyListeners();
      }
    }
  });

  Future<SavingsInterestAccrualResult?> _accrueSavingsInterestUnlocked({
    required bool refreshSnapshots,
  }) async {
    if (!hasLiveConnection || offlineTransactionOperations.isNotEmpty) {
      return null;
    }
    await _verifyBoundInstallation(force: true, forMutation: true);
    SavingsInterestAccrualResult result;
    try {
      result = await repository.accrueSavingsInterest();
    } on ApiException catch (error) {
      // Older saved desktop installations do not expose automatic accrual.
      // Their account and manual-interest history remain readable.
      if (error.statusCode == 404 || error.statusCode == 405) return null;
      rethrow;
    }
    if (!result.hasConsistentMetadata ||
        result.credits.any(_hasUnsafeSavingsInterestCredit)) {
      throw ApiException(
        message: 'Automatic savings interest returned inconsistent account or money effects. Refresh before changing savings settings.',
      );
    }
    if (refreshSnapshots) {
      await _refreshAfterCommittedSavingsInterest(
        scope: selectedFinanceScope,
        scopeGeneration: _financeScopeRequestToken ?? 0,
      );
    }
    return result;
  }

  Future<void> _refreshSavingsInterestCreditsUnlocked({
    required bool silent,
  }) async {
    final requestedScope = selectedFinanceScope;
    final scopeGeneration = _financeScopeRequestToken ?? 0;
    if (!silent) {
      isRefreshing = true;
      notifyListeners();
    }
    try {
      final applied = await _loadSavingsInterestCredits(scope: requestedScope);
      if (applied) errorMessage = null;
    } catch (error) {
      if (_isCurrentScopedRequest(requestedScope, scopeGeneration)) {
        errorMessage = _message(error);
        if (!silent) rethrow;
      }
    } finally {
      if (!silent && _isCurrentScopedRequest(requestedScope, scopeGeneration)) {
        isRefreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshCutoffs({
    bool silent = false,
    bool propagateError = false,
  }) => _withFinancialBaselineLock(
    () =>
        _refreshCutoffsUnlocked(silent: silent, propagateError: propagateError),
  );

  Future<void> _refreshCutoffsUnlocked({
    required bool silent,
    required bool propagateError,
  }) async {
    final requestedScope = selectedFinanceScope;
    await _verifyBoundInstallation(force: true);
    _requireSafeFinancialBaselineRead(requestedScope);
    final scopeGeneration = _financeScopeRequestToken ?? 0;
    final first = DateTime(anchor.year, anchor.month - 1, 1);
    final last = DateTime(anchor.year, anchor.month + 2, 0);
    if (!silent) {
      isRefreshing = true;
      notifyListeners();
    }
    try {
      final loaded = await repository.cutoffPeriods(
        from: first,
        to: last,
        scope: requestedScope,
      );
      if (loaded.any((period) => period.scope != requestedScope)) {
        throw const FormatException(
          'The cutoff list returned another money scope.',
        );
      }
      if (_isCurrentScopedRequest(requestedScope, scopeGeneration)) {
        _serverCutoffPeriods = loaded;
        cutoffPeriods = _projectCutoffPeriods(
          _serverCutoffPeriods!,
          requestedScope,
        );
        _cutoffsBaselineLoaded = true;
        errorMessage = null;
      }
    } catch (error) {
      if (_isCurrentScopedRequest(requestedScope, scopeGeneration)) {
        errorMessage = _message(error);
        if (!silent || propagateError) rethrow;
      }
    } finally {
      if (!silent && _isCurrentScopedRequest(requestedScope, scopeGeneration)) {
        isRefreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshJointDeals({bool silent = false}) =>
      _withFinancialBaselineLock(
        () => _refreshJointDealsUnlocked(silent: silent),
      );

  Future<void> _refreshJointDealsUnlocked({required bool silent}) async {
    if (!isJointScope) {
      _jointParticipants = const [];
      _archivedJointParticipants = const [];
      _jointDeals = const [];
      _archivedJointDeals = const [];
      _jointPenalties = const [];
      _jointDealsSummary = null;
      _clearDealsPenaltyMoneySnapshot();
      _lastJointDealsRefreshError = null;
      _jointDealsBaselineLoaded = false;
      if (!silent) notifyListeners();
      return;
    }
    await _verifyBoundInstallation(force: true);
    final scopeGeneration = _financeScopeRequestToken ?? 0;
    final requestToken = (_jointDealsRequestToken ?? 0) + 1;
    _jointDealsRequestToken = requestToken;
    if (!silent) {
      isRefreshing = true;
      notifyListeners();
    }
    try {
      final loaded = await Future.wait<Object>([
        repository.jointParticipants(includeArchived: true),
        repository.jointDeals(includeArchived: true),
        _loadAllJointPenalties(),
        repository.jointDealsSummary(),
      ]);
      if (_isCurrentJointDealsRequest(requestToken, scopeGeneration)) {
        final summary = loaded[3] as JointDealsSummary;
        if (_hasUnsafeJointDealsSummary(summary)) {
          throw ApiException(
            message: 'Deals and penalties returned inconsistent scope or cash-balance data. Refresh and try again.',
          );
        }
        final penalties = loaded[2] as List<JointPenalty>;
        if (penalties.any(_hasUnsafePenaltyEffects)) {
          throw ApiException(
            message: 'A penalty returned unsafe cash or budget behavior. Refresh and try again.',
          );
        }
        _jointParticipants = (loaded[0] as List<JointParticipant>)
            .where((participant) => participant.isActive)
            .toList();
        _archivedJointParticipants = (loaded[0] as List<JointParticipant>)
            .where((participant) => participant.isArchived)
            .toList();
        _jointDeals = (loaded[1] as List<JointDeal>)
            .where((deal) => deal.isActive)
            .toList();
        _archivedJointDeals = (loaded[1] as List<JointDeal>)
            .where((deal) => deal.isArchived)
            .toList();
        _jointPenalties = penalties
            .where((penalty) => !penalty.isArchived && !penalty.isVoided)
            .toList();
        _jointDealsSummary = summary;
        if (summary.hasDealsPenaltyMoneyData) {
          _applyDealsPenaltyMoneySnapshot(
            summary.dealsPenaltyMoneyAccount,
            summary.dealsPenaltyMoneyBalanceMinor,
          );
        }
        _jointDealsBaselineLoaded = true;
        _lastJointDealsRefreshError = null;
        errorMessage = null;
      }
    } catch (error) {
      if (_isCurrentJointDealsRequest(requestToken, scopeGeneration)) {
        _lastJointDealsRefreshError = _message(error);
        errorMessage = _lastJointDealsRefreshError;
        if (!silent) rethrow;
      }
    } finally {
      if (!silent &&
          _isCurrentJointDealsRequest(requestToken, scopeGeneration)) {
        isRefreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshJointDealsPage() async {
    if (!isJointScope) {
      await refreshJointDeals();
      return;
    }
    final scopeGeneration = _financeScopeRequestToken ?? 0;
    Object? accountsError;
    isRefreshing = true;
    errorMessage = null;
    notifyListeners();
    try {
      _lastJointDealsRefreshError = null;
      final dealsFuture = refreshJointDeals(silent: true);
      final accountsFuture = () async {
        try {
          await _loadAccounts(scope: FinanceScope.joint);
        } catch (error) {
          accountsError = error;
        }
      }();
      await Future.wait([dealsFuture, accountsFuture]);
      if (!_isCurrentScopedRequest(FinanceScope.joint, scopeGeneration)) {
        return;
      }
      final dealsApplied =
          (_jointDealsBaselineLoaded ?? false) &&
          _lastJointDealsRefreshError == null;
      final accountsApplied =
          (_accountsBaselineLoaded ?? false) && accountsError == null;

      // Prefer the freshly loaded account resource when both reads succeed.
      // If either endpoint fails, preserve the successful endpoint's balance
      // instead of letting an older cached account mask a newer summary.
      if (accountsApplied) {
        final systemAccount = accounts
            .where((account) => account.isDealsPenaltyMoney)
            .firstOrNull;
        _applyDealsPenaltyMoneySnapshot(
          systemAccount,
          systemAccount?.balanceMinor ?? 0,
        );
      } else if (dealsApplied && jointDealsSummary.hasDealsPenaltyMoneyData) {
        _applyDealsPenaltyMoneySnapshot(
          jointDealsSummary.dealsPenaltyMoneyAccount,
          jointDealsSummary.dealsPenaltyMoneyBalanceMinor,
        );
      }
      final warnings = <String>[];
      if (!dealsApplied) {
        warnings.add(
          _lastJointDealsRefreshError ??
              'Deals and penalty totals could not be refreshed.',
        );
      }
      if (accountsError != null) {
        warnings.add(
          'Joint accounts could not be refreshed: ${_message(accountsError!)}',
        );
      }
      errorMessage = warnings.isEmpty ? null : warnings.join(' ');
    } finally {
      if (_isCurrentScopedRequest(FinanceScope.joint, scopeGeneration)) {
        isRefreshing = false;
        notifyListeners();
      }
    }
  }

  Future<List<JointPenalty>> _loadAllJointPenalties() async {
    final loaded = <JointPenalty>[];
    var page = 1;
    var lastPage = 1;
    do {
      final result = await repository.jointPenalties(page: page, perPage: 100);
      loaded.addAll(result.items);
      lastPage = result.lastPage;
      page += 1;
    } while (page <= lastPage);
    return loaded;
  }

  bool _isCurrentJointDealsRequest(int requestToken, int scopeGeneration) =>
      requestToken == (_jointDealsRequestToken ?? 0) &&
      _isCurrentScopedRequest(FinanceScope.joint, scopeGeneration);

  Future<void> saveJointParticipant({
    JointParticipant? existing,
    required String name,
  }) => _mutation(() async {
    _requireJointScope();
    JointParticipant saved;
    if (existing == null) {
      saved = await repository.createJointParticipant(name: name);
    } else {
      saved = await repository.updateJointParticipant(existing.id, name: name);
    }
    _upsertJointParticipant(saved);
    await refreshJointDeals(silent: true);
  });

  Future<void> archiveJointParticipant(JointParticipant participant) =>
      _mutation(() async {
        _requireJointScope();
        await repository.deleteJointParticipant(participant.id);
        _upsertJointParticipant(participant.copyWith(isArchived: true));
        await refreshJointDeals(silent: true);
      });

  Future<void> restoreJointParticipant(JointParticipant participant) =>
      _mutation(() async {
        _requireJointScope();
        final restored = await repository.updateJointParticipant(
          participant.id,
          name: participant.name,
          isArchived: false,
        );
        _upsertJointParticipant(restored);
        await refreshJointDeals(silent: true);
      });

  Future<void> saveJointDeal({
    JointDeal? existing,
    required String title,
    String? description,
    required int amountPerOccurrenceMinor,
  }) => _mutation(() async {
    _requireJointScope();
    JointDeal saved;
    if (existing == null) {
      saved = await repository.createJointDeal(
        title: title,
        description: description,
        amountPerOccurrenceMinor: amountPerOccurrenceMinor,
      );
    } else {
      saved = await repository.updateJointDeal(
        existing.id,
        title: title,
        description: description,
        amountPerOccurrenceMinor: amountPerOccurrenceMinor,
      );
    }
    _upsertJointDeal(saved);
    await refreshJointDeals(silent: true);
  });

  Future<void> archiveJointDeal(JointDeal deal) => _mutation(() async {
    _requireJointScope();
    await repository.deleteJointDeal(deal.id);
    _upsertJointDeal(deal.copyWith(isArchived: true));
    await refreshJointDeals(silent: true);
  });

  Future<void> restoreJointDeal(JointDeal deal) => _mutation(() async {
    _requireJointScope();
    final restored = await repository.updateJointDeal(
      deal.id,
      title: deal.title,
      description: deal.description,
      amountPerOccurrenceMinor: deal.amountPerOccurrenceMinor,
      isArchived: false,
    );
    _upsertJointDeal(restored);
    await refreshJointDeals(silent: true);
  });

  Future<void> saveJointPenalty({
    JointPenalty? existing,
    required String clientUuid,
    required int dealId,
    int? participantId,
    String? participantName,
    required DateTime occurredOn,
    required int quantity,
    String? notes,
  }) => _mutation(() async {
    _requireJointScope();
    if (participantId == null && (participantName?.trim().isEmpty ?? true)) {
      throw const FormatException('Choose or name a participant.');
    }
    JointPenalty saved;
    if (existing == null) {
      saved = await repository.createJointPenalty(
        clientUuid: clientUuid,
        dealId: dealId,
        participantId: participantId,
        participantName: participantName,
        occurredOn: occurredOn,
        quantity: quantity,
        notes: notes,
      );
    } else {
      if (existing.isPaid || existing.isSettled) {
        throw const FormatException(
          'Mark this paid penalty unpaid before editing it.',
        );
      }
      saved = await repository.updateJointPenalty(
        existing.id,
        version: existing.version,
        dealId: dealId,
        participantId: participantId,
        participantName: participantName,
        occurredOn: occurredOn,
        quantity: quantity,
        notes: notes,
      );
    }
    _upsertJointPenalty(saved);
    await Future.wait([
      refreshJointDeals(silent: true),
      refreshDashboard(silent: true),
    ]);
  });

  Future<void> settleJointPenalty(
    JointPenalty penalty, {
    DateTime? settledOn,
    required String paymentMode,
    required String paymentClientUuid,
    int? sourceAccountId,
  }) => _mutation(() async {
    _requireJointScope();
    _requireSynchronizedTransactions(FinanceScope.joint);
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
    if (paymentMode == 'account_transfer') {
      if (sourceAccountId == null) {
        throw const FormatException(
          'Choose a Joint source account for the payment.',
        );
      }
      final source = penaltyPaymentSourceAccounts
          .where((account) => account.id == sourceAccountId)
          .firstOrNull;
      if (source == null) {
        throw const FormatException(
          'The selected source must be an active standard Joint account.',
        );
      }
      if (source.balanceMinor < penalty.totalAmountMinor) {
        throw const FormatException(
          'The selected Joint account does not have enough available balance.',
        );
      }
    }
    final saved = await repository.settleJointPenalty(
      penalty.id,
      version: penalty.version,
      settledOn: settledOn,
      paymentMode: paymentMode,
      paymentClientUuid: paymentClientUuid,
      sourceAccountId: sourceAccountId,
    );
    if (_hasUnsafePenaltyEffects(saved)) {
      throw ApiException(
        message: 'The payment returned unsafe Joint-total, cashflow, or budget effects. Refresh and verify it before trying again.',
      );
    }
    // Direct payments add the full amount to the system Joint account. A
    // contribution payment transfers it between two Joint accounts. Neither
    // mode creates income/expense transactions or changes cashflow/budgets.
    _upsertJointPenalty(saved);
    await Future.wait(<Future<void>>[
      refreshJointDeals(silent: true),
      refreshDashboard(silent: true),
    ]);
    await _refreshAccountsAfterCommittedPenalty();
  });

  Future<void> reopenJointPenalty(JointPenalty penalty) => _mutation(() async {
    _requireJointScope();
    _requireSynchronizedTransactions(FinanceScope.joint);
    final reversesFinancialPayment =
        ((penalty.currentPayment?.isAccountTransfer == true ||
                penalty.currentPayment?.isExternalDeposit == true) &&
            penalty.currentPayment?.isPosted == true) ||
        ((penalty.settlementMode == 'account_transfer' ||
                penalty.settlementMode == 'external_deposit') &&
            penalty.financiallyRecorded);
    final saved = await repository.reopenJointPenalty(
      penalty.id,
      version: penalty.version,
    );
    if (_hasUnsafePenaltyEffects(saved)) {
      throw ApiException(
        message: 'The reopened payment returned unsafe Joint-total, cashflow, or budget effects. Refresh and verify it before trying again.',
      );
    }
    _upsertJointPenalty(saved);
    await Future.wait(<Future<void>>[
      refreshJointDeals(silent: true),
      refreshDashboard(silent: true),
    ]);
    if (reversesFinancialPayment) {
      await _refreshAccountsAfterCommittedPenalty();
    }
  });

  Future<void> deleteJointPenalty(JointPenalty penalty) => _mutation(() async {
    _requireJointScope();
    if (penalty.isPaid || penalty.isSettled) {
      throw const FormatException(
        'Mark this paid penalty unpaid before deleting it.',
      );
    }
    await repository.deleteJointPenalty(penalty.id, version: penalty.version);
    _jointPenalties = jointPenalties
        .where((item) => item.id != penalty.id)
        .toList();
    await Future.wait([
      refreshJointDeals(silent: true),
      refreshDashboard(silent: true),
    ]);
  });

  bool _hasUnsafeJointSplitExpense(JointSplitExpense split) {
    final first = split.firstAccount;
    final second = split.secondAccount;
    final category = split.category;
    final firstTransaction = split.firstTransaction;
    final secondTransaction = split.secondTransaction;
    final expectedFirstShare = (split.amountMinor + 1) ~/ 2;
    final expectedSecondShare = split.amountMinor ~/ 2;
    if (!split.hasEffectMetadata ||
        split.scope != FinanceScope.joint ||
        split.id <= 0 ||
        split.clientUuid.trim().isEmpty ||
        split.amountMinor < 2 ||
        split.amountMinor > Money.maxMinorUnits ||
        split.firstAccountId == split.secondAccountId ||
        split.firstAccountId <= 0 ||
        split.secondAccountId <= 0 ||
        split.categoryId <= 0 ||
        (split.cutoffPeriodId ?? 0) <= 0 ||
        split.firstAccountNameSnapshot.trim().isEmpty ||
        split.secondAccountNameSnapshot.trim().isEmpty ||
        split.categoryNameSnapshot.trim().isEmpty ||
        split.splitMethod != 'equal' ||
        split.oddMinorRecipient != 'first' ||
        split.expenseCountedMinor != split.amountMinor ||
        split.firstShareMinor != expectedFirstShare ||
        split.secondShareMinor != expectedSecondShare ||
        split.firstShareMinor + split.secondShareMinor != split.amountMinor ||
        split.totalDebitMinor != split.amountMinor ||
        split.totalCashChangeMinor != -split.amountMinor ||
        split.status != 'posted' ||
        split.version != 1 ||
        !split.isImmutable ||
        split.componentCount != 2 ||
        !split.affectsAccountBalance ||
        !split.affectsIndividualAccountBalances ||
        !split.affectsTotalCashBalance ||
        split.affectsIncome ||
        !split.affectsExpense ||
        !split.affectsCashflow ||
        !split.affectsBudget ||
        first == null ||
        second == null ||
        first.id != split.firstAccountId ||
        second.id != split.secondAccountId ||
        first.scope != FinanceScope.joint ||
        second.scope != FinanceScope.joint ||
        !first.isStandardAccount ||
        !second.isStandardAccount ||
        category == null ||
        category.id != split.categoryId ||
        category.kind != 'expense' ||
        category.isSystem ||
        firstTransaction == null ||
        secondTransaction == null ||
        _hasUnsafeJointSplitComponent(
          split,
          firstTransaction,
          component: 'first',
          accountId: split.firstAccountId,
          shareMinor: split.firstShareMinor,
        ) ||
        _hasUnsafeJointSplitComponent(
          split,
          secondTransaction,
          component: 'second',
          accountId: split.secondAccountId,
          shareMinor: split.secondShareMinor,
        )) {
      return true;
    }
    final componentIds = split.componentTransactions
        .map((transaction) => transaction.id)
        .toSet();
    return split.componentTransactions.length != 2 ||
        firstTransaction.id <= 0 ||
        secondTransaction.id <= 0 ||
        componentIds.length != 2 ||
        !componentIds.contains(firstTransaction.id) ||
        !componentIds.contains(secondTransaction.id);
  }

  bool _hasUnsafeJointSplitComponent(
    JointSplitExpense split,
    TransactionRecord transaction, {
    required String component,
    required int accountId,
    required int shareMinor,
  }) =>
      transaction.scope != FinanceScope.joint ||
      transaction.kind != 'expense' ||
      transaction.amountMinor != shareMinor ||
      transaction.occurredOn != split.occurredOn ||
      transaction.accountId != accountId ||
      transaction.categoryId != split.categoryId ||
      transaction.cutoffPeriodId != split.cutoffPeriodId ||
      transaction.payee != split.payee ||
      transaction.note != split.note ||
      transaction.sourceType != 'joint_split_expense' ||
      transaction.sourceId != split.id ||
      transaction.sourceComponent != component;

  bool _hasUnsafeJointSplitProjection(TransactionRecord transaction) {
    if (!transaction.isManagedJointSplitExpense) {
      return transaction.jointSplitExpense != null;
    }
    final split = transaction.jointSplitExpense;
    if (!transaction.isJointSplitExpenseAggregate ||
        split == null ||
        _hasUnsafeJointSplitExpense(split)) {
      return true;
    }
    return transaction.scope != FinanceScope.joint ||
        transaction.kind != 'expense' ||
        transaction.id != split.firstTransaction!.id ||
        transaction.clientUuid != split.clientUuid ||
        transaction.amountMinor != split.amountMinor ||
        transaction.occurredOn != split.occurredOn ||
        transaction.accountId != null ||
        transaction.account != null ||
        transaction.categoryId != split.categoryId ||
        transaction.cutoffPeriodId != split.cutoffPeriodId ||
        transaction.payee != split.payee ||
        transaction.note != split.note ||
        transaction.category != null &&
            transaction.category!.id != split.categoryId ||
        transaction.sourceId != split.id ||
        transaction.version != split.version;
  }

  bool _hasUnsafeJointSplitProjections(List<TransactionRecord> transactions) {
    final splitIds = <int>{};
    for (final transaction in transactions) {
      if (!transaction.isManagedJointSplitExpense &&
          transaction.jointSplitExpense == null) {
        continue;
      }
      if (_hasUnsafeJointSplitProjection(transaction) ||
          !splitIds.add(transaction.sourceId!)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _refreshAfterCommittedJointSplitExpense(
    int scopeGeneration,
  ) async {
    final warnings = <String>[];
    final reportPeriod = reportSummary?.period;

    Future<void> capture(String label, Future<void> Function() refresh) async {
      try {
        await refresh();
      } catch (error) {
        warnings.add('$label: ${_message(error)}');
      }
    }

    await Future.wait(<Future<void>>[
      capture(
        'account balances',
        () => _loadAccounts(scope: FinanceScope.joint),
      ),
      capture(
        'transaction history',
        () => refreshTransactions(silent: true, propagateError: true),
      ),
      capture('dashboard', () async {
        await _loadDashboard();
      }),
      capture(
        'cutoff totals',
        () => refreshCutoffs(silent: true, propagateError: true),
      ),
      if (reportPeriod != null)
        capture('report', () => loadReport(reportPeriod, propagateError: true)),
    ]);
    if (_isCurrentScopedRequest(FinanceScope.joint, scopeGeneration) &&
        warnings.isNotEmpty) {
      errorMessage =
          'Split expense saved, but some updated data could not be loaded (${warnings.join('; ')}). Use Refresh before adding another expense.';
    }
  }

  bool _hasUnsafeAccountTransfer(AccountTransfer transfer) {
    final totalDebit =
        BigInt.from(transfer.amountMinor) +
        BigInt.from(transfer.serviceChargeMinor);
    final hasFee = transfer.serviceChargeMinor > 0;
    final source = transfer.sourceAccount;
    final destination = transfer.destinationAccount;
    final fee = transfer.feeTransaction;
    final sourceCountsTowardAvailable =
        source?.countsTowardAvailableMoney == true;
    final destinationCountsTowardAvailable =
        destination?.countsTowardAvailableMoney == true;
    final expectedSourceAvailableChange = sourceCountsTowardAvailable
        ? -totalDebit.toInt()
        : 0;
    final expectedDestinationAvailableChange = destinationCountsTowardAvailable
        ? transfer.amountMinor
        : 0;
    final expectedPrincipalAvailableChange =
        (sourceCountsTowardAvailable ? -transfer.amountMinor : 0) +
        (destinationCountsTowardAvailable ? transfer.amountMinor : 0);
    final expectedFeeAvailableChange = sourceCountsTowardAvailable
        ? -transfer.serviceChargeMinor
        : 0;
    final expectedAvailableChange =
        expectedSourceAvailableChange + expectedDestinationAvailableChange;

    if (!transfer.hasEffectMetadata ||
        ((source?.isSavingsAccount == true ||
                destination?.isSavingsAccount == true) &&
            !transfer.hasAvailableMoneyEffectMetadata) ||
        transfer.id <= 0 ||
        transfer.clientUuid.trim().isEmpty ||
        transfer.status != 'posted' ||
        transfer.version != 1 ||
        !transfer.isImmutable ||
        transfer.sourceAccountId == transfer.destinationAccountId ||
        transfer.sourceAccountName.trim().isEmpty ||
        transfer.destinationAccountName.trim().isEmpty ||
        transfer.amountMinor <= 0 ||
        transfer.serviceChargeMinor < 0 ||
        totalDebit > BigInt.from(Money.maxMinorUnits) ||
        transfer.totalSourceDebitMinor != totalDebit.toInt() ||
        transfer.destinationCreditMinor != transfer.amountMinor ||
        transfer.totalCashChangeMinor != -transfer.serviceChargeMinor ||
        !transfer.principalAffectsIndividualAccountBalances ||
        transfer.principalAffectsTotalCashBalance ||
        transfer.serviceChargeAffectsAccountBalance != hasFee ||
        transfer.affectsTotalCashBalance != hasFee ||
        transfer.affectsIncome ||
        transfer.affectsExpense != hasFee ||
        transfer.affectsCashflow != hasFee ||
        transfer.affectsBudget != hasFee ||
        transfer.sourceAvailableMoneyChangeMinor !=
            expectedSourceAvailableChange ||
        transfer.destinationAvailableMoneyChangeMinor !=
            expectedDestinationAvailableChange ||
        transfer.principalAvailableMoneyChangeMinor !=
            expectedPrincipalAvailableChange ||
        transfer.serviceChargeAvailableMoneyChangeMinor !=
            expectedFeeAvailableChange ||
        transfer.availableMoneyChangeMinor != expectedAvailableChange ||
        transfer.principalAffectsAvailableMoney !=
            (expectedPrincipalAvailableChange != 0) ||
        transfer.serviceChargeAffectsAvailableMoney !=
            (expectedFeeAvailableChange != 0) ||
        transfer.affectsAvailableMoney != (expectedAvailableChange != 0) ||
        source == null ||
        destination == null ||
        source.id != transfer.sourceAccountId ||
        destination.id != transfer.destinationAccountId ||
        !source.hasConsistentClassificationMetadata ||
        !destination.hasConsistentClassificationMetadata ||
        source.scope != transfer.scope ||
        destination.scope != transfer.scope ||
        !source.isTransferAccount ||
        !destination.isTransferAccount) {
      return true;
    }

    if (!hasFee) return fee != null;
    return fee == null ||
        fee.kind != 'expense' ||
        fee.amountMinor != transfer.serviceChargeMinor ||
        fee.occurredOn != transfer.transferredOn ||
        fee.accountId != transfer.sourceAccountId ||
        fee.scope != transfer.scope ||
        fee.sourceType != 'account_transfer_fee' ||
        fee.sourceId != transfer.id ||
        fee.category?.isTransferFee != true ||
        fee.category?.isSystem != true;
  }

  bool _hasUnsafeCreditCardPayment(CreditCardPayment payment) {
    final totalDebit =
        BigInt.from(payment.amountMinor) +
        BigInt.from(payment.serviceChargeMinor);
    final hasFee = payment.serviceChargeMinor > 0;
    final source = payment.sourceAccount;
    final card = payment.creditCardAccount;
    final fee = payment.feeTransaction;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    if (!payment.hasEffectMetadata ||
        payment.id <= 0 ||
        !_looksLikeUuid(payment.clientUuid) ||
        payment.status != 'posted' ||
        payment.version != 1 ||
        !payment.isImmutable ||
        payment.sourceAccountId == payment.creditCardAccountId ||
        payment.sourceDisplayName.trim().isEmpty ||
        payment.creditCardDisplayName.trim().isEmpty ||
        payment.amountMinor <= 0 ||
        payment.amountMinor > Money.maxMinorUnits ||
        payment.serviceChargeMinor < 0 ||
        totalDebit > BigInt.from(Money.maxMinorUnits) ||
        payment.totalSourceDebitMinor != totalDebit.toInt() ||
        payment.paidOn.isAfter(todayDate) ||
        payment.sourceCashChangeMinor != -totalDebit.toInt() ||
        payment.creditCardDebtChangeMinor != -payment.amountMinor ||
        payment.debtReductionMinor != payment.amountMinor ||
        payment.totalCashChangeMinor != -totalDebit.toInt() ||
        payment.netPositionChangeMinor != -payment.serviceChargeMinor ||
        !payment.affectsAccountBalance ||
        !payment.affectsIndividualAccountBalances ||
        !payment.affectsTotalCashBalance ||
        !payment.affectsCreditCardDebt ||
        payment.affectsNetPosition != hasFee ||
        payment.serviceChargeAffectsAccountBalance != hasFee ||
        payment.serviceChargeAffectsExpense != hasFee ||
        payment.affectsIncome ||
        payment.affectsExpense != hasFee ||
        payment.affectsCashflow != hasFee ||
        payment.affectsBudget != hasFee ||
        source == null ||
        card == null ||
        source.id != payment.sourceAccountId ||
        card.id != payment.creditCardAccountId ||
        !source.hasConsistentClassificationMetadata ||
        !card.hasConsistentClassificationMetadata ||
        source.scope != payment.scope ||
        card.scope != payment.scope ||
        !source.isStandardAccount ||
        source.isCreditCard ||
        !card.isCreditCard) {
      return true;
    }

    if (!hasFee) {
      return fee != null || payment.serviceChargeTransactionId != null;
    }
    return fee == null ||
        payment.serviceChargeTransactionId == null ||
        payment.serviceChargeTransactionId != fee.id ||
        fee.kind != 'expense' ||
        fee.amountMinor != payment.serviceChargeMinor ||
        fee.occurredOn != payment.paidOn ||
        fee.accountId != payment.sourceAccountId ||
        fee.scope != payment.scope ||
        fee.sourceType != 'credit_card_payment_fee' ||
        fee.sourceId != payment.id ||
        fee.category?.isTransferFee != true ||
        fee.category?.isSystem != true;
  }

  bool _hasUnsafeSavingsInterestCredit(SavingsInterestCredit credit) {
    final account = credit.savingsAccount;
    final transaction = credit.interestTransaction;
    final transactionAccount = transaction?.account;
    final category = transaction?.category;
    final expectedMonth =
        '${credit.creditedOn.year.toString().padLeft(4, '0')}-${credit.creditedOn.month.toString().padLeft(2, '0')}';
    return !credit.hasEffectMetadata ||
        !credit.hasConsistentCalculationMetadata ||
        !credit.hasAliasMetadata ||
        !credit.hasConsistentAliases ||
        !_looksLikeUuid(credit.clientUuid) ||
        credit.id <= 0 ||
        credit.savingsAccountId <= 0 ||
        credit.interestTransactionId <= 0 ||
        credit.status != 'posted' ||
        credit.version != 1 ||
        !credit.isImmutable ||
        credit.savingsAccountDisplayName.trim().isEmpty ||
        credit.amountMinor <= 0 ||
        credit.amountMinor > Money.maxMinorUnits ||
        credit.creditedMonth != expectedMonth ||
        credit.accountBalanceChangeMinor != credit.amountMinor ||
        credit.savingsBalanceChangeMinor != credit.amountMinor ||
        credit.totalCashChangeMinor != credit.amountMinor ||
        credit.availableMoneyChangeMinor != 0 ||
        credit.netPositionChangeMinor != credit.amountMinor ||
        !credit.affectsAccountBalance ||
        !credit.affectsIndividualAccountBalances ||
        !credit.affectsTotalCashBalance ||
        credit.affectsAvailableMoney ||
        !credit.affectsSavingsBalance ||
        !credit.affectsNetPosition ||
        !credit.affectsIncome ||
        credit.affectsExpense ||
        !credit.affectsCashflow ||
        credit.affectsBudget ||
        account == null ||
        account.id != credit.savingsAccountId ||
        !account.hasConsistentClassificationMetadata ||
        account.scope != credit.scope ||
        !account.isSavingsAccount ||
        account.isSystem ||
        transaction == null ||
        transaction.id != credit.interestTransactionId ||
        transaction.id <= 0 ||
        transaction.clientUuid.toLowerCase() !=
            credit.clientUuid.toLowerCase() ||
        transaction.version != 1 ||
        transaction.kind != 'income' ||
        transaction.amountMinor != credit.amountMinor ||
        transaction.occurredOn != credit.creditedOn ||
        transaction.accountId != credit.savingsAccountId ||
        transactionAccount == null ||
        transactionAccount.id != credit.savingsAccountId ||
        !transactionAccount.hasConsistentClassificationMetadata ||
        transactionAccount.scope != credit.scope ||
        !transactionAccount.isSavingsAccount ||
        transactionAccount.isSystem ||
        transaction.scope != credit.scope ||
        transaction.sourceType != 'savings_interest' ||
        transaction.sourceId != credit.id ||
        category == null ||
        category.id <= 0 ||
        transaction.categoryId != category.id ||
        category.kind != 'income' ||
        category.systemKey != 'savings_interest' ||
        category.categoryRole != 'savings_interest' ||
        !category.isSystem ||
        category.isArchived;
  }

  Future<void> _refreshAfterCommittedAccountTransfer({
    required FinanceScope scope,
    required int scopeGeneration,
    required bool refreshCategories,
  }) async {
    final warnings = <String>[];
    final reportPeriod = reportSummary?.period;

    Future<void> capture(String label, Future<void> Function() refresh) async {
      try {
        await refresh();
      } catch (error) {
        warnings.add('$label: ${_message(error)}');
      }
    }

    await Future.wait(<Future<void>>[
      capture('account balances', () => _loadAccounts(scope: scope)),
      capture('transfer history', () async {
        await _loadAccountTransfers(scope: scope);
      }),
      refreshDashboard(silent: true),
      refreshTransactions(silent: true),
      refreshCutoffs(silent: true),
      if (refreshCategories) capture('categories', _loadCategories),
      if (reportPeriod != null) loadReport(reportPeriod),
    ]);

    if (_isCurrentScopedRequest(scope, scopeGeneration) &&
        warnings.isNotEmpty) {
      errorMessage =
          'Transfer saved, but some updated data could not be loaded (${warnings.join('; ')}). Use Refresh before creating another transfer.';
    }
  }

  Future<void> _refreshAfterCommittedCreditCardPayment({
    required FinanceScope scope,
    required int scopeGeneration,
    required bool refreshManagedExpenseData,
  }) async {
    final warnings = <String>[];
    final reportPeriod = reportSummary?.period;

    Future<void> capture(String label, Future<void> Function() refresh) async {
      try {
        await refresh();
      } catch (error) {
        warnings.add('$label: ${_message(error)}');
      }
    }

    await Future.wait(<Future<void>>[
      capture(
        'account balances',
        () => _loadAccounts(scope: scope, networkOnly: true),
      ),
      capture('card payment history', () async {
        await _loadCreditCardPayments(scope: scope, networkOnly: true);
      }),
      capture('dashboard', () async {
        await _loadDashboard(networkOnly: true);
      }),
      if (refreshManagedExpenseData)
        capture(
          'transaction history',
          () => refreshTransactions(
            silent: true,
            propagateError: true,
            networkOnly: true,
          ),
        ),
      if (refreshManagedExpenseData)
        capture(
          'cutoff totals',
          () => refreshCutoffs(silent: true, propagateError: true),
        ),
      if (refreshManagedExpenseData) capture('categories', _loadCategories),
      if (reportPeriod != null)
        capture(
          'report',
          () =>
              loadReport(reportPeriod, propagateError: true, networkOnly: true),
        ),
    ]);
    if (_isCurrentScopedRequest(scope, scopeGeneration) &&
        warnings.isNotEmpty) {
      errorMessage =
          'Card payment saved, but some updated data could not be loaded (${warnings.join('; ')}). Use Refresh before making another payment.';
    }
  }

  Future<void> _refreshAfterCommittedSavingsInterest({
    required FinanceScope scope,
    required int scopeGeneration,
  }) async {
    final warnings = <String>[];
    final reportPeriod = reportSummary?.period;

    Future<void> capture(String label, Future<void> Function() refresh) async {
      try {
        await refresh();
      } catch (error) {
        warnings.add('$label: ${_message(error)}');
      }
    }

    await Future.wait(<Future<void>>[
      capture(
        'account balances',
        () => _loadAccounts(scope: scope, networkOnly: true),
      ),
      capture('savings interest history', () async {
        await _loadSavingsInterestCredits(scope: scope, networkOnly: true);
      }),
      capture('dashboard', () async {
        await _loadDashboard(networkOnly: true);
      }),
      capture(
        'transaction history',
        () => refreshTransactions(
          silent: true,
          propagateError: true,
          networkOnly: true,
        ),
      ),
      capture('categories', _loadCategories),
      if (reportPeriod != null)
        capture(
          'report',
          () =>
              loadReport(reportPeriod, propagateError: true, networkOnly: true),
        ),
    ]);
    if (_isCurrentScopedRequest(scope, scopeGeneration) &&
        warnings.isNotEmpty) {
      errorMessage =
          'Automatic savings interest was processed, but some updated data could not be loaded (${warnings.join('; ')}). Use Refresh before changing savings or its rate.';
    }
  }

  bool _hasUnsafePenaltyEffects(JointPenalty penalty) {
    final payment = penalty.currentPayment;
    if (penalty.affectsCashflow ||
        penalty.affectsBudget ||
        payment?.affectsCashflow == true ||
        payment?.affectsBudget == true) {
      return true;
    }

    if (!penalty.isPaid) {
      return penalty.affectsAccountBalance ||
          penalty.affectsTotalCashBalance ||
          penalty.affectsIndividualAccountBalances ||
          payment?.isPosted == true ||
          payment?.affectsTotalCashBalance == true ||
          payment?.affectsIndividualAccountBalances == true;
    }

    final mode = payment?.mode ?? penalty.settlementMode;
    switch (mode) {
      case 'external_deposit':
        return !penalty.financiallyRecorded ||
            !penalty.affectsAccountBalance ||
            !penalty.affectsTotalCashBalance ||
            !penalty.affectsIndividualAccountBalances ||
            (payment != null &&
                (!payment.isPosted ||
                    !payment.financiallyRecorded ||
                    !payment.affectsTotalCashBalance ||
                    !payment.affectsIndividualAccountBalances));
      case 'account_transfer':
        return !penalty.financiallyRecorded ||
            penalty.affectsAccountBalance ||
            penalty.affectsTotalCashBalance ||
            !penalty.affectsIndividualAccountBalances ||
            (payment != null &&
                (!payment.isPosted ||
                    !payment.financiallyRecorded ||
                    payment.affectsTotalCashBalance ||
                    !payment.affectsIndividualAccountBalances));
      case 'tracking':
        // Historical tracking-only payments remain readable and reopenable.
        return penalty.financiallyRecorded ||
            penalty.affectsAccountBalance ||
            penalty.affectsTotalCashBalance ||
            penalty.affectsIndividualAccountBalances ||
            (payment != null &&
                (!payment.isPosted ||
                    payment.financiallyRecorded ||
                    payment.affectsTotalCashBalance ||
                    payment.affectsIndividualAccountBalances));
      default:
        return true;
    }
  }

  bool _hasUnsafeJointDealsSummary(JointDealsSummary summary) {
    if (summary.scope != FinanceScope.joint ||
        summary.affectsCashflow ||
        summary.affectsBudget) {
      return true;
    }
    final hasExternalDeposits =
        summary.externalDepositPaidMinor > 0 ||
        summary.externalDepositPaidOccurrences > 0 ||
        summary.externalDepositPaidEntries > 0;
    final hasBalanceRecordedPayments =
        summary.balanceRecordedPaidMinor > 0 ||
        summary.balanceRecordedPaidOccurrences > 0 ||
        summary.balanceRecordedPaidEntries > 0;
    return summary.affectsAccountBalance != hasExternalDeposits ||
        summary.affectsTotalCashBalance != hasExternalDeposits ||
        summary.affectsIndividualAccountBalances != hasBalanceRecordedPayments;
  }

  Future<void> _refreshAccountsAfterCommittedPenalty() async {
    try {
      await _loadAccounts(scope: FinanceScope.joint);
    } catch (error) {
      // The payment/reversal already committed. Preserve that success and make
      // the read-only refresh failure a warning instead of inviting a retry.
      errorMessage =
          'The payment was saved, but account balances could not be refreshed: ${_message(error)}';
    }
  }

  void _upsertJointParticipant(JointParticipant saved) {
    _jointParticipants = [
      ...jointParticipants.where((item) => item.id != saved.id),
      if (saved.isActive) saved,
    ];
    _archivedJointParticipants = [
      ...archivedJointParticipants.where((item) => item.id != saved.id),
      if (saved.isArchived) saved,
    ];
  }

  void _upsertJointDeal(JointDeal saved) {
    _jointDeals = [
      ...jointDeals.where((item) => item.id != saved.id),
      if (saved.isActive) saved,
    ];
    _archivedJointDeals = [
      ...archivedJointDeals.where((item) => item.id != saved.id),
      if (saved.isArchived) saved,
    ];
  }

  void _upsertJointPenalty(JointPenalty saved) {
    _jointPenalties = [
      ...jointPenalties.where((item) => item.id != saved.id),
      if (!saved.isArchived && !saved.isVoided) saved,
    ];
  }

  void _requireJointScope() {
    if (!isJointScope) {
      throw const FormatException(
        'Switch to Joint money to manage deals and penalties.',
      );
    }
  }

  Future<void> saveTransaction({
    TransactionRecord? existing,
    required String clientUuid,
    required String kind,
    required int amountMinor,
    required DateTime occurredOn,
    required int accountId,
    required int categoryId,
    String? payee,
    String? note,
    int? installmentMonths,
    DateTime? installmentStartOn,
  }) => _mutation(() async {
    if (existing?.isManagedTransaction == true) {
      throw const FormatException(
        'This transaction is managed automatically and cannot be edited here.',
      );
    }
    if (categories
            .where((category) => category.id == categoryId)
            .firstOrNull
            ?.isSystem ==
        true) {
      throw const FormatException(
        'System categories can only be used by their managed feature.',
      );
    }
    final selectedAccount = accounts
        .where((account) => account.id == accountId)
        .firstOrNull;
    final desiredAccount =
        selectedAccount ??
        (existing?.accountId == accountId ? existing?.account : null);
    if (desiredAccount?.isSavingsAccount == true) {
      throw const FormatException(
        'Use Transfer money to move savings. Monthly interest is added automatically from the rate saved on the account.',
      );
    }
    _validateStandardTransactionFunding(
      existing: existing,
      desiredAccount: desiredAccount,
      desiredKind: kind,
      desiredAmountMinor: amountMinor,
    );
    if (selectedAccount?.isCreditCard == true && kind != 'expense') {
      throw const FormatException(
        'Credit cards can only be used for expenses. Use Pay card to reduce debt.',
      );
    }
    final installmentMonthlyMinor = _normalizeInstallmentMonthlyMinor(
      amountMinor: amountMinor,
      installmentMonths: installmentMonths,
      installmentStartOn: installmentStartOn,
      occurredOn: occurredOn,
      account: desiredAccount,
      kind: kind,
    );
    if (offlineTransactionsEnabled) {
      await _queueTransactionSave(
        existing: existing,
        clientUuid: clientUuid,
        kind: kind,
        amountMinor: amountMinor,
        occurredOn: occurredOn,
        accountId: accountId,
        categoryId: categoryId,
        payee: payee,
        note: note,
        installmentMonths: installmentMonths,
        installmentMonthlyMinor: installmentMonthlyMinor,
        installmentStartOn: installmentStartOn,
      );
      return;
    }
    if (existing == null) {
      await repository.createTransaction(
        clientUuid: clientUuid,
        kind: kind,
        amountMinor: amountMinor,
        occurredOn: occurredOn,
        accountId: accountId,
        categoryId: categoryId,
        payee: payee,
        note: note,
        installmentMonths: installmentMonths,
        installmentMonthlyMinor: installmentMonthlyMinor,
        installmentStartOn: installmentStartOn,
      );
    } else {
      await repository.updateTransaction(
        existing.id,
        version: existing.version,
        kind: kind,
        amountMinor: amountMinor,
        occurredOn: occurredOn,
        accountId: accountId,
        categoryId: categoryId,
        payee: payee,
        note: note,
        installmentMonths: installmentMonths,
        installmentMonthlyMinor: installmentMonthlyMinor,
        installmentStartOn: installmentStartOn,
      );
    }
    await _refreshFinancialData();
  }, allowOffline: offlineTransactionsEnabled);

  Future<void> saveInstallmentPlan({
    InstallmentPlan? existing,
    required String clientUuid,
    required int accountId,
    required int categoryId,
    required int installmentMonthlyMinor,
    required int installmentMonths,
    required DateTime installmentStartOn,
    int? downPaymentMinor,
    String? payee,
    String? note,
    bool isIdempotentRetry = false,
  }) => _mutation(() async {
    final scope = existing?.scope ?? selectedFinanceScope;
    _requireSynchronizedTransactions(scope);
    if (existing?.isActive == false) {
      throw const FormatException(
        'Only an active installment plan can be edited.',
      );
    }
    final accountChanged = existing == null || accountId != existing.accountId;
    final categoryChanged =
        existing == null || categoryId != existing.categoryId;
    final amountChanged =
        existing == null ||
        installmentMonthlyMinor != existing.installmentMonthlyMinor;
    final monthsChanged =
        existing == null || installmentMonths != existing.installmentMonths;
    final effectiveDownPaymentMinor =
        downPaymentMinor ?? existing?.downPaymentMinor ?? 0;
    if (installmentMonthlyMinor <= 0 ||
        installmentMonthlyMinor > Money.maxMinorUnits) {
      throw const FormatException('Enter a valid monthly payment.');
    }
    if (installmentMonths < 2 || installmentMonths > 120) {
      throw const FormatException(
        'Installments must run from 2 to 120 months.',
      );
    }
    if (effectiveDownPaymentMinor < 0 ||
        effectiveDownPaymentMinor > Money.maxMinorUnits) {
      throw const FormatException('Enter a valid down payment.');
    }
    if (existing != null &&
        effectiveDownPaymentMinor != existing.downPaymentMinor) {
      throw const FormatException(
        'A saved down payment cannot be changed or charged again.',
      );
    }
    final start = DateTime(
      installmentStartOn.year,
      installmentStartOn.month,
      installmentStartOn.day,
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final existingStart = existing?.installmentStartOn;
    final startChanged =
        existingStart == null ||
        start.year != existingStart.year ||
        start.month != existingStart.month ||
        start.day != existingStart.day;
    if (existing?.hasPayments == true &&
        (categoryChanged || amountChanged || monthsChanged || startChanged)) {
      throw const FormatException(
        'The category, amount, months, and schedule cannot change after a payment is recorded.',
      );
    }
    if (accountChanged) {
      final account = accounts
          .where(
            (item) =>
                item.id == accountId &&
                item.scope == scope &&
                !item.isArchived &&
                item.isStandardAccount &&
                !item.isCreditCard,
          )
          .firstOrNull;
      if (account == null) {
        throw const FormatException(
          'Choose an active cash, bank, or e-wallet account for this plan.',
        );
      }
    }
    if (categoryChanged) {
      final category = categories
          .where(
            (item) =>
                item.id == categoryId &&
                item.kind == 'expense' &&
                !item.isArchived &&
                !item.isSystem,
          )
          .firstOrNull;
      if (category == null) {
        throw const FormatException(
          'Choose an active standard expense category for this plan.',
        );
      }
    }
    if (existing == null && !start.isAfter(today)) {
      throw const FormatException(
        'A future installment plan must start after today.',
      );
    }
    if (existing != null && startChanged && start.isBefore(today)) {
      throw const FormatException(
        'The first payment date cannot be before today.',
      );
    }
    if (existing == null &&
        effectiveDownPaymentMinor > 0 &&
        !isIdempotentRetry) {
      final downPaymentAccount = accounts
          .where(
            (item) =>
                item.id == accountId &&
                item.scope == scope &&
                !item.isArchived &&
                item.isStandardAccount &&
                !item.isCreditCard,
          )
          .firstOrNull;
      _validateStandardTransactionFunding(
        existing: null,
        desiredAccount: downPaymentAccount,
        desiredKind: 'expense',
        desiredAmountMinor: effectiveDownPaymentMinor,
      );
    }
    final InstallmentPlan saved;
    if (existing == null) {
      saved = await repository.createInstallmentPlan(
        clientUuid: clientUuid,
        accountId: accountId,
        categoryId: categoryId,
        installmentMonthlyMinor: installmentMonthlyMinor,
        installmentMonths: installmentMonths,
        installmentStartOn: start,
        downPaymentMinor: effectiveDownPaymentMinor,
        payee: payee,
        note: note,
      );
    } else {
      saved = await repository.updateInstallmentPlan(
        existing.id,
        version: existing.version,
        accountId: accountChanged ? accountId : null,
        categoryId: categoryChanged ? categoryId : null,
        installmentMonthlyMinor: amountChanged ? installmentMonthlyMinor : null,
        installmentMonths: monthsChanged ? installmentMonths : null,
        installmentStartOn: startChanged ? start : null,
        payee: payee,
        note: note,
      );
    }
    _acceptInstallmentPlanMutationResult(saved, scope);
    if (existing == null && effectiveDownPaymentMinor > 0) {
      await Future.wait([
        refreshInstallmentPlans(silent: true, propagateError: true),
        _refreshFinancialData(),
      ]);
    } else {
      await refreshInstallmentPlans(silent: true, propagateError: true);
    }
  });

  Future<void> archiveInstallmentPlan(InstallmentPlan plan) =>
      _mutation(() async {
        _requireSynchronizedTransactions(plan.scope);
        if (plan.isArchived) return;
        final saved = await repository.archiveInstallmentPlan(
          plan.id,
          version: plan.version,
        );
        _acceptInstallmentPlanMutationResult(saved, plan.scope);
        await refreshInstallmentPlans(silent: true, propagateError: true);
      });

  Future<void> recordInstallmentPayment({
    required InstallmentPlan plan,
    required String clientUuid,
    required DateTime paidOn,
    required int accountId,
    bool isIdempotentRetry = false,
  }) => _mutation(() async {
    _requireSynchronizedTransactions(plan.scope);
    if (!plan.isActive || plan.remainingInstallments <= 0) {
      throw const FormatException(
        'This installment plan has no payment left to record.',
      );
    }
    final account = accounts
        .where(
          (item) =>
              item.id == accountId &&
              item.scope == plan.scope &&
              !item.isArchived &&
              item.isStandardAccount &&
              !item.isCreditCard,
        )
        .firstOrNull;
    if (account == null && !isIdempotentRetry) {
      throw const FormatException(
        'Choose an active cash, bank, or e-wallet account for this payment.',
      );
    }
    final normalizedPaidOn = DateTime(paidOn.year, paidOn.month, paidOn.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (normalizedPaidOn.isAfter(today)) {
      throw const FormatException('Payment date cannot be in the future.');
    }
    // A replay after a dropped response must reach the server with the same
    // UUID even if reconnecting already reloaded the account debit. The
    // backend resolves UUID replays before its ordinary funding/version
    // checks; a request that never committed still receives those checks.
    if (!isIdempotentRetry) {
      _validateStandardTransactionFunding(
        existing: null,
        desiredAccount: account!,
        desiredKind: 'expense',
        desiredAmountMinor: plan.installmentMonthlyMinor,
      );
    }
    final result = await repository.recordInstallmentPayment(
      plan.id,
      clientUuid: clientUuid,
      version: plan.version,
      paidOn: normalizedPaidOn,
      accountId: accountId == plan.accountId ? null : accountId,
    );
    _acceptInstallmentPlanMutationResult(result.plan, plan.scope);
    await Future.wait([
      refreshInstallmentPlans(silent: true, propagateError: true),
      _refreshFinancialData(),
    ]);
  });

  void _acceptInstallmentPlanMutationResult(
    InstallmentPlan saved,
    FinanceScope expectedScope,
  ) {
    if (_invalidInstallmentPlan(saved, expectedScope)) {
      _installmentPlansBaselineLoaded = false;
      throw const FormatException(
        'The saved installment plan response was inconsistent.',
      );
    }
    if (!(_installmentPlansBaselineLoaded ?? false) ||
        selectedFinanceScope != expectedScope ||
        installmentPlans.any((plan) => plan.scope != expectedScope)) {
      _installmentPlansBaselineLoaded = false;
      return;
    }
    installmentPlans =
        [
          saved,
          ...installmentPlans.where((plan) => plan.id != saved.id),
        ]..sort((first, second) {
          final firstDate = first.nextPaymentOn ?? first.installmentStartOn;
          final secondDate = second.nextPaymentOn ?? second.installmentStartOn;
          final byDate = firstDate.compareTo(secondDate);
          return byDate != 0 ? byDate : first.id.compareTo(second.id);
        });
  }

  /// Returns the signed balance after replacing [existing] with a proposed
  /// transaction. The current account balance already contains the existing
  /// transaction (and any pending offline projection), so its old effect must
  /// be reversed before the proposed effect is applied.
  int projectedBalanceAfterTransaction({
    required Account account,
    required TransactionRecord? existing,
    required int desiredAccountId,
    required String desiredKind,
    required int desiredAmountMinor,
  }) {
    var projected = account.balanceMinor;
    if (existing?.accountId == account.id) {
      projected -= _cashEffect(existing!);
    }
    if (desiredAccountId == account.id) {
      projected += desiredKind == 'income'
          ? desiredAmountMinor
          : -desiredAmountMinor;
    }
    return projected;
  }

  bool transactionWouldOverdraw({
    required Account account,
    required TransactionRecord? existing,
    required int desiredAccountId,
    required String desiredKind,
    required int desiredAmountMinor,
  }) {
    if (account.isCreditCard) return false;
    final projected = projectedBalanceAfterTransaction(
      account: account,
      existing: existing,
      desiredAccountId: desiredAccountId,
      desiredKind: desiredKind,
      desiredAmountMinor: desiredAmountMinor,
    );
    // Legacy ledgers may already be negative. Permit neutral or improving
    // changes, but never allow a transaction to create or worsen an overdraft.
    return projected < 0 && projected < account.balanceMinor;
  }

  void _validateStandardTransactionFunding({
    required TransactionRecord? existing,
    required Account? desiredAccount,
    required String desiredKind,
    required int desiredAmountMinor,
  }) {
    final affected = <int, Account>{};
    final previousAccount = existing == null
        ? null
        : accounts
                  .where((account) => account.id == existing.accountId)
                  .firstOrNull ??
              existing.account;
    if (previousAccount != null && !previousAccount.isCreditCard) {
      affected[previousAccount.id] = previousAccount;
    }
    if (desiredAccount != null && !desiredAccount.isCreditCard) {
      affected[desiredAccount.id] = desiredAccount;
    }
    for (final account in affected.values) {
      if (transactionWouldOverdraw(
        account: account,
        existing: existing,
        desiredAccountId: desiredAccount?.id ?? -1,
        desiredKind: desiredKind,
        desiredAmountMinor: desiredAmountMinor,
      )) {
        final projected = projectedBalanceAfterTransaction(
          account: account,
          existing: existing,
          desiredAccountId: desiredAccount?.id ?? -1,
          desiredKind: desiredKind,
          desiredAmountMinor: desiredAmountMinor,
        );
        throw FormatException(
          '${account.displayName} does not have enough available balance. '
          'This change would leave ${Money.format(projected, currencyCode: currencyCode, locale: locale)}.',
        );
      }
    }
  }

  int? _normalizeInstallmentMonthlyMinor({
    required int amountMinor,
    required int? installmentMonths,
    required DateTime? installmentStartOn,
    required DateTime occurredOn,
    required Account? account,
    required String kind,
  }) {
    if (installmentMonths == null) {
      if (installmentStartOn != null) {
        throw const FormatException(
          'Choose installment months before setting a first billing date.',
        );
      }
      return null;
    }
    if (account == null || kind != 'expense') {
      throw const FormatException(
        'Installments are only available for single-account expenses.',
      );
    }
    if (installmentMonths < 2 || installmentMonths > 120) {
      throw const FormatException(
        'Installments must run from 2 to 120 months.',
      );
    }
    final start = installmentStartOn ?? occurredOn;
    final purchaseDate = DateTime(
      occurredOn.year,
      occurredOn.month,
      occurredOn.day,
    );
    final firstBillingDate = DateTime(start.year, start.month, start.day);
    if (firstBillingDate.isBefore(purchaseDate)) {
      throw const FormatException(
        'The first installment date cannot be before the purchase date.',
      );
    }
    if (!account.isCreditCard &&
        !firstBillingDate.isAtSameMomentAs(purchaseDate)) {
      throw const FormatException(
        'The first payment date must match the transaction date for a cash, bank, or e-wallet installment.',
      );
    }
    return account.isCreditCard
        ? (amountMinor + installmentMonths - 1) ~/ installmentMonths
        : amountMinor;
  }

  Future<JointSplitExpense> saveJointSplitExpense({
    required String clientUuid,
    required int firstAccountId,
    required int secondAccountId,
    required int amountMinor,
    required DateTime occurredOn,
    required int categoryId,
    String? payee,
    String? note,
  }) => _withFinancialBaselineLock(() async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _verifyBoundInstallation(force: true, forMutation: true);
      _requireSynchronizedTransactions(FinanceScope.joint);
      if (!isJointScope) {
        throw const FormatException(
          'Split 50/50 is available only for a new Joint expense.',
        );
      }
      if (clientUuid.trim().isEmpty) {
        throw const FormatException(
          'A stable split expense reference is required.',
        );
      }
      if (firstAccountId == secondAccountId) {
        throw const FormatException('Choose two different Joint accounts.');
      }
      if (amountMinor < 2 || amountMinor > Money.maxMinorUnits) {
        throw const FormatException(
          'A split expense must total at least 0.02.',
        );
      }
      final today = DateTime.now();
      final expenseDate = DateTime(
        occurredOn.year,
        occurredOn.month,
        occurredOn.day,
      );
      if (expenseDate.isAfter(DateTime(today.year, today.month, today.day))) {
        throw const FormatException('Expense date cannot be in the future.');
      }
      final first = jointSplitExpenseAccounts
          .where((account) => account.id == firstAccountId)
          .firstOrNull;
      final second = jointSplitExpenseAccounts
          .where((account) => account.id == secondAccountId)
          .firstOrNull;
      if (first == null || second == null) {
        throw const FormatException(
          'Choose two active standard Joint accounts.',
        );
      }
      final firstShare = (amountMinor + 1) ~/ 2;
      final secondShare = amountMinor ~/ 2;
      if (first.balanceMinor < firstShare) {
        throw FormatException(
          '${first.displayName} does not have enough available balance for its share.',
        );
      }
      if (second.balanceMinor < secondShare) {
        throw FormatException(
          '${second.displayName} does not have enough available balance for its share.',
        );
      }
      final category = standardTransactionExpenseCategories
          .where((item) => item.id == categoryId)
          .firstOrNull;
      if (category == null) {
        throw const FormatException(
          'Choose an active standard expense category.',
        );
      }
      final requestedPayee = (payee?.trim().isEmpty ?? true)
          ? null
          : payee!.trim();
      final requestedNote = (note?.trim().isEmpty ?? true)
          ? null
          : note!.trim();
      final scopeGeneration = _financeScopeRequestToken ?? 0;
      final saved = await repository.createJointSplitExpense(
        clientUuid: clientUuid,
        firstAccountId: firstAccountId,
        secondAccountId: secondAccountId,
        amountMinor: amountMinor,
        occurredOn: expenseDate,
        categoryId: categoryId,
        payee: requestedPayee,
        note: requestedNote,
      );
      if (_hasUnsafeJointSplitExpense(saved) ||
          saved.clientUuid != clientUuid ||
          saved.firstAccountId != firstAccountId ||
          saved.secondAccountId != secondAccountId ||
          saved.amountMinor != amountMinor ||
          saved.occurredOn != expenseDate ||
          saved.categoryId != categoryId ||
          saved.payee != requestedPayee ||
          saved.note != requestedNote) {
        throw ApiException(
          message: 'The split expense response did not match the requested expense. Refresh balances before trying again.',
        );
      }

      if (_isCurrentScopedRequest(FinanceScope.joint, scopeGeneration)) {
        _jointSplitExpenses = [
          saved,
          ...jointSplitExpenses.where((item) => item.id != saved.id),
        ];
        transactions = [
          _jointSplitAggregate(saved),
          ...transactions.where(
            (transaction) =>
                !transaction.isManagedJointSplitExpense ||
                transaction.sourceId != saved.id,
          ),
        ];
        await _refreshAfterCommittedJointSplitExpense(scopeGeneration);
      }
      return saved;
    } catch (error) {
      errorMessage = _message(error);
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  });

  TransactionRecord _jointSplitAggregate(JointSplitExpense split) =>
      TransactionRecord(
        id: split.firstTransaction!.id,
        clientUuid: split.clientUuid,
        kind: 'expense',
        amountMinor: split.amountMinor,
        occurredOn: split.occurredOn,
        version: split.version,
        categoryId: split.categoryId,
        cutoffPeriodId: split.cutoffPeriodId,
        payee: split.payee,
        note: split.note,
        category: split.category,
        sourceType: 'joint_split_expense',
        sourceId: split.id,
        sourceComponent: 'group',
        jointSplitExpense: split,
        scope: FinanceScope.joint,
      );

  Future<void> deleteTransaction(
    TransactionRecord transaction,
  ) => _mutation(() async {
    if (transaction.isManagedTransaction) {
      throw const FormatException(
        'This transaction is managed automatically and cannot be deleted here.',
      );
    }
    if (offlineTransactionsEnabled) {
      await _queueTransactionDelete(transaction);
      return;
    }
    await repository.deleteTransaction(transaction.id, transaction.version);
    await _refreshFinancialData();
  }, allowOffline: offlineTransactionsEnabled);

  Future<void> _queueTransactionSave({
    TransactionRecord? existing,
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
  }) async {
    if (_offlineBlockingMessage != null) {
      throw const FormatException(
        'Saved transaction changes are locked to another Budget Flow database. Reconnect to it or use the explicit discard recovery action.',
      );
    }
    if (!offlineCoreReady) {
      throw const FormatException(
        'Saved settings, accounts, categories, complete transaction history, dashboard, and cutoff budgets must be loaded before offline changes are allowed.',
      );
    }
    final current = _transactionOutbox;
    final store = offlineStore;
    if (current == null || store == null) {
      throw const FormatException(
        'Offline transaction storage is not available on this device.',
      );
    }
    if (current.installationId == null) {
      throw const FormatException(
        'Connect to this Budget Flow database once before saving transactions offline.',
      );
    }
    if (!_looksLikeUuid(existing?.clientUuid ?? clientUuid) ||
        !const {'income', 'expense'}.contains(kind) ||
        amountMinor <= 0 ||
        amountMinor > Money.maxMinorUnits ||
        (payee?.trim().runes.length ?? 0) > 150 ||
        (note?.trim().runes.length ?? 0) > 2000) {
      throw const FormatException('Enter a valid transaction before saving.');
    }
    final today = DateTime.now();
    final normalizedDate = DateTime(
      occurredOn.year,
      occurredOn.month,
      occurredOn.day,
    );
    if (normalizedDate.isAfter(DateTime(today.year, today.month, today.day))) {
      throw const FormatException('Transaction date cannot be in the future.');
    }
    final activeAccount = accounts
        .where(
          (item) =>
              item.id == accountId &&
              item.scope == (existing?.scope ?? selectedFinanceScope) &&
              !item.isArchived,
        )
        .firstOrNull;
    final account =
        activeAccount ??
        (existing?.accountId == accountId &&
                existing?.account?.scope ==
                    (existing?.scope ?? selectedFinanceScope)
            ? existing?.account
            : null);
    final activeCategory = categories
        .where(
          (item) =>
              item.id == categoryId &&
              item.kind == kind &&
              !item.isArchived &&
              !item.isSystem,
        )
        .firstOrNull;
    final category =
        activeCategory ??
        (existing?.categoryId == categoryId &&
                existing?.category?.kind == kind &&
                existing?.category?.isSystem != true
            ? existing?.category
            : null);
    if (account == null || account.id <= 0 || category == null) {
      throw const FormatException(
        'Choose a saved active account and standard category before queuing this transaction.',
      );
    }
    _validateOfflineCreditCardEdit(
      existing: existing,
      desiredAccount: account,
      desiredKind: kind,
      desiredAmountMinor: amountMinor,
    );
    final scope = existing?.scope ?? account.scope;
    final sameCutoff =
        existing != null &&
        existing.accountId == accountId &&
        existing.occurredOn.year == occurredOn.year &&
        existing.occurredOn.month == occurredOn.month &&
        existing.occurredOn.day == occurredOn.day;
    await _withOutboxLock(() async {
      if (_offlineBlockingMessage != null) {
        throw const FormatException(
          'Saved transaction changes are locked to another Budget Flow database.',
        );
      }
      final latest = _transactionOutbox;
      if (latest == null || latest.installationId == null) {
        throw const FormatException(
          'The verified offline transaction queue is no longer available.',
        );
      }
      final next = TransactionOutbox.fromSnapshot(
        latest.toSnapshot(),
        recoverInFlight: false,
      );
      final desired = transactionDraftSnapshot(
        id: existing?.id ?? next.nextLocalId,
        clientUuid: existing?.clientUuid ?? clientUuid,
        kind: kind,
        amountMinor: amountMinor,
        occurredOn: normalizedDate,
        account: account,
        category: category,
        scope: scope,
        version: existing?.version ?? 0,
        payee: payee,
        note: note,
        installmentMonths: installmentMonths,
        installmentMonthlyMinor: installmentMonthlyMinor,
        installmentStartOn: installmentStartOn,
        cutoffPeriodId: sameCutoff ? existing.cutoffPeriodId : null,
      );
      if (existing == null) {
        next.queueCreate(
          operationUuid: newClientUuid(),
          queuedAt: DateTime.now().toUtc(),
          scope: scope,
          desiredSnapshot: desired,
        );
      } else {
        next.queueUpdate(
          operationUuid: newClientUuid(),
          queuedAt: DateTime.now().toUtc(),
          existing: existing,
          desiredSnapshot: desired,
        );
      }
      await store.saveOutbox(next.toSnapshot());
      _transactionOutbox = next;
    });
    _reapplyOfflineTransactionProjection();
    notifyListeners();
    if (!isOffline) {
      Zone.root.run(() => unawaited(syncPendingTransactions(silent: true)));
    }
  }

  Future<void> _queueTransactionDelete(TransactionRecord transaction) async {
    if (_offlineBlockingMessage != null) {
      throw const FormatException(
        'Saved transaction changes are locked to another Budget Flow database. Reconnect to it or use the explicit discard recovery action.',
      );
    }
    if (!offlineCoreReady) {
      throw const FormatException(
        'Reconnect and load saved settings, accounts, categories, complete transaction history, dashboard, and cutoff budgets before deleting offline.',
      );
    }
    final current = _transactionOutbox;
    final store = offlineStore;
    if (current == null || store == null) {
      throw const FormatException(
        'Offline transaction storage is not available on this device.',
      );
    }
    if (current.installationId == null) {
      throw const FormatException(
        'Connect to this Budget Flow database once before deleting transactions offline.',
      );
    }
    _validateOfflineCreditCardDelete(transaction);
    await _withOutboxLock(() async {
      if (_offlineBlockingMessage != null) {
        throw const FormatException(
          'Saved transaction changes are locked to another Budget Flow database.',
        );
      }
      final latest = _transactionOutbox;
      if (latest == null || latest.installationId == null) {
        throw const FormatException(
          'The verified offline transaction queue is no longer available.',
        );
      }
      final next =
          TransactionOutbox.fromSnapshot(
            latest.toSnapshot(),
            recoverInFlight: false,
          )..queueDelete(
            operationUuid: newClientUuid(),
            queuedAt: DateTime.now().toUtc(),
            existing: transaction,
          );
      await store.saveOutbox(next.toSnapshot());
      _transactionOutbox = next;
    });
    _reapplyOfflineTransactionProjection();
    notifyListeners();
    if (!isOffline) {
      Zone.root.run(() => unawaited(syncPendingTransactions(silent: true)));
    }
  }

  void _validateOfflineCreditCardEdit({
    required TransactionRecord? existing,
    required Account desiredAccount,
    required String desiredKind,
    required int desiredAmountMinor,
  }) {
    final balances = <int, int>{};
    final cards = <int, Account>{};
    if (existing != null) {
      final activeOldAccount = accounts
          .where((account) => account.id == existing.accountId)
          .firstOrNull;
      final oldAccount = activeOldAccount ?? existing.account;
      if (oldAccount?.isCreditCard == true) {
        cards[oldAccount!.id] = oldAccount;
        balances[oldAccount.id] =
            (activeOldAccount == null && oldAccount.isArchived
                ? 0
                : oldAccount.balanceMinor) -
            _cashEffect(existing);
      }
    }
    if (desiredAccount.isCreditCard) {
      cards[desiredAccount.id] = desiredAccount;
      balances[desiredAccount.id] =
          (balances[desiredAccount.id] ?? desiredAccount.balanceMinor) +
          (desiredKind == 'income' ? desiredAmountMinor : -desiredAmountMinor);
    }
    _validateProjectedCreditCardBalances(cards, balances);
  }

  void _validateOfflineCreditCardDelete(TransactionRecord transaction) {
    final activeAccount = accounts
        .where((item) => item.id == transaction.accountId)
        .firstOrNull;
    final account = activeAccount ?? transaction.account;
    if (account?.isCreditCard != true) return;
    _validateProjectedCreditCardBalances(
      {account!.id: account},
      {
        account.id:
            (activeAccount == null && account.isArchived
                ? 0
                : account.balanceMinor) -
            _cashEffect(transaction),
      },
    );
  }

  void _validateProjectedCreditCardBalances(
    Map<int, Account> cards,
    Map<int, int> balances,
  ) {
    for (final entry in balances.entries) {
      final balance = entry.value;
      final card = cards[entry.key]!;
      if (card.isArchived && balance != 0) {
        throw const FormatException(
          'This offline change would alter a paid archived credit card. Reconnect and reactivate the card first.',
        );
      }
      if (balance > 0) {
        throw const FormatException(
          'This offline change would overpay the credit card. Reconnect and review card payments first.',
        );
      }
      final debt = -balance;
      if (card.creditLimitMinor != null && debt > card.creditLimitMinor!) {
        throw const FormatException(
          'This purchase would exceed the saved credit limit. Reconnect if the card limit has changed.',
        );
      }
    }
  }

  Future<void> keepServerTransaction(
    OfflineTransactionOperation operation,
  ) async {
    final expectedInstallation = _transactionOutbox?.installationId;
    if (!hasLiveConnection ||
        _offlineBlockingMessage != null ||
        health?.ok != true ||
        health?.installationId?.trim().toLowerCase() != expectedInstallation) {
      throw const FormatException(
        'Reconnect before keeping the server version so the saved baseline can be refreshed safely.',
      );
    }
    await _withFinancialBaselineLock(() async {
      await _verifyBoundInstallation(force: true, forMutation: true);
      final applied = offlineTransactionOperations
          .where(
            (item) =>
                item.scope == operation.scope &&
                item.status == OfflineOperationStatus.applied,
          )
          .map((item) => item.operationUuid)
          .toSet();
      await _adoptSyncedFinancialData(
        scope: operation.scope,
        operationUuids: applied,
      );
    });
    await _withOutboxLock(() async {
      final latest = _transactionOutbox;
      final store = offlineStore;
      if (latest == null || store == null) return;
      final matching = latest.operations
          .where((item) => item.operationUuid == operation.operationUuid)
          .firstOrNull;
      if (matching == null) return;
      final next = TransactionOutbox.fromSnapshot(
        latest.toSnapshot(),
        recoverInFlight: false,
      )..discard(matching);
      await store.saveOutbox(next.toSnapshot());
      _transactionOutbox = next;
    });
    _reapplyOfflineTransactionProjection();
    notifyListeners();
  }

  Future<void> retryTransactionAgainstServer(
    OfflineTransactionOperation operation,
  ) async {
    final expectedInstallation = _transactionOutbox?.installationId;
    if (!hasLiveConnection ||
        _offlineBlockingMessage != null ||
        health?.ok != true ||
        health?.installationId?.trim().toLowerCase() != expectedInstallation) {
      throw const FormatException(
        'Reconnect to the verified Budget Flow database before reviewing and retrying this change.',
      );
    }
    if (operation.status != OfflineOperationStatus.conflict ||
        operation.serverTransaction == null ||
        operation.serverTransaction!.isManagedTransaction ||
        _rebasedRetrySnapshot(operation) == null) {
      throw const FormatException(
        'This change cannot be retried automatically. Keep the server version and enter a new transaction if needed.',
      );
    }
    await _withFinancialBaselineLock(() async {
      final verified = await repository.health();
      if (!verified.ok ||
          verified.installationId?.trim().toLowerCase() !=
              expectedInstallation) {
        throw const FormatException(
          'The database identity changed. The saved conflict was kept and was not retried.',
        );
      }
      final applied = offlineTransactionOperations
          .where(
            (item) =>
                item.scope == operation.scope &&
                item.status == OfflineOperationStatus.applied,
          )
          .map((item) => item.operationUuid)
          .toSet();
      final canonicalTransactions = await _adoptSyncedFinancialData(
        scope: operation.scope,
        operationUuids: applied,
      );
      final canonical = canonicalTransactions
          .where((item) => item.id == operation.serverId)
          .firstOrNull;
      final reviewed = operation.serverTransaction;
      if (canonical?.isManagedTransaction == true) {
        await _withOutboxLock(() async {
          final latest = _transactionOutbox;
          final store = offlineStore;
          if (latest == null || store == null) return;
          final next =
              TransactionOutbox.fromSnapshot(
                latest.toSnapshot(),
                recoverInFlight: false,
              )..refreshConflictServerSnapshot(
                operationUuid: operation.operationUuid,
                currentServerSnapshot: transactionSnapshot(canonical!),
                message: 'This transaction is now managed by another workflow and cannot be retried as an ordinary transaction.',
                allowManaged: true,
              );
          await store.saveOutbox(next.toSnapshot());
          _transactionOutbox = next;
        });
        _reapplyOfflineTransactionProjection();
        notifyListeners();
        throw const FormatException(
          'The server transaction is now managed and cannot be retried here. Review it and keep the server version.',
        );
      }
      if (canonical == null) {
        await _withOutboxLock(() async {
          final latest = _transactionOutbox;
          final store = offlineStore;
          if (latest == null || store == null) return;
          final next =
              TransactionOutbox.fromSnapshot(
                latest.toSnapshot(),
                recoverInFlight: false,
              )..markConflictServerDeleted(
                operationUuid: operation.operationUuid,
                message: 'The server transaction was deleted after this conflict was saved. This local retry is no longer available.',
              );
          await store.saveOutbox(next.toSnapshot());
          _transactionOutbox = next;
        });
        _reapplyOfflineTransactionProjection();
        notifyListeners();
        throw const FormatException(
          'The server transaction was deleted. Review and discard this local change.',
        );
      }
      if (reviewed != null && !_sameCanonicalTransaction(canonical, reviewed)) {
        await _withOutboxLock(() async {
          final latest = _transactionOutbox;
          final store = offlineStore;
          if (latest == null || store == null) return;
          final next =
              TransactionOutbox.fromSnapshot(
                latest.toSnapshot(),
                recoverInFlight: false,
              )..refreshConflictServerSnapshot(
                operationUuid: operation.operationUuid,
                currentServerSnapshot: transactionSnapshot(canonical),
                message: 'The server transaction changed again. Review the updated server version before retrying.',
              );
          await store.saveOutbox(next.toSnapshot());
          _transactionOutbox = next;
        });
        _reapplyOfflineTransactionProjection();
        notifyListeners();
        throw const FormatException(
          'The server transaction changed again. Review the updated values before confirming a retry.',
        );
      }
      final rebased = _rebasedRetrySnapshotAgainst(operation, canonical);
      if (rebased == null) {
        throw const FormatException(
          'The current server transaction could not be safely rebased. The saved conflict was kept.',
        );
      }
      await _withOutboxLock(() async {
        final latest = _transactionOutbox;
        final store = offlineStore;
        if (latest == null || store == null) {
          throw const FormatException(
            'Offline transaction storage is unavailable.',
          );
        }
        final matching = latest.operations
            .where((item) => item.operationUuid == operation.operationUuid)
            .firstOrNull;
        if (matching == null ||
            matching.status != OfflineOperationStatus.conflict) {
          throw const FormatException(
            'This conflict changed while it was being refreshed. Review it again.',
          );
        }
        final next = TransactionOutbox.fromSnapshot(
          latest.toSnapshot(),
          recoverInFlight: false,
        )..discard(matching);
        next.queueUpdate(
          operationUuid: newClientUuid(),
          queuedAt: DateTime.now().toUtc(),
          existing: canonical,
          desiredSnapshot: rebased,
        );
        await store.saveOutbox(next.toSnapshot());
        _transactionOutbox = next;
      });
    });
    _reapplyOfflineTransactionProjection();
    notifyListeners();
    if (!isOffline) unawaited(syncPendingTransactions(silent: true));
  }

  Map<String, Object?>? _rebasedRetrySnapshot(
    OfflineTransactionOperation operation,
  ) {
    final current = operation.serverTransaction;
    return current == null
        ? null
        : _rebasedRetrySnapshotAgainst(operation, current);
  }

  Map<String, Object?>? _rebasedRetrySnapshotAgainst(
    OfflineTransactionOperation operation,
    TransactionRecord current,
  ) {
    final base = operation.baseSnapshot;
    final desired = operation.desiredSnapshot;
    if (base == null || desired == null) return null;
    final rebased = transactionSnapshot(current);
    for (final field in const [
      'kind',
      'amount_minor',
      'occurred_on',
      'account_id',
      'category_id',
      'payee',
      'note',
    ]) {
      if (base[field] != desired[field]) rebased[field] = desired[field];
    }
    if (base['account_id'] != desired['account_id']) {
      rebased['account'] = desired['account'];
    }
    if (base['account_id'] != desired['account_id'] ||
        base['occurred_on'] != desired['occurred_on']) {
      rebased['cutoff_period_id'] = null;
    }
    if (base['category_id'] != desired['category_id'] ||
        base['kind'] != desired['kind']) {
      rebased['category'] = desired['category'];
    }
    rebased
      ..['id'] = current.id
      ..['client_uuid'] = current.clientUuid.toLowerCase()
      ..['version'] = current.version
      ..['scope'] = current.scope.apiValue
      ..['source_type'] = null
      ..['source_id'] = null
      ..['source_component'] = null;
    return rebased;
  }

  void _reapplyOfflineTransactionProjection() {
    transactions = _projectTransactionHistory(
      _serverTransactions ?? const [],
      selectedFinanceScope,
    );
    accounts = _projectAccounts(
      _serverAccounts ?? const [],
      selectedFinanceScope,
    );
    final dashboardBaseline = _serverDashboard;
    if (dashboardBaseline != null) {
      dashboard = _projectReportSummary(dashboardBaseline);
    }
    final reportBaseline = _serverReportSummary;
    if (reportBaseline != null) {
      reportSummary = _projectReportSummary(reportBaseline);
    }
    cutoffPeriods = _projectCutoffPeriods(
      _serverCutoffPeriods ?? const [],
      selectedFinanceScope,
    );
  }

  Future<void> syncPendingTransactions({
    bool silent = false,
    bool manual = false,
  }) async {
    if (!offlineTransactionsEnabled ||
        (_isSyncingTransactions ?? false) ||
        _offlineBlockingMessage != null) {
      return;
    }
    final store = offlineStore;
    if (store == null || _transactionOutbox?.installationId == null) return;
    // Claim the single-flight slot before any reconnect/probe await. A second
    // resume/timer/manual trigger must never invalidate a batch after its
    // frozen envelope has been durably marked in flight.
    final requestToken = (_offlineSyncRequestToken ?? 0) + 1;
    _offlineSyncRequestToken = requestToken;
    _isSyncingTransactions = true;
    if (!silent) notifyListeners();
    final reconnectingFromSavedData = isOffline || api.cacheOnlyReads;
    try {
      if (reconnectingFromSavedData) {
        try {
          await _withFinancialBaselineLock(
            () => _restoreNetworkReadsIfNeeded(activateReads: false),
          );
          notifyListeners();
        } catch (error) {
          _isOffline = true;
          errorMessage = 'Still offline. ${_message(error)}';
          if (!silent) notifyListeners();
          return;
        }
      } else {
        try {
          await _withFinancialBaselineLock(
            () => _verifyBoundInstallation(force: true, forMutation: true),
          );
        } catch (error) {
          errorMessage = _message(error);
          if (!silent) notifyListeners();
          return;
        }
      }
      final now = DateTime.now().toUtc();
      final scopes = <FinanceScope>[];
      for (final operation in offlineTransactionOperations) {
        final isReady =
            operation.status == OfflineOperationStatus.applied ||
            (manual
                ? operation.status == OfflineOperationStatus.queued ||
                      operation.status == OfflineOperationStatus.uncertain ||
                      (operation.status == OfflineOperationStatus.rejected &&
                          operation.retryable)
                : operation.canAutoRetry &&
                      (operation.nextRetryAt == null ||
                          !operation.nextRetryAt!.isAfter(now)));
        if (isReady && !scopes.contains(operation.scope)) {
          scopes.add(operation.scope);
        }
      }
      if (scopes.isEmpty &&
          reconnectingFromSavedData &&
          !_hasAmbiguousTransactionOutcome(selectedFinanceScope)) {
        try {
          await _withFinancialBaselineLock(
            () => _adoptSyncedFinancialData(
              scope: selectedFinanceScope,
              operationUuids: const <String>{},
            ),
          );
          api.cacheOnlyReads = false;
          _isOffline = false;
          errorMessage = null;
        } catch (error) {
          api.cacheOnlyReads = true;
          _isOffline = true;
          errorMessage =
              'Connected, but current financial data could not be refreshed. Saved data remains visible. ${_message(error)}';
        }
        return;
      }
      for (final scope in scopes) {
        if (requestToken != (_offlineSyncRequestToken ?? 0) ||
            _offlineBlockingMessage != null) {
          break;
        }
        var batches = 0;
        final maximumBatches = manual ? 100 : 3;
        do {
          await _withFinancialBaselineLock(
            () => _syncPendingTransactionScope(
              scope: scope,
              store: store,
              requestToken: requestToken,
              silent: silent,
              manual: manual,
            ),
          );
          batches++;
          final retryOutcomeNeedsBackoff = offlineTransactionOperations.any(
            (item) =>
                item.scope == scope &&
                item.status == OfflineOperationStatus.uncertain,
          );
          final hasAnotherQueuedBatch = offlineTransactionOperations.any(
            (item) =>
                item.scope == scope &&
                item.status == OfflineOperationStatus.queued,
          );
          if (isOffline ||
              _offlineBlockingMessage != null ||
              (!manual && retryOutcomeNeedsBackoff) ||
              !hasAnotherQueuedBatch ||
              batches >= maximumBatches) {
            break;
          }
        } while (true);
        if (isOffline) break;
      }
    } finally {
      if (requestToken == (_offlineSyncRequestToken ?? 0)) {
        _isSyncingTransactions = false;
        notifyListeners();
      }
    }
  }

  Future<void> _syncPendingTransactionScope({
    required FinanceScope scope,
    required OfflineStore store,
    required int requestToken,
    required bool silent,
    required bool manual,
  }) async {
    var attempted = <OfflineTransactionOperation>[];
    var committed = false;
    try {
      attempted = await _withOutboxLock(() async {
        final latest = _transactionOutbox!;
        final now = DateTime.now().toUtc();
        final ambiguous = latest.operations
            .where(
              (item) =>
                  item.scope == scope &&
                  (item.status == OfflineOperationStatus.inFlight ||
                      item.status == OfflineOperationStatus.uncertain),
            )
            .toList();
        // An unknown outcome is a same-scope FIFO barrier. Exact-replay it
        // before any later queued sibling; otherwise a fresh baseline could
        // already contain the ambiguous commit and then receive its local
        // projection a second time.
        final candidates = ambiguous.isNotEmpty
            ? (ambiguous.any(
                    (item) => item.status == OfflineOperationStatus.inFlight,
                  )
                  ? <OfflineTransactionOperation>[]
                  : ambiguous
                        .where(
                          (item) =>
                              manual ||
                              (item.canAutoRetry &&
                                  (item.nextRetryAt == null ||
                                      !item.nextRetryAt!.isAfter(now))),
                        )
                        .take(_syncBatchSize)
                        .toList())
            : (manual
                  ? latest.operations
                        .where(
                          (item) =>
                              item.scope == scope &&
                              (item.status == OfflineOperationStatus.queued ||
                                  (item.status ==
                                          OfflineOperationStatus.rejected &&
                                      item.retryable)),
                        )
                        .take(_syncBatchSize)
                        .toList()
                  : latest.operations
                        .where(
                          (item) =>
                              item.scope == scope &&
                              item.canAutoRetry &&
                              (item.nextRetryAt == null ||
                                  !item.nextRetryAt!.isAfter(now)),
                        )
                        .take(_syncBatchSize)
                        .toList());
        if (candidates.isEmpty) return <OfflineTransactionOperation>[];
        final next = TransactionOutbox.fromSnapshot(
          latest.toSnapshot(),
          recoverInFlight: false,
        )..markAttempted(candidates, now);
        await store.saveOutbox(next.toSnapshot());
        _transactionOutbox = next;
        return next.operations
            .where(
              (item) => candidates.any(
                (candidate) => candidate.operationUuid == item.operationUuid,
              ),
            )
            .toList();
      });
      if (attempted.isEmpty) {
        final awaitingRefresh = offlineTransactionOperations
            .where(
              (item) =>
                  item.scope == scope &&
                  item.status == OfflineOperationStatus.applied,
            )
            .map((item) => item.operationUuid)
            .toSet();
        if (awaitingRefresh.isNotEmpty) {
          await _adoptSyncedFinancialData(
            scope: scope,
            operationUuids: awaitingRefresh,
          );
        }
        return;
      }
      _reapplyOfflineTransactionProjection();
      notifyListeners();
      final installationId = _transactionOutbox!.installationId!;
      final batch = await repository.syncTransactions(
        installationId: installationId,
        operations: attempted,
      );
      if (requestToken != (_offlineSyncRequestToken ?? 0)) return;
      await _withOutboxLock(() async {
        final latest = _transactionOutbox!;
        final next = TransactionOutbox.fromSnapshot(
          latest.toSnapshot(),
          recoverInFlight: false,
        )..applyBatch(batch);
        await store.saveOutbox(next.toSnapshot());
        _transactionOutbox = next;
      });
      committed = true;
      _lastSuccessfulSyncAt = batch.serverTime ?? DateTime.now().toUtc();
      _reapplyOfflineTransactionProjection();
      notifyListeners();
    } catch (error) {
      if (requestToken != (_offlineSyncRequestToken ?? 0)) return;
      if (attempted.isNotEmpty) {
        try {
          await _withOutboxLock(() async {
            final latest = _transactionOutbox!;
            final next = TransactionOutbox.fromSnapshot(
              latest.toSnapshot(),
              recoverInFlight: false,
            );
            if (error is ApiException && error.statusCode == 422) {
              final rejected = _invalidBatchOperationUuids(
                attempted,
                error.errors,
              );
              next.markPreprocessingRejected(
                attempted,
                rejectedOperationUuids: rejected,
                message: error.message,
                errors: error.errors,
              );
            } else {
              next.markUncertain(attempted, message: _message(error));
            }
            await store.saveOutbox(next.toSnapshot());
            _transactionOutbox = next;
          });
        } catch (_) {
          // The durable in-flight envelope remains safe for exact replay.
        }
      }
      if (error is ApiException && error.isConnectionError) {
        _isOffline = true;
        api.cacheOnlyReads = true;
      }
      if (error is ApiException && error.code == 'INSTANCE_MISMATCH') {
        _offlineBlockingMessage = error.message;
      }
      _reapplyOfflineTransactionProjection();
      errorMessage =
          'Transactions remain saved on this device. ${_message(error)}';
      if (!silent && error is! ApiException) rethrow;
    } finally {
      if (committed &&
          requestToken == (_offlineSyncRequestToken ?? 0) &&
          !_hasAmbiguousTransactionOutcome(scope)) {
        try {
          final applied = offlineTransactionOperations
              .where(
                (item) =>
                    item.scope == scope &&
                    item.status == OfflineOperationStatus.applied,
              )
              .map((item) => item.operationUuid)
              .toSet();
          // Adopt after every valid batch. Conflict/rejection-only batches also
          // need a canonical server baseline before their local delta is
          // reviewed or discarded.
          await _adoptSyncedFinancialData(
            scope: scope,
            operationUuids: applied,
          );
          _isOffline = false;
          api.cacheOnlyReads = false;
        } catch (error) {
          if (_hasPossiblyCommittedOperations(scope)) {
            _isOffline = true;
            api.cacheOnlyReads = true;
          }
          errorMessage =
              'Transactions synced, but some saved totals are still awaiting refresh. ${_message(error)}';
        }
      }
    }
  }

  Future<List<TransactionRecord>> _adoptSyncedFinancialData({
    required FinanceScope scope,
    required Set<String> operationUuids,
  }) async {
    if (_hasAmbiguousTransactionOutcome(scope)) {
      throw FormatException(
        'Resolve the uncertain ${scope.label} transaction outcome before refreshing financial totals.',
      );
    }
    final store = offlineStore;
    final installationId = _transactionOutbox?.installationId;
    if (store == null || installationId == null) return const [];
    final requestedScopeGeneration = _financeScopeRequestToken ?? 0;
    final requestedAnchor = DateTime(anchor.year, anchor.month, anchor.day);
    final requestedPeriod = selectedPeriod;
    final requestedReportToken = _reportRequestToken ?? 0;
    final first = DateTime(requestedAnchor.year, requestedAnchor.month - 1, 1);
    final last = DateTime(requestedAnchor.year, requestedAnchor.month + 2, 0);
    final accountQuery = <String, Object?>{
      'include_archived': 0,
      'scope': scope.apiValue,
    };
    final dashboardQuery = <String, Object?>{
      'period': requestedPeriod,
      'anchor': apiDate(requestedAnchor),
      'scope': scope.apiValue,
    };
    final cutoffQuery = <String, Object?>{
      'from': apiDate(first),
      'to': apiDate(last),
      'scope': scope.apiValue,
    };
    final accountsResponse = await api.networkGet(
      '/accounts',
      query: accountQuery,
    );
    final loadedAccounts = _responseItems(accountsResponse)
        .map(Account.fromJson)
        .toList();
    if (loadedAccounts.any(
      (account) =>
          account.scope != scope ||
          !account.hasConsistentClassificationMetadata,
    )) {
      throw const FormatException(
        'The coordinated account refresh returned inconsistent account metadata.',
      );
    }

    var transactionPages = <Object?>[];
    final loadedTransactions = await _loadTransactionPages(
      scope,
      networkOnly: true,
      savePages: (pages) async => transactionPages = pages,
    );
    if (_hasUnsafeJointSplitProjections(loadedTransactions)) {
      throw const FormatException(
        'The coordinated transaction refresh returned an unsafe split expense.',
      );
    }
    _validateAppliedOperationsAgainstBaseline(
      scope: scope,
      operationUuids: operationUuids,
      transactions: loadedTransactions,
    );

    final dashboardResponse = await api.networkGet(
      '/dashboard',
      query: dashboardQuery,
    );
    final loadedDashboard = ReportSummary.fromJson(
      dashboardResponse,
      fallbackPeriod: requestedPeriod,
    );
    if (loadedDashboard.scope != scope ||
        !loadedDashboard.hasConsistentAccountMoneyMetadata ||
        loadedDashboard.recentTransactions.any(
          (transaction) =>
              transaction.account?.hasConsistentClassificationMetadata == false,
        ) ||
        _hasUnsafeJointSplitProjections(loadedDashboard.recentTransactions) ||
        (scope == FinanceScope.joint &&
            loadedDashboard.hasJointObligations &&
            _hasUnsafeJointObligations(loadedDashboard.jointObligations))) {
      throw const FormatException(
        'The coordinated dashboard refresh returned inconsistent data.',
      );
    }

    final cutoffResponse = await api.networkGet(
      '/cutoff-periods',
      query: cutoffQuery,
    );
    final loadedCutoffs = _responseItems(cutoffResponse)
        .map(CutoffPeriod.fromJson)
        .toList();
    if (loadedCutoffs.any((period) => period.scope != scope)) {
      throw const FormatException(
        'The coordinated cutoff refresh returned another money scope.',
      );
    }

    Object? reportResponse;
    ReportSummary? loadedReport;
    Map<String, Object?>? reportQuery;
    final currentReport = reportSummary;
    if (currentReport != null && currentReport.scope == scope) {
      reportQuery = <String, Object?>{
        'period': currentReport.period,
        'anchor': apiDate(requestedAnchor),
        'scope': scope.apiValue,
      };
      reportResponse = await api.networkGet(
        '/reports/summary',
        query: reportQuery,
      );
      loadedReport = ReportSummary.fromJson(
        reportResponse,
        fallbackPeriod: currentReport.period,
      );
      if (loadedReport.scope != scope ||
          !loadedReport.hasConsistentAccountMoneyMetadata ||
          loadedReport.recentTransactions.any(
            (transaction) =>
                transaction.account?.hasConsistentClassificationMetadata ==
                false,
          ) ||
          _hasUnsafeJointSplitProjections(loadedReport.recentTransactions)) {
        throw const FormatException(
          'The coordinated report refresh returned inconsistent data.',
        );
      }
    }

    final included = await store.includedFinancialOperationUuids(
      scope.apiValue,
    );
    included.addAll(operationUuids);
    final responses = <String, Object?>{
      api.cacheKeyFor('/accounts', query: accountQuery): accountsResponse,
      api.cacheKeyFor('/dashboard', query: dashboardQuery): dashboardResponse,
      api.cacheKeyFor('/cutoff-periods', query: cutoffQuery): cutoffResponse,
      if (reportResponse != null && reportQuery != null)
        api.cacheKeyFor('/reports/summary', query: reportQuery): reportResponse,
    };
    await store.saveFinancialSnapshot(
      installationId: installationId,
      scope: scope.apiValue,
      responses: responses,
      datasets: {_offlineDatasetKey('transactions', scope): transactionPages},
      includedOperationUuids: included,
    );
    // The durable cache now includes these operations even if this scope is
    // not visible. Publish the watermark before attempting outbox retirement
    // so a same-process scope switch cannot project a surviving receipt twice.
    (_includedFinancialOperationUuids ??=
            <FinanceScope, Set<String>>{})[scope] =
        included;
    final scopeStillCurrent =
        scope == selectedFinanceScope &&
        requestedScopeGeneration == (_financeScopeRequestToken ?? 0);
    final periodStillCurrent =
        scopeStillCurrent &&
        requestedPeriod == selectedPeriod &&
        requestedAnchor == DateTime(anchor.year, anchor.month, anchor.day);
    if (scopeStillCurrent) {
      _serverAccounts = loadedAccounts;
      accounts = _projectAccounts(loadedAccounts, scope);
      _serverTransactions = loadedTransactions;
      transactions = _projectTransactionHistory(loadedTransactions, scope);
      if (scope == FinanceScope.joint) {
        final systemAccount = accounts
            .where((account) => account.isDealsPenaltyMoney)
            .firstOrNull;
        _applyDealsPenaltyMoneySnapshot(
          systemAccount,
          systemAccount?.balanceMinor ?? 0,
        );
      }
    }
    if (periodStillCurrent) {
      _serverDashboard = loadedDashboard;
      dashboard = _projectReportSummary(loadedDashboard);
      _serverCutoffPeriods = loadedCutoffs;
      cutoffPeriods = _projectCutoffPeriods(loadedCutoffs, scope);
      if (loadedReport != null &&
          requestedReportToken == (_reportRequestToken ?? 0)) {
        _serverReportSummary = loadedReport;
        reportSummary = _projectReportSummary(loadedReport);
      }
    }
    if (scopeStillCurrent) {
      _lastSavedDataAt = DateTime.now().toUtc();
      notifyListeners();
    }
    await _withOutboxLock(() async {
      final latest = _transactionOutbox!;
      final next = TransactionOutbox.fromSnapshot(
        latest.toSnapshot(),
        recoverInFlight: false,
      )..removeApplied(operationUuids);
      await store.saveOutbox(next.toSnapshot());
      _transactionOutbox = next;
    });
    return loadedTransactions;
  }

  void _validateAppliedOperationsAgainstBaseline({
    required FinanceScope scope,
    required Set<String> operationUuids,
    required List<TransactionRecord> transactions,
  }) {
    final byId = {
      for (final transaction in transactions) transaction.id: transaction,
    };
    final operations = offlineTransactionOperations.where(
      (operation) =>
          operation.scope == scope &&
          operationUuids.contains(operation.operationUuid) &&
          operation.status == OfflineOperationStatus.applied,
    );
    for (final operation in operations) {
      if (operation.action == OfflineTransactionAction.delete) {
        if (byId.containsKey(operation.serverId)) {
          throw const FormatException(
            'The refreshed transaction history still contains a deleted transaction.',
          );
        }
        continue;
      }
      final receipt = operation.desiredTransaction;
      final canonical = receipt == null ? null : byId[receipt.id];
      // The sync receipt is immutable. A later remote delete legitimately
      // makes that applied create/update absent from the complete active list;
      // absence is therefore a superseding state, not a reason to resurrect
      // the receipt projection forever.
      if (receipt == null) {
        throw const FormatException(
          'The applied transaction receipt was incomplete.',
        );
      }
      if (canonical == null) continue;
      if (canonical.isManagedTransaction ||
          canonical.clientUuid.toLowerCase() !=
              receipt.clientUuid.toLowerCase() ||
          canonical.scope != receipt.scope ||
          canonical.version < receipt.version ||
          (canonical.version == receipt.version &&
              !_sameCanonicalTransaction(canonical, receipt))) {
        throw const FormatException(
          'The refreshed transaction history did not confirm an applied transaction.',
        );
      }
    }
  }

  bool _sameCanonicalTransaction(
    TransactionRecord first,
    TransactionRecord second,
  ) =>
      first.id == second.id &&
      first.clientUuid.toLowerCase() == second.clientUuid.toLowerCase() &&
      first.scope == second.scope &&
      first.version == second.version &&
      first.kind == second.kind &&
      first.amountMinor == second.amountMinor &&
      first.occurredOn == second.occurredOn &&
      first.accountId == second.accountId &&
      first.categoryId == second.categoryId &&
      first.cutoffPeriodId == second.cutoffPeriodId &&
      first.payee?.trim() == second.payee?.trim() &&
      first.note?.trim() == second.note?.trim() &&
      !first.isManagedTransaction;

  List<dynamic> _responseItems(Object? response) {
    final data = dataOf(response);
    if (data is List) return data;
    final map = jsonMap(data);
    final nested = map['items'] ?? map['data'];
    return nested is List ? nested : const [];
  }

  Future<void> saveAccount({
    Account? existing,
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
  }) => _mutation(() async {
    _requireSynchronizedTransactions(existing?.scope ?? scope);
    if (existing != null && existing.isSavingsAccount != (type == 'savings')) {
      throw const FormatException(
        'Accounts cannot be converted between savings and everyday account types.',
      );
    }
    final requestedRateBasisPoints = type == 'savings'
        ? monthlyInterestRateBasisPoints ??
              existing?.monthlyInterestRateBasisPoints ??
              0
        : 0;
    if (requestedRateBasisPoints < 0 || requestedRateBasisPoints > 10000) {
      throw const FormatException(
        'Monthly interest rate must be from 0% to 100%.',
      );
    }
    if (type == 'savings' && openingBalanceMinor < 0) {
      throw const FormatException(
        'Savings opening balance cannot be negative.',
      );
    }
    final switchToCreatedScope =
        existing == null && scope != selectedFinanceScope;
    final requestedScope = existing?.scope ?? scope;
    late final Account saved;
    try {
      if (existing == null) {
        saved = await repository.createAccount(
          name: name,
          type: type,
          openingBalanceMinor: openingBalanceMinor,
          color: color,
          scope: scope,
          openingDebtMinor: openingDebtMinor,
          creditLimitMinor: creditLimitMinor,
          statementDay: statementDay,
          dueDay: dueDay,
          cardDesign: cardDesign,
          monthlyInterestRateBasisPoints: requestedRateBasisPoints,
        );
      } else {
        saved = await repository.updateAccount(
          existing.id,
          name: name,
          type: type,
          openingBalanceMinor: openingBalanceMinor,
          color: color,
          openingDebtMinor: openingDebtMinor,
          creditLimitMinor: creditLimitMinor,
          statementDay: statementDay,
          dueDay: dueDay,
          cardDesign: cardDesign,
          monthlyInterestRateBasisPoints: requestedRateBasisPoints,
        );
      }
      if (saved.id <= 0 ||
          (existing != null && saved.id != existing.id) ||
          saved.scope != requestedScope ||
          saved.type != type ||
          !saved.hasConsistentClassificationMetadata ||
          !saved.hasConsistentInterestScheduleMetadata ||
          (type == 'savings' &&
              saved.monthlyInterestRateBasisPoints !=
                  requestedRateBasisPoints)) {
        throw ApiException(
          message: 'The saved account response did not match its savings settings. Refresh accounts before trying again.',
        );
      }
    } catch (error, stackTrace) {
      if (existing?.isSavingsAccount == true) {
        try {
          await _refreshAfterCommittedSavingsInterest(
            scope: requestedScope,
            scopeGeneration: _financeScopeRequestToken ?? 0,
          );
        } catch (_) {
          // Settling old-rate interest can commit before a PATCH fails or its
          // response is lost. Reconciliation must not replace that failure.
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    if (switchToCreatedScope) {
      await setFinanceScope(scope);
      return;
    }
    if (existing?.isSavingsAccount == true) {
      await _refreshAfterCommittedSavingsInterest(
        scope: requestedScope,
        scopeGeneration: _financeScopeRequestToken ?? 0,
      );
      return;
    }
    await Future.wait([_loadAccounts(), refreshDashboard(silent: true)]);
  });

  Future<void> deleteAccount(Account account) => _mutation(() async {
    _requireSynchronizedTransactions(account.scope);
    try {
      await repository.deleteAccount(account.id);
    } catch (error, stackTrace) {
      if (account.isSavingsAccount) {
        try {
          await _refreshAfterCommittedSavingsInterest(
            scope: account.scope,
            scopeGeneration: _financeScopeRequestToken ?? 0,
          );
        } catch (_) {
          // Savings interest may have committed before an archive error or a
          // lost response. Keep the original archive failure authoritative.
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    await Future.wait([
      _loadAccounts(),
      refreshDashboard(silent: true),
      refreshTransactions(silent: true),
    ]);
  });

  Future<AccountTransfer> saveAccountTransfer({
    required FinanceScope scope,
    required String clientUuid,
    required int sourceAccountId,
    required int destinationAccountId,
    required int amountMinor,
    required DateTime transferredOn,
    required int serviceChargeMinor,
    String? note,
  }) => _withFinancialBaselineLock(() async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _verifyBoundInstallation(force: true, forMutation: true);
      _requireSynchronizedTransactions(scope);
      if (scope != selectedFinanceScope) {
        throw const FormatException(
          'The money scope changed. Reopen Transfer money and try again.',
        );
      }
      if (clientUuid.trim().isEmpty) {
        throw const FormatException('A stable transfer reference is required.');
      }
      if (sourceAccountId == destinationAccountId) {
        throw const FormatException(
          'Choose two different accounts for this transfer.',
        );
      }
      if (amountMinor <= 0) {
        throw const FormatException(
          'Transfer amount must be greater than zero.',
        );
      }
      if (serviceChargeMinor < 0) {
        throw const FormatException('Service charge cannot be negative.');
      }
      final totalDebit =
          BigInt.from(amountMinor) + BigInt.from(serviceChargeMinor);
      if (totalDebit > BigInt.from(Money.maxMinorUnits)) {
        throw const FormatException('The total source debit is too large.');
      }
      final transferDate = DateTime(
        transferredOn.year,
        transferredOn.month,
        transferredOn.day,
      );
      final available = accountTransferAccounts;
      final source = available
          .where((account) => account.id == sourceAccountId)
          .firstOrNull;
      final destination = available
          .where((account) => account.id == destinationAccountId)
          .firstOrNull;
      if (source == null || destination == null) {
        throw FormatException(
          'Choose active ${scope.label} everyday or savings accounts for this transfer.',
        );
      }
      final frozenSavingsAccount = [source, destination]
          .where(
            (account) =>
                account.isSavingsAccount &&
                account.interestLastProcessedOn != null &&
                transferDate.isBefore(account.interestLastProcessedOn!),
          )
          .firstOrNull;
      if (frozenSavingsAccount != null) {
        throw FormatException(
          'Transfer date cannot be before ${apiDate(frozenSavingsAccount.interestLastProcessedOn!)} for ${frozenSavingsAccount.displayName}. Automatic interest through that date is already finalized.',
        );
      }
      if (source.balanceMinor < totalDebit.toInt()) {
        throw const FormatException(
          'The source account does not have enough available balance for the amount and service charge.',
        );
      }
      final scopeGeneration = _financeScopeRequestToken ?? 0;
      final requestedNote = (note?.trim().isEmpty ?? true)
          ? null
          : note!.trim();
      final saved = await repository.createAccountTransfer(
        clientUuid: clientUuid,
        sourceAccountId: sourceAccountId,
        destinationAccountId: destinationAccountId,
        amountMinor: amountMinor,
        transferredOn: transferDate,
        serviceChargeMinor: serviceChargeMinor,
        note: requestedNote,
      );
      if (_hasUnsafeAccountTransfer(saved) ||
          saved.scope != scope ||
          saved.clientUuid.toLowerCase() != clientUuid.toLowerCase() ||
          saved.sourceAccountId != sourceAccountId ||
          saved.destinationAccountId != destinationAccountId ||
          saved.amountMinor != amountMinor ||
          saved.serviceChargeMinor != serviceChargeMinor ||
          saved.transferredOn != transferDate ||
          saved.note != requestedNote) {
        throw ApiException(
          message: 'The transfer response did not match the requested movement. Refresh balances before trying again.',
        );
      }

      if (_isCurrentScopedRequest(scope, scopeGeneration)) {
        _accountTransfers = [
          saved,
          ...accountTransfers.where((transfer) => transfer.id != saved.id),
        ];
        await _refreshAfterCommittedAccountTransfer(
          scope: scope,
          scopeGeneration: scopeGeneration,
          refreshCategories: serviceChargeMinor > 0,
        );
      }
      return saved;
    } catch (error) {
      errorMessage = _message(error);
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  });

  Future<CreditCardPayment> saveCreditCardPayment({
    required FinanceScope scope,
    required String clientUuid,
    required int sourceAccountId,
    required int creditCardAccountId,
    required int amountMinor,
    required DateTime paidOn,
    int serviceChargeMinor = 0,
    String? note,
  }) => _withFinancialBaselineLock(() async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _verifyBoundInstallation(force: true, forMutation: true);
      _requireSynchronizedTransactions(scope);
      if (scope != selectedFinanceScope) {
        throw const FormatException(
          'The money scope changed. Reopen Pay card and try again.',
        );
      }
      if (!_looksLikeUuid(clientUuid)) {
        throw const FormatException(
          'A stable card payment reference is required.',
        );
      }
      if (sourceAccountId == creditCardAccountId) {
        throw const FormatException('Choose a cash account and a credit card.');
      }
      if (amountMinor <= 0 || amountMinor > Money.maxMinorUnits) {
        throw const FormatException(
          'Payment amount must be greater than zero.',
        );
      }
      if (serviceChargeMinor < 0) {
        throw const FormatException('Service charge cannot be negative.');
      }
      final totalDebit =
          BigInt.from(amountMinor) + BigInt.from(serviceChargeMinor);
      if (totalDebit > BigInt.from(Money.maxMinorUnits)) {
        throw const FormatException('The total source debit is too large.');
      }
      final today = DateTime.now();
      final paymentDate = DateTime(paidOn.year, paidOn.month, paidOn.day);
      if (paymentDate.isAfter(DateTime(today.year, today.month, today.day))) {
        throw const FormatException('Payment date cannot be in the future.');
      }
      final source = creditCardPaymentSourceAccounts
          .where((account) => account.id == sourceAccountId)
          .firstOrNull;
      final card = creditCardAccounts
          .where((account) => account.id == creditCardAccountId)
          .firstOrNull;
      if (source == null || card == null) {
        throw FormatException(
          'Choose an active ${scope.label} cash account and credit card.',
        );
      }
      if (BigInt.from(source.balanceMinor) < totalDebit) {
        throw const FormatException(
          'The payment account does not have enough available cash for the payment and service charge.',
        );
      }
      if (card.debtMinor < amountMinor) {
        throw const FormatException(
          'Payment cannot be greater than the current card debt.',
        );
      }
      final scopeGeneration = _financeScopeRequestToken ?? 0;
      final requestedNote = (note?.trim().isEmpty ?? true)
          ? null
          : note!.trim();
      final saved = await repository.createCreditCardPayment(
        clientUuid: clientUuid,
        sourceAccountId: sourceAccountId,
        creditCardAccountId: creditCardAccountId,
        amountMinor: amountMinor,
        paidOn: paymentDate,
        serviceChargeMinor: serviceChargeMinor,
        note: requestedNote,
      );
      if (_hasUnsafeCreditCardPayment(saved) ||
          saved.scope != scope ||
          saved.clientUuid != clientUuid ||
          saved.sourceAccountId != sourceAccountId ||
          saved.creditCardAccountId != creditCardAccountId ||
          saved.amountMinor != amountMinor ||
          saved.serviceChargeMinor != serviceChargeMinor ||
          saved.paidOn != paymentDate ||
          saved.note != requestedNote) {
        throw ApiException(
          message: 'The card payment response did not match the requested payment. Refresh balances before trying again.',
        );
      }
      if (_isCurrentScopedRequest(scope, scopeGeneration)) {
        _creditCardPayments = [
          saved,
          ...creditCardPayments.where((payment) => payment.id != saved.id),
        ];
        await _refreshAfterCommittedCreditCardPayment(
          scope: scope,
          scopeGeneration: scopeGeneration,
          refreshManagedExpenseData: serviceChargeMinor > 0,
        );
      }
      return saved;
    } catch (error) {
      errorMessage = _message(error);
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  });

  Future<SavingsInterestCredit> saveSavingsInterestCredit({
    required FinanceScope scope,
    required String clientUuid,
    required int savingsAccountId,
    required int amountMinor,
    required DateTime creditedOn,
    String? note,
  }) => _withFinancialBaselineLock(() async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _verifyBoundInstallation(force: true, forMutation: true);
      _requireSynchronizedTransactions(scope);
      final normalizedClientUuid = clientUuid.trim().toLowerCase();
      if (scope != selectedFinanceScope) {
        throw const FormatException(
          'The money scope changed. Reopen Savings and try again.',
        );
      }
      if (!_looksLikeUuid(normalizedClientUuid)) {
        throw const FormatException(
          'A stable savings interest reference is required.',
        );
      }
      if (amountMinor <= 0 || amountMinor > Money.maxMinorUnits) {
        throw const FormatException(
          'Interest amount must be greater than zero.',
        );
      }
      final creditDate = DateTime(
        creditedOn.year,
        creditedOn.month,
        creditedOn.day,
      );
      final account = savingsAccounts
          .where((item) => item.id == savingsAccountId)
          .firstOrNull;
      if (account == null) {
        throw FormatException(
          'Choose an active ${scope.label} savings account.',
        );
      }
      final scopeGeneration = _financeScopeRequestToken ?? 0;
      final requestedNote = (note?.trim().isEmpty ?? true)
          ? null
          : note!.trim();
      final saved = await repository.createSavingsInterestCredit(
        clientUuid: normalizedClientUuid,
        savingsAccountId: savingsAccountId,
        amountMinor: amountMinor,
        creditedOn: creditDate,
        note: requestedNote,
      );
      if (_hasUnsafeSavingsInterestCredit(saved) ||
          saved.scope != scope ||
          saved.clientUuid.toLowerCase() != normalizedClientUuid ||
          saved.savingsAccountId != savingsAccountId ||
          saved.amountMinor != amountMinor ||
          saved.creditedOn != creditDate ||
          saved.note != requestedNote) {
        throw ApiException(
          message: 'The savings interest response did not match the requested credit. Refresh balances before trying again.',
        );
      }
      if (_isCurrentScopedRequest(scope, scopeGeneration)) {
        _savingsInterestCredits = [
          saved,
          ...savingsInterestCredits.where((credit) => credit.id != saved.id),
        ];
        await _refreshAfterCommittedSavingsInterest(
          scope: scope,
          scopeGeneration: scopeGeneration,
        );
      }
      return saved;
    } catch (error) {
      errorMessage = _message(error);
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  });

  Future<void> refreshJewelry() =>
      _withFinancialBaselineLock(_refreshJewelryUnlocked);

  Future<void> _refreshJewelryUnlocked() async {
    isRefreshing = true;
    goldPriceRefreshNotice = null;
    notifyListeners();
    try {
      await _loadGoldPrice();
      await Future.wait([_loadJewelry(), _loadManualGoldPrices()]);
      errorMessage = null;
      await refreshDashboard(silent: true);
    } catch (error) {
      errorMessage = _message(error);
    } finally {
      isRefreshing = false;
      notifyListeners();
    }
  }

  Future<void> refreshGoldPrice() =>
      _withFinancialBaselineLock(_refreshGoldPriceUnlocked);

  Future<void> _refreshGoldPriceUnlocked() async {
    if (isGoldPriceRefreshing) return;
    isGoldPriceRefreshing = true;
    goldPriceRefreshNotice = null;
    notifyListeners();
    try {
      await _verifyBoundInstallation(force: true, forMutation: true);
      final quote = await _loadGoldPrice(refresh: true);
      if (quote == null || !_isLiveGoldPrice(quote)) return;

      try {
        final refreshedData = await Future.wait<Object>([
          repository.manualGoldPrices(),
          repository.jewelry(),
        ]);
        manualGoldPrices = refreshedData[0] as ManualGoldPriceList;
        jewelryItems = refreshedData[1] as List<JewelryItem>;
        manualGoldPricesLoaded = true;
        _manualGoldPricesBaselineLoaded = true;
        _jewelryBaselineLoaded = true;
        manualGoldPriceError = null;
        goldPriceRefreshNotice = _goldPriceRefreshMessage(quote);

        try {
          final dashboardApplied = await _loadDashboard();
          if (dashboardApplied) errorMessage = null;
        } catch (error) {
          final message = _message(error);
          errorMessage = message;
          goldPriceRefreshNotice =
              '${goldPriceRefreshNotice!} The dashboard gold total could not be refreshed: $message';
        }
      } catch (error) {
        manualGoldPricesLoaded = false;
        manualGoldPriceError = _message(error);
        goldPriceError =
            'The latest online price was saved, but Budget Flow could not reload the updated saved prices and jewelry: ${_message(error)}';
      }
    } finally {
      isGoldPriceRefreshing = false;
      notifyListeners();
    }
  }

  Future<void> saveManualGoldPrices(List<ManualGoldPriceRate> rates) =>
      _mutation(() async {
        manualGoldPrices = await repository.updateManualGoldPrices(rates);
        manualGoldPricesLoaded = true;
        _manualGoldPricesBaselineLoaded = true;
        manualGoldPriceError = null;
        goldPriceRefreshNotice = null;
      });

  Future<void> refreshManualGoldPrices() =>
      _withFinancialBaselineLock(_refreshManualGoldPricesUnlocked);

  Future<void> _refreshManualGoldPricesUnlocked() async {
    if (isManualGoldPriceRefreshing) return;
    isManualGoldPriceRefreshing = true;
    notifyListeners();
    try {
      await _loadManualGoldPrices();
    } finally {
      isManualGoldPriceRefreshing = false;
      notifyListeners();
    }
  }

  Future<void> saveJewelry({
    JewelryItem? existing,
    required String name,
    required String jewelryType,
    required int karat,
    required int weightMg,
    DateTime? acquiredOn,
    int? purchaseValueMinor,
    required int estimatedValueMinor,
    String? notes,
  }) => _mutation(() async {
    if (existing == null) {
      await repository.createJewelry(
        name: name,
        jewelryType: jewelryType,
        karat: karat,
        weightMg: weightMg,
        acquiredOn: acquiredOn,
        purchaseValueMinor: purchaseValueMinor,
        estimatedValueMinor: estimatedValueMinor,
        notes: notes,
      );
    } else {
      await repository.updateJewelry(
        existing.id,
        name: name,
        jewelryType: jewelryType,
        karat: karat,
        weightMg: weightMg,
        acquiredOn: acquiredOn,
        purchaseValueMinor: purchaseValueMinor,
        estimatedValueMinor: estimatedValueMinor,
        notes: notes,
      );
    }
    await _loadJewelry();
    await refreshDashboard(silent: true);
  });

  Future<void> deleteJewelry(JewelryItem item) => _mutation(() async {
    await repository.deleteJewelry(item.id);
    await _loadJewelry();
    await refreshDashboard(silent: true);
  });

  Future<void> convertJewelry({
    required JewelryItem item,
    required String clientUuid,
    required int accountId,
    required int amountMinor,
    required DateTime convertedOn,
  }) => _mutation(() async {
    final destination = accounts
        .where((account) => account.id == accountId)
        .firstOrNull;
    if (destination == null ||
        destination.isArchived ||
        !destination.isStandardAccount ||
        destination.isCreditCard) {
      throw const FormatException(
        'Choose an active cash, bank, or e-wallet account for the gold proceeds.',
      );
    }
    _requireSynchronizedTransactions(destination.scope);
    await repository.convertJewelry(
      item.id,
      clientUuid: clientUuid,
      accountId: accountId,
      amountMinor: amountMinor,
      convertedOn: convertedOn,
    );
    await Future.wait([_loadJewelry(), _refreshFinancialData()]);
  });

  Future<void> saveCategory({
    Category? existing,
    required String name,
    required String kind,
    required String color,
    required String icon,
  }) => _mutation(() async {
    _requireSynchronizedTransactions(selectedFinanceScope, allScopes: true);
    if (existing?.isSystem == true) {
      throw const FormatException(
        'System categories are managed automatically and cannot be edited here.',
      );
    }
    if (existing == null) {
      await repository.createCategory(
        name: name,
        kind: kind,
        color: color,
        icon: icon,
      );
    } else {
      await repository.updateCategory(
        existing.id,
        name: name,
        kind: kind,
        color: color,
        icon: icon,
      );
    }
    await _loadCategories();
  });

  Future<void> deleteCategory(Category category) => _mutation(() async {
    _requireSynchronizedTransactions(selectedFinanceScope, allScopes: true);
    if (category.isSystem) {
      throw const FormatException(
        'System categories are managed automatically and cannot be deleted.',
      );
    }
    await repository.deleteCategory(category.id);
    await Future.wait([
      _loadCategories(),
      refreshDashboard(silent: true),
      refreshTransactions(silent: true),
    ]);
  });

  Future<void> updateCutoffBudget(CutoffPeriod period, int amountMinor) =>
      _mutation(() async {
        _requireSynchronizedTransactions(period.scope);
        await repository.updateCutoffBudget(
          period.id,
          totalBudgetMinor: amountMinor,
          items: period.items
              .map(
                (item) => {
                  'category_id': item.categoryId,
                  'amount_minor': item.budgetMinor,
                },
              )
              .toList(),
        );
        await Future.wait([
          refreshCutoffs(silent: true),
          refreshDashboard(silent: true),
        ]);
      });

  Future<void> resetCutoffBudget(CutoffPeriod period) => _mutation(() async {
    _requireSynchronizedTransactions(period.scope);
    await repository.resetCutoffBudget(period.id);
    await Future.wait([
      refreshCutoffs(silent: true),
      refreshDashboard(silent: true),
    ]);
  });

  Future<void> saveSettings(AppSettings next) => _mutation(() async {
    _requireSynchronizedTransactions(selectedFinanceScope, allScopes: true);
    settings = await repository.updateSettings(next);
  });

  Future<void> createSchedule({
    required String name,
    required DateTime effectiveFrom,
    required int firstBudgetMinor,
    required int secondBudgetMinor,
  }) => _mutation(() async {
    final scope = selectedFinanceScope;
    _requireSynchronizedTransactions(scope);
    await repository.createCutoffSchedule(
      name: name,
      effectiveFrom: DateTime(effectiveFrom.year, effectiveFrom.month, 1),
      rules: [
        {
          'label': 'First cutoff',
          'start_day': 1,
          'default_budget_minor': firstBudgetMinor,
        },
        {
          'label': 'Second cutoff',
          'start_day': 16,
          'default_budget_minor': secondBudgetMinor,
        },
      ],
      scope: scope,
    );
    await Future.wait([_loadSchedules(), refreshCutoffs(silent: true)]);
  });

  Future<void> _mutation(
    Future<void> Function() action, {
    bool allowOffline = false,
  }) async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      if (!allowOffline && (isOffline || api.cacheOnlyReads)) {
        throw const FormatException(
          'This change requires a live connection. Only ordinary transactions can be saved offline.',
        );
      }
      await _withFinancialBaselineLock(() async {
        if (!allowOffline) {
          await _verifyBoundInstallation(force: true, forMutation: true);
        }
        await action();
      });
    } catch (error) {
      errorMessage = _message(error);
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  void _requireSynchronizedTransactions(
    FinanceScope scope, {
    bool allScopes = false,
  }) {
    if (isOffline || api.cacheOnlyReads) {
      throw const FormatException(
        'This change requires a live connection. Reconnect and sync transactions first.',
      );
    }
    final hasBlockingOperation = offlineTransactionOperations.any(
      (operation) => allScopes || operation.scope == scope,
    );
    if (hasBlockingOperation) {
      throw FormatException(
        allScopes
            ? 'Sync or resolve every pending transaction before changing categories.'
            : 'Sync or resolve pending ${scope.label} transactions before making this balance or budget change.',
      );
    }
  }

  bool _hasPossiblyCommittedOperations([FinanceScope? scope]) =>
      offlineTransactionOperations.any(
        (operation) =>
            (scope == null || operation.scope == scope) &&
            (operation.status == OfflineOperationStatus.inFlight ||
                operation.status == OfflineOperationStatus.applied ||
                operation.status == OfflineOperationStatus.uncertain),
      );

  bool _hasAmbiguousTransactionOutcome(FinanceScope scope) =>
      offlineTransactionOperations.any(
        (operation) =>
            operation.scope == scope &&
            (operation.status == OfflineOperationStatus.inFlight ||
                operation.status == OfflineOperationStatus.uncertain),
      );

  Set<String> _invalidBatchOperationUuids(
    List<OfflineTransactionOperation> attempted,
    Map<String, List<String>> errors,
  ) {
    final indexes = <int>{};
    var rejectAll = errors.isEmpty;
    for (final key in errors.keys) {
      final match = RegExp(r'^operations\.(\d+)(?:\.|$)').firstMatch(key);
      if (match == null) {
        rejectAll = true;
        continue;
      }
      final index = int.tryParse(match.group(1)!);
      if (index == null || index < 0 || index >= attempted.length) {
        rejectAll = true;
      } else {
        indexes.add(index);
      }
    }
    if (rejectAll) {
      return attempted.map((item) => item.operationUuid).toSet();
    }
    return indexes.map((index) => attempted[index].operationUuid).toSet();
  }

  void _requireSafeFinancialBaselineRead(FinanceScope scope) {
    if (api.cacheOnlyReads) return;
    if (_hasPossiblyCommittedOperations(scope)) {
      throw FormatException(
        'Sync saved ${scope.label} transactions before refreshing financial totals.',
      );
    }
  }

  Future<void> _refreshFinancialData() => Future.wait([
    refreshTransactions(silent: true),
    refreshDashboard(silent: true),
    refreshCutoffs(silent: true),
    _loadAccounts(),
  ]);

  Future<void> _loadSettings() async {
    await _verifyBoundInstallation(force: true);
    settings = await repository.settings();
    _settingsBaselineLoaded = true;
  }

  Future<void> _loadHealth() async {
    health = await repository.health();
  }

  Future<void> _restoreNetworkReadsIfNeeded({bool activateReads = true}) async {
    if (!api.cacheOnlyReads && !isOffline) return;
    await _loadHealth();
    final checked = health;
    if (!(checked?.ok ?? false)) {
      throw ApiException(
        message: checked?.message ?? 'The Budget Flow API is unavailable.',
      );
    }
    await _acceptVerifiedInstallation(checked?.installationId);
    health = checked;
    if (activateReads) {
      api.cacheOnlyReads = false;
      _isOffline = false;
    }
  }

  Future<void> _verifyBoundInstallation({
    bool force = false,
    bool forMutation = false,
  }) async {
    if (offlineStore == null && api.cacheNamespace == null) return;
    if (api.cacheOnlyReads || isOffline) {
      if (forMutation) {
        throw const FormatException(
          'Reconnect to the verified Budget Flow database before making this change.',
        );
      }
      return;
    }
    final expected =
        _transactionOutbox?.installationId?.trim().toLowerCase() ??
        api.cacheNamespace?.trim().toLowerCase();
    if (expected == null || !_looksLikeUuid(expected)) {
      throw const FormatException(
        'Reconnect once to verify this Budget Flow database before using saved financial data.',
      );
    }
    final verifiedAt = _lastVerifiedInstallationAt;
    if (!force &&
        verifiedAt != null &&
        DateTime.now().toUtc().difference(verifiedAt) <
            const Duration(seconds: 3)) {
      return;
    }
    final active = _installationVerification;
    final probe = active ?? _probeBoundInstallation(expected);
    _installationVerification = probe;
    bool verified;
    try {
      verified = await probe;
    } finally {
      if (identical(_installationVerification, probe)) {
        _installationVerification = null;
      }
    }
    if (!verified && forMutation) {
      throw const FormatException(
        'Reconnect to the verified Budget Flow database before making this change.',
      );
    }
  }

  Future<bool> _probeBoundInstallation(String expected) async {
    try {
      final verified = await repository.health();
      if (!verified.ok) {
        _isOffline = true;
        api.cacheOnlyReads = true;
        return false;
      }
      final actual = verified.installationId?.trim().toLowerCase();
      if (actual == null || actual != expected) {
        _offlineBlockingMessage = 'This address now points to a different Budget Flow database. Saved data and transaction changes were kept isolated.';
        _isOffline = true;
        api.cacheOnlyReads = true;
        throw ApiException(
          message: _offlineBlockingMessage!,
          statusCode: 409,
          code: 'INSTANCE_MISMATCH',
        );
      }
      health = verified;
      _lastVerifiedInstallationAt = DateTime.now().toUtc();
      return true;
    } on ApiException catch (error) {
      if (!error.isConnectionError) rethrow;
      _isOffline = true;
      api.cacheOnlyReads = true;
      return false;
    }
  }

  Future<void> _loadAccounts({FinanceScope? scope, bool networkOnly = false}) =>
      _withFinancialBaselineLock(
        () => _loadAccountsUnlocked(scope: scope, networkOnly: networkOnly),
      );

  Future<void> _loadAccountsUnlocked({
    FinanceScope? scope,
    bool networkOnly = false,
  }) async {
    final requestedScope = scope ?? selectedFinanceScope;
    await _verifyBoundInstallation(force: true);
    _requireSafeFinancialBaselineRead(requestedScope);
    final scopeGeneration = _financeScopeRequestToken ?? 0;
    final requestToken = (_accountsRequestToken ?? 0) + 1;
    _accountsRequestToken = requestToken;
    final loaded = await repository.accounts(
      scope: requestedScope,
      networkOnly: networkOnly,
    );
    if (loaded.any(
      (account) =>
          account.scope != requestedScope ||
          !account.hasConsistentClassificationMetadata,
    )) {
      throw const FormatException(
        'The account list returned inconsistent account metadata.',
      );
    }
    if (requestToken == (_accountsRequestToken ?? 0) &&
        _isCurrentScopedRequest(requestedScope, scopeGeneration)) {
      _serverAccounts = loaded;
      accounts = _projectAccounts(_serverAccounts!, requestedScope);
      _accountsBaselineLoaded = true;
      if (requestedScope == FinanceScope.joint) {
        final systemAccount = accounts
            .where((account) => account.isDealsPenaltyMoney)
            .firstOrNull;
        _applyDealsPenaltyMoneySnapshot(
          systemAccount,
          systemAccount?.balanceMinor ?? 0,
        );
      }
    }
  }

  Future<bool> _loadAccountTransfers({FinanceScope? scope}) async {
    final requestedScope = scope ?? selectedFinanceScope;
    await _verifyBoundInstallation(force: true);
    final scopeGeneration = _financeScopeRequestToken ?? 0;
    final requestToken = (_accountTransfersRequestToken ?? 0) + 1;
    _accountTransfersRequestToken = requestToken;
    final loaded = await repository.accountTransfers(
      scope: requestedScope,
      page: 1,
      perPage: 50,
    );
    if (requestToken != (_accountTransfersRequestToken ?? 0) ||
        !_isCurrentScopedRequest(requestedScope, scopeGeneration)) {
      return false;
    }
    if (loaded.items.any(
      (transfer) =>
          transfer.scope != requestedScope ||
          _hasUnsafeAccountTransfer(transfer),
    )) {
      throw ApiException(
        message: 'Transfer history returned inconsistent account or cash effects. Refresh and try again.',
      );
    }
    _accountTransfers = loaded.items;
    _accountTransfersBaselineLoaded = true;
    return true;
  }

  Future<bool> _loadCreditCardPayments({
    FinanceScope? scope,
    bool networkOnly = false,
  }) async {
    final requestedScope = scope ?? selectedFinanceScope;
    await _verifyBoundInstallation(force: true);
    final scopeGeneration = _financeScopeRequestToken ?? 0;
    final requestToken = (_creditCardPaymentsRequestToken ?? 0) + 1;
    _creditCardPaymentsRequestToken = requestToken;
    final loaded = await repository.creditCardPayments(
      scope: requestedScope,
      page: 1,
      perPage: 50,
      networkOnly: networkOnly,
    );
    if (requestToken != (_creditCardPaymentsRequestToken ?? 0) ||
        !_isCurrentScopedRequest(requestedScope, scopeGeneration)) {
      return false;
    }
    if (loaded.items.any(
      (payment) =>
          payment.scope != requestedScope ||
          _hasUnsafeCreditCardPayment(payment),
    )) {
      throw ApiException(
        message: 'Card payment history returned inconsistent cash or debt effects. Refresh and try again.',
      );
    }
    _creditCardPayments = loaded.items;
    _creditCardPaymentsBaselineLoaded = true;
    return true;
  }

  Future<bool> _loadSavingsInterestCredits({
    FinanceScope? scope,
    bool networkOnly = false,
  }) async {
    final requestedScope = scope ?? selectedFinanceScope;
    await _verifyBoundInstallation(force: true);
    final scopeGeneration = _financeScopeRequestToken ?? 0;
    final requestToken = (_savingsInterestCreditsRequestToken ?? 0) + 1;
    _savingsInterestCreditsRequestToken = requestToken;
    final loaded = await repository.savingsInterestCredits(
      scope: requestedScope,
      page: 1,
      perPage: 50,
      networkOnly: networkOnly,
    );
    if (requestToken != (_savingsInterestCreditsRequestToken ?? 0) ||
        !_isCurrentScopedRequest(requestedScope, scopeGeneration)) {
      return false;
    }
    if (loaded.items.any(
      (credit) =>
          credit.scope != requestedScope ||
          _hasUnsafeSavingsInterestCredit(credit),
    )) {
      throw ApiException(
        message: 'Savings interest history returned inconsistent account or money effects. Refresh and try again.',
      );
    }
    _savingsInterestCredits = loaded.items;
    _savingsInterestCreditsBaselineLoaded = true;
    return true;
  }

  void _applyDealsPenaltyMoneySnapshot(Account? account, int balanceMinor) {
    _dealsPenaltyMoneyAccountSnapshot = account;
    _dealsPenaltyMoneyBalanceSnapshot = balanceMinor;
    _hasDealsPenaltyMoneySnapshot = true;
  }

  void _clearDealsPenaltyMoneySnapshot() {
    _dealsPenaltyMoneyAccountSnapshot = null;
    _dealsPenaltyMoneyBalanceSnapshot = null;
    _hasDealsPenaltyMoneySnapshot = false;
  }

  Future<void> _loadJewelry() async {
    await _verifyBoundInstallation(force: true);
    jewelryItems = await repository.jewelry();
    _jewelryBaselineLoaded = true;
  }

  Future<bool> _loadDashboard({bool networkOnly = false}) =>
      _withFinancialBaselineLock(
        () => _loadDashboardUnlocked(networkOnly: networkOnly),
      );

  Future<bool> _loadDashboardUnlocked({bool networkOnly = false}) async {
    await _verifyBoundInstallation(force: true);
    final requestToken = (_dashboardRequestToken ?? 0) + 1;
    _dashboardRequestToken = requestToken;
    final requestedPeriod = selectedPeriod;
    final requestedAnchor = DateTime(anchor.year, anchor.month, anchor.day);
    final requestedScope = selectedFinanceScope;
    _requireSafeFinancialBaselineRead(requestedScope);
    try {
      final loaded = await repository.dashboard(
        period: requestedPeriod,
        anchor: requestedAnchor,
        scope: requestedScope,
        networkOnly: networkOnly,
      );
      if (loaded.scope != requestedScope ||
          !loaded.hasConsistentAccountMoneyMetadata ||
          loaded.recentTransactions.any(
            (transaction) =>
                transaction.account?.hasConsistentClassificationMetadata ==
                false,
          )) {
        throw ApiException(
          message: 'The dashboard returned inconsistent account or savings totals. Refresh and try again.',
        );
      }
      if (requestedScope == FinanceScope.joint &&
          loaded.hasJointObligations &&
          _hasUnsafeJointObligations(loaded.jointObligations)) {
        throw ApiException(
          message: 'The dashboard returned inconsistent penalty cash effects. Refresh and try again.',
        );
      }
      if (_hasUnsafeJointSplitProjections(loaded.recentTransactions)) {
        throw ApiException(
          message: 'The dashboard returned an unsafe split-expense component or total. Refresh and try again.',
        );
      }
      if (!_isCurrentDashboardRequest(
        requestToken,
        requestedPeriod,
        requestedAnchor,
        requestedScope,
      )) {
        return false;
      }
      _serverDashboard = loaded;
      dashboard = _projectReportSummary(loaded);
      return true;
    } catch (_) {
      if (!_isCurrentDashboardRequest(
        requestToken,
        requestedPeriod,
        requestedAnchor,
        requestedScope,
      )) {
        return false;
      }
      rethrow;
    }
  }

  bool _hasUnsafeJointObligations(JointObligationsSummary obligations) {
    if (obligations.affectsCashflow || obligations.affectsBudget) return true;
    final deposits = obligations.externalDepositsInPeriodMinor;
    final reversals = obligations.externalDepositReversalsInPeriodMinor;
    final netAdjustment = obligations.netExternalDepositAdjustmentInPeriodMinor;
    if (deposits < 0 ||
        reversals < 0 ||
        netAdjustment != deposits - reversals) {
      return true;
    }
    if (obligations.affectsAccountBalance !=
        obligations.affectsTotalCashBalance) {
      return true;
    }
    final hasExternalCashEvent =
        deposits != 0 || reversals != 0 || netAdjustment != 0;
    if (hasExternalCashEvent &&
        (!obligations.affectsTotalCashBalance ||
            !obligations.affectsIndividualAccountBalances)) {
      return true;
    }
    if (obligations.affectsTotalCashBalance &&
        (!obligations.affectsIndividualAccountBalances ||
            (obligations.dealsPenaltyMoneyAccount == null &&
                !hasExternalCashEvent))) {
      return true;
    }
    return false;
  }

  bool _isCurrentDashboardRequest(
    int requestToken,
    String requestedPeriod,
    DateTime requestedAnchor,
    FinanceScope requestedScope,
  ) =>
      requestToken == (_dashboardRequestToken ?? 0) &&
      requestedPeriod == selectedPeriod &&
      requestedAnchor.year == anchor.year &&
      requestedAnchor.month == anchor.month &&
      requestedAnchor.day == anchor.day &&
      requestedScope == selectedFinanceScope;

  Future<GoldPriceQuote?> _loadGoldPrice({bool refresh = false}) async {
    try {
      await _verifyBoundInstallation(force: true);
      goldPriceQuote = await repository.goldPrice(refresh: refresh);
      _goldPriceBaselineLoaded = true;
      goldPriceError = null;
      return goldPriceQuote;
    } catch (error) {
      goldPriceError = _message(error);
      return null;
    }
  }

  Future<void> _loadManualGoldPrices() async {
    try {
      await _verifyBoundInstallation(force: true);
      manualGoldPrices = await repository.manualGoldPrices();
      manualGoldPricesLoaded = true;
      _manualGoldPricesBaselineLoaded = true;
      manualGoldPriceError = null;
    } catch (error) {
      manualGoldPriceError = _message(error);
    }
  }

  Future<void> _loadCategories() async {
    await _verifyBoundInstallation(force: true);
    categories = await repository.categories();
    _categoriesBaselineLoaded = true;
  }

  Future<void> _loadSchedules({FinanceScope? scope}) async {
    final requestedScope = scope ?? selectedFinanceScope;
    await _verifyBoundInstallation(force: true);
    final scopeGeneration = _financeScopeRequestToken ?? 0;
    final loaded = await repository.cutoffSchedules(scope: requestedScope);
    if (loaded.any((schedule) => schedule.scope != requestedScope)) {
      throw const FormatException(
        'The cutoff schedule list returned another money scope.',
      );
    }
    if (_isCurrentScopedRequest(requestedScope, scopeGeneration)) {
      cutoffSchedules = loaded;
      _schedulesBaselineLoaded = true;
    }
  }

  bool _isCurrentScopeGeneration(int generation) =>
      generation == (_financeScopeRequestToken ?? 0);

  bool _isCurrentScopedRequest(FinanceScope requestedScope, int generation) =>
      _isCurrentScopeGeneration(generation) &&
      requestedScope == selectedFinanceScope;

  bool _isCurrentReportRequest(
    int requestToken,
    String requestedPeriod,
    DateTime requestedAnchor,
    FinanceScope requestedScope,
    int scopeGeneration,
  ) =>
      requestToken == (_reportRequestToken ?? 0) &&
      requestedPeriod == selectedPeriod &&
      requestedAnchor.year == anchor.year &&
      requestedAnchor.month == anchor.month &&
      requestedAnchor.day == anchor.day &&
      _isCurrentScopedRequest(requestedScope, scopeGeneration);

  bool _isLiveGoldPrice(GoldPriceQuote quote) =>
      quote.hasSynchronizationMetadata
      ? quote.didSynchronize
      : (!quote.isCached &&
            !quote.isStale &&
            quote.source.trim().toLowerCase() == 'live');

  String _goldPriceRefreshMessage(GoldPriceQuote quote) {
    if (!quote.didSynchronize) {
      return 'Latest online gold price saved. Saved karat prices and held jewelry values were reloaded. Cash accounts and past conversions are unchanged.';
    }
    final rates = quote.ratesUpdated == 0
        ? 'No saved karat prices were changed.'
        : 'Updated ${quote.ratesUpdated} saved karat ${quote.ratesUpdated == 1 ? 'price' : 'prices'}.';
    if (quote.jewelryRevaluationSkippedReason != null) {
      final reason =
          quote.jewelryRevaluationSkippedReason == 'portfolio_currency_not_php'
          ? 'Held jewelry values were not recalculated because the portfolio currency is not PHP.'
          : 'Held jewelry values were not recalculated.';
      return 'Latest online gold price saved. $rates $reason Cash accounts and past conversions are unchanged.';
    }
    final jewelry = quote.jewelryRevalued == 0
        ? 'No held jewelry items were recalculated.'
        : 'Recalculated ${quote.jewelryRevalued} held jewelry ${quote.jewelryRevalued == 1 ? 'item' : 'items'}.';
    return 'Latest online gold price saved. $rates $jewelry Cash accounts and past conversions are unchanged.';
  }

  String newClientUuid() {
    final random = Random.secure();
    final values = List<int>.generate(16, (_) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40;
    values[8] = (values[8] & 0x3f) | 0x80;
    final hex = values
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<T> _withOutboxLock<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    final previous = _outboxMutationQueue ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _outboxMutationQueue = next;
    return completer.future;
  }

  Future<T> _withConfigLock<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    final previous = _configMutationQueue ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _configMutationQueue = next;
    return completer.future;
  }

  Future<T> _withFinancialBaselineLock<T>(Future<T> Function() action) {
    // The cross-request baseline/outbox protocol is a mobile offline feature.
    // Desktop production has no OfflineStore or transaction outbox and keeps
    // its established online-only concurrent scoped-read behavior.
    if (offlineStore == null && _transactionOutbox == null) return action();
    if (identical(Zone.current[_financialBaselineZoneKey], this)) {
      return action();
    }
    final completer = Completer<T>();
    final previous = _financialBaselineQueue ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) async {
      try {
        completer.complete(
          await runZoned(action, zoneValues: {_financialBaselineZoneKey: this}),
        );
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _financialBaselineQueue = next;
    return completer.future;
  }

  bool _looksLikeUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(value.trim());

  String _automaticInterestWarning(Object error) =>
      'Automatic savings interest could not be completed (${_message(error)}). Current balances were refreshed; review the affected savings account and rate, then refresh again.';

  String _message(Object error) {
    if (error is ApiException) {
      if (error.errors.isNotEmpty) {
        return error.errors.values.expand((messages) => messages).join('\n');
      }
      return error.message;
    }
    if (error is FormatException) return error.message;
    return 'Something went wrong. Please try again.';
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    api.close();
    super.dispose();
  }
}
