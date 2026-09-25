import 'dart:convert';
import 'dart:io';

import 'package:expenses_tracker_offline/core/api_client.dart';
import 'package:expenses_tracker_offline/core/local_database.dart';
import 'package:expenses_tracker_offline/models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File file;
  late LocalDatabase database;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('report-preferences-');
    file = File('${directory.path}/data.json');
    database = LocalDatabase(file: file);
  });

  tearDown(() => directory.delete(recursive: true));

  Future<AppSettings> settings(LocalDatabase db) async =>
      AppSettings.fromJson(await db.request('GET', '/settings'));

  test('settings default to visible and preserve independent visibility', () {
    final original = AppSettings.fromJson({
      'currency_code': 'PHP',
      'locale': 'en_PH',
      'timezone': 'Asia/Manila',
      'week_starts_on': 1,
    });
    expect(original.showJewelryInReports, isTrue);
    expect(original.showCreditCardsInReports, isTrue);

    final jewelryHidden = original.copyWith(showJewelryInReports: false);
    final restored = AppSettings.fromJson({'data': jewelryHidden.toJson()});
    expect(restored.showJewelryInReports, isFalse);
    expect(restored.showCreditCardsInReports, isTrue);

    final cardsHidden = restored.copyWith(
      showJewelryInReports: true,
      showCreditCardsInReports: false,
    );
    final copied = cardsHidden.copyWith(currencyCode: 'USD');
    expect(copied.showJewelryInReports, isTrue);
    expect(copied.showCreditCardsInReports, isFalse);
    expect(copied.currencyCode, 'USD');
  });

  test('visibility persists after restart and backup restoration', () async {
    final defaults = await settings(database);
    expect(defaults.showJewelryInReports, isTrue);
    expect(defaults.showCreditCardsInReports, isTrue);

    for (final visibility in [(false, true), (true, false), (false, false)]) {
      final next = defaults.copyWith(
        showJewelryInReports: visibility.$1,
        showCreditCardsInReports: visibility.$2,
      );
      await database.request('PATCH', '/settings', body: next.toJson());
      final restarted = LocalDatabase(file: file);
      expect((await settings(restarted)).toJson(), next.toJson());

      final restored = LocalDatabase(
        file: File('${directory.path}/restored.json'),
      );
      await restored.importBackup(await database.exportBackup());
      expect((await settings(restored)).toJson(), next.toJson());
    }
  });

  test('older settings updates preserve report visibility', () async {
    await database.request(
      'PATCH',
      '/settings',
      body: const AppSettings(
        showJewelryInReports: false,
        showCreditCardsInReports: false,
      ).toJson(),
    );
    await database.request(
      'PATCH',
      '/settings',
      body: {
        'currency_code': 'USD',
        'locale': 'en_US',
        'timezone': 'Asia/Manila',
        'week_starts_on': 0,
      },
    );
    final updated = await settings(database);
    expect(updated.showJewelryInReports, isFalse);
    expect(updated.showCreditCardsInReports, isFalse);
    expect(updated.currencyCode, 'USD');
  });

  test(
    'legacy saved data and backups keep both report sections visible',
    () async {
      final legacy = jsonDecode(await database.exportBackup()) as Map;
      final oldSettings = legacy['settings'] as Map;
      oldSettings.remove('show_jewelry_in_reports');
      oldSettings.remove('show_credit_cards_in_reports');
      final legacyJson = jsonEncode(legacy);

      await file.writeAsString(legacyJson);
      final restarted = LocalDatabase(file: file);
      final loaded = await restarted.request('GET', '/settings');
      expect(loaded['data']['show_jewelry_in_reports'], isTrue);
      expect(loaded['data']['show_credit_cards_in_reports'], isTrue);

      await database.importBackup(legacyJson);
      final restored = await database.request('GET', '/settings');
      expect(restored['data']['show_jewelry_in_reports'], isTrue);
      expect(restored['data']['show_credit_cards_in_reports'], isTrue);
      final exported = jsonDecode(await database.exportBackup()) as Map;
      expect(exported['accounts'], legacy['accounts']);
      expect(exported['transactions'], legacy['transactions']);
    },
  );

  test('invalid report visibility updates preserve saved settings', () async {
    final original = await database.exportBackup();
    final bytes = await file.readAsString();
    for (final field in [
      'show_jewelry_in_reports',
      'show_credit_cards_in_reports',
    ]) {
      for (final invalid in [null, 'false', 0]) {
        await expectLater(
          database.request(
            'PATCH',
            '/settings',
            body: {...const AppSettings().toJson(), field: invalid},
          ),
          throwsA(isA<ApiException>()),
        );
        expect(await database.exportBackup(), original);
        expect(await file.readAsString(), bytes);
      }
    }
  });

  test('invalid visibility in backups cannot replace current data', () async {
    final original = await database.exportBackup();
    final bytes = await file.readAsString();
    for (final field in [
      'show_jewelry_in_reports',
      'show_credit_cards_in_reports',
    ]) {
      for (final invalid in [null, 'false', 0]) {
        final altered = jsonDecode(original) as Map;
        altered['settings'][field] = invalid;
        await expectLater(
          database.importBackup(jsonEncode(altered)),
          throwsFormatException,
        );
        expect(await database.exportBackup(), original);
        expect(await file.readAsString(), bytes);
      }
    }
  });
}
