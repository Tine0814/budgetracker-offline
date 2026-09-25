import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../models/domain_models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late String period;

  @override
  void initState() {
    super.initState();
    period = widget.controller.selectedPeriod;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.controller.loadReport(period);
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = widget.controller.selectedFinanceScope;
    final isJoint = scope == FinanceScope.joint;
    final showCreditCards = widget.controller.settings.showCreditCardsInReports;
    final loadedSummary = widget.controller.reportSummary;
    if (!widget.controller.hasSavedSettings || loadedSummary == null) {
      return SingleChildScrollView(
        padding: responsivePagePadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: isJoint ? 'Joint reports' : 'Personal reports',
              subtitle: isJoint
                  ? 'Review the cashflow and budget you share together.'
                  : 'Review your cashflow, spending, and savings.',
              actions: [
                FinanceScopeSelector(selected: scope, onSelected: _selectScope),
                OutlinedButton.icon(
                  onPressed: () => widget.controller.loadReport(period),
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FinanceScopeNotice(scope: scope),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in const ['week', 'month', 'year', 'cutoff'])
                  ChoiceChip(
                    label: Text(value[0].toUpperCase() + value.substring(1)),
                    selected: period == value,
                    onSelected: (_) => _selectPeriod(value),
                  ),
                IconButton(
                  tooltip: 'Previous period',
                  onPressed: () => _move(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                IconButton(
                  tooltip: 'Next period',
                  onPressed: () => _move(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SectionCard(
              child: EmptyState(
                icon: widget.controller.isRefreshing
                    ? Icons.sync_rounded
                    : Icons.cloud_off_rounded,
                title: widget.controller.isRefreshing
                    ? 'Loading this report…'
                    : !widget.controller.hasSavedSettings
                    ? 'Money formatting is not saved on this device'
                    : 'This report is not saved for the selected period',
                message: !widget.controller.hasSavedSettings
                    ? 'Your display preferences could not be read. Try refreshing saved data.'
                    : 'Your report could not be calculated. Try refreshing this period.',
              ),
            ),
          ],
        ),
      );
    }
    final summary = loadedSummary;
    return SingleChildScrollView(
      padding: responsivePagePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: isJoint ? 'Joint reports' : 'Personal reports',
            subtitle: isJoint
                ? 'Review the cashflow and budget you share together.'
                : 'Review your cashflow, spending, and savings.',
            actions: [
              FinanceScopeSelector(selected: scope, onSelected: _selectScope),
              OutlinedButton.icon(
                onPressed: () => widget.controller.loadReport(period),
                icon: const Icon(Icons.refresh_rounded, size: 19),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FinanceScopeNotice(scope: scope),
          if (widget.controller.pendingProjectionCount > 0) ...[
            const SizedBox(height: 12),
            SectionCard(
              child: Text(
                'Top-line cashflow and visible balance and budget totals include pending transaction adjustments. The chart and category breakdown remain saved server data until sync completes.',
                style: TextStyle(
                  color: context.palette.inkSoft,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: _ReportToolbar(
              period: period,
              summary: summary,
              onPeriodSelected: _selectPeriod,
              onPrevious: () => _move(-1),
              onNext: () => _move(1),
            ),
          ),
          const SizedBox(height: 18),
          if (!isJoint)
            _PersonalReportsDashboard(
              summary: summary,
              showCreditCards: showCreditCards,
              currencyCode: widget.controller.currencyCode,
              locale: widget.controller.locale,
            ),
          if (isJoint) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1000
                    ? 4
                    : constraints.maxWidth >= 600
                    ? 2
                    : 1;
                final width =
                    (constraints.maxWidth - (columns - 1) * 14) / columns;
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children:
                      [
                            _ReportMetric(
                              'Income',
                              summary.incomeMinor,
                              Icons.south_west_rounded,
                              context.palette.green,
                            ),
                            _ReportMetric(
                              'Expenses',
                              summary.expenseMinor,
                              Icons.north_east_rounded,
                              context.palette.orange,
                            ),
                            _ReportMetric(
                              'Net cashflow',
                              summary.netMinor,
                              Icons.stacked_line_chart_rounded,
                              summary.netMinor >= 0
                                  ? context.palette.greenDark
                                  : context.palette.red,
                            ),
                            _ReportMetric(
                              'Budget remaining',
                              summary.hasBudget
                                  ? summary.remainingBudgetMinor
                                  : null,
                              Icons.savings_rounded,
                              summary.remainingBudgetMinor >= 0
                                  ? context.palette.greenDark
                                  : context.palette.red,
                            ),
                            if (summary.accounts.any(
                              (account) => account.isSavingsAccount,
                            )) ...[
                              _ReportMetric(
                                'Available money',
                                summary.availableMoneyMinor,
                                Icons.account_balance_wallet_outlined,
                                context.palette.greenDark,
                              ),
                              _ReportMetric(
                                'Savings set aside',
                                summary.savingsBalanceMinor,
                                Icons.savings_rounded,
                                context.palette.greenDark,
                              ),
                            ],
                            if (showCreditCards &&
                                summary.accounts.any(
                                  (account) => account.isCreditCard,
                                )) ...[
                              _ReportMetric(
                                'Credit card utang',
                                summary.creditCardDebtMinor,
                                Icons.credit_card_rounded,
                                context.palette.red,
                              ),
                              _ReportMetric(
                                'Net cash position',
                                summary.netPositionMinor,
                                Icons.account_balance_wallet_outlined,
                                summary.netPositionMinor >= 0
                                    ? context.palette.greenDark
                                    : context.palette.red,
                              ),
                            ],
                          ]
                          .map(
                            (metric) => SizedBox(
                              width: width,
                              child: metric.buildWith(
                                context,
                                widget.controller.currencyCode,
                                widget.controller.locale,
                              ),
                            ),
                          )
                          .toList(),
                );
              },
            ),
            if (isJoint &&
                summary.hasJointObligations &&
                _hasDirectPenaltyCashEvents(summary.jointObligations)) ...[
              const SizedBox(height: 18),
              _DirectPenaltyDepositReport(
                obligations: summary.jointObligations,
                periodLabel: summary.label,
                currencyCode: widget.controller.currencyCode,
                locale: widget.controller.locale,
              ),
            ],
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 920;
                final trend = _TrendReport(
                  summary: summary,
                  currencyCode: widget.controller.currencyCode,
                  locale: widget.controller.locale,
                );
                final ratios = _RatiosPanel(summary: summary);
                if (stacked) {
                  return Column(
                    children: [trend, const SizedBox(height: 18), ratios],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: trend),
                    const SizedBox(width: 18),
                    Expanded(flex: 3, child: ratios),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            _CategoryReport(
              items: summary.categories,
              total: summary.expenseMinor,
              currencyCode: widget.controller.currencyCode,
              locale: widget.controller.locale,
            ),
          ],
        ],
      ),
    );
  }

  bool _hasDirectPenaltyCashEvents(JointObligationsSummary obligations) =>
      obligations.externalDepositsInPeriodMinor != 0 ||
      obligations.externalDepositReversalsInPeriodMinor != 0 ||
      obligations.netExternalDepositAdjustmentInPeriodMinor != 0;

  Future<void> _selectPeriod(String value) async {
    setState(() => period = value);
    final dashboardLoad = widget.controller.setPeriod(value);
    final reportLoad = widget.controller.loadReport(value);
    await Future.wait([dashboardLoad.catchError((_) {}), reportLoad]);
  }

  Future<void> _selectScope(FinanceScope value) async {
    await widget.controller.setFinanceScope(value);
    if (mounted) await widget.controller.loadReport(period);
  }

  Future<void> _move(int direction) async {
    if (widget.controller.selectedPeriod != period) {
      await widget.controller.setPeriod(period).catchError((_) {});
    }
    final dashboardAndCutoffs = widget.controller.moveAnchor(direction);
    final reportLoad = widget.controller.loadReport(period);
    await Future.wait([dashboardAndCutoffs.catchError((_) {}), reportLoad]);
  }
}

class _PersonalReportsDashboard extends StatelessWidget {
  const _PersonalReportsDashboard({
    required this.summary,
    required this.showCreditCards,
    required this.currencyCode,
    required this.locale,
  });

  final ReportSummary summary;
  final bool showCreditCards;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasCreditCards =
        showCreditCards &&
        summary.accounts.any((account) => account.isCreditCard);
    final hasSavings = summary.accounts.any(
      (account) => account.isSavingsAccount,
    );
    final metrics = <_PersonalReportKpiData>[
      _PersonalReportKpiData(
        keyName: 'income',
        label: 'Income',
        value: summary.incomeMinor,
        icon: Icons.south_west_rounded,
        color: palette.green,
        caption: 'Money received this period',
      ),
      _PersonalReportKpiData(
        keyName: 'expenses',
        label: 'Expenses',
        value: summary.expenseMinor,
        icon: Icons.north_east_rounded,
        color: palette.orange,
        caption: 'Money spent this period',
      ),
      _PersonalReportKpiData(
        keyName: 'net',
        label: 'Net cashflow',
        value: summary.netMinor,
        icon: Icons.stacked_line_chart_rounded,
        color: summary.netMinor >= 0 ? palette.greenDark : palette.red,
        caption: 'Income minus expenses',
      ),
      _PersonalReportKpiData(
        keyName: 'budget',
        label: 'Budget remaining',
        value: summary.hasBudget ? summary.remainingBudgetMinor : null,
        icon: Icons.savings_outlined,
        color: !summary.hasBudget
            ? palette.muted
            : summary.remainingBudgetMinor >= 0
            ? palette.greenDark
            : palette.red,
        caption: summary.hasBudget
            ? 'Available from this period budget'
            : 'No budget set for this period',
      ),
      if (hasSavings) ...[
        _PersonalReportKpiData(
          keyName: 'available-money',
          label: 'Available money',
          value: summary.availableMoneyMinor,
          icon: Icons.account_balance_wallet_outlined,
          color: palette.greenDark,
          caption: 'Everyday money, excluding savings',
        ),
        _PersonalReportKpiData(
          keyName: 'savings',
          label: 'Savings set aside',
          value: summary.savingsBalanceMinor,
          icon: Icons.savings_rounded,
          color: palette.greenDark,
          caption: 'Included in assets, not available money',
        ),
      ],
      if (hasCreditCards) ...[
        _PersonalReportKpiData(
          keyName: 'credit-debt',
          label: 'Credit card utang',
          value: summary.creditCardDebtMinor,
          icon: Icons.credit_card_rounded,
          color: palette.red,
          caption: 'Outstanding card balance',
        ),
        _PersonalReportKpiData(
          keyName: 'net-position',
          label: 'Net cash position',
          value: summary.netPositionMinor,
          icon: Icons.account_balance_wallet_outlined,
          color: summary.netPositionMinor >= 0
              ? palette.greenDark
              : palette.red,
          caption: 'Cash balance after card debt',
        ),
      ],
    ];

    return Column(
      key: const Key('reports-personal-dashboard'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PersonalReportHero(
          summary: summary,
          currencyCode: currencyCode,
          locale: locale,
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          key: const Key('reports-personal-kpi-grid'),
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final columns = textScale > 1.35
                ? constraints.maxWidth >= 900
                      ? 2
                      : 1
                : constraints.maxWidth >= 1100
                ? 4
                : constraints.maxWidth >= 650
                ? 2
                : 1;
            final cardWidth =
                (constraints.maxWidth - (columns - 1) * 14) / columns;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final metric in metrics)
                  SizedBox(
                    width: cardWidth,
                    child: _PersonalReportKpiCard(
                      data: metric,
                      currencyCode: currencyCode,
                      locale: locale,
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        _PersonalTrendPanel(
          summary: summary,
          currencyCode: currencyCode,
          locale: locale,
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          key: const Key('reports-personal-insights-grid'),
          builder: (context, constraints) {
            final stacked =
                constraints.maxWidth < 960 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.35;
            final categories = _PersonalCategoryInsights(
              items: summary.categories,
              total: summary.expenseMinor,
              currencyCode: currencyCode,
              locale: locale,
            );
            final ratios = _PersonalRatiosPanel(summary: summary);
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [categories, const SizedBox(height: 18), ratios],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: categories),
                const SizedBox(width: 18),
                Expanded(flex: 4, child: ratios),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PersonalReportHero extends StatelessWidget {
  const _PersonalReportHero({
    required this.summary,
    required this.currencyCode,
    required this.locale,
  });

  final ReportSummary summary;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final positive = summary.netMinor >= 0;
    final range =
        '${DateFormat('MMM d').format(summary.startsOn)} – '
        '${DateFormat('MMM d, y').format(summary.endsOn)}';
    final heroEnd = Color.lerp(
      palette.heroEnd,
      positive ? palette.green : palette.red,
      0.13,
    )!;
    return Semantics(
      key: const Key('reports-personal-hero'),
      container: true,
      label: 'Personal report for ${summary.label}, $range',
      value:
          'Net cashflow ${Money.format(summary.netMinor, currencyCode: currencyCode, locale: locale)}',
      child: ExcludeSemantics(
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [palette.heroStart, heroEnd],
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: palette.onHero.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(
                color: palette.heroEnd.withValues(alpha: 0.2),
                blurRadius: 30,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -80,
                top: -120,
                child: Container(
                  width: 290,
                  height: 290,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: palette.onHero.withValues(alpha: 0.08),
                      width: 34,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: -70,
                bottom: -120,
                child: Container(
                  width: 230,
                  height: 230,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.onHero.withValues(alpha: 0.035),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(26),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked =
                        constraints.maxWidth < 760 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.35;
                    final primary = _PersonalHeroPrimary(
                      summary: summary,
                      range: range,
                      positive: positive,
                      currencyCode: currencyCode,
                      locale: locale,
                    );
                    final flow = _PersonalHeroFlowSummary(
                      summary: summary,
                      currencyCode: currencyCode,
                      locale: locale,
                    );
                    if (stacked) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [primary, const SizedBox(height: 22), flow],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(flex: 6, child: primary),
                        const SizedBox(width: 26),
                        Expanded(flex: 4, child: flow),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonalHeroPrimary extends StatelessWidget {
  const _PersonalHeroPrimary({
    required this.summary,
    required this.range,
    required this.positive,
    required this.currencyCode,
    required this.locale,
  });

  final ReportSummary summary;
  final String range;
  final bool positive;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final status = summary.netMinor == 0
        ? 'Balanced cashflow'
        : positive
        ? 'Positive cashflow'
        : 'Negative cashflow';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PERSONAL PERFORMANCE',
          style: TextStyle(
            color: palette.onHeroMuted,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          summary.label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.onHero,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(range, style: TextStyle(color: palette.onHeroMuted, fontSize: 12)),
        const SizedBox(height: 24),
        Text(
          'Net cashflow',
          style: TextStyle(
            color: palette.onHeroMuted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Container(
          key: const Key('reports-personal-hero-net'),
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyLabel(
              minorUnits: summary.netMinor,
              currencyCode: currencyCode,
              locale: locale,
              compact: true,
              style: TextStyle(
                color: palette.onHero,
                fontSize: 42,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.4,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: palette.onHero.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: palette.onHero.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                summary.netMinor == 0
                    ? Icons.horizontal_rule_rounded
                    : positive
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
                size: 16,
                color: palette.onHero,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  status,
                  style: TextStyle(
                    color: palette.onHero,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PersonalHeroFlowSummary extends StatelessWidget {
  const _PersonalHeroFlowSummary({
    required this.summary,
    required this.currencyCode,
    required this.locale,
  });

  final ReportSummary summary;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.onHero.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: palette.onHero.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Period movement',
            style: TextStyle(
              color: palette.onHero,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 15),
          _PersonalHeroFlowRow(
            label: 'Income',
            value: summary.incomeMinor,
            icon: Icons.arrow_downward_rounded,
            currencyCode: currencyCode,
            locale: locale,
          ),
          const SizedBox(height: 13),
          Divider(color: palette.onHero.withValues(alpha: 0.12), height: 1),
          const SizedBox(height: 13),
          _PersonalHeroFlowRow(
            label: 'Expenses',
            value: summary.expenseMinor,
            icon: Icons.arrow_upward_rounded,
            currencyCode: currencyCode,
            locale: locale,
          ),
        ],
      ),
    );
  }
}

class _PersonalHeroFlowRow extends StatelessWidget {
  const _PersonalHeroFlowRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.currencyCode,
    required this.locale,
  });

  final String label;
  final int value;
  final IconData icon;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: context.palette.onHero.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 17, color: context.palette.onHero),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: context.palette.onHeroMuted,
                fontSize: 10.5,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: MoneyLabel(
                minorUnits: value,
                currencyCode: currencyCode,
                locale: locale,
                compact: true,
                style: TextStyle(
                  color: context.palette.onHero,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _PersonalReportKpiData {
  const _PersonalReportKpiData({
    required this.keyName,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.caption,
  });

  final String keyName;
  final String label;
  final int? value;
  final IconData icon;
  final Color color;
  final String caption;
}

class _PersonalReportKpiCard extends StatelessWidget {
  const _PersonalReportKpiCard({
    required this.data,
    required this.currencyCode,
    required this.locale,
  });

  final _PersonalReportKpiData data;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final semanticValue = data.value == null
        ? 'Not applicable'
        : Money.format(data.value!, currencyCode: currencyCode, locale: locale);
    return Semantics(
      key: ValueKey('reports-personal-kpi-${data.keyName}'),
      container: true,
      label: data.label,
      value: semanticValue,
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 148),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(palette.surfaceRaised, data.color, 0.055)!,
                palette.surface,
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Color.lerp(palette.border, data.color, 0.28)!,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 39,
                    height: 39,
                    decoration: BoxDecoration(
                      color: data.color.withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(data.icon, color: data.color, size: 19),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      data.label.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.65,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (data.value == null)
                Text(
                  'Not applicable',
                  style: TextStyle(
                    color: palette.inkSoft,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                )
              else
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: MoneyLabel(
                    minorUnits: data.value!,
                    currencyCode: currencyCode,
                    locale: locale,
                    compact: true,
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
              const SizedBox(height: 7),
              Text(
                data.caption,
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 10.5,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonalTrendPanel extends StatelessWidget {
  const _PersonalTrendPanel({
    required this.summary,
    required this.currencyCode,
    required this.locale,
  });

  final ReportSummary summary;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final maxValue = summary.buckets
        .map((bucket) => math.max(bucket.incomeMinor, bucket.expenseMinor))
        .fold<int>(1, math.max);
    return SectionCard(
      key: const Key('reports-personal-trend'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  constraints.maxWidth < 700 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.35;
              final title = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: palette.infoSoft,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      Icons.auto_graph_rounded,
                      color: palette.greenDark,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cashflow by period',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Side-by-side income and expenses',
                          style: TextStyle(color: palette.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final legend = Wrap(
                spacing: 14,
                runSpacing: 7,
                children: [
                  _PersonalLegendItem(label: 'Income', color: palette.green),
                  _PersonalLegendItem(label: 'Expenses', color: palette.orange),
                ],
              );
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, const SizedBox(height: 13), legend],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 18),
                  legend,
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _PersonalTrendTotal(
                label: 'Total income',
                value: summary.incomeMinor,
                color: palette.green,
                currencyCode: currencyCode,
                locale: locale,
              ),
              _PersonalTrendTotal(
                label: 'Total expenses',
                value: summary.expenseMinor,
                color: palette.orange,
                currencyCode: currencyCode,
                locale: locale,
              ),
              _PersonalTrendTotal(
                label: 'Net cashflow',
                value: summary.netMinor,
                color: summary.netMinor >= 0 ? palette.greenDark : palette.red,
                currencyCode: currencyCode,
                locale: locale,
              ),
            ],
          ),
          const SizedBox(height: 22),
          if (summary.buckets.isEmpty)
            const EmptyState(
              icon: Icons.bar_chart_rounded,
              title: 'No report data',
              message: 'Transactions in this period will appear here.',
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final minChartWidth = math.max(
                  constraints.maxWidth,
                  summary.buckets.length * 54.0,
                );
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: minChartWidth,
                    height: 245,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          bottom: 28,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              for (var index = 0; index < 4; index++)
                                Divider(
                                  height: 1,
                                  color: palette.border.withValues(alpha: 0.7),
                                ),
                            ],
                          ),
                        ),
                        Positioned.fill(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (final bucket in summary.buckets)
                                Expanded(
                                  child: _PersonalTrendBucket(
                                    bucket: bucket,
                                    maxValue: maxValue,
                                    currencyCode: currencyCode,
                                    locale: locale,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _PersonalLegendItem extends StatelessWidget {
  const _PersonalLegendItem({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: TextStyle(
          color: context.palette.inkSoft,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _PersonalTrendTotal extends StatelessWidget {
  const _PersonalTrendTotal({
    required this.label,
    required this.value,
    required this.color,
    required this.currencyCode,
    required this.locale,
  });

  final String label;
  final int value;
  final Color color;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 150),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.075),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.17)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: context.palette.muted, fontSize: 10),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: MoneyLabel(
            minorUnits: value,
            currencyCode: currencyCode,
            locale: locale,
            compact: true,
            style: TextStyle(
              color: context.palette.ink,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

class _PersonalTrendBucket extends StatelessWidget {
  const _PersonalTrendBucket({
    required this.bucket,
    required this.maxValue,
    required this.currencyCode,
    required this.locale,
  });

  final CashflowBucket bucket;
  final int maxValue;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final incomeRatio = bucket.incomeMinor / maxValue;
    final expenseRatio = bucket.expenseMinor / maxValue;
    final label = bucket.label.length > 7
        ? bucket.label.substring(0, 7)
        : bucket.label;
    return Semantics(
      label:
          '${bucket.label}. Income ${Money.format(bucket.incomeMinor, currencyCode: currencyCode, locale: locale)}. '
          'Expenses ${Money.format(bucket.expenseMinor, currencyCode: currencyCode, locale: locale)}.',
      child: ExcludeSemantics(
        child: Tooltip(
          message:
              '${bucket.label}\nIncome: ${Money.format(bucket.incomeMinor, currencyCode: currencyCode, locale: locale)}\n'
              'Expenses: ${Money.format(bucket.expenseMinor, currencyCode: currencyCode, locale: locale)}',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: FractionallySizedBox(
                          heightFactor: incomeRatio.clamp(0.0, 1.0),
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 16),
                            decoration: BoxDecoration(
                              color: context.palette.green,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(5),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: FractionallySizedBox(
                          heightFactor: expenseRatio.clamp(0.0, 1.0),
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 16),
                            decoration: BoxDecoration(
                              color: context.palette.orange,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.palette.muted, fontSize: 9.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonalRatiosPanel extends StatelessWidget {
  const _PersonalRatiosPanel({required this.summary});

  final ReportSummary summary;

  @override
  Widget build(BuildContext context) => SectionCard(
    key: const Key('reports-personal-ratios'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.palette.violetSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.speed_rounded,
                color: context.palette.violet,
                size: 20,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Key ratios',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Efficiency at a glance',
                    style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _PersonalRatioTile(
          label: 'Savings rate',
          value: summary.savingsRatePercent,
          caption: 'Share of income kept',
          color: context.palette.green,
          icon: Icons.savings_outlined,
        ),
        const SizedBox(height: 14),
        _PersonalRatioTile(
          label: 'Budget used',
          value: summary.utilizationPercent,
          caption: 'Share of budget spent',
          color: context.palette.orange,
          icon: Icons.donut_large_rounded,
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: context.palette.surfaceMuted,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: context.palette.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 17,
                color: context.palette.muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Weekly reports show actual cashflow without inventing a prorated cutoff budget.',
                  style: TextStyle(
                    color: context.palette.muted,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PersonalRatioTile extends StatelessWidget {
  const _PersonalRatioTile({
    required this.label,
    required this.value,
    required this.caption,
    required this.color,
    required this.icon,
  });

  final String label;
  final double? value;
  final String caption;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final normalized = value == null ? 0.0 : value! / 100;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.lerp(context.palette.surface, color, 0.045),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Color.lerp(context.palette.border, color, 0.22)!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: context.palette.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                value == null ? '—' : '${value!.round()}%',
                style: TextStyle(
                  color: color,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: normalized.clamp(0.0, 1.0),
              minHeight: 7,
              color: color,
              backgroundColor: context.palette.border,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            caption,
            style: TextStyle(color: context.palette.muted, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

class _PersonalCategoryInsights extends StatelessWidget {
  const _PersonalCategoryInsights({
    required this.items,
    required this.total,
    required this.currencyCode,
    required this.locale,
  });

  final List<CategorySpend> items;
  final int total;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) => SectionCard(
    key: const Key('reports-personal-category-insights'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.palette.orangeSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.pie_chart_outline_rounded,
                color: context.palette.orange,
                size: 20,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Expense breakdown',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Category share and budget status',
                    style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (items.isEmpty)
          const EmptyState(
            icon: Icons.pie_chart_outline_rounded,
            title: 'Nothing to break down',
            message: 'No expenses were recorded in this period.',
          )
        else
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) const Divider(height: 26),
            _PersonalCategoryInsightRow(
              item: items[index],
              share: total == 0 ? 0 : items[index].amountMinor / total,
              currencyCode: currencyCode,
              locale: locale,
            ),
          ],
      ],
    ),
  );
}

class _PersonalCategoryInsightRow extends StatelessWidget {
  const _PersonalCategoryInsightRow({
    required this.item,
    required this.share,
    required this.currencyCode,
    required this.locale,
  });

  final CategorySpend item;
  final double share;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = colorFromHex(
      item.color,
      fallback: palette.green,
      legacyReplacement: palette.greenDark,
    );
    final over = item.budgetMinor > 0 && item.amountMinor > item.budgetMinor;
    return Semantics(
      container: true,
      label:
          '${item.name}, ${(share * 100).round()} percent of expenses. '
          'Spent ${Money.format(item.amountMinor, currencyCode: currencyCode, locale: locale)}.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  flex: 2,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: MoneyLabel(
                      minorUnits: item.amountMinor,
                      currencyCode: currencyCode,
                      locale: locale,
                      compact: true,
                      style: TextStyle(
                        color: palette.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: share.clamp(0.0, 1.0),
                      minHeight: 7,
                      color: color,
                      backgroundColor: palette.border,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${(share * 100).round()}%',
                  style: TextStyle(
                    color: palette.inkSoft,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  item.budgetMinor == 0
                      ? 'Budget —'
                      : 'Budget ${Money.format(item.budgetMinor, currencyCode: currencyCode, locale: locale)}',
                  style: TextStyle(color: palette.muted, fontSize: 10.5),
                ),
                StatusPill(
                  label: item.budgetMinor == 0
                      ? 'No budget'
                      : over
                      ? 'Over'
                      : 'On track',
                  positive: !over,
                  neutral: item.budgetMinor == 0,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectPenaltyDepositReport extends StatelessWidget {
  const _DirectPenaltyDepositReport({
    required this.obligations,
    required this.periodLabel,
    required this.currencyCode,
    required this.locale,
  });

  final JointObligationsSummary obligations;
  final String periodLabel;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Semantics(
      container: true,
      label: 'Direct penalty deposit cash reconciliation. This is separate from income, expenses, net cashflow, and budget.',
      child: Column(
        key: const Key('reports-direct-penalty-cash-adjustment'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                color: context.palette.greenDark,
                size: 21,
              ),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'DIRECT PENALTY DEPOSIT RECONCILIATION',
                  style: TextStyle(
                    color: context.palette.greenDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$periodLabel · cash adjustment only. Already reflected in Joint account balances; not income, expenses, net cashflow, or budget.',
            style: TextStyle(
              color: context.palette.inkSoft,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 680 ? 3 : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 10) / columns;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _PenaltyReconciliationAmount(
                    label: 'Deposited directly',
                    amountMinor: obligations.externalDepositsInPeriodMinor,
                    currencyCode: currencyCode,
                    locale: locale,
                  ),
                  _PenaltyReconciliationAmount(
                    label: 'Direct deposits reversed',
                    amountMinor:
                        -obligations.externalDepositReversalsInPeriodMinor,
                    currencyCode: currencyCode,
                    locale: locale,
                  ),
                  _PenaltyReconciliationAmount(
                    label: 'Net cash adjustment',
                    amountMinor:
                        obligations.netExternalDepositAdjustmentInPeriodMinor,
                    currencyCode: currencyCode,
                    locale: locale,
                    emphasized: true,
                  ),
                ].map((item) => SizedBox(width: width, child: item)).toList(),
              );
            },
          ),
        ],
      ),
    ),
  );
}

class _PenaltyReconciliationAmount extends StatelessWidget {
  const _PenaltyReconciliationAmount({
    required this.label,
    required this.amountMinor,
    required this.currencyCode,
    required this.locale,
    this.emphasized = false,
  });

  final String label;
  final int amountMinor;
  final String currencyCode;
  final String locale;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: emphasized
          ? context.palette.successSoft
          : context.palette.surfaceMuted,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: context.palette.muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: MoneyLabel(
            minorUnits: amountMinor,
            currencyCode: currencyCode,
            locale: locale,
            style: TextStyle(
              color: context.palette.ink,
              fontSize: emphasized ? 19 : 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ReportToolbar extends StatelessWidget {
  const _ReportToolbar({
    required this.period,
    required this.summary,
    required this.onPeriodSelected,
    required this.onPrevious,
    required this.onNext,
  });

  final String period;
  final ReportSummary summary;
  final ValueChanged<String> onPeriodSelected;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final picker = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'week', label: Text('Weekly')),
          ButtonSegment(value: 'month', label: Text('Monthly')),
          ButtonSegment(value: 'year', label: Text('Yearly')),
          ButtonSegment(value: 'cutoff', label: Text('Per cutoff')),
        ],
        selected: {period},
        onSelectionChanged: (value) => onPeriodSelected(value.first),
        showSelectedIcon: false,
      ),
    );
    final navigator = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onPrevious,
          tooltip: 'Previous period',
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 210),
            child: Column(
              children: [
                Text(
                  summary.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.palette.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${DateFormat('MMM d').format(summary.startsOn)} – ${DateFormat('MMM d, y').format(summary.endsOn)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.palette.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          onPressed: onNext,
          tooltip: 'Next period',
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 820) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              picker,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: navigator),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: picker),
            const SizedBox(width: 16),
            navigator,
          ],
        );
      },
    );
  }
}

class _ReportMetric {
  const _ReportMetric(this.label, this.value, this.icon, this.color);
  final String label;
  final int? value;
  final IconData icon;
  final Color color;

  Widget buildWith(BuildContext context, String currencyCode, String locale) =>
      SectionCard(
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (value == null)
                    Text(
                      'Not applicable',
                      style: TextStyle(
                        color: context.palette.muted,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else
                    MoneyLabel(
                      minorUnits: value!,
                      currencyCode: currencyCode,
                      locale: locale,
                      compact: true,
                      style: TextStyle(
                        color: context.palette.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _TrendReport extends StatelessWidget {
  const _TrendReport({
    required this.summary,
    required this.currencyCode,
    required this.locale,
  });
  final ReportSummary summary;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final maxValue = summary.buckets
        .map((bucket) => math.max(bucket.incomeMinor, bucket.expenseMinor))
        .fold<int>(1, math.max);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cashflow by period',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Side-by-side income and expenses',
            style: TextStyle(color: context.palette.muted, fontSize: 12),
          ),
          const SizedBox(height: 22),
          if (summary.buckets.isEmpty)
            const EmptyState(
              icon: Icons.bar_chart_rounded,
              title: 'No report data',
              message: 'Transactions in this period will appear here.',
            )
          else
            SizedBox(
              height: 245,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: summary.buckets.map((bucket) {
                  final incomeRatio = bucket.incomeMinor / maxValue;
                  final expenseRatio = bucket.expenseMinor / maxValue;
                  return Expanded(
                    child: Tooltip(
                      message:
                          '${bucket.label}\nIncome: ${bucket.incomeMinor}\nExpenses: ${bucket.expenseMinor}',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Container(
                                      height: 205 * incomeRatio,
                                      decoration: BoxDecoration(
                                        color: context.palette.green,
                                        borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(4),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Flexible(
                                    child: Container(
                                      height: 205 * expenseRatio,
                                      decoration: BoxDecoration(
                                        color: context.palette.orange,
                                        borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(4),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              bucket.label.length > 5
                                  ? bucket.label.substring(0, 5)
                                  : bucket.label,
                              style: TextStyle(
                                color: context.palette.muted,
                                fontSize: 9.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _RatiosPanel extends StatelessWidget {
  const _RatiosPanel({required this.summary});
  final ReportSummary summary;

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Key ratios', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 20),
        _ratio(
          context,
          'Savings rate',
          summary.savingsRatePercent,
          'Share of income kept',
          context.palette.green,
        ),
        const SizedBox(height: 22),
        _ratio(
          context,
          'Budget used',
          summary.utilizationPercent,
          'Share of budget spent',
          context.palette.orange,
        ),
        const Divider(height: 32),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 17,
              color: context.palette.muted,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Weekly reports show actual cashflow without inventing a prorated cutoff budget.',
                style: TextStyle(color: context.palette.muted, fontSize: 11.5),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _ratio(
    BuildContext context,
    String label,
    double? value,
    String caption,
    Color color,
  ) {
    final normalized = value == null ? 0.0 : value / 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: context.palette.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              value == null ? '—' : '${(normalized * 100).round()}%',
              style: TextStyle(
                color: color,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: normalized.clamp(0.0, 1.0),
            minHeight: 7,
            color: color,
            backgroundColor: context.palette.border,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          caption,
          style: TextStyle(color: context.palette.muted, fontSize: 10.5),
        ),
      ],
    );
  }
}

class _CategoryReport extends StatelessWidget {
  const _CategoryReport({
    required this.items,
    required this.total,
    required this.currencyCode,
    required this.locale,
  });
  final List<CategorySpend> items;
  final int total;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Expense breakdown',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Category share and budget status',
          style: TextStyle(color: context.palette.muted, fontSize: 12),
        ),
        const SizedBox(height: 16),
        if (items.isEmpty)
          const EmptyState(
            icon: Icons.pie_chart_outline_rounded,
            title: 'Nothing to break down',
            message: 'No expenses were recorded in this period.',
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 850),
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  context.palette.surfaceMuted,
                ),
                columns: const [
                  DataColumn(label: Text('CATEGORY')),
                  DataColumn(label: Text('SHARE')),
                  DataColumn(label: Text('SPENT'), numeric: true),
                  DataColumn(label: Text('BUDGET'), numeric: true),
                  DataColumn(label: Text('STATUS')),
                ],
                rows: items.map((item) {
                  final share = total == 0 ? 0.0 : item.amountMinor / total;
                  final over =
                      item.budgetMinor > 0 &&
                      item.amountMinor > item.budgetMinor;
                  return DataRow(
                    cells: [
                      DataCell(
                        Row(
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: colorFromHex(
                                  item.color,
                                  fallback: context.palette.green,
                                  legacyReplacement: context.palette.greenDark,
                                ),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 9),
                            Text(
                              item.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 150,
                          child: Row(
                            children: [
                              Expanded(
                                child: LinearProgressIndicator(
                                  value: share,
                                  minHeight: 5,
                                  color: colorFromHex(
                                    item.color,
                                    fallback: context.palette.green,
                                    legacyReplacement:
                                        context.palette.greenDark,
                                  ),
                                  backgroundColor: context.palette.border,
                                ),
                              ),
                              const SizedBox(width: 9),
                              Text('${(share * 100).round()}%'),
                            ],
                          ),
                        ),
                      ),
                      DataCell(
                        MoneyLabel(
                          minorUnits: item.amountMinor,
                          currencyCode: currencyCode,
                          locale: locale,
                        ),
                      ),
                      DataCell(
                        item.budgetMinor == 0
                            ? const Text('—')
                            : MoneyLabel(
                                minorUnits: item.budgetMinor,
                                currencyCode: currencyCode,
                                locale: locale,
                              ),
                      ),
                      DataCell(
                        StatusPill(
                          label: item.budgetMinor == 0
                              ? 'No budget'
                              : over
                              ? 'Over'
                              : 'On track',
                          positive: !over,
                          neutral: item.budgetMinor == 0,
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
      ],
    ),
  );
}
