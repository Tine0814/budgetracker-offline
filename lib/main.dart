import 'package:flutter/material.dart';

import 'app.dart';
import 'core/api_client.dart';
import 'core/app_repository.dart';
import 'core/config_store.dart';
import 'state/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final configStore = ConfigStore();
  final config = await configStore.load();
  final data = ApiClient();
  runApp(
    BudgetTrackerApp(
      controller: AppController(
        configStore: configStore,
        api: data,
        repository: AppRepository(data),
        enableOfflineTransactions: false,
        initialConfig: config,
      ),
    ),
  );
}
