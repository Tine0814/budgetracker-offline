import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../models/domain_models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';

String _periodDates(CutoffPeriod period) =>
    '${DateFormat('MMM d').format(period.startsOn)} – ${DateFormat('MMM d, y').format(period.endsOn)}';

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

class BudgetsPage extends StatelessWidget {
  const BudgetsPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final periods = [...controller.cutoffPeriods]
      ..sort((a, b) => b.startsOn.compareTo(a.startsOn));
    final today = _today();
    final active = periods
        .where(
          (period) =>
              !period.startsOn.isAfter(today) && !period.endsOn.isBefore(today),
        )
        .firstOrNull;
    return SingleChildScrollView(
      padding: responsivePagePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: 'Cutoffs & budgets',
            subtitle: 'Give your payday a plan before spending begins.',
            actions: [
              OutlinedButton.icon(
                onPressed: controller.refreshCutoffs,
                icon: const Icon(Icons.refresh_rounded, size: 19),
                label: const Text('Refresh'),
              ),
              FilledButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _ScheduleDialog(controller: controller),
                ),
                icon: const Icon(Icons.tune_rounded, size: 19),
                label: const Text('New schedule version'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (!controller.hasSavedCutoffs)
            const SectionCard(
              child: EmptyState(
                icon: Icons.calendar_month_outlined,
                title: 'Cutoffs could not be loaded',
                message: 'Try refreshing your saved budget data.',
              ),
            )
          else ...[
            if (active != null) ...[
              _CurrentCutoff(period: active, controller: controller),
              const SizedBox(height: 18),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final schedules = _SchedulePanel(
                  schedules: controller.cutoffSchedules,
                  controller: controller,
                  available: controller.hasSavedSchedules,
                );
                final history = _PeriodsPanel(
                  periods: periods,
                  controller: controller,
                  onEdit: (period) => _showBudgetDialog(context, period),
                  onReset: (period) => _resetBudget(context, period),
                );
                if (constraints.maxWidth < 980) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [schedules, const SizedBox(height: 18), history],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4, child: schedules),
                    const SizedBox(width: 18),
                    Expanded(flex: 7, child: history),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showBudgetDialog(
    BuildContext context,
    CutoffPeriod period,
  ) async {
    final amount = await showDialog<int>(
      context: context,
      builder: (_) => _BudgetDialog(period: period, controller: controller),
    );
    if (amount == null || !context.mounted) return;
    try {
      await controller.updateCutoffBudget(period, amount);
      if (context.mounted) showSuccess(context, 'Cutoff budget updated.');
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _resetBudget(BuildContext context, CutoffPeriod period) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Text('Reset ${period.label} budget?'),
        content: const Text(
          'This removes the custom total and category allocations for this cutoff and restores its schedule defaults. Your transactions stay saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset budget'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.resetCutoffBudget(period);
      if (context.mounted) showSuccess(context, 'Schedule budget restored.');
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }
}

class _CurrentCutoff extends StatelessWidget {
  const _CurrentCutoff({required this.period, required this.controller});
  final CutoffPeriod period;
  final AppController controller;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('current-cutoff-card'),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [context.palette.heroStart, context.palette.heroEnd],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(19),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final title = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CutoffIcon(hero: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CURRENT CUTOFF',
                    style: TextStyle(
                      color: context.palette.onHeroMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    period.label,
                    key: const Key('current-cutoff-title'),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.palette.onHero,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _periodDates(period),
                    style: TextStyle(
                      color: context.palette.onHeroMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        final progress = _CutoffProgress(
          key: const Key('current-cutoff-progress'),
          period: period,
          controller: controller,
          hero: true,
        );
        final scaledWidth =
            constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1);
        if (scaledWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [title, const SizedBox(height: 22), progress],
          );
        }
        return Row(
          children: [
            Expanded(flex: 3, child: title),
            const SizedBox(width: 24),
            Expanded(flex: 2, child: progress),
          ],
        );
      },
    ),
  );
}

class _CutoffIcon extends StatelessWidget {
  const _CutoffIcon({this.hero = false, this.over = false});
  final bool hero;
  final bool over;
  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: hero
          ? context.palette.onHero.withValues(alpha: 0.12)
          : over
          ? context.palette.orangeSoft
          : context.palette.mint,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(
      Icons.calendar_view_week_rounded,
      size: 22,
      color: hero
          ? context.palette.onHero
          : over
          ? context.palette.orange
          : context.palette.greenDark,
    ),
  );
}

class _CutoffProgress extends StatelessWidget {
  const _CutoffProgress({
    super.key,
    required this.period,
    required this.controller,
    this.hero = false,
  });
  final CutoffPeriod period;
  final AppController controller;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final utilization = period.utilization;
    final ratio = (utilization ?? 0).clamp(0.0, 1.0);
    final remaining = period.remainingMinor;
    final ink = hero ? context.palette.onHero : context.palette.ink;
    final muted = hero ? context.palette.onHeroMuted : context.palette.muted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: hero ? 8 : 6,
            color: remaining < 0
                ? context.palette.orange
                : hero
                ? context.palette.onHero
                : context.palette.green,
            backgroundColor: hero
                ? context.palette.onHero.withValues(alpha: 0.15)
                : context.palette.border,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              utilization == null
                  ? 'No budget set'
                  : '${(utilization * 100).round()}% used',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: Money.format(
                      remaining.abs(),
                      currencyCode: controller.currencyCode,
                      locale: controller.locale,
                    ),
                    style: TextStyle(color: ink, fontWeight: FontWeight.w800),
                  ),
                  TextSpan(
                    text: remaining < 0 ? ' over' : ' left',
                    style: TextStyle(color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SchedulePanel extends StatelessWidget {
  const _SchedulePanel({
    required this.schedules,
    required this.controller,
    required this.available,
  });
  final List<CutoffSchedule> schedules;
  final AppController controller;
  final bool available;

  @override
  Widget build(BuildContext context) {
    final sorted = [...schedules]
      ..sort((a, b) => b.effectiveFrom.compareTo(a.effectiveFrom));
    final today = _today();
    final current = sorted
        .where(
          (s) =>
              !s.effectiveFrom.isAfter(today) &&
              (s.effectiveTo == null || !s.effectiveTo!.isBefore(today)),
        )
        .firstOrNull;
    final upcoming = sorted.reversed
        .where((s) => s.effectiveFrom.isAfter(today))
        .firstOrNull;
    final shown = [?current, ?upcoming];
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Schedule', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Recurring cutoff defaults',
            style: TextStyle(color: context.palette.muted, fontSize: 12),
          ),
          const SizedBox(height: 18),
          if (!available)
            const Text(
              'Your cutoff schedule could not be read. Try refreshing saved data.',
            )
          else if (shown.isEmpty) ...[
            const Text(
              'No schedule yet',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Create a schedule to set your recurring cutoff budgets.',
            ),
          ] else
            for (final schedule in shown) ...[
              if (schedule != shown.first) const Divider(height: 32),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    schedule.name,
                    style: TextStyle(
                      color: context.palette.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  StatusPill(
                    label: schedule == current ? 'Active' : 'Upcoming',
                    neutral: schedule != current,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                schedule.effectiveFrom == DateTime(1900, 1, 1)
                    ? 'Default monthly schedule'
                    : 'Effective ${DateFormat('MMMM y').format(schedule.effectiveFrom)}',
                style: TextStyle(color: context.palette.muted, fontSize: 12),
              ),
              const Divider(height: 24),
              for (final rule in schedule.rules)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: context.palette.mint,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${rule.startDay}',
                          style: TextStyle(
                            color: context.palette.greenDark,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rule.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              rule.startDay == 1
                                  ? 'Days 1–15'
                                  : 'Day 16 to month end',
                              style: TextStyle(
                                color: context.palette.muted,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 6),
                            MoneyLabel(
                              minorUnits: rule.defaultBudgetMinor,
                              currencyCode: controller.currencyCode,
                              locale: controller.locale,
                              style: TextStyle(
                                color: context.palette.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          if (sorted.length > shown.length)
            Text(
              '${sorted.length - shown.length} other schedule version${sorted.length - shown.length == 1 ? '' : 's'} saved',
              style: TextStyle(color: context.palette.muted, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _PeriodsPanel extends StatelessWidget {
  const _PeriodsPanel({
    required this.periods,
    required this.controller,
    required this.onEdit,
    required this.onReset,
  });
  final List<CutoffPeriod> periods;
  final AppController controller;
  final ValueChanged<CutoffPeriod> onEdit;
  final ValueChanged<CutoffPeriod> onReset;

  @override
  Widget build(BuildContext context) => SectionCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Cutoff periods', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Budgets and spending by pay period',
          style: TextStyle(color: context.palette.muted, fontSize: 12),
        ),
        const SizedBox(height: 16),
        if (periods.isEmpty) ...[
          const Text(
            'No cutoff periods yet',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Your cutoff periods will appear after a schedule is created.',
          ),
        ] else
          for (final period in periods)
            Container(
              key: Key('cutoff-period-${period.id}'),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.palette.surfaceMuted,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.palette.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CutoffIcon(over: period.remainingMinor < 0),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              period.label,
                              key: Key('cutoff-period-title-${period.id}'),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.palette.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _periodDates(period),
                              style: TextStyle(
                                color: context.palette.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: Money.format(
                            period.spentMinor,
                            currencyCode: controller.currencyCode,
                            locale: controller.locale,
                          ),
                          style: TextStyle(
                            color: context.palette.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextSpan(
                          text:
                              ' spent of ${Money.format(period.budgetMinor, currencyCode: controller.currencyCode, locale: controller.locale)}',
                          style: TextStyle(color: context.palette.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _CutoffProgress(
                    key: Key('cutoff-period-progress-${period.id}'),
                    period: period,
                    controller: controller,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (period.isBudgetOverridden)
                        const StatusPill(label: 'Custom budget', neutral: true),
                      TextButton.icon(
                        key: Key('cutoff-period-edit-${period.id}'),
                        onPressed: () => onEdit(period),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit budget'),
                      ),
                      if (period.isBudgetOverridden)
                        TextButton(
                          onPressed: () => onReset(period),
                          child: const Text('Reset to default'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
      ],
    ),
  );
}

class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog({required this.period, required this.controller});
  final CutoffPeriod period;
  final AppController controller;
  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  final formKey = GlobalKey<FormState>();
  late final field = TextEditingController(
    text: Money.decimal(widget.period.budgetMinor),
  );
  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    title: Text('Set ${widget.period.label} budget'),
    content: SizedBox(
      width: 430,
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _periodDates(widget.period),
              style: TextStyle(color: context.palette.muted),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: field,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Total budget',
                prefixText: widget.controller.currencyCode == 'PHP'
                    ? '₱ '
                    : '${widget.controller.currencyCode} ',
              ),
              validator: (value) {
                try {
                  final amount = Money.parse(value ?? '');
                  final allocated = widget.period.items.fold<int>(
                    0,
                    (sum, item) => sum + item.budgetMinor,
                  );
                  if (amount < 0) return 'Budget cannot be negative.';
                  if (amount < allocated) {
                    return 'Keep the budget at or above its category allocations.';
                  }
                  return null;
                } on FormatException catch (error) {
                  return error.message;
                }
              },
            ),
            const SizedBox(height: 12),
            Text(
              'This changes only this cutoff. Your schedule defaults stay the same.',
              style: TextStyle(color: context.palette.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (formKey.currentState!.validate()) {
            Navigator.pop(context, Money.parse(field.text));
          }
        },
        child: const Text('Save budget'),
      ),
    ],
  );
}

class _ScheduleDialog extends StatefulWidget {
  const _ScheduleDialog({required this.controller});
  final AppController controller;

  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  final key = GlobalKey<FormState>();
  final nameController = TextEditingController(text: 'Semi-monthly');
  final firstController = TextEditingController();
  final secondController = TextEditingController();
  DateTime effectiveFrom = DateTime(
    DateTime.now().year,
    DateTime.now().month + 1,
    1,
  );
  bool saving = false;

  @override
  void dispose() {
    nameController.dispose();
    firstController.dispose();
    secondController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalInset = width < 480 ? 16.0 : 40.0;
    final dialogWidth = (width - horizontalInset * 2 - 48)
        .clamp(0.0, 540.0)
        .toDouble();
    final budgetFields = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _budgetField(firstController, 'First cutoff budget'),
        const SizedBox(height: 12),
        _budgetField(secondController, 'Second cutoff budget'),
      ],
    );
    return AlertDialog(
      scrollable: true,
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: 24,
      ),
      title: Text('New cutoff schedule'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: dialogWidth,
          maxWidth: dialogWidth,
        ),
        child: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Changes begin on a future month and keep your past cutoffs unchanged.',
                style: TextStyle(color: context.palette.muted),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Schedule name'),
                validator: (value) =>
                    (value?.trim().isEmpty ?? true) ? 'Enter a name.' : null,
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: _pickMonth,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Effective month',
                    suffixIcon: Icon(Icons.calendar_month_rounded),
                  ),
                  child: Text(DateFormat('MMMM y').format(effectiveFrom)),
                ),
              ),
              const SizedBox(height: 14),
              budgetFields,
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: context.palette.muted,
                  ),
                  SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'First cutoff is days 1–15; second is day 16 through month-end.',
                      style: TextStyle(
                        color: context.palette.muted,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: context.palette.greenDark,
          ),
          onPressed: saving ? null : _save,
          child: Text(saving ? 'Saving…' : 'Create version'),
        ),
      ],
    );
  }

  Widget _budgetField(TextEditingController controller, String label) =>
      TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          prefixText: widget.controller.currencyCode == 'PHP'
              ? '₱ '
              : '${widget.controller.currencyCode} ',
        ),
        validator: (value) {
          try {
            return Money.parse(value?.isEmpty == true ? '0' : value ?? '0') < 0
                ? 'Cannot be negative.'
                : null;
          } on FormatException catch (error) {
            return error.message;
          }
        },
      );

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: effectiveFrom,
      firstDate: DateTime(DateTime.now().year, DateTime.now().month + 1, 1),
      lastDate: DateTime(DateTime.now().year + 5, 12, 1),
    );
    if (picked != null) {
      setState(() => effectiveFrom = DateTime(picked.year, picked.month, 1));
    }
  }

  Future<void> _save() async {
    if (!key.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await widget.controller.createSchedule(
        name: nameController.text.trim(),
        effectiveFrom: effectiveFrom,
        firstBudgetMinor: Money.parse(
          firstController.text.isEmpty ? '0' : firstController.text,
        ),
        secondBudgetMinor: Money.parse(
          secondController.text.isEmpty ? '0' : secondController.text,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}
