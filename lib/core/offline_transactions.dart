import '../models/domain_models.dart';
import 'money.dart';
import 'offline_store.dart';

enum OfflineTransactionAction {
  create,
  update,
  delete;

  static OfflineTransactionAction parse(Object? value) => values.firstWhere(
    (item) => item.name == value?.toString(),
    orElse: () =>
        throw FormatException('Unsupported offline transaction action: $value'),
  );
}

enum OfflineOperationStatus {
  queued,
  inFlight,
  uncertain,
  applied,
  conflict,
  rejected;

  String get storedValue => switch (this) {
    OfflineOperationStatus.inFlight => 'in_flight',
    _ => name,
  };

  static OfflineOperationStatus parse(Object? value) => switch (value
      ?.toString()) {
    'queued' => queued,
    'in_flight' => inFlight,
    'uncertain' => uncertain,
    'applied' => applied,
    'conflict' => conflict,
    'rejected' => rejected,
    _ => throw FormatException('Unsupported offline operation status: $value'),
  };
}

class OfflineTransactionOperation {
  OfflineTransactionOperation({
    required String operationUuid,
    required this.action,
    required this.localId,
    required this.queuedAt,
    required this.scope,
    required this.status,
    this.serverId,
    this.baseVersion,
    Map<String, Object?>? baseSnapshot,
    Map<String, Object?>? desiredSnapshot,
    Map<String, Object?>? resultTransaction,
    Map<String, Object?>? currentServerTransaction,
    Map<String, Object?>? tombstone,
    this.code,
    this.message,
    this.retryable = false,
    this.attemptCount = 0,
    this.lastAttemptAt,
    this.nextRetryAt,
    this.httpStatus,
    Map<String, List<String>> errors = const {},
  }) : operationUuid = operationUuid.trim().toLowerCase(),
       baseSnapshot = _frozenSnapshot(baseSnapshot),
       desiredSnapshot = _frozenSnapshot(desiredSnapshot),
       resultTransaction = _frozenSnapshot(resultTransaction),
       currentServerTransaction = _frozenSnapshot(currentServerTransaction),
       tombstone = _frozenSnapshot(tombstone),
       errors = _frozenErrors(errors);

  factory OfflineTransactionOperation.fromJson(
    Object? value, {
    bool recoverInFlight = true,
  }) {
    final map = jsonMap(value);
    final action = OfflineTransactionAction.parse(map['action']);
    final localId = jsonInt(map['local_id']);
    final queuedAt = DateTime.tryParse(map['queued_at']?.toString() ?? '');
    if (localId >= 0 || queuedAt == null) {
      throw const FormatException('Invalid offline transaction operation.');
    }
    return OfflineTransactionOperation(
      operationUuid: map['operation_uuid']?.toString() ?? '',
      action: action,
      localId: localId,
      queuedAt: queuedAt.toUtc(),
      scope: FinanceScope.fromJson(map['scope']),
      status:
          recoverInFlight &&
              OfflineOperationStatus.parse(map['status']) ==
                  OfflineOperationStatus.inFlight
          ? OfflineOperationStatus.uncertain
          : OfflineOperationStatus.parse(map['status']),
      serverId: map['server_id'] == null ? null : jsonInt(map['server_id']),
      baseVersion: map['base_version'] == null
          ? null
          : jsonInt(map['base_version']),
      baseSnapshot: _optionalMap(map['base_snapshot']),
      desiredSnapshot: _optionalMap(map['desired_snapshot']),
      resultTransaction: _optionalMap(map['result_transaction']),
      currentServerTransaction: _optionalMap(map['current_server_transaction']),
      tombstone: _optionalMap(map['tombstone']),
      code: _trimmed(map['code']),
      message: _trimmed(map['message']),
      retryable: jsonBool(map['retryable']),
      attemptCount: jsonInt(map['attempt_count']),
      lastAttemptAt: _optionalDate(map['last_attempt_at']),
      nextRetryAt: _optionalDate(map['next_retry_at']),
      httpStatus: map['http_status'] == null
          ? null
          : jsonInt(map['http_status']),
      errors: _errors(map['errors']),
    ).validated();
  }

  final String operationUuid;
  final OfflineTransactionAction action;

  /// Negative queue-operation correlation ID for every action.
  final int localId;
  final DateTime queuedAt;
  final FinanceScope scope;
  final OfflineOperationStatus status;
  final int? serverId;
  final int? baseVersion;
  final Map<String, Object?>? baseSnapshot;
  final Map<String, Object?>? desiredSnapshot;
  final Map<String, Object?>? resultTransaction;
  final Map<String, Object?>? currentServerTransaction;
  final Map<String, Object?>? tombstone;
  final String? code;
  final String? message;
  final bool retryable;
  final int attemptCount;
  final DateTime? lastAttemptAt;
  final DateTime? nextRetryAt;
  final int? httpStatus;
  final Map<String, List<String>> errors;

  bool get wasAttempted => attemptCount > 0;
  bool get isFrozen => wasAttempted || status != OfflineOperationStatus.queued;
  bool get isPendingProjection => const {
    OfflineOperationStatus.queued,
    OfflineOperationStatus.inFlight,
    OfflineOperationStatus.uncertain,
    OfflineOperationStatus.applied,
  }.contains(status);
  bool get needsAttention =>
      status == OfflineOperationStatus.conflict ||
      status == OfflineOperationStatus.rejected ||
      (status == OfflineOperationStatus.uncertain && attemptCount >= 5);
  bool get canAutoRetry =>
      attemptCount < 5 &&
      (status == OfflineOperationStatus.queued ||
          status == OfflineOperationStatus.uncertain ||
          (status == OfflineOperationStatus.rejected && retryable));

  TransactionRecord? get baseTransaction => _transaction(baseSnapshot);
  TransactionRecord? get desiredTransaction =>
      _transaction(resultTransaction ?? desiredSnapshot);
  TransactionRecord? get serverTransaction =>
      _transaction(currentServerTransaction);

  OfflineTransactionOperation validated() {
    final queuedUtc = queuedAt.toUtc();
    if (!_isUuid(operationUuid) ||
        localId >= 0 ||
        queuedUtc.year < 1000 ||
        queuedUtc.year > 9999) {
      throw const FormatException('Invalid offline operation identity.');
    }
    if (action == OfflineTransactionAction.create) {
      if (serverId != null || baseVersion != null || desiredSnapshot == null) {
        throw const FormatException('Invalid queued transaction create.');
      }
    } else if ((serverId ?? 0) <= 0 ||
        (baseVersion ?? 0) <= 0 ||
        baseSnapshot == null ||
        (action == OfflineTransactionAction.update &&
            desiredSnapshot == null) ||
        (action == OfflineTransactionAction.delete &&
            desiredSnapshot != null)) {
      throw const FormatException('Invalid queued transaction mutation.');
    }
    if (action == OfflineTransactionAction.update &&
        _updatePayload(baseSnapshot!, desiredSnapshot!).isEmpty) {
      throw const FormatException('A queued update has no changed fields.');
    }
    if (baseSnapshot != null) {
      _validateOrdinarySnapshot(
        baseSnapshot!,
        scope: scope,
        expectedId: serverId,
        requirePositiveVersion: true,
        requireActiveAccount: false,
        requireActiveCategory: false,
      );
    }
    if (desiredSnapshot != null) {
      _validateOrdinarySnapshot(
        desiredSnapshot!,
        scope: scope,
        expectedId: action == OfflineTransactionAction.create
            ? localId
            : serverId,
        requirePositiveVersion: action != OfflineTransactionAction.create,
        requireActiveAccount:
            action == OfflineTransactionAction.create ||
            baseSnapshot?['account_id'] != desiredSnapshot!['account_id'],
        requireActiveCategory:
            action == OfflineTransactionAction.create ||
            baseSnapshot?['category_id'] != desiredSnapshot!['category_id'],
      );
    }
    if (baseSnapshot != null &&
        desiredSnapshot != null &&
        (baseSnapshot!['id'] != desiredSnapshot!['id'] ||
            baseSnapshot!['version'] != baseVersion ||
            desiredSnapshot!['version'] != baseVersion ||
            baseSnapshot!['client_uuid']?.toString().trim().toLowerCase() !=
                desiredSnapshot!['client_uuid']
                    ?.toString()
                    .trim()
                    .toLowerCase())) {
      throw const FormatException(
        'A queued update cannot change transaction identity.',
      );
    }
    return this;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'operation_uuid': operationUuid,
    'action': action.name,
    'local_id': localId,
    'queued_at': queuedAt.toUtc().toIso8601String(),
    'scope': scope.apiValue,
    'status': status.storedValue,
    'server_id': serverId,
    'base_version': baseVersion,
    'base_snapshot': baseSnapshot,
    'desired_snapshot': desiredSnapshot,
    'result_transaction': resultTransaction,
    'current_server_transaction': currentServerTransaction,
    'tombstone': tombstone,
    'code': code,
    'message': message,
    'retryable': retryable,
    'attempt_count': attemptCount,
    'last_attempt_at': lastAttemptAt?.toUtc().toIso8601String(),
    'next_retry_at': nextRetryAt?.toUtc().toIso8601String(),
    'http_status': httpStatus,
    'errors': errors,
  };

  Map<String, Object?> toSyncEnvelope() {
    final envelope = <String, Object?>{
      'operation_uuid': operationUuid,
      'action': action.name,
      'local_id': localId,
      'queued_at': queuedAt.toUtc().toIso8601String(),
    };
    switch (action) {
      case OfflineTransactionAction.create:
        envelope['payload'] = _createPayload(desiredSnapshot!);
      case OfflineTransactionAction.update:
        envelope
          ..['server_id'] = serverId
          ..['base_version'] = baseVersion
          ..['payload'] = _updatePayload(baseSnapshot!, desiredSnapshot!);
      case OfflineTransactionAction.delete:
        envelope
          ..['server_id'] = serverId
          ..['base_version'] = baseVersion;
    }
    return _deepFreezeMap(envelope);
  }

  OfflineTransactionOperation copyWith({
    OfflineTransactionAction? action,
    OfflineOperationStatus? status,
    Map<String, Object?>? desiredSnapshot,
    bool clearDesiredSnapshot = false,
    Map<String, Object?>? resultTransaction,
    bool clearResultTransaction = false,
    Map<String, Object?>? currentServerTransaction,
    bool clearCurrentServerTransaction = false,
    Map<String, Object?>? tombstone,
    bool clearTombstone = false,
    String? code,
    bool clearCode = false,
    String? message,
    bool clearMessage = false,
    bool? retryable,
    int? attemptCount,
    DateTime? lastAttemptAt,
    bool clearLastAttemptAt = false,
    DateTime? nextRetryAt,
    bool clearNextRetryAt = false,
    int? httpStatus,
    bool clearHttpStatus = false,
    Map<String, List<String>>? errors,
    int? baseVersion,
    Map<String, Object?>? baseSnapshot,
  }) => OfflineTransactionOperation(
    operationUuid: operationUuid,
    action: action ?? this.action,
    localId: localId,
    queuedAt: queuedAt,
    scope: scope,
    status: status ?? this.status,
    serverId: serverId,
    baseVersion: baseVersion ?? this.baseVersion,
    baseSnapshot: baseSnapshot ?? this.baseSnapshot,
    desiredSnapshot: clearDesiredSnapshot
        ? null
        : desiredSnapshot ?? this.desiredSnapshot,
    resultTransaction: clearResultTransaction
        ? null
        : resultTransaction ?? this.resultTransaction,
    currentServerTransaction: clearCurrentServerTransaction
        ? null
        : currentServerTransaction ?? this.currentServerTransaction,
    tombstone: clearTombstone ? null : tombstone ?? this.tombstone,
    code: clearCode ? null : code ?? this.code,
    message: clearMessage ? null : message ?? this.message,
    retryable: retryable ?? this.retryable,
    attemptCount: attemptCount ?? this.attemptCount,
    lastAttemptAt: clearLastAttemptAt
        ? null
        : lastAttemptAt ?? this.lastAttemptAt,
    nextRetryAt: clearNextRetryAt ? null : nextRetryAt ?? this.nextRetryAt,
    httpStatus: clearHttpStatus ? null : httpStatus ?? this.httpStatus,
    errors: errors ?? this.errors,
  );
}

class TransactionSyncBatch {
  const TransactionSyncBatch({
    required this.requiresRefresh,
    required this.results,
    this.installationId,
    this.serverTime,
  });

  factory TransactionSyncBatch.fromJson(Object? value) {
    final data = jsonMap(dataOf(value));
    final rawResults = data['results'];
    final processedCount = data['processed_count'];
    final appliedCount = data['applied_count'];
    final conflictCount = data['conflict_count'];
    final rejectedCount = data['rejected_count'];
    final retryableCount = data['retryable_count'];
    final replayedCount = data['replayed_count'];
    final requiresRefresh = data['requires_refresh'];
    final installationId = _trimmed(data['installation_id'])?.toLowerCase();
    final serverTime = DateTime.tryParse(data['server_time']?.toString() ?? '');
    if (rawResults is! List ||
        processedCount is! int ||
        appliedCount is! int ||
        conflictCount is! int ||
        rejectedCount is! int ||
        retryableCount is! int ||
        replayedCount is! int ||
        requiresRefresh is! bool ||
        !_isUuid(installationId ?? '') ||
        serverTime == null) {
      throw const FormatException('Invalid transaction sync batch.');
    }
    final results = rawResults.map(TransactionSyncResult.fromJson).toList();
    if (processedCount != results.length ||
        appliedCount !=
            results.where((item) => item.status == 'applied').length ||
        conflictCount !=
            results.where((item) => item.status == 'conflict').length ||
        rejectedCount !=
            results.where((item) => item.status == 'rejected').length ||
        retryableCount != results.where((item) => item.retryable).length ||
        replayedCount != results.where((item) => item.replayed).length ||
        data['has_conflicts'] is! bool ||
        data['has_conflicts'] != (conflictCount > 0) ||
        data['has_rejections'] is! bool ||
        data['has_rejections'] != (rejectedCount > 0)) {
      throw const FormatException(
        'Transaction sync counts did not match its results.',
      );
    }
    return TransactionSyncBatch(
      requiresRefresh: requiresRefresh,
      installationId: installationId,
      serverTime: serverTime.toUtc(),
      results: results,
    );
  }

  final bool requiresRefresh;
  final String? installationId;
  final DateTime? serverTime;
  final List<TransactionSyncResult> results;
}

class TransactionSyncResult {
  const TransactionSyncResult({
    required this.operationUuid,
    required this.localId,
    required this.action,
    required this.status,
    required this.queuedAt,
    required this.replayed,
    required this.httpStatus,
    required this.retryable,
    this.code,
    this.message,
    this.serverId,
    this.transaction,
    this.currentServerTransaction,
    this.tombstone,
    this.currentState,
    this.errors = const {},
  });

  factory TransactionSyncResult.fromJson(Object? value) {
    final map = jsonMap(value);
    final queuedAt = DateTime.tryParse(map['queued_at']?.toString() ?? '');
    final status = map['status']?.toString();
    final operationUuid = map['operation_uuid']
        ?.toString()
        .trim()
        .toLowerCase();
    if (queuedAt == null ||
        !_isUuid(operationUuid ?? '') ||
        map['local_id'] is! int ||
        (map['local_id'] as int) >= 0 ||
        map['action'] is! String ||
        map['replayed'] is! bool ||
        map['http_status'] is! int ||
        map['retryable'] is! bool ||
        !const {'applied', 'conflict', 'rejected'}.contains(status)) {
      throw const FormatException('Invalid transaction sync result.');
    }
    for (final field in const [
      'transaction',
      'current_server_transaction',
      'tombstone',
    ]) {
      if (map[field] != null && map[field] is! Map) {
        throw const FormatException('Invalid transaction sync result state.');
      }
    }
    if (map['server_id'] != null && map['server_id'] is! int ||
        map['code'] != null && map['code'] is! String ||
        map['message'] != null && map['message'] is! String ||
        map['current_state'] != null && map['current_state'] is! String ||
        map['errors'] != null && map['errors'] is! Map) {
      throw const FormatException('Invalid transaction sync result fields.');
    }
    return TransactionSyncResult(
      operationUuid: operationUuid!,
      localId: map['local_id'] as int,
      action: OfflineTransactionAction.parse(map['action']),
      status: status!,
      queuedAt: queuedAt.toUtc(),
      replayed: map['replayed'] as bool,
      httpStatus: map['http_status'] as int,
      retryable: map['retryable'] as bool,
      code: _trimmed(map['code']),
      message: _trimmed(map['message']),
      serverId: map['server_id'] == null ? null : jsonInt(map['server_id']),
      transaction: _optionalMap(map['transaction']),
      currentServerTransaction: _optionalMap(map['current_server_transaction']),
      tombstone: _optionalMap(map['tombstone']),
      currentState: _trimmed(map['current_state']),
      errors: _errors(map['errors']),
    );
  }

  final String operationUuid;
  final int localId;
  final OfflineTransactionAction action;
  final String status;
  final DateTime queuedAt;
  final bool replayed;
  final int httpStatus;
  final bool retryable;
  final String? code;
  final String? message;
  final int? serverId;
  final Map<String, Object?>? transaction;
  final Map<String, Object?>? currentServerTransaction;
  final Map<String, Object?>? tombstone;
  final String? currentState;
  final Map<String, List<String>> errors;
}

class TransactionOutbox {
  TransactionOutbox({
    List<OfflineTransactionOperation> operations = const [],
    int nextLocalId = -1,
    this.installationId,
  }) : _operations = [...operations],
       // Public constructor name intentionally differs from mutable storage.
       // ignore: prefer_initializing_formals
       _nextLocalId = nextLocalId;

  factory TransactionOutbox.fromSnapshot(
    TransactionOutboxSnapshot snapshot, {
    bool recoverInFlight = true,
  }) {
    final operations = snapshot.operations
        .map(
          (value) => OfflineTransactionOperation.fromJson(
            value,
            recoverInFlight: recoverInFlight,
          ),
        )
        .toList();
    return TransactionOutbox(
      operations: operations,
      nextLocalId: snapshot.nextLocalId,
      installationId: snapshot.installationId,
    );
  }

  final List<OfflineTransactionOperation> _operations;
  int _nextLocalId;
  String? installationId;

  List<OfflineTransactionOperation> get operations =>
      List.unmodifiable(_operations);
  int get nextLocalId => _nextLocalId;
  int get pendingCount =>
      _operations.where((item) => item.isPendingProjection).length;
  int get conflictCount =>
      _operations.where((item) => item.needsAttention).length;
  bool get hasOperations => _operations.isNotEmpty;

  TransactionOutboxSnapshot toSnapshot() => TransactionOutboxSnapshot(
    operations: _operations.map((operation) => operation.toJson()).toList(),
    nextLocalId: _nextLocalId,
    installationId: installationId,
  );

  OfflineTransactionOperation queueCreate({
    required String operationUuid,
    required DateTime queuedAt,
    required FinanceScope scope,
    required Map<String, Object?> desiredSnapshot,
  }) {
    final operation = OfflineTransactionOperation(
      operationUuid: operationUuid,
      action: OfflineTransactionAction.create,
      localId: _allocateLocalId(),
      queuedAt: queuedAt.toUtc(),
      scope: scope,
      status: OfflineOperationStatus.queued,
      desiredSnapshot: desiredSnapshot,
    ).validated();
    _operations.add(operation);
    return operation;
  }

  OfflineTransactionOperation? queueUpdate({
    required String operationUuid,
    required DateTime queuedAt,
    required TransactionRecord existing,
    required Map<String, Object?> desiredSnapshot,
  }) {
    final createIndex = existing.id < 0
        ? _operations.indexWhere(
            (item) =>
                item.action == OfflineTransactionAction.create &&
                item.desiredTransaction?.id == existing.id,
          )
        : -1;
    if (createIndex >= 0) {
      final current = _operations[createIndex];
      _ensureEditable(current);
      final updated = current
          .copyWith(desiredSnapshot: desiredSnapshot)
          .validated();
      _operations[createIndex] = updated;
      return updated;
    }

    final updateIndex = _operations.indexWhere(
      (item) =>
          item.serverId == existing.id &&
          item.action == OfflineTransactionAction.update,
    );
    if (updateIndex >= 0) {
      final current = _operations[updateIndex];
      _ensureEditable(current);
      if (_sameMutableSnapshot(current.baseSnapshot!, desiredSnapshot)) {
        _operations.removeAt(updateIndex);
        return null;
      }
      final updated = current
          .copyWith(desiredSnapshot: desiredSnapshot)
          .validated();
      _operations[updateIndex] = updated;
      return updated;
    }
    if (_operations.any(
      (item) => item.serverId == existing.id && item.isPendingProjection,
    )) {
      throw const FormatException(
        'This transaction is waiting for sync and cannot be changed yet.',
      );
    }
    final base = transactionSnapshot(existing);
    if (_sameMutableSnapshot(base, desiredSnapshot)) return null;
    final operation = OfflineTransactionOperation(
      operationUuid: operationUuid,
      action: OfflineTransactionAction.update,
      localId: _allocateLocalId(),
      queuedAt: queuedAt.toUtc(),
      scope: existing.scope,
      status: OfflineOperationStatus.queued,
      serverId: existing.id,
      baseVersion: existing.version,
      baseSnapshot: base,
      desiredSnapshot: desiredSnapshot,
    ).validated();
    _operations.add(operation);
    return operation;
  }

  OfflineTransactionOperation? queueDelete({
    required String operationUuid,
    required DateTime queuedAt,
    required TransactionRecord existing,
  }) {
    if (existing.id < 0) {
      final index = _operations.indexWhere(
        (item) =>
            item.action == OfflineTransactionAction.create &&
            item.desiredTransaction?.id == existing.id,
      );
      if (index < 0) {
        throw const FormatException('The pending transaction was not found.');
      }
      _ensureEditable(_operations[index]);
      _operations.removeAt(index);
      return null;
    }
    final existingIndex = _operations.indexWhere(
      (item) => item.serverId == existing.id,
    );
    if (existingIndex >= 0) {
      final current = _operations[existingIndex];
      _ensureEditable(current);
      if (current.action == OfflineTransactionAction.delete) return current;
      final deleted = current
          .copyWith(
            action: OfflineTransactionAction.delete,
            clearDesiredSnapshot: true,
          )
          .validated();
      _operations[existingIndex] = deleted;
      return deleted;
    }
    final operation = OfflineTransactionOperation(
      operationUuid: operationUuid,
      action: OfflineTransactionAction.delete,
      localId: _allocateLocalId(),
      queuedAt: queuedAt.toUtc(),
      scope: existing.scope,
      status: OfflineOperationStatus.queued,
      serverId: existing.id,
      baseVersion: existing.version,
      baseSnapshot: transactionSnapshot(existing),
    ).validated();
    _operations.add(operation);
    return operation;
  }

  List<OfflineTransactionOperation> ready({
    required DateTime now,
    int maximum = 100,
  }) => _operations
      .where(
        (item) =>
            item.canAutoRetry &&
            (item.nextRetryAt == null || !item.nextRetryAt!.isAfter(now)),
      )
      .take(maximum)
      .toList();

  void markAttempted(
    Iterable<OfflineTransactionOperation> attempted,
    DateTime now,
  ) {
    final ids = attempted.map((item) => item.operationUuid).toSet();
    for (var index = 0; index < _operations.length; index++) {
      final operation = _operations[index];
      if (!ids.contains(operation.operationUuid)) continue;
      if (operation.status != OfflineOperationStatus.queued &&
          operation.status != OfflineOperationStatus.uncertain &&
          !(operation.status == OfflineOperationStatus.rejected &&
              operation.retryable)) {
        throw const FormatException(
          'Only a queued or retryable transaction may be sent.',
        );
      }
      final count = operation.attemptCount + 1;
      _operations[index] = operation.copyWith(
        status: OfflineOperationStatus.inFlight,
        attemptCount: count,
        lastAttemptAt: now.toUtc(),
        nextRetryAt: now.toUtc().add(_backoff(count)),
        clearCode: true,
        clearMessage: true,
        clearHttpStatus: true,
        retryable: false,
        errors: const {},
      );
    }
  }

  void markUncertain(
    Iterable<OfflineTransactionOperation> attempted, {
    String? message,
  }) {
    final ids = attempted.map((item) => item.operationUuid).toSet();
    for (var index = 0; index < _operations.length; index++) {
      final operation = _operations[index];
      if (!ids.contains(operation.operationUuid)) continue;
      if (operation.status != OfflineOperationStatus.inFlight) continue;
      _operations[index] = operation.copyWith(
        status: OfflineOperationStatus.uncertain,
        message: message,
        retryable: true,
      );
    }
  }

  void markPreprocessingRejected(
    Iterable<OfflineTransactionOperation> attempted, {
    required Set<String> rejectedOperationUuids,
    required String message,
    required Map<String, List<String>> errors,
  }) {
    final ids = attempted.map((item) => item.operationUuid).toSet();
    for (var index = 0; index < _operations.length; index++) {
      final operation = _operations[index];
      if (!ids.contains(operation.operationUuid) ||
          operation.status != OfflineOperationStatus.inFlight) {
        continue;
      }
      if (rejectedOperationUuids.contains(operation.operationUuid)) {
        _operations[index] = operation.copyWith(
          status: OfflineOperationStatus.rejected,
          code: 'VALIDATION_ERROR',
          message: message,
          retryable: false,
          httpStatus: 422,
          errors: errors,
        );
      } else {
        // The whole request was rejected before processing. Valid siblings
        // were never sent to the service and can safely retain their frozen
        // envelope for a later batch. Undo this batch's attempt metadata too:
        // a valid sibling at the retry cap must not become silently stuck.
        final restoredAttemptCount = operation.attemptCount > 0
            ? operation.attemptCount - 1
            : 0;
        _operations[index] = operation.copyWith(
          // A sibling retried after an earlier ambiguous response may already
          // be committed. Keep it uncertain so live baselines cannot be read
          // and optimistically overlaid before its exact replay resolves.
          status: restoredAttemptCount == 0
              ? OfflineOperationStatus.queued
              : OfflineOperationStatus.uncertain,
          attemptCount: restoredAttemptCount,
          message: 'A different operation in the batch failed validation.',
          retryable: true,
          clearCode: true,
          clearHttpStatus: true,
          clearLastAttemptAt: true,
          clearNextRetryAt: true,
          errors: const {},
        );
      }
    }
  }

  void applyBatch(TransactionSyncBatch batch) {
    for (final result in batch.results) {
      final index = _operations.indexWhere(
        (item) => item.operationUuid == result.operationUuid,
      );
      if (index < 0) {
        throw const FormatException(
          'A sync result referenced an unknown operation.',
        );
      }
      final current = _operations[index];
      if (current.status != OfflineOperationStatus.inFlight) {
        throw const FormatException(
          'A sync result was received for an operation that was not in flight.',
        );
      }
      final nextStatus = switch (result.status) {
        'applied' => OfflineOperationStatus.applied,
        'conflict' => OfflineOperationStatus.conflict,
        // A server-side failure can be reported after the database commit or
        // an after-commit callback loses its connection. Exact UUID replay is
        // the only safe resolution, including for non-retryable 5xx errors.
        'rejected' when result.httpStatus >= 500 =>
          OfflineOperationStatus.uncertain,
        'rejected' when result.retryable => OfflineOperationStatus.uncertain,
        _ => OfflineOperationStatus.rejected,
      };
      _operations[index] = current.copyWith(
        status: nextStatus,
        resultTransaction: result.transaction,
        clearResultTransaction: result.transaction == null,
        currentServerTransaction: result.currentServerTransaction,
        clearCurrentServerTransaction: result.currentServerTransaction == null,
        tombstone: result.tombstone,
        clearTombstone: result.tombstone == null,
        code: result.code,
        clearCode: result.code == null,
        message: result.message,
        clearMessage: result.message == null,
        retryable: result.retryable,
        httpStatus: result.httpStatus,
        errors: result.errors,
      );
    }
  }

  void removeAppliedForScope(FinanceScope scope) {
    _operations.removeWhere(
      (item) =>
          item.scope == scope && item.status == OfflineOperationStatus.applied,
    );
  }

  void removeApplied(Set<String> operationUuids) {
    _operations.removeWhere(
      (item) =>
          operationUuids.contains(item.operationUuid) &&
          item.status == OfflineOperationStatus.applied,
    );
  }

  void refreshConflictServerSnapshot({
    required String operationUuid,
    required Map<String, Object?> currentServerSnapshot,
    required String message,
    bool allowManaged = false,
  }) {
    final index = _operations.indexWhere(
      (item) => item.operationUuid == operationUuid,
    );
    if (index < 0 ||
        _operations[index].status != OfflineOperationStatus.conflict) {
      throw const FormatException(
        'The transaction conflict is no longer available.',
      );
    }
    final operation = _operations[index];
    if (allowManaged) {
      final current = TransactionRecord.fromJson(currentServerSnapshot);
      if (!current.isManagedTransaction ||
          current.id != operation.serverId ||
          current.scope != operation.scope ||
          current.version <= 0) {
        throw const FormatException(
          'The managed server transaction does not match this conflict.',
        );
      }
    } else {
      _validateOrdinarySnapshot(
        currentServerSnapshot,
        scope: operation.scope,
        expectedId: operation.serverId,
        requirePositiveVersion: true,
        requireActiveAccount: false,
        requireActiveCategory: false,
      );
    }
    _operations[index] = operation
        .copyWith(
          currentServerTransaction: currentServerSnapshot,
          message: message,
        )
        .validated();
  }

  void markConflictServerDeleted({
    required String operationUuid,
    required String message,
  }) {
    final index = _operations.indexWhere(
      (item) => item.operationUuid == operationUuid,
    );
    if (index < 0 ||
        _operations[index].status != OfflineOperationStatus.conflict) {
      throw const FormatException(
        'The transaction conflict is no longer available.',
      );
    }
    _operations[index] = _operations[index]
        .copyWith(
          clearCurrentServerTransaction: true,
          code: 'TRANSACTION_DELETED',
          message: message,
          retryable: false,
        )
        .validated();
  }

  void discard(OfflineTransactionOperation operation) {
    if (operation.status != OfflineOperationStatus.conflict &&
        operation.status != OfflineOperationStatus.rejected) {
      throw const FormatException(
        'Only a resolved conflict or rejected change can be discarded.',
      );
    }
    _operations.removeWhere(
      (item) => item.operationUuid == operation.operationUuid,
    );
  }

  int _allocateLocalId() {
    final value = _nextLocalId;
    _nextLocalId -= 1;
    return value;
  }

  static void _ensureEditable(OfflineTransactionOperation operation) {
    if (operation.isFrozen) {
      throw const FormatException(
        'This transaction was already sent and is locked until sync resolves.',
      );
    }
  }
}

Map<String, Object?> transactionSnapshot(TransactionRecord transaction) => {
  'id': transaction.id,
  'client_uuid': transaction.clientUuid,
  'kind': transaction.kind,
  'amount_minor': transaction.amountMinor,
  'occurred_on': _apiDate(transaction.occurredOn),
  'version': transaction.version,
  'account_id': transaction.accountId,
  'category_id': transaction.categoryId,
  'cutoff_period_id': transaction.cutoffPeriodId,
  'payee': transaction.payee,
  'note': transaction.note,
  'installment_months': transaction.installmentMonths,
  'installment_monthly_minor': transaction.installmentMonthlyMinor,
  'installment_start_on': transaction.installmentStartOn == null
      ? null
      : apiDate(transaction.installmentStartOn!),
  'installment_plan_id': transaction.installmentPlanId,
  'installment_number': transaction.installmentNumber,
  'scope': transaction.scope.apiValue,
  'source_type': transaction.sourceType,
  'source_id': transaction.sourceId,
  'source_component': transaction.sourceComponent,
  'account': transaction.account == null
      ? null
      : {
          'id': transaction.account!.id,
          'name': transaction.account!.name,
          'type': transaction.account!.type,
          'opening_balance_minor': transaction.account!.openingBalanceMinor,
          'balance_minor': transaction.account!.balanceMinor,
          'color': transaction.account!.color,
          'card_design': transaction.account!.cardDesign,
          'is_archived': transaction.account!.isArchived,
          'scope': transaction.account!.scope.apiValue,
          'system_key': transaction.account!.systemKey,
          'account_role': transaction.account!.accountRole,
          'is_system': transaction.account!.isSystem,
          'is_liability': transaction.account!.isLiability,
          'opening_debt_minor': transaction.account!.openingDebtMinor,
          'credit_limit_minor': transaction.account!.creditLimitMinor,
          'statement_day': transaction.account!.statementDay,
          'due_day': transaction.account!.dueDay,
          'debt_minor': transaction.account!.debtMinor,
          'available_credit_minor': transaction.account!.availableCreditMinor,
        },
  'category': transaction.category == null
      ? null
      : {
          'id': transaction.category!.id,
          'name': transaction.category!.name,
          'kind': transaction.category!.kind,
          'color': transaction.category!.color,
          'icon': transaction.category!.icon,
          'is_archived': transaction.category!.isArchived,
          'system_key': transaction.category!.systemKey,
          'category_role': transaction.category!.categoryRole,
          'is_system': transaction.category!.isSystem,
        },
};

Map<String, Object?> transactionDraftSnapshot({
  required int id,
  required String clientUuid,
  required String kind,
  required int amountMinor,
  required DateTime occurredOn,
  required Account account,
  required Category category,
  required FinanceScope scope,
  required int version,
  String? payee,
  String? note,
  int? installmentMonths,
  int? installmentMonthlyMinor,
  DateTime? installmentStartOn,
  int? cutoffPeriodId,
}) => transactionSnapshot(
  TransactionRecord(
    id: id,
    clientUuid: clientUuid,
    kind: kind,
    amountMinor: amountMinor,
    occurredOn: DateTime(occurredOn.year, occurredOn.month, occurredOn.day),
    version: version,
    accountId: account.id,
    categoryId: category.id,
    cutoffPeriodId: cutoffPeriodId,
    payee: _normalizedOptional(payee),
    note: _normalizedOptional(note),
    installmentMonths: installmentMonths,
    installmentMonthlyMinor: installmentMonthlyMinor,
    installmentStartOn: installmentStartOn == null
        ? null
        : DateTime(
            installmentStartOn.year,
            installmentStartOn.month,
            installmentStartOn.day,
          ),
    account: account,
    category: category,
    scope: scope,
  ),
);

Map<String, Object?> _createPayload(Map<String, Object?> desired) => {
  'client_uuid': desired['client_uuid'],
  'kind': desired['kind'],
  'amount_minor': desired['amount_minor'],
  'occurred_on': desired['occurred_on'],
  'account_id': desired['account_id'],
  'category_id': desired['category_id'],
  'payee': desired['payee'],
  'note': desired['note'],
  'installment_months': desired['installment_months'],
  'installment_monthly_minor': desired['installment_monthly_minor'],
  'installment_start_on': desired['installment_start_on'],
};

Map<String, Object?> _updatePayload(
  Map<String, Object?> base,
  Map<String, Object?> desired,
) {
  const fields = [
    'kind',
    'amount_minor',
    'occurred_on',
    'account_id',
    'category_id',
    'payee',
    'note',
    'installment_months',
    'installment_monthly_minor',
    'installment_start_on',
  ];
  return <String, Object?>{
    for (final field in fields)
      if (base[field] != desired[field]) field: desired[field],
  };
}

bool _sameMutableSnapshot(
  Map<String, Object?> first,
  Map<String, Object?> second,
) => _updatePayload(first, second).isEmpty;

Duration _backoff(int attemptCount) {
  final seconds = switch (attemptCount) {
    <= 1 => 5,
    2 => 15,
    3 => 60,
    4 => 300,
    _ => 900,
  };
  return Duration(seconds: seconds);
}

TransactionRecord? _transaction(Map<String, Object?>? value) =>
    value == null ? null : TransactionRecord.fromJson(value);

Map<String, Object?>? _optionalMap(Object? value) =>
    value is Map ? jsonMap(value).cast<String, Object?>() : null;

DateTime? _optionalDate(Object? value) =>
    DateTime.tryParse(value?.toString() ?? '')?.toUtc();

String? _trimmed(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String? _normalizedOptional(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String _apiDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

Map<String, List<String>> _errors(Object? value) {
  final map = jsonMap(value);
  return {
    for (final entry in map.entries)
      entry.key: entry.value is List
          ? (entry.value as List).map((item) => item.toString()).toList()
          : [entry.value.toString()],
  };
}

Map<String, Object?>? _frozenSnapshot(Map<String, Object?>? value) {
  if (value == null) return null;
  final normalized = _deepFreezeMap(value);
  final clientUuid = normalized['client_uuid'];
  if (clientUuid is String) {
    final mutable = Map<String, Object?>.from(normalized)
      ..['client_uuid'] = clientUuid.trim().toLowerCase();
    return Map<String, Object?>.unmodifiable(mutable);
  }
  return normalized;
}

Map<String, Object?> _deepFreezeMap(Map<dynamic, dynamic> value) =>
    Map<String, Object?>.unmodifiable({
      for (final entry in value.entries)
        entry.key.toString(): _deepFreeze(entry.value),
    });

Object? _deepFreeze(Object? value) => switch (value) {
  Map<dynamic, dynamic> map => _deepFreezeMap(map),
  List<dynamic> list => List<Object?>.unmodifiable(list.map(_deepFreeze)),
  _ => value,
};

Map<String, List<String>> _frozenErrors(Map<String, List<String>> value) =>
    Map<String, List<String>>.unmodifiable({
      for (final entry in value.entries)
        entry.key: List<String>.unmodifiable(entry.value),
    });

bool _isUuid(String value) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
).hasMatch(value.trim());

void _validateOrdinarySnapshot(
  Map<String, Object?> snapshot, {
  required FinanceScope scope,
  required int? expectedId,
  required bool requirePositiveVersion,
  required bool requireActiveAccount,
  required bool requireActiveCategory,
}) {
  final rawScope = snapshot['scope']?.toString().trim().toLowerCase();
  final occurredOnText = snapshot['occurred_on']?.toString() ?? '';
  final occurredOn = DateTime.tryParse(occurredOnText);
  final amount = jsonInt(snapshot['amount_minor']);
  final version = jsonInt(snapshot['version']);
  if (jsonInt(snapshot['id']) != expectedId ||
      rawScope != scope.apiValue ||
      !_isUuid(snapshot['client_uuid']?.toString() ?? '') ||
      !const {'income', 'expense'}.contains(snapshot['kind']) ||
      amount <= 0 ||
      amount > Money.maxMinorUnits ||
      occurredOn == null ||
      !_isDateOnly(occurredOnText, occurredOn) ||
      jsonInt(snapshot['account_id']) <= 0 ||
      jsonInt(snapshot['category_id']) <= 0 ||
      (snapshot['payee']?.toString().trim().runes.length ?? 0) > 150 ||
      (snapshot['note']?.toString().trim().runes.length ?? 0) > 2000 ||
      snapshot['source_type'] != null ||
      snapshot['source_id'] != null ||
      snapshot['source_component'] != null ||
      (requirePositiveVersion ? version <= 0 : version != 0)) {
    throw const FormatException('Invalid queued transaction snapshot.');
  }
  final account = jsonMap(snapshot['account']);
  final category = jsonMap(snapshot['category']);
  final isCreditCard =
      account['type']?.toString() == 'credit_card' ||
      account['account_role']?.toString() == 'credit_card';
  if (jsonInt(account['id']) != jsonInt(snapshot['account_id']) ||
      account['scope']?.toString().trim().toLowerCase() != scope.apiValue ||
      jsonInt(category['id']) != jsonInt(snapshot['category_id']) ||
      category['kind']?.toString() != snapshot['kind'] ||
      jsonBool(category['is_system']) ||
      (isCreditCard && snapshot['kind'] != 'expense') ||
      (requireActiveAccount && jsonBool(account['is_archived'])) ||
      (requireActiveCategory && jsonBool(category['is_archived']))) {
    throw const FormatException(
      'Queued transaction references are invalid or unavailable.',
    );
  }
}

bool _isDateOnly(String value, DateTime parsed) =>
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) && _apiDate(parsed) == value;
