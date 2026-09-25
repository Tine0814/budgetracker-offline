import 'package:expeneses_tracker_offline/core/api_client.dart';
import 'package:expeneses_tracker_offline/core/app_repository.dart';
import 'package:expeneses_tracker_offline/core/config_store.dart';
import 'package:expeneses_tracker_offline/models/domain_models.dart';
import 'package:expeneses_tracker_offline/state/app_controller.dart';
import 'package:expeneses_tracker_offline/theme/app_theme.dart';
import 'package:expeneses_tracker_offline/ui/pages/budgets_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in <double>[320, 360, 412, 800]) {
    for (final largeText in [false, true]) {
      testWidgets('cutoff cards fit ${width.toInt()}px with '
          '${largeText ? 'large text, labels and amounts' : 'standard text'}', (
        tester,
      ) async {
        final controller = _controller(stress: largeText);
        final scale = largeText ? 1.8 : 1.0;
        await _pump(
          tester,
          controller,
          size: Size(width, 760),
          textScale: scale,
        );

        final current = find.byKey(const Key('current-cutoff-card'));
        final currentTitle = find.byKey(const Key('current-cutoff-title'));
        final currentProgress = find.byKey(
          const Key('current-cutoff-progress'),
        );
        expect(current, findsOneWidget);
        final titleRect = tester.getRect(currentTitle);
        expect(titleRect.width, greaterThanOrEqualTo(128));
        expect(
          titleRect.height,
          lessThan(largeText ? 240 : 90),
          reason: 'The cutoff name must not wrap one letter per line.',
        );
        _expectInside(tester, currentTitle, current);
        _expectInside(tester, currentProgress, current);
        if (width < 600) {
          expect(
            tester.getRect(currentProgress).top,
            greaterThanOrEqualTo(titleRect.bottom),
          );
        }
        expect(tester.takeException(), isNull);

        for (final period in controller.cutoffPeriods) {
          final card = find.byKey(Key('cutoff-period-${period.id}'));
          final title = find.byKey(Key('cutoff-period-title-${period.id}'));
          final progress = find.byKey(
            Key('cutoff-period-progress-${period.id}'),
          );
          final edit = find.byKey(Key('cutoff-period-edit-${period.id}'));
          expect(card, findsOneWidget);
          await tester.ensureVisible(edit);
          await tester.pumpAndSettle();
          _expectInside(tester, title, card);
          _expectInside(tester, progress, card);
          _expectInside(tester, edit, card);
          expect(tester.getRect(title).width, greaterThanOrEqualTo(100));
          expect(tester.getRect(title).height, lessThan(largeText ? 240 : 90));
          if (width < 600) {
            expect(
              tester.getRect(progress).top,
              greaterThanOrEqualTo(tester.getRect(title).bottom),
            );
          }
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('empty cutoff page keeps schedule creation available', (
    tester,
  ) async {
    final controller = _controller()
      ..cutoffPeriods = const []
      ..cutoffSchedules = const [];
    await _pump(tester, controller, size: const Size(320, 568));
    expect(find.text('No cutoff periods yet'), findsOneWidget);
    expect(find.text('No schedule yet'), findsOneWidget);
    final create = find.text('New schedule version');
    await tester.ensureVisible(create);
    expect(create.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('budget editor stays usable with keyboard and cancels safely', (
    tester,
  ) async {
    final controller = _controller(stress: true);
    await _pump(tester, controller, size: const Size(320, 568));
    await _openBudget(tester, 101);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();

    final field = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextFormField),
    );
    await tester.ensureVisible(field);
    await tester.enterText(field, '1234.56');
    final input = tester.widget<TextField>(
      find.descendant(of: field, matching: find.byType(TextField)),
    );
    expect(
      input.keyboardType,
      const TextInputType.numberWithOptions(decimal: true),
    );
    await tester.ensureVisible(find.text('Save budget'));
    expect(find.text('Save budget').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(controller.budgetUpdates, isEmpty);
    expect(tester.takeException(), isNull);

    // Reopening after the closing animation also catches disposed controllers
    // that were still attached to the departing dialog route.
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await _openBudget(tester, 101);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('budget editor saves the edited amount on a narrow phone', (
    tester,
  ) async {
    final controller = _controller();
    await _pump(tester, controller, size: const Size(320, 568));
    await _openBudget(tester, 101);
    final field = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(field, '1234.56');
    await tester.tap(find.text('Save budget'));
    await tester.pumpAndSettle();
    expect(controller.budgetUpdates, [(101, 123456)]);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('schedule form scrolls above keyboard and creates a version', (
    tester,
  ) async {
    final controller = _controller();
    await _pump(tester, controller, size: const Size(320, 568));
    await tester.tap(find.text('New schedule version'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();

    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextFormField),
    );
    expect(fields, findsNWidgets(3));
    for (final entry in <(int, String)>[
      (0, 'My payday plan'),
      (1, '2500'),
      (2, '3500'),
    ]) {
      final field = fields.at(entry.$1);
      await tester.ensureVisible(field);
      await tester.enterText(field, entry.$2);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.ensureVisible(find.text('Create version'));
    expect(find.text('Create version').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Create version'));
    await tester.pumpAndSettle();
    expect(controller.createdSchedules, [('My payday plan', 250000, 350000)]);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

void _expectInside(WidgetTester tester, Finder child, Finder parent) {
  final inner = tester.getRect(child);
  final outer = tester.getRect(parent);
  expect(inner.left, greaterThanOrEqualTo(outer.left - 0.5));
  expect(inner.top, greaterThanOrEqualTo(outer.top - 0.5));
  expect(inner.right, lessThanOrEqualTo(outer.right + 0.5));
  expect(inner.bottom, lessThanOrEqualTo(outer.bottom + 0.5));
}

Future<void> _openBudget(WidgetTester tester, int id) async {
  final edit = find.byKey(Key('cutoff-period-edit-$id'));
  await tester.ensureVisible(edit);
  await tester.tap(edit);
  await tester.pumpAndSettle();
  expect(find.text('Save budget'), findsOneWidget);
}

Future<void> _pump(
  WidgetTester tester,
  AppController controller, {
  required Size size,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetViewInsets();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(body: BudgetsPage(controller: controller)),
    ),
  );
  await tester.pumpAndSettle();
}

_RecordingController _controller({bool stress = false}) {
  final now = DateTime.now();
  final controller = _RecordingController();
  final firstLabel = stress
      ? 'First cutoff for household and personal spending'
      : 'First cutoff';
  final secondLabel = stress
      ? 'Second cutoff for household and personal spending'
      : 'Second cutoff';
  final budget = stress ? 987654321000 : 2500000;
  controller.cutoffPeriods = [
    CutoffPeriod(
      id: 101,
      label: secondLabel,
      startsOn: now.subtract(const Duration(days: 3)),
      endsOn: now.add(const Duration(days: 12)),
      budgetMinor: budget,
      spentMinor: stress ? 123456789012 : 1234500,
    ),
    CutoffPeriod(
      id: 102,
      label: firstLabel,
      startsOn: now.add(const Duration(days: 13)),
      endsOn: now.add(const Duration(days: 27)),
      budgetMinor: 0,
      spentMinor: 0,
    ),
    CutoffPeriod(
      id: 103,
      label: firstLabel,
      startsOn: now.subtract(const Duration(days: 18)),
      endsOn: now.subtract(const Duration(days: 4)),
      budgetMinor: budget,
      spentMinor: budget + 1000000,
      isBudgetOverridden: true,
    ),
  ];
  controller.cutoffSchedules = [
    CutoffSchedule(
      id: 1,
      name: stress
          ? 'Semi-monthly household and personal spending schedule'
          : 'Semi-monthly',
      effectiveFrom: DateTime(now.year, now.month),
      rules: [
        CutoffRule(
          id: 1,
          label: firstLabel,
          startDay: 1,
          defaultBudgetMinor: budget,
        ),
        CutoffRule(
          id: 2,
          label: secondLabel,
          startDay: 16,
          defaultBudgetMinor: budget,
        ),
      ],
    ),
  ];
  addTearDown(controller.dispose);
  return controller;
}

class _RecordingController extends AppController {
  factory _RecordingController() => _RecordingController._(ApiClient());

  _RecordingController._(ApiClient api)
    : super(
        configStore: ConfigStore(),
        api: api,
        repository: AppRepository(api),
        enableOfflineTransactions: false,
      );

  final budgetUpdates = <(int, int)>[];
  final createdSchedules = <(String, int, int)>[];

  @override
  Future<void> updateCutoffBudget(CutoffPeriod period, int amountMinor) async {
    budgetUpdates.add((period.id, amountMinor));
  }

  @override
  Future<void> createSchedule({
    required String name,
    required DateTime effectiveFrom,
    required int firstBudgetMinor,
    required int secondBudgetMinor,
  }) async {
    createdSchedules.add((name, firstBudgetMinor, secondBudgetMinor));
  }
}
