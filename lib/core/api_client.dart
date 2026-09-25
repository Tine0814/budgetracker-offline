import 'dart:convert';

import 'local_database.dart';
import 'offline_store.dart';

class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.statusCode,
    this.code,
    this.errors = const {},
    this.isConnectionError = false,
  });

  final String message;
  final int? statusCode;
  final String? code;
  final Map<String, List<String>> errors;
  final bool isConnectionError;

  @override
  String toString() => message;
}

/// Compatibility facade for the original screens. Every operation goes
/// directly to LocalDatabase in this process. There is no networking.
class ApiClient {
  ApiClient({
    String baseUrl = 'local',
    LocalDatabase? database,
    this.offlineStore,
  }) : database = database ?? LocalDatabase();
  final LocalDatabase database;
  OfflineStore? offlineStore;
  String baseUrl = 'local';
  String? cacheNamespace;
  bool cacheOnlyReads = false;
  void Function(bool offline)? onOfflineStateChanged;
  bool get isOffline => false;
  DateTime? get lastNetworkSuccessAt => null;
  DateTime? get lastCacheFallbackAt => null;
  DateTime? get lastCachedResponseSavedAt => null;
  int get cacheFallbackCount => 0;
  String cacheKeyFor(String path, {Map<String, Object?> query = const {}}) =>
      jsonEncode({'path': path, 'query': query});
  Future<dynamic> get(
    String path, {
    Map<String, Object?> query = const {},
    Set<int> additionalSuccessStatusCodes = const {},
  }) => database.request('GET', path, query: query);
  Future<dynamic> networkGet(
    String path, {
    Map<String, Object?> query = const {},
    Set<int> additionalSuccessStatusCodes = const {},
    bool cacheResponse = false,
  }) => get(path, query: query);
  Future<dynamic> post(String path, {Object? body}) =>
      database.request('POST', path, body: body);
  Future<dynamic> put(String path, {Object? body}) =>
      database.request('PUT', path, body: body);
  Future<dynamic> patch(String path, {Object? body}) =>
      database.request('PATCH', path, body: body);
  Future<dynamic> delete(String path, {Object? body}) =>
      database.request('DELETE', path, body: body);
  void close() {}
}
