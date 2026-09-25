import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'money.dart';

class OfflineCacheEntry {
  const OfflineCacheEntry({required this.response, required this.savedAt});

  final Object? response;
  final DateTime savedAt;
}

class OfflineDatasetSnapshot {
  const OfflineDatasetSnapshot({
    required this.pages,
    required this.savedAt,
    required this.scope,
  });

  final List<Object?> pages;
  final DateTime savedAt;
  final String? scope;
}

class TransactionOutboxSnapshot {
  const TransactionOutboxSnapshot({
    required this.operations,
    required this.nextLocalId,
    this.installationId,
  });

  final List<Map<String, Object?>> operations;
  final int nextLocalId;
  final String? installationId;

  TransactionOutboxSnapshot copyWith({
    List<Map<String, Object?>>? operations,
    int? nextLocalId,
    String? installationId,
    bool clearInstallationId = false,
  }) => TransactionOutboxSnapshot(
    operations: operations ?? this.operations,
    nextLocalId: nextLocalId ?? this.nextLocalId,
    installationId: clearInstallationId
        ? null
        : installationId ?? this.installationId,
  );
}

class OutboxRecoveryException implements Exception {
  const OutboxRecoveryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// JSON-only persistence shared across Flutter desktop and mobile.
///
/// Cached reads are disposable and live in their own file. Pending financial
/// mutations live in a separately journaled file and are never silently reset
/// if recovery fails.
class OfflineStore {
  OfflineStore({
    Future<Directory> Function()? supportDirectoryProvider,
    Future<File> Function()? cacheFileProvider,
    Future<File> Function()? outboxFileProvider,
  }) : _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory,
       // Public injectable names intentionally differ from private storage.
       // ignore: prefer_initializing_formals
       _cacheFileProvider = cacheFileProvider,
       // ignore: prefer_initializing_formals
       _outboxFileProvider = outboxFileProvider;

  static const cacheSchemaVersion = 1;
  static const outboxSchemaVersion = 1;
  static const _maximumCacheEntries = 300;

  final Future<Directory> Function() _supportDirectoryProvider;
  final Future<File> Function()? _cacheFileProvider;
  final Future<File> Function()? _outboxFileProvider;

  Map<String, Object?>? _cacheState;
  int _cacheGeneration = 0;
  Future<void>? _cacheLoadFuture;
  Future<void> _cacheWriteQueue = Future<void>.value();
  TransactionOutboxSnapshot? _outboxState;
  int _outboxGeneration = 0;
  Future<void>? _outboxLoadFuture;
  Future<void> _outboxWriteQueue = Future<void>.value();

  Future<OfflineCacheEntry?> cachedResponse(String key) async {
    await _ensureCacheLoaded();
    final cache = _jsonMap(_cacheState?['responses']);
    final entry = _cacheEntry(cache[key]);
    if (entry == null) return null;
    return OfflineCacheEntry(
      response: _deepClone(entry.response),
      savedAt: entry.savedAt,
    );
  }

  Future<String?> cacheInstallationId() async {
    await _ensureCacheLoaded();
    return _trimmed(_cacheState?['installation_id']);
  }

  /// Binds disposable reads to one database installation. A changed identity
  /// clears every old response before any new endpoint can fall back to it.
  Future<void> bindCacheInstallation(String installationId) =>
      _serializeCache(() async {
        await _ensureCacheLoaded();
        final normalized = installationId.trim().toLowerCase();
        if (!_isUuid(normalized)) {
          throw const FormatException('A cache installation ID is required.');
        }
        final previous = _trimmed(_cacheState?['installation_id']);
        if (previous == normalized) return;
        final previousState = _deepClone(_cacheState) as Map;
        final previousGeneration = _cacheGeneration;
        _cacheState = _emptyCacheState(installationId: normalized);
        try {
          await _persistCache();
        } catch (_) {
          _cacheState = _objectMap(previousState);
          _cacheGeneration = previousGeneration;
          rethrow;
        }
      });

  Future<void> saveCachedResponse(String key, Object? response) =>
      _serializeCache(() async {
        await _ensureCacheLoaded();
        final responses = _mutableMap(_cacheState?['responses']);
        responses[key] = _cacheValue(_deepClone(response));
        _trimCache(responses);
        _cacheState!['responses'] = responses;
        await _persistCache();
      });

  Future<OfflineDatasetSnapshot?> cachedDataset(String key) async {
    await _ensureCacheLoaded();
    final datasets = _jsonMap(_cacheState?['datasets']);
    final value = _jsonMap(datasets[key]);
    final pages = value['pages'];
    if (pages is! List) return null;
    return OfflineDatasetSnapshot(
      pages: List<Object?>.from(_deepClone(pages) as List),
      savedAt: _date(value['saved_at']),
      scope: value['scope']?.toString(),
    );
  }

  Future<void> saveDataset(
    String key, {
    required List<Object?> pages,
    String? scope,
  }) => _serializeCache(() async {
    await _ensureCacheLoaded();
    final datasets = _mutableMap(_cacheState?['datasets']);
    datasets[key] = <String, Object?>{
      'saved_at': DateTime.now().toUtc().toIso8601String(),
      'scope': scope,
      'pages': _deepClone(pages),
    };
    _cacheState!['datasets'] = datasets;
    await _persistCache();
  });

  Future<Set<String>> includedFinancialOperationUuids(String scope) async {
    await _ensureCacheLoaded();
    final adoptions = _jsonMap(_cacheState?['financial_adoptions']);
    final value = _jsonMap(adoptions[scope]);
    final items = value['operation_uuids'];
    return items is List
        ? items.map((item) => item.toString()).toSet()
        : <String>{};
  }

  /// Commits one coordinated financial baseline twice. Once both writes
  /// succeed, primary and backup share the operation watermark.
  Future<void> saveFinancialSnapshot({
    required String installationId,
    required String scope,
    required Map<String, Object?> responses,
    required Map<String, List<Object?>> datasets,
    required Set<String> includedOperationUuids,
  }) => _serializeCache(() async {
    await _ensureCacheLoaded();
    final normalizedInstallationId = installationId.trim().toLowerCase();
    if (!_isUuid(normalizedInstallationId) ||
        _trimmed(_cacheState?['installation_id']) != normalizedInstallationId) {
      throw const OutboxRecoveryException(
        'Financial cache identity changed before synchronized data was saved.',
      );
    }
    final previousState = _deepClone(_cacheState) as Map;
    final previousGeneration = _cacheGeneration;
    try {
      final savedAt = DateTime.now().toUtc().toIso8601String();
      final cachedResponses = _mutableMap(_cacheState?['responses'])
        ..removeWhere((key, _) => _isTransactionDerivedResponse(key, scope));
      for (final entry in responses.entries) {
        cachedResponses[entry.key] = <String, Object?>{
          'saved_at': savedAt,
          'response': _deepClone(entry.value),
        };
      }
      final cachedDatasets = _mutableMap(_cacheState?['datasets'])
        ..removeWhere(
          (key, _) =>
              key.endsWith('|transactions|$scope') ||
              key.contains('|transactions|$scope|'),
        );
      for (final entry in datasets.entries) {
        cachedDatasets[entry.key] = <String, Object?>{
          'saved_at': savedAt,
          'scope': scope,
          'pages': _deepClone(entry.value),
        };
      }
      final adoptions = _mutableMap(_cacheState?['financial_adoptions']);
      adoptions[scope] = <String, Object?>{
        'saved_at': savedAt,
        'operation_uuids': includedOperationUuids.toList()..sort(),
      };
      _cacheState!
        ..['responses'] = cachedResponses
        ..['datasets'] = cachedDatasets
        ..['financial_adoptions'] = adoptions;
      await _persistCache();
      await _persistCache();
    } catch (_) {
      _cacheState = _objectMap(previousState);
      _cacheGeneration = previousGeneration;
      rethrow;
    }
  });

  Future<void> clearCachedResponses() => _serializeCache(() async {
    await _ensureCacheLoaded();
    final previousState = _deepClone(_cacheState) as Map;
    final previousGeneration = _cacheGeneration;
    _cacheState = _emptyCacheState(
      installationId: _trimmed(_cacheState?['installation_id']),
    );
    try {
      await _persistCache();
    } catch (_) {
      _cacheState = _objectMap(previousState);
      _cacheGeneration = previousGeneration;
      rethrow;
    }
  });

  Future<TransactionOutboxSnapshot> loadOutbox() async {
    await _ensureOutboxLoaded();
    return _copyOutbox(_outboxState!);
  }

  Future<void> saveOutbox(TransactionOutboxSnapshot snapshot) =>
      _serializeOutbox(() async {
        await _ensureOutboxLoaded();
        final candidate = <String, Object?>{
          'installation_id': snapshot.installationId,
          'next_local_id': snapshot.nextLocalId,
          'operations': snapshot.operations,
        };
        if (!_isValidOutboxPayload(candidate)) {
          throw const FormatException(
            'The pending transaction queue contains an invalid operation.',
          );
        }
        final previous = _copyOutbox(_outboxState!);
        _outboxState = _copyOutbox(snapshot);
        try {
          await _persistOutbox();
        } catch (_) {
          _outboxState = previous;
          rethrow;
        }
      });

  Future<void> _ensureCacheLoaded() {
    final existing = _cacheLoadFuture;
    if (existing != null) return existing;
    final future = _loadCache();
    _cacheLoadFuture = future;
    return future;
  }

  Future<void> _loadCache() async {
    try {
      final file = await _cacheFile();
      final recovered = await _recoverDocument(
        file,
        schemaVersion: cacheSchemaVersion,
        validatePayload: _isValidCachePayload,
      );
      final map = _mutableMap(recovered.payload);
      map['schema_version'] = cacheSchemaVersion;
      map['responses'] = _mutableMap(map['responses']);
      map['datasets'] = _mutableMap(map['datasets']);
      map['financial_adoptions'] = _mutableMap(map['financial_adoptions']);
      _cacheGeneration = recovered.generation;
      _cacheState = map;
    } catch (_) {
      // Cache loss is recoverable: network reads will repopulate it.
      _cacheState = _emptyCacheState();
    }
  }

  Future<void> _ensureOutboxLoaded() {
    final existing = _outboxLoadFuture;
    if (existing != null) return existing;
    final future = _loadOutbox();
    _outboxLoadFuture = future;
    return future;
  }

  Future<void> _loadOutbox() async {
    final file = await _outboxFile();
    if (!await file.exists() &&
        !await _temporary(file).exists() &&
        !await _backup(file).exists()) {
      _outboxState = const TransactionOutboxSnapshot(
        operations: [],
        nextLocalId: -1,
      );
      return;
    }
    _RecoveredDocument recovered;
    try {
      recovered = await _recoverDocument(
        file,
        schemaVersion: outboxSchemaVersion,
        validatePayload: _isValidOutboxPayload,
      );
    } catch (error) {
      throw OutboxRecoveryException(
        'The pending transaction queue could not be recovered. Its files were preserved for manual recovery. $error',
      );
    }
    final map = _jsonMap(recovered.payload);
    final operations = (map['operations'] as List)
        .whereType<Map>()
        .map(_objectMap)
        .toList();
    final storedNext = map['next_local_id'];
    final nextLocalId = storedNext is num ? storedNext.toInt() : -1;
    _outboxState = TransactionOutboxSnapshot(
      operations: operations,
      nextLocalId: nextLocalId < 0 ? nextLocalId : -1,
      installationId: _trimmed(map['installation_id']),
    );
    _outboxGeneration = recovered.generation;
  }

  Future<void> _persistCache() async {
    final file = await _cacheFile();
    final nextGeneration = _cacheGeneration + 1;
    await _atomicWrite(
      file,
      jsonEncode(
        _document(
          schemaVersion: cacheSchemaVersion,
          generation: nextGeneration,
          payload: _cachePayload(),
        ),
      ),
    );
    _cacheGeneration = nextGeneration;
  }

  Future<void> _persistOutbox() async {
    final file = await _outboxFile();
    final snapshot = _outboxState!;
    final nextGeneration = _outboxGeneration + 1;
    await _atomicWrite(
      file,
      jsonEncode(
        _document(
          schemaVersion: outboxSchemaVersion,
          generation: nextGeneration,
          payload: {
            'installation_id': snapshot.installationId,
            'next_local_id': snapshot.nextLocalId,
            'operations': snapshot.operations,
          },
        ),
      ),
    );
    _outboxGeneration = nextGeneration;
  }

  Map<String, Object?> _cachePayload() => <String, Object?>{
    'installation_id': _trimmed(_cacheState?['installation_id']),
    'responses': _mutableMap(_cacheState?['responses']),
    'datasets': _mutableMap(_cacheState?['datasets']),
    'financial_adoptions': _mutableMap(_cacheState?['financial_adoptions']),
  };

  Future<void> _atomicWrite(File target, String contents) async {
    await target.parent.create(recursive: true);
    final temporary = _temporary(target);
    final backup = _backup(target);
    await temporary.writeAsString(contents, flush: true);
    try {
      if (await target.exists()) {
        if (await backup.exists()) await backup.delete();
        await target.rename(backup.path);
      }
      await temporary.rename(target.path);
    } catch (_) {
      if (!await target.exists() && await backup.exists()) {
        await backup.rename(target.path);
      }
      // A handled failure must not leave a newer-looking uncommitted journal
      // that could be mistaken for a crash-recoverable generation on restart.
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {
        // Keep the original filesystem error. Recovery still validates every
        // generation and its checksum before loading it.
      }
      rethrow;
    }
  }

  Future<_RecoveredDocument> _recoverDocument(
    File file, {
    required int schemaVersion,
    required bool Function(Map<String, Object?> payload) validatePayload,
  }) async {
    final recovered = <_RecoveredDocument>[];
    for (final candidate in [file, _temporary(file), _backup(file)]) {
      final decoded = await _decodeDocument(
        candidate,
        schemaVersion: schemaVersion,
        validatePayload: validatePayload,
      );
      if (decoded != null) recovered.add(decoded);
    }
    if (recovered.isEmpty) {
      throw const FormatException(
        'No complete, supported persisted generation was found.',
      );
    }
    recovered.sort((a, b) => b.generation.compareTo(a.generation));
    final newestGeneration = recovered.first.generation;
    // At an equal generation, primary is committed, tmp is the crash journal,
    // and backup is the prior committed copy.
    for (final preferred in [file.path, _temporary(file).path]) {
      final match = recovered
          .where(
            (item) =>
                item.generation == newestGeneration &&
                item.source.path == preferred,
          )
          .firstOrNull;
      if (match != null) return match;
    }
    return recovered.first;
  }

  Future<_RecoveredDocument?> _decodeDocument(
    File file, {
    required int schemaVersion,
    required bool Function(Map<String, Object?> payload) validatePayload,
  }) async {
    if (!await file.exists()) return null;
    try {
      final decoded = _jsonMap(jsonDecode(await file.readAsString()));
      if (decoded['schema_version'] != schemaVersion) return null;

      final wrappedPayload = decoded['payload'];
      if (wrappedPayload is Map) {
        final generation = decoded['generation'];
        final checksum = decoded['checksum'];
        if (generation is! int || generation < 1 || checksum is! String) {
          return null;
        }
        final payload = _objectMap(wrappedPayload);
        if (_documentChecksum(
                  schemaVersion: schemaVersion,
                  generation: generation,
                  payload: payload,
                ) !=
                checksum ||
            !validatePayload(payload)) {
          return null;
        }
        return _RecoveredDocument(
          payload: payload,
          generation: generation,
          source: file,
        );
      }

      // Read the short-lived pre-journal format once so early development
      // builds do not lose a valid queue. Its first successful save upgrades it.
      if (!validatePayload(decoded)) return null;
      return _RecoveredDocument(payload: decoded, generation: 0, source: file);
    } catch (_) {
      return null;
    }
  }

  Future<File> _cacheFile() async {
    final override = _cacheFileProvider;
    if (override != null) return override();
    final directory = await _supportDirectoryProvider();
    return File(
      '${directory.path}${Platform.pathSeparator}Budget Tracker'
      '${Platform.pathSeparator}offline_cache.json',
    );
  }

  Future<File> _outboxFile() async {
    final override = _outboxFileProvider;
    if (override != null) return override();
    final directory = await _supportDirectoryProvider();
    return File(
      '${directory.path}${Platform.pathSeparator}Budget Tracker'
      '${Platform.pathSeparator}transaction_outbox.json',
    );
  }

  Future<void> _serializeCache(Future<void> Function() action) =>
      _serialize(_cacheWriteQueue, (next) => _cacheWriteQueue = next, action);

  Future<void> _serializeOutbox(Future<void> Function() action) =>
      _serialize(_outboxWriteQueue, (next) => _outboxWriteQueue = next, action);

  Future<void> _serialize(
    Future<void> queue,
    void Function(Future<void>) setQueue,
    Future<void> Function() action,
  ) {
    final completer = Completer<void>();
    final next = queue.catchError((_) {}).then((_) async {
      try {
        await action();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    setQueue(next);
    return completer.future;
  }

  void _trimCache(Map<String, Object?> cache) {
    if (cache.length <= _maximumCacheEntries) return;
    final keys = cache.keys.toList()
      ..sort((a, b) {
        final aDate = _jsonMap(cache[a])['saved_at']?.toString() ?? '';
        final bDate = _jsonMap(cache[b])['saved_at']?.toString() ?? '';
        return aDate.compareTo(bDate);
      });
    for (final key in keys.take(cache.length - _maximumCacheEntries)) {
      cache.remove(key);
    }
  }

  static Map<String, Object?> _emptyCacheState({String? installationId}) =>
      <String, Object?>{
        'schema_version': cacheSchemaVersion,
        'installation_id': installationId,
        'responses': <String, Object?>{},
        'datasets': <String, Object?>{},
        'financial_adoptions': <String, Object?>{},
      };

  static Map<String, Object?> _cacheValue(Object? response) =>
      <String, Object?>{
        'saved_at': DateTime.now().toUtc().toIso8601String(),
        'response': response,
      };

  static OfflineCacheEntry? _cacheEntry(Object? value) {
    final map = _jsonMap(value);
    if (map.isEmpty || !map.containsKey('response')) return null;
    return OfflineCacheEntry(
      response: map['response'],
      savedAt: _date(map['saved_at']),
    );
  }

  static DateTime _date(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  static File _backup(File file) => File('${file.path}.bak');

  static File _temporary(File file) => File('${file.path}.tmp');

  static Map<String, Object?> _document({
    required int schemaVersion,
    required int generation,
    required Map<String, Object?> payload,
  }) {
    final cloned = _objectMap(_deepClone(payload) as Map);
    return <String, Object?>{
      'schema_version': schemaVersion,
      'generation': generation,
      'payload': cloned,
      'checksum': _documentChecksum(
        schemaVersion: schemaVersion,
        generation: generation,
        payload: cloned,
      ),
    };
  }

  static String _documentChecksum({
    required int schemaVersion,
    required int generation,
    required Map<String, Object?> payload,
  }) => _checksum(
    jsonEncode({
      'schema_version': schemaVersion,
      'generation': generation,
      'payload': payload,
    }),
  );

  static bool _isValidCachePayload(Map<String, Object?> payload) {
    final installationId = _trimmed(payload['installation_id']);
    return payload['responses'] is Map &&
        payload['datasets'] is Map &&
        (payload['financial_adoptions'] == null ||
            payload['financial_adoptions'] is Map) &&
        (installationId == null || _isUuid(installationId));
  }

  static bool _isTransactionDerivedResponse(String key, String scope) {
    final encoded = key.split('#').first;
    try {
      final map = _jsonMap(jsonDecode(encoded));
      final path = map['path']?.toString();
      final query = _jsonMap(map['query']);
      return query['scope']?.toString() == scope &&
          const {
            '/accounts',
            '/transactions',
            '/dashboard',
            '/reports/summary',
            '/cutoff-periods',
            '/cutoff-periods/current',
          }.contains(path);
    } catch (_) {
      return false;
    }
  }

  static bool _isValidOutboxPayload(Map<String, Object?> payload) {
    final operations = payload['operations'];
    final nextLocalId = payload['next_local_id'];
    if (operations is! List ||
        nextLocalId is! num ||
        nextLocalId.toInt() != nextLocalId ||
        nextLocalId.toInt() >= 0) {
      return false;
    }
    var minimumLocalId = 0;
    final operationUuids = <String>{};
    final localIds = <int>{};
    for (final value in operations) {
      if (value is! Map) return false;
      final operation = _objectMap(value);
      final localId = operation['local_id'];
      final action = operation['action'];
      final status = operation['status'];
      final queuedAt = DateTime.tryParse(
        operation['queued_at']?.toString() ?? '',
      )?.toUtc();
      if (localId is! num ||
          localId.toInt() != localId ||
          localId.toInt() >= 0 ||
          !_isUuid(_trimmed(operation['operation_uuid'])) ||
          !const {'create', 'update', 'delete'}.contains(action) ||
          !const {
            'queued',
            'in_flight',
            'uncertain',
            'applied',
            'conflict',
            'rejected',
          }.contains(status) ||
          queuedAt == null ||
          queuedAt.year < 1000 ||
          queuedAt.year > 9999) {
        return false;
      }
      if (!operationUuids.add(
            operation['operation_uuid'].toString().trim().toLowerCase(),
          ) ||
          !localIds.add(localId.toInt())) {
        return false;
      }
      final serverId = operation['server_id'];
      final baseVersion = operation['base_version'];
      if (action == 'create') {
        if (serverId != null ||
            baseVersion != null ||
            !_isValidTransactionSnapshot(
              operation['desired_snapshot'],
              scope: operation['scope'],
              expectedId: localId.toInt(),
              allowNegativeId: true,
            )) {
          return false;
        }
      } else if (serverId is! int ||
          serverId <= 0 ||
          baseVersion is! int ||
          baseVersion <= 0 ||
          !_isValidTransactionSnapshot(
            operation['base_snapshot'],
            scope: operation['scope'],
            expectedId: serverId,
            expectedVersion: baseVersion,
          ) ||
          (action == 'update' &&
              !_isValidTransactionSnapshot(
                operation['desired_snapshot'],
                scope: operation['scope'],
                expectedId: serverId,
                expectedVersion: baseVersion,
              )) ||
          (action == 'delete' && operation['desired_snapshot'] != null)) {
        return false;
      }
      minimumLocalId = localId.toInt() < minimumLocalId
          ? localId.toInt()
          : minimumLocalId;
    }
    if (operations.isNotEmpty && nextLocalId.toInt() > minimumLocalId - 1) {
      return false;
    }
    final installationId = _trimmed(payload['installation_id']);
    return installationId == null || _isUuid(installationId);
  }

  static bool _isValidTransactionSnapshot(
    Object? value, {
    required Object? scope,
    int? expectedId,
    int? expectedVersion,
    bool allowNegativeId = false,
  }) {
    if (value is! Map || !const {'personal', 'joint'}.contains(scope)) {
      return false;
    }
    final snapshot = _objectMap(value);
    final id = snapshot['id'];
    final version = snapshot['version'];
    final amount = snapshot['amount_minor'];
    final accountId = snapshot['account_id'];
    final categoryId = snapshot['category_id'];
    final occurredOnText = snapshot['occurred_on']?.toString() ?? '';
    final occurredOn = DateTime.tryParse(occurredOnText);
    return id is int &&
        (allowNegativeId ? id < 0 : id > 0) &&
        (expectedId == null || id == expectedId) &&
        version is int &&
        version >= 0 &&
        (expectedVersion == null || version == expectedVersion) &&
        _isUuid(_trimmed(snapshot['client_uuid'])) &&
        const {'income', 'expense'}.contains(snapshot['kind']) &&
        amount is int &&
        amount > 0 &&
        amount <= Money.maxMinorUnits &&
        accountId is int &&
        accountId > 0 &&
        categoryId is int &&
        categoryId > 0 &&
        occurredOn != null &&
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(occurredOnText) &&
        _dateOnly(occurredOn) == occurredOnText &&
        (snapshot['payee']?.toString().trim().runes.length ?? 0) <= 150 &&
        (snapshot['note']?.toString().trim().runes.length ?? 0) <= 2000 &&
        snapshot['scope'] == scope &&
        snapshot['source_type'] == null &&
        snapshot['source_id'] == null &&
        snapshot['source_component'] == null;
  }

  static bool _isUuid(String? value) =>
      value != null &&
      RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
      ).hasMatch(value);

  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  // FNV-1a is used as a corruption/torn-write checksum, not for security.
  static String _checksum(String value) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static Object? _deepClone(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    return jsonDecode(jsonEncode(value));
  }

  static TransactionOutboxSnapshot _copyOutbox(
    TransactionOutboxSnapshot value,
  ) => TransactionOutboxSnapshot(
    operations: (jsonDecode(jsonEncode(value.operations)) as List)
        .whereType<Map>()
        .map(_objectMap)
        .toList(),
    nextLocalId: value.nextLocalId,
    installationId: value.installationId,
  );

  static Map<String, Object?> _mutableMap(Object? value) =>
      value is Map ? _objectMap(value) : <String, Object?>{};

  static Map<String, Object?> _jsonMap(Object? value) =>
      value is Map ? _objectMap(value) : const <String, Object?>{};

  static Map<String, Object?> _objectMap(Map<dynamic, dynamic> value) =>
      value.map((key, item) => MapEntry(key.toString(), item as Object?));

  static String? _trimmed(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

class _RecoveredDocument {
  const _RecoveredDocument({
    required this.payload,
    required this.generation,
    required this.source,
  });

  final Map<String, Object?> payload;
  final int generation;
  final File source;
}
