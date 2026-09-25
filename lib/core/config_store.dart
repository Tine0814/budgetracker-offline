import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

enum AppThemePreference {
  dark,
  light,
  system;

  static AppThemePreference fromStorage(Object? value) =>
      switch (value?.toString().trim().toLowerCase()) {
        'light' => AppThemePreference.light,
        'system' => AppThemePreference.system,
        _ => AppThemePreference.dark,
      };
}

class AppConfig {
  const AppConfig({
    this.apiBaseUrl = 'local',
    this.themePreference = AppThemePreference.dark,
  });
  // Internal compatibility key; never an address or a network connection.
  static const validatedDefaultApiBaseUrl = 'local';
  final String apiBaseUrl;
  final AppThemePreference themePreference;
  AppConfig copyWith({AppThemePreference? themePreference}) =>
      AppConfig(themePreference: themePreference ?? this.themePreference);
}

class ConfigStore {
  ConfigStore({
    Future<Directory> Function()? supportDirectoryProvider,
    Future<File> Function()? configFileProvider,
  }) : _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory,
       // Public injection name intentionally differs from private storage.
       // ignore: prefer_initializing_formals
       _configFileProvider = configFileProvider;
  final Future<Directory> Function() _supportDirectoryProvider;
  final Future<File> Function()? _configFileProvider;
  Future<File> _file() async {
    if (_configFileProvider != null) return _configFileProvider();
    final directory = await _supportDirectoryProvider();
    return File('${directory.path}/expeneses_tracker_offline/preferences.json');
  }

  Future<AppConfig> load() async {
    final file = await _file();
    if (!await file.exists()) return const AppConfig();
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const AppConfig();
      return AppConfig(
        themePreference: AppThemePreference.fromStorage(decoded['theme_mode']),
      );
    } on FormatException {
      return const AppConfig();
    }
  }

  Future<void> save(AppConfig config) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'theme_mode': config.themePreference.name}),
      flush: true,
    );
    await temporary.rename(file.path);
  }
}
