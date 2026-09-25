import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../core/money.dart';
import '../../models/domain_models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../account_designs.dart';
import '../widgets/common.dart';
import 'transactions_page.dart';

void _handleDashboardTransition(Future<void> transition) {
  unawaited(transition.catchError((Object _) {}));
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.controller,
    required this.onOpenTransactions,
  });

  final AppController controller;
  final VoidCallback onOpenTransactions;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isJoint = controller.isJointScope;
    final loadedSummary = controller.dashboard;
    final canAddTransaction =
        !controller.offlineTransactionsEnabled ||
        controller.canSaveOfflineTransactions;
    const disabledAddReason =
        'Reconnect and load saved settings, accounts, categories, complete transaction history, dashboard, and cutoff budgets before adding a transaction.';
    if (!controller.hasSavedSettings || loadedSummary == null) {
      final isLoadingDashboard =
          controller.hasSavedSettings &&
          loadedSummary == null &&
          controller.isDashboardRefreshing;
      return SingleChildScrollView(
        padding: responsivePagePadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DashboardHeader(
              title: isJoint ? 'Joint overview' : 'Good ${_dayPart()}',
              subtitle: isJoint
                  ? 'Track the money, expenses, and budget you share together.'
                  : 'A clear view of your money, saved on your phone.',
              scope: controller.selectedFinanceScope,
              onScopeSelected: controller.setFinanceScope,
              onRefresh: controller.refreshAll,
              onAddTransaction: canAddTransaction
                  ? () => showTransactionEditor(context, controller)
                  : null,
              addTransactionDisabledReason: canAddTransaction
                  ? null
                  : disabledAddReason,
            ),
            const SizedBox(height: 18),
            if (isLoadingDashboard) ...[
              FinanceScopeNotice(scope: controller.selectedFinanceScope),
              const SizedBox(height: 24),
              const _DashboardInitialRefreshSkeleton(),
            ] else
              SectionCard(
                child: EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: !controller.hasSavedSettings
                      ? 'Money formatting is not saved on this device'
                      : 'This overview is not saved for the selected period',
                  message: !controller.hasSavedSettings
                      ? 'Your display preferences could not be read. Try refreshing saved data.'
                      : 'Your totals could not be calculated. Try refreshing this period.',
                ),
              ),
          ],
        ),
      );
    }
    final summary = loadedSummary;
    final isDashboardRefreshing = controller.isDashboardRefreshing;
    Widget refreshablePanel({
      required String id,
      required String label,
      required Widget child,
    }) => _DashboardRefreshOverlay(
      id: id,
      label: label,
      refreshing: isDashboardRefreshing,
      child: child,
    );
    final jewelryPortfolio = summary.jewelryPortfolio;
    final hasGoldCostBasis = jewelryPortfolio.costKnownCount > 0;
    final goldGainLoss = jewelryPortfolio.unrealizedGainLossMinor;
    final goldGainLossColor = !hasGoldCostBasis || goldGainLoss == 0
        ? palette.muted
        : goldGainLoss > 0
        ? palette.greenDark
        : palette.red;
    final balanceAccounts = summary.accounts
        .where(
          (account) =>
              account.scope == controller.selectedFinanceScope &&
              !account.isLiability,
        )
        .toList(growable: false);
    final installmentSummary = _InstallmentMonthSummary.fromSources(
      transactions: controller.transactions,
      installmentPlans: controller.installmentPlans,
      accounts: controller.accounts,
      categories: controller.categories,
      historyAvailable: controller.hasSavedTransactions,
      plansAvailable: controller.hasSavedInstallmentPlans,
      scope: controller.selectedFinanceScope,
      anchor: controller.anchor,
      palette: palette,
    );
    final upcomingCardBilling = _NextMonthCreditCardBillingSummary.fromSources(
      transactions: controller.transactions,
      accounts: controller.accounts,
      historyAvailable: controller.hasSavedTransactions,
      accountsAvailable: controller.hasSavedAccounts,
      scope: controller.selectedFinanceScope,
      palette: palette,
    );
    final dashboardIntro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DashboardHeader(
          title: isJoint ? 'Joint overview' : 'Good ${_dayPart()}',
          subtitle: isJoint
              ? 'Track the money, expenses, and budget you share together.'
              : 'A clear view of your money, saved on your phone.',
          scope: controller.selectedFinanceScope,
          onScopeSelected: controller.setFinanceScope,
          onRefresh: controller.refreshAll,
          onAddTransaction: canAddTransaction
              ? () => showTransactionEditor(context, controller)
              : null,
          addTransactionDisabledReason: canAddTransaction
              ? null
              : disabledAddReason,
        ),
        const SizedBox(height: 16),
        FinanceScopeNotice(scope: controller.selectedFinanceScope),
        if (!isDashboardRefreshing && !controller.hasSavedDashboard) ...[
          const SizedBox(height: 12),
          _DashboardStaleDataNotice(summaryLabel: summary.label),
        ],
        if (controller.pendingProjectionCount > 0) ...[
          const SizedBox(height: 12),
          SectionCard(
            child: Text(
              'Top-line cash, credit-card utang, net position, income, expense, and budget figures include pending transaction adjustments. Charts and category breakdowns remain from the last complete server sync.',
              style: TextStyle(
                color: palette.inkSoft,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ],
    );
    Widget dashboardMain({required bool categoryInRail}) => Column(
      key: const Key('dashboard-main-content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DashboardSectionHeading(
          key: const Key('dashboard-current-position-section'),
          eyebrow: 'CURRENT SNAPSHOT',
          title: isJoint ? 'Shared position' : 'Current position',
          subtitle: isJoint
              ? 'Cash held across active Joint accounts.'
              : 'Cash you can use and assets you currently hold.',
        ),
        const SizedBox(height: 14),
        refreshablePanel(
          id: 'current-position',
          label: 'current position',
          child: _CurrentPosition(
            availableMoneyMinor: summary.availableMoneyMinor,
            savingsBalanceMinor: summary.savingsBalanceMinor,
            creditCardDebtMinor: summary.creditCardDebtMinor,
            netPositionMinor: summary.netPositionMinor,
            showSavings: summary.accounts.any(
              (account) => account.isSavingsAccount,
            ),
            showCreditCardDebt: summary.accounts.any(
              (account) => account.isCreditCard,
            ),
            portfolio: jewelryPortfolio,
            hasGoldCostBasis: hasGoldCostBasis,
            goldGainLossMinor: goldGainLoss,
            goldGainLossColor: goldGainLossColor,
            currencyCode: controller.currencyCode,
            locale: controller.locale,
            scope: controller.selectedFinanceScope,
          ),
        ),
        const SizedBox(height: 30),
        _DashboardSectionHeading(
          key: const Key('dashboard-this-period-section'),
          eyebrow: 'SELECTED PERIOD',
          title: 'This period',
          subtitle: 'Income, spending, and budget performance over time.',
          trailing: isDashboardRefreshing ? 'Updating…' : summary.label,
        ),
        const SizedBox(height: 14),
        _PeriodToolbar(controller: controller, summary: summary),
        const SizedBox(height: 18),
        refreshablePanel(
          id: 'cashflow',
          label: 'cashflow and period totals',
          child: _CashflowPanel(
            summary: summary,
            currencyCode: controller.currencyCode,
            locale: controller.locale,
          ),
        ),
        const SizedBox(height: 18),
        if (!categoryInRail) ...[
          refreshablePanel(
            id: 'categories-main',
            label: 'spending categories',
            child: _CategoryPanel(
              items: summary.categories,
              total: summary.expenseMinor,
              currencyCode: controller.currencyCode,
              locale: controller.locale,
            ),
          ),
          const SizedBox(height: 18),
          _InstallmentSummaryPanel(
            summary: installmentSummary,
            controller: controller,
            currencyCode: controller.currencyCode,
            locale: controller.locale,
          ),
          const SizedBox(height: 18),
        ],
        LayoutBuilder(
          key: const Key('dashboard-budget-billing-group'),
          builder: (context, constraints) {
            final stacked =
                constraints.maxWidth < 980 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.35;
            final budget = refreshablePanel(
              id: 'budget',
              label: 'budget progress',
              child: _BudgetPanel(
                summary: summary,
                currencyCode: controller.currencyCode,
                locale: controller.locale,
              ),
            );
            final billing = _NextMonthCreditCardBillingPanel(
              summary: upcomingCardBilling,
              currencyCode: controller.currencyCode,
              locale: controller.locale,
            );
            if (stacked) {
              return Column(
                children: [budget, const SizedBox(height: 18), billing],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: budget),
                const SizedBox(width: 18),
                Expanded(flex: 7, child: billing),
              ],
            );
          },
        ),
      ],
    );
    final accountRail = balanceAccounts.isEmpty
        ? null
        : refreshablePanel(
            id: 'accounts',
            label: 'account balances',
            child: _DashboardAccountRail(
              accounts: balanceAccounts,
              asOf: summary.endsOn,
              currencyCode: controller.currencyCode,
              locale: controller.locale,
              scope: controller.selectedFinanceScope,
            ),
          );
    return SingleChildScrollView(
      padding: responsivePagePadding(context),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useSideRail =
                  accountRail != null &&
                  constraints.maxWidth >= 1180 &&
                  MediaQuery.textScalerOf(context).scale(1) <= 1.35;
              if (useSideRail) {
                return Row(
                  key: const Key('dashboard-wide-layout'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          dashboardIntro,
                          const SizedBox(height: 30),
                          dashboardMain(categoryInRail: true),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    SizedBox(
                      width: 356,
                      child: Column(
                        key: const Key('dashboard-side-column'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          accountRail,
                          const SizedBox(height: 18),
                          refreshablePanel(
                            id: 'categories-rail',
                            label: 'spending categories',
                            child: _CategoryPanel(
                              items: summary.categories,
                              total: summary.expenseMinor,
                              currencyCode: controller.currencyCode,
                              locale: controller.locale,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _InstallmentSummaryPanel(
                            summary: installmentSummary,
                            controller: controller,
                            currencyCode: controller.currencyCode,
                            locale: controller.locale,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  dashboardIntro,
                  if (accountRail != null) ...[
                    const SizedBox(height: 24),
                    accountRail,
                  ],
                  const SizedBox(height: 30),
                  dashboardMain(categoryInRail: false),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String _dayPart() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'morning';
    if (hour < 18) return 'afternoon';
    return 'evening';
  }
}

class _DashboardStaleDataNotice extends StatelessWidget {
  const _DashboardStaleDataNotice({required this.summaryLabel});

  final String summaryLabel;

  @override
  Widget build(BuildContext context) {
    final message =
        'Showing the last loaded $summaryLabel overview. The selected period '
        'could not be refreshed, so these values may be out of date.';
    return Semantics(
      key: const Key('dashboard-stale-data-notice'),
      container: true,
      liveRegion: true,
      label: message,
      child: SectionCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.history_toggle_off_rounded,
              size: 20,
              color: context.palette.orange,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: context.palette.inkSoft,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardRefreshOverlay extends StatelessWidget {
  const _DashboardRefreshOverlay({
    required this.id,
    required this.label,
    required this.refreshing,
    required this.child,
  });

  final String id;
  final String label;
  final bool refreshing;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    clipBehavior: Clip.none,
    children: [
      ExcludeSemantics(
        excluding: refreshing,
        child: IgnorePointer(ignoring: refreshing, child: child),
      ),
      if (refreshing)
        Positioned.fill(
          child: Semantics(
            key: ValueKey('dashboard-refresh-skeleton-$id'),
            container: true,
            label: 'Updating $label',
            value: 'Previous values are temporarily hidden while fresh data loads.',
            child: AbsorbPointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: const _DashboardSkeletonSurface(),
              ),
            ),
          ),
        ),
    ],
  );
}

class _DashboardInitialRefreshSkeleton extends StatelessWidget {
  const _DashboardInitialRefreshSkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
    key: const Key('dashboard-initial-refresh-skeleton'),
    container: true,
    liveRegion: true,
    label: 'Loading dashboard data for the selected money scope',
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _DashboardSectionHeading(
            eyebrow: 'CURRENT SNAPSHOT',
            title: 'Current position',
            subtitle: 'Loading saved balances and assets.',
          ),
          const SizedBox(height: 14),
          const _DashboardSkeletonBlock(id: 'current-position', height: 174),
          const SizedBox(height: 30),
          const _DashboardSectionHeading(
            eyebrow: 'SELECTED PERIOD',
            title: 'This period',
            subtitle: 'Loading income, spending, and budget performance.',
            trailing: 'Updating…',
          ),
          const SizedBox(height: 14),
          const _DashboardSkeletonBlock(id: 'period-toolbar', height: 68),
          const SizedBox(height: 18),
          const _DashboardSkeletonBlock(id: 'cashflow', height: 280),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 760;
              const first = _DashboardSkeletonBlock(
                id: 'categories-main',
                height: 220,
              );
              const second = _DashboardSkeletonBlock(id: 'budget', height: 220);
              if (!twoColumns) {
                return const Column(
                  children: [first, SizedBox(height: 18), second],
                );
              }
              return const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: first),
                  SizedBox(width: 18),
                  Expanded(child: second),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}

class _DashboardSkeletonBlock extends StatelessWidget {
  const _DashboardSkeletonBlock({required this.id, required this.height});

  final String id;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: ValueKey('dashboard-refresh-skeleton-$id'),
    height: height,
    child: const ClipRRect(
      borderRadius: BorderRadius.all(Radius.circular(18)),
      child: _DashboardSkeletonSurface(),
    ),
  );
}

class _DashboardSkeletonSurface extends StatefulWidget {
  const _DashboardSkeletonSurface();

  @override
  State<_DashboardSkeletonSurface> createState() =>
      _DashboardSkeletonSurfaceState();
}

class _DashboardSkeletonSurfaceState extends State<_DashboardSkeletonSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1350),
  );
  bool? _reducedMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    if (_reducedMotion == reducedMotion) return;
    _reducedMotion = reducedMotion;
    if (reducedMotion) {
      _animation
        ..stop()
        ..value = 0.5;
    } else {
      _animation.repeat();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final highlight = Color.alphaBlend(
      palette.ink.withValues(alpha: 0.09),
      palette.surfaceMuted,
    );
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => CustomPaint(
        painter: _DashboardSkeletonPainter(
          background: palette.surface,
          base: palette.surfaceMuted,
          highlight: highlight,
          border: palette.border,
          progress: _animation.value,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _DashboardSkeletonPainter extends CustomPainter {
  const _DashboardSkeletonPainter({
    required this.background,
    required this.base,
    required this.highlight,
    required this.border,
    required this.progress,
  });

  final Color background;
  final Color base;
  final Color highlight;
  final Color border;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = background);
    if (size.isEmpty) return;

    final shimmerCenter = -size.width + (size.width * 3 * progress);
    final fill = Paint()
      ..shader =
          LinearGradient(
            colors: [base, highlight, base],
            stops: const [0.24, 0.5, 0.76],
          ).createShader(
            Rect.fromLTWH(
              shimmerCenter - size.width,
              0,
              size.width * 2,
              size.height,
            ),
          );
    final margin = math.min(18.0, size.width * 0.08);
    final contentWidth = math.max(0.0, size.width - (margin * 2));
    final shapes = <Rect>[
      Rect.fromLTWH(margin, margin, contentWidth * 0.34, 12),
      if (size.height >= 58)
        Rect.fromLTWH(margin, margin + 25, contentWidth * 0.72, 9),
      if (size.height >= 94)
        Rect.fromLTWH(margin, margin + 54, contentWidth, 34),
      if (size.height >= 150)
        Rect.fromLTWH(margin, margin + 105, contentWidth * 0.62, 12),
      if (size.height >= 185)
        Rect.fromLTWH(margin, margin + 132, contentWidth * 0.84, 10),
    ];
    for (final shape in shapes) {
      final clipped = shape.intersect(bounds.deflate(margin));
      if (!clipped.isEmpty) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(clipped, const Radius.circular(7)),
          fill,
        );
      }
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds.deflate(0.5), const Radius.circular(18)),
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_DashboardSkeletonPainter oldDelegate) =>
      oldDelegate.background != background ||
      oldDelegate.base != base ||
      oldDelegate.highlight != highlight ||
      oldDelegate.border != border ||
      oldDelegate.progress != progress;
}

class _InstallmentMonthSummary {
  const _InstallmentMonthSummary({
    required this.month,
    required this.plans,
    required this.upcomingPlans,
    required this.overduePlans,
    required this.scheduledCount,
    required this.monthlyTotalMinor,
  });

  factory _InstallmentMonthSummary.fromSources({
    required List<TransactionRecord> transactions,
    required List<InstallmentPlan> installmentPlans,
    required List<Account> accounts,
    required List<Category> categories,
    required bool historyAvailable,
    required bool plansAvailable,
    required FinanceScope scope,
    required DateTime anchor,
    required AppPalette palette,
  }) {
    final month = DateTime(anchor.year, anchor.month);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (!historyAvailable && !plansAvailable) {
      return _InstallmentMonthSummary(
        month: month,
        plans: const [],
        upcomingPlans: const [],
        overduePlans: const [],
        scheduledCount: 0,
        monthlyTotalMinor: null,
      );
    }

    final installmentTransactions =
        (historyAvailable ? transactions : const <TransactionRecord>[])
            .where(
              (transaction) =>
                  transaction.scope == scope &&
                  transaction.kind == 'expense' &&
                  transaction.isInstallment &&
                  transaction.installmentPlanId == null,
            )
            .toList(growable: false);

    Account? resolveLegacyAccount(TransactionRecord transaction) {
      Account? account;
      for (final candidate in accounts) {
        if (candidate.id == transaction.accountId && candidate.scope == scope) {
          account = candidate;
          break;
        }
      }
      final embeddedAccount = transaction.account;
      if (account == null && embeddedAccount?.scope == scope) {
        account = embeddedAccount;
      }
      return account;
    }

    Category? resolveLegacyCategory(TransactionRecord transaction) {
      Category? category = transaction.category;
      if (category == null && transaction.categoryId != null) {
        for (final candidate in categories) {
          if (candidate.id == transaction.categoryId) {
            category = candidate;
            break;
          }
        }
      }
      return category;
    }

    _InstallmentPlanSummary buildLegacySummary(
      TransactionRecord transaction, {
      required int monthIndex,
      String rowRole = 'scheduled',
      bool isUpcoming = false,
    }) {
      final start = transaction.installmentStartOn ?? transaction.occurredOn;
      final account = resolveLegacyAccount(transaction);
      final category = resolveLegacyCategory(transaction);
      final payee = transaction.payee?.trim() ?? '';
      final categoryName = category?.name.trim() ?? '';
      final accountName = account?.displayName.trim() ?? '';
      final name = payee.isNotEmpty
          ? payee
          : categoryName.isNotEmpty
          ? categoryName
          : accountName.isNotEmpty
          ? accountName
          : 'Installment purchase';
      final accountContext = accountName.isEmpty
          ? 'Installment account details unavailable'
          : account!.isCreditCard
          ? '$accountName · Credit card'
          : accountName;
      final design = account == null
          ? genericBankCardDesign
          : bankCardDesignFor(account.cardDesign);
      final visual = account == null
          ? AccountCardVisual.fromDesign(design)
          : AccountCardVisual.forAccount(account, design, palette);
      final shortMark = account == null
          ? 'CARD'
          : design.key == 'other'
          ? accountCardShortMark(account.type)
          : design.shortMark;
      final monthly = transaction.installmentMonthlyMinor;
      return _InstallmentPlanSummary(
        id: transaction.id,
        name: name,
        accountContext: accountContext,
        visual: visual,
        pattern: design.pattern,
        shortMark: shortMark,
        monthlyMinor: monthly != null && monthly > 0 ? monthly : null,
        billingDay: start.day,
        monthNumber: monthIndex + 1,
        totalMonths: transaction.installmentMonths!,
        dueOn: _installmentDateForMonth(start, monthIndex),
        isUpcoming: isUpcoming,
        rowRole: rowRole,
        showActions: false,
      );
    }

    final activeTransactions = installmentTransactions
        .where((transaction) {
          final start =
              transaction.installmentStartOn ?? transaction.occurredOn;
          final monthIndex =
              (month.year - start.year) * 12 + month.month - start.month;
          return monthIndex >= 0 &&
              monthIndex < (transaction.installmentMonths ?? 0);
        })
        .toList(growable: false);
    final legacyPlans = activeTransactions.map((transaction) {
      final start = transaction.installmentStartOn ?? transaction.occurredOn;
      final monthIndex =
          (month.year - start.year) * 12 + month.month - start.month;
      return buildLegacySummary(transaction, monthIndex: monthIndex);
    }).toList();

    final plans = <_InstallmentPlanSummary>[...legacyPlans];
    final upcomingPlans = <_InstallmentPlanSummary>[];
    final overduePlans = <_InstallmentPlanSummary>[];

    // Credit-card installment purchases post their full debt when they are
    // created, but their saved installment metadata still describes the
    // monthly billing schedule. Surface the next on-or-after-today occurrence
    // as a read-only reminder. When the selected month already shows that
    // exact occurrence, THIS MONTH owns the row so it is not duplicated here.
    for (final transaction in installmentTransactions) {
      final account = resolveLegacyAccount(transaction);
      if (account?.isCreditCard != true) continue;
      final start = transaction.installmentStartOn ?? transaction.occurredOn;
      final totalMonths = transaction.installmentMonths ?? 0;
      var nextMonthIndex = math.max(
        0,
        (today.year - start.year) * 12 + today.month - start.month,
      );
      var nextDue = _installmentDateForMonth(start, nextMonthIndex);
      if (nextDue.isBefore(today)) {
        nextMonthIndex += 1;
        nextDue = _installmentDateForMonth(start, nextMonthIndex);
      }
      if (nextMonthIndex >= totalMonths) continue;

      final selectedMonthIndex =
          (month.year - start.year) * 12 + month.month - start.month;
      if (selectedMonthIndex == nextMonthIndex) continue;

      upcomingPlans.add(
        buildLegacySummary(
          transaction,
          monthIndex: nextMonthIndex,
          rowRole: 'credit-card-upcoming',
          isUpcoming: true,
        ),
      );
    }

    var savedScheduledTotalMinor = 0;
    var savedScheduledCount = 0;
    if (plansAvailable) {
      for (final plan in installmentPlans) {
        if (plan.scope != scope || !plan.isActive) continue;
        final nextDue = plan.nextPaymentOn;
        if (nextDue == null) continue;
        final normalizedDue = DateTime(
          nextDue.year,
          nextDue.month,
          nextDue.day,
        );
        final isOverdue = normalizedDue.isBefore(today);

        Account? account;
        for (final candidate in accounts) {
          if (candidate.id == plan.accountId && candidate.scope == scope) {
            account = candidate;
            break;
          }
        }
        final embeddedAccount = plan.account;
        if (account == null && embeddedAccount?.scope == scope) {
          account = embeddedAccount;
        }
        Category? category = plan.category;
        if (category == null) {
          for (final candidate in categories) {
            if (candidate.id == plan.categoryId) {
              category = candidate;
              break;
            }
          }
        }
        final payee = plan.payee?.trim() ?? '';
        final categoryName = category?.name.trim() ?? '';
        final accountName = account?.displayName.trim() ?? '';
        final name = payee.isNotEmpty
            ? payee
            : categoryName.isNotEmpty
            ? categoryName
            : accountName.isNotEmpty
            ? accountName
            : 'Installment plan';
        final accountContext = accountName.isEmpty
            ? 'Installment account details unavailable'
            : accountName;
        final design = account == null
            ? genericBankCardDesign
            : bankCardDesignFor(account.cardDesign);
        final visual = account == null
            ? AccountCardVisual.fromDesign(design)
            : AccountCardVisual.forAccount(account, design, palette);
        final shortMark = account == null
            ? 'CARD'
            : design.key == 'other'
            ? accountCardShortMark(account.type)
            : design.shortMark;
        _InstallmentPlanSummary buildSummary({
          required DateTime dueOn,
          required int installmentNumber,
          required String rowRole,
          bool isUpcoming = false,
          bool isOverdue = false,
          bool showActions = true,
        }) => _InstallmentPlanSummary(
          id: plan.id,
          name: name,
          accountContext: accountContext,
          visual: visual,
          pattern: design.pattern,
          shortMark: shortMark,
          monthlyMinor: plan.installmentMonthlyMinor,
          billingDay: dueOn.day,
          monthNumber: installmentNumber,
          totalMonths: plan.installmentMonths,
          dueOn: dueOn,
          sourcePlan: plan,
          isUpcoming: isUpcoming,
          isOverdue: isOverdue,
          rowRole: rowRole,
          showActions: showActions,
        );

        // The selected month's forecast follows the original contractual
        // schedule. Payments already recorded suppress their corresponding
        // ordinals, while missed installments remain visible in later
        // scheduled months until those ordinals are paid.
        final scheduledMonthIndex =
            (month.year - plan.installmentStartOn.year) * 12 +
            month.month -
            plan.installmentStartOn.month;
        final scheduledInstallmentNumber = scheduledMonthIndex + 1;
        final isScheduledThisMonth =
            scheduledMonthIndex >= 0 &&
            scheduledMonthIndex < plan.installmentMonths &&
            scheduledInstallmentNumber > plan.paidInstallments;
        final nextInstallmentNumber =
            plan.nextInstallmentNumber ?? plan.paidInstallments + 1;
        final scheduledRepresentsNextPayment =
            isScheduledThisMonth &&
            scheduledInstallmentNumber == nextInstallmentNumber &&
            month.year == nextDue.year &&
            month.month == nextDue.month;
        if (isScheduledThisMonth) {
          savedScheduledTotalMinor += plan.installmentMonthlyMinor;
          savedScheduledCount += 1;
          final scheduledDue = _installmentDateForMonth(
            plan.installmentStartOn,
            scheduledMonthIndex,
          );
          // When this exact installment is already overdue, its actionable
          // overdue row below also serves as the selected-month list item.
          if (!(scheduledRepresentsNextPayment && isOverdue)) {
            plans.add(
              buildSummary(
                dueOn: scheduledDue,
                installmentNumber: scheduledInstallmentNumber,
                rowRole: 'scheduled',
                // A separate next-payment row owns the management actions when
                // the selected forecast month is not the canonical next due.
                showActions: scheduledRepresentsNextPayment && !isOverdue,
              ),
            );
          }
        }

        final nextPaymentSummary = buildSummary(
          dueOn: nextDue,
          installmentNumber: nextInstallmentNumber,
          rowRole: isOverdue ? 'overdue' : 'upcoming',
          isUpcoming: normalizedDue.isAfter(today),
          isOverdue: isOverdue,
        );
        if (isOverdue) {
          overduePlans.add(nextPaymentSummary);
        } else if (!scheduledRepresentsNextPayment) {
          upcomingPlans.add(nextPaymentSummary);
        }
      }
    }
    plans.sort((first, second) {
      final byDay = first.billingDay.compareTo(second.billingDay);
      if (byDay != 0) return byDay;
      final byName = first.name.toLowerCase().compareTo(
        second.name.toLowerCase(),
      );
      return byName != 0 ? byName : first.id.compareTo(second.id);
    });
    upcomingPlans.sort((first, second) {
      final byDate = first.dueOn.compareTo(second.dueOn);
      if (byDate != 0) return byDate;
      final byId = first.id.compareTo(second.id);
      if (byId != 0) return byId;
      final byRole = first.rowRole.compareTo(second.rowRole);
      if (byRole != 0) return byRole;
      return first.name.toLowerCase().compareTo(second.name.toLowerCase());
    });
    overduePlans.sort((first, second) {
      final byDate = first.dueOn.compareTo(second.dueOn);
      return byDate != 0 ? byDate : first.id.compareTo(second.id);
    });
    final hasIncompleteAmount = legacyPlans.any(
      (plan) => plan.monthlyMinor == null,
    );
    final legacyMonthlyTotalMinor = legacyPlans.fold<int>(
      0,
      (total, plan) => total + (plan.monthlyMinor ?? 0),
    );
    return _InstallmentMonthSummary(
      month: month,
      plans: List.unmodifiable(plans),
      upcomingPlans: List.unmodifiable(upcomingPlans),
      overduePlans: List.unmodifiable(overduePlans),
      scheduledCount: legacyPlans.length + savedScheduledCount,
      monthlyTotalMinor:
          !historyAvailable || !plansAvailable || hasIncompleteAmount
          ? null
          : legacyMonthlyTotalMinor + savedScheduledTotalMinor,
    );
  }

  final DateTime month;
  final List<_InstallmentPlanSummary> plans;
  final List<_InstallmentPlanSummary> upcomingPlans;
  final List<_InstallmentPlanSummary> overduePlans;
  final int scheduledCount;
  final int? monthlyTotalMinor;

  int get activeCount => scheduledCount;
  bool get isAvailable => monthlyTotalMinor != null;
}

class _NextMonthCreditCardBillingSummary {
  const _NextMonthCreditCardBillingSummary({
    required this.cards,
    required this.totalMinor,
    required this.historyAvailable,
  });

  factory _NextMonthCreditCardBillingSummary.fromSources({
    required List<TransactionRecord> transactions,
    required List<Account> accounts,
    required bool historyAvailable,
    required bool accountsAvailable,
    required FinanceScope scope,
    required AppPalette palette,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (!historyAvailable || !accountsAvailable) {
      return _NextMonthCreditCardBillingSummary(
        cards: const [],
        totalMinor: null,
        historyAvailable: false,
      );
    }

    final groups = <int, _NextMonthCreditCardBillingBuilder>{
      for (final account in accounts)
        if (account.scope == scope &&
            account.isCreditCard &&
            !account.isArchived)
          account.id: _NextMonthCreditCardBillingBuilder(
            account,
            cycle: _CreditCardBillingCycle.forUpcomingStatement(
              account: account,
              today: today,
            ),
          ),
    };

    _NextMonthCreditCardBillingBuilder? resolveBuilder(
      TransactionRecord transaction,
    ) {
      final accountId = transaction.accountId ?? transaction.account?.id;
      return accountId == null ? null : groups[accountId];
    }

    for (final transaction in transactions) {
      if (transaction.scope != scope ||
          transaction.kind != 'expense' ||
          transaction.isManagedTransaction ||
          !transaction.isInstallment ||
          transaction.installmentPlanId != null) {
        continue;
      }
      final builder = resolveBuilder(transaction);
      if (builder == null) continue;
      final start = transaction.installmentStartOn ?? transaction.occurredOn;
      final totalMonths = transaction.installmentMonths ?? 0;
      final billedCount = _installmentOccurrencesThrough(
        start: start,
        totalMonths: totalMonths,
        cutoff: builder.cycle.statementOn,
      );
      final monthlyMinor = transaction.installmentMonthlyMinor;
      final amountMinor = transaction.amountMinor;
      final scheduleCompleteByCutoff = billedCount >= totalMonths;
      if (amountMinor <= 0 ||
          (!scheduleCompleteByCutoff &&
              (monthlyMinor == null || monthlyMinor <= 0))) {
        builder.hasIncompleteInstallment = true;
        continue;
      }

      if (!scheduleCompleteByCutoff) {
        final billedPrincipal = math.min(
          amountMinor,
          monthlyMinor! * billedCount,
        );
        builder.deferredInstallmentMinor += amountMinor - billedPrincipal;
      }
    }

    final cards =
        groups.values
            .map((builder) {
              final design = bankCardDesignFor(builder.account.cardDesign);
              final visual = AccountCardVisual.forAccount(
                builder.account,
                design,
                palette,
              );
              final projectedTotal = builder.hasIncompleteInstallment
                  ? null
                  : math.max(
                      0,
                      builder.account.debtMinor -
                          builder.deferredInstallmentMinor,
                    );
              return _NextMonthCreditCardBillingCard(
                account: builder.account,
                design: design,
                visual: visual,
                cycle: builder.cycle,
                totalMinor: projectedTotal,
              );
            })
            .toList(growable: false)
          ..sort((first, second) {
            final byName = first.account.displayName.toLowerCase().compareTo(
              second.account.displayName.toLowerCase(),
            );
            return byName != 0
                ? byName
                : first.account.id.compareTo(second.account.id);
          });
    final hasIncompleteAmount = cards.any((card) => card.totalMinor == null);
    return _NextMonthCreditCardBillingSummary(
      cards: List.unmodifiable(cards),
      totalMinor: hasIncompleteAmount
          ? null
          : cards.fold<int>(0, (total, card) => total + (card.totalMinor ?? 0)),
      historyAvailable: true,
    );
  }

  final List<_NextMonthCreditCardBillingCard> cards;
  final int? totalMinor;
  final bool historyAvailable;

  bool get isAvailable => totalMinor != null;
}

class _NextMonthCreditCardBillingBuilder {
  _NextMonthCreditCardBillingBuilder(this.account, {required this.cycle});

  final Account account;
  final _CreditCardBillingCycle cycle;
  int deferredInstallmentMinor = 0;
  bool hasIncompleteInstallment = false;
}

class _NextMonthCreditCardBillingCard {
  const _NextMonthCreditCardBillingCard({
    required this.account,
    required this.design,
    required this.visual,
    required this.cycle,
    required this.totalMinor,
  });

  final Account account;
  final BankCardDesign design;
  final AccountCardVisual visual;
  final _CreditCardBillingCycle cycle;
  final int? totalMinor;
}

class _CreditCardBillingCycle {
  const _CreditCardBillingCycle({
    required this.statementOn,
    required this.dueOn,
    required this.usesMonthEndEstimate,
  });

  factory _CreditCardBillingCycle.forUpcomingStatement({
    required Account account,
    required DateTime today,
  }) {
    final todayDate = DateTime(today.year, today.month, today.day);
    final savedStatementDay = account.statementDay;
    final usesMonthEndEstimate =
        savedStatementDay == null ||
        savedStatementDay < 1 ||
        savedStatementDay > 31;
    DateTime statementForMonth(DateTime month) => usesMonthEndEstimate
        ? DateTime(month.year, month.month + 1, 0)
        : _clampedDayInMonth(month, savedStatementDay);

    var statementMonth = DateTime(todayDate.year, todayDate.month);
    var statementOn = statementForMonth(statementMonth);
    if (statementOn.isBefore(todayDate)) {
      statementMonth = DateTime(todayDate.year, todayDate.month + 1);
      statementOn = statementForMonth(statementMonth);
    }
    final dueDay = account.dueDay;
    DateTime? dueOn;
    if (dueDay != null && dueDay >= 1 && dueDay <= 31) {
      dueOn = _clampedDayInMonth(statementOn, dueDay);
      if (!dueOn.isAfter(statementOn)) {
        dueOn = _clampedDayInMonth(
          DateTime(statementOn.year, statementOn.month + 1),
          dueDay,
        );
      }
    }
    return _CreditCardBillingCycle(
      statementOn: statementOn,
      dueOn: dueOn,
      usesMonthEndEstimate: usesMonthEndEstimate,
    );
  }

  final DateTime statementOn;
  final DateTime? dueOn;
  final bool usesMonthEndEstimate;
}

int _installmentOccurrencesThrough({
  required DateTime start,
  required int totalMonths,
  required DateTime cutoff,
}) {
  if (totalMonths <= 0) return 0;
  final monthIndex =
      (cutoff.year - start.year) * 12 + cutoff.month - start.month;
  if (monthIndex < 0) return 0;
  var count = math.min(totalMonths, monthIndex + 1);
  if (monthIndex < totalMonths &&
      _installmentDateForMonth(start, monthIndex).isAfter(cutoff)) {
    count -= 1;
  }
  return count.clamp(0, totalMonths);
}

DateTime _clampedDayInMonth(DateTime month, int day) {
  final lastDay = DateTime(month.year, month.month + 1, 0).day;
  return DateTime(month.year, month.month, math.min(day, lastDay));
}

class _InstallmentPlanSummary {
  const _InstallmentPlanSummary({
    required this.id,
    required this.name,
    required this.accountContext,
    required this.visual,
    required this.pattern,
    required this.shortMark,
    required this.monthlyMinor,
    required this.billingDay,
    required this.monthNumber,
    required this.totalMonths,
    required this.dueOn,
    this.sourcePlan,
    this.isUpcoming = false,
    this.isOverdue = false,
    this.rowRole = 'scheduled',
    this.showActions = true,
  });

  final int id;
  final String name;
  final String accountContext;
  final AccountCardVisual visual;
  final BankCardPattern pattern;
  final String shortMark;
  final int? monthlyMinor;
  final int billingDay;
  final int monthNumber;
  final int totalMonths;
  final DateTime dueOn;
  final InstallmentPlan? sourcePlan;
  final bool isUpcoming;
  final bool isOverdue;
  final String rowRole;
  final bool showActions;

  int get remainingAfterCurrent => totalMonths - monthNumber;
  bool get isSavedPlan => sourcePlan != null;
  bool get isUpcomingCreditCardSchedule => rowRole == 'credit-card-upcoming';
  int get paidInstallments => sourcePlan?.paidInstallments ?? monthNumber;
  int get remainingInstallments =>
      sourcePlan?.remainingInstallments ?? remainingAfterCurrent;

  String get savedRowKey => switch (rowRole) {
    'overdue' => 'dashboard-overdue-installment-plan-row-$id',
    'upcoming' => 'dashboard-upcoming-installment-plan-row-$id',
    _ => 'dashboard-installment-plan-row-$id',
  };

  String get recordPaymentKey => switch (rowRole) {
    'overdue' => 'dashboard-overdue-installment-record-payment-$id',
    'upcoming' => 'dashboard-upcoming-installment-record-payment-$id',
    _ => 'dashboard-installment-record-payment-$id',
  };

  String get manageMenuKey => switch (rowRole) {
    'overdue' => 'dashboard-overdue-installment-plan-menu-$id',
    'upcoming' => 'dashboard-upcoming-installment-plan-menu-$id',
    _ => 'dashboard-installment-plan-menu-$id',
  };

  String get rowKey => isSavedPlan
      ? savedRowKey
      : isUpcomingCreditCardSchedule
      ? 'dashboard-upcoming-credit-card-installment-row-$id'
      : 'dashboard-installment-row-$id';

  String get legacyCardKeyPrefix => isUpcomingCreditCardSchedule
      ? 'dashboard-upcoming-credit-card-installment'
      : 'dashboard-installment';
}

DateTime _installmentDateForMonth(DateTime start, int monthOffset) {
  final first = DateTime(start.year, start.month + monthOffset, 1);
  final lastDay = DateTime(first.year, first.month + 1, 0).day;
  return DateTime(first.year, first.month, math.min(start.day, lastDay));
}

Future<void> showInstallmentPaymentDialog(
  BuildContext context,
  AppController controller, {
  required InstallmentPlan plan,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) =>
      _InstallmentPaymentDialog(controller: controller, plan: plan),
);

class _InstallmentPaymentDialog extends StatefulWidget {
  const _InstallmentPaymentDialog({
    required this.controller,
    required this.plan,
  });

  final AppController controller;
  final InstallmentPlan plan;

  @override
  State<_InstallmentPaymentDialog> createState() =>
      _InstallmentPaymentDialogState();
}

class _InstallmentPaymentDialogState extends State<_InstallmentPaymentDialog> {
  late final String clientUuid;
  late DateTime paidOn;
  int? accountId;
  bool saving = false;
  bool reconnecting = false;
  bool paymentAttempted = false;
  Account? attemptedAccount;
  DateTime? attemptedPaidOn;

  List<Account> get paymentAccounts {
    final active = widget.controller.accounts
        .where(
          (account) =>
              account.scope == widget.plan.scope &&
              !account.isArchived &&
              account.isStandardAccount &&
              !account.isCreditCard,
        )
        .toList();
    final attempted = attemptedAccount;
    if (attempted != null &&
        !active.any((account) => account.id == attempted.id)) {
      active.add(attempted);
    }
    return active;
  }

  Account? get selectedAccount =>
      paymentAccounts.where((account) => account.id == accountId).firstOrNull;

  bool get currentAccountWouldOverdraw {
    final account = selectedAccount;
    return account != null &&
        widget.controller.transactionWouldOverdraw(
          account: account,
          existing: null,
          desiredAccountId: account.id,
          desiredKind: 'expense',
          desiredAmountMinor: widget.plan.installmentMonthlyMinor,
        );
  }

  bool get insufficientFunds =>
      !paymentAttempted && currentAccountWouldOverdraw;

  @override
  void initState() {
    super.initState();
    clientUuid = widget.controller.newClientUuid();
    final now = DateTime.now();
    paidOn = DateTime(now.year, now.month, now.day);
    final options = paymentAccounts;
    accountId = options.any((account) => account.id == widget.plan.accountId)
        ? widget.plan.accountId
        : options.firstOrNull?.id;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final account = selectedAccount;
    final retryAfterBalanceChange =
        paymentAttempted && currentAccountWouldOverdraw;
    final after = account == null
        ? null
        : widget.controller.projectedBalanceAfterTransaction(
            account: account,
            existing: null,
            desiredAccountId: account.id,
            desiredKind: 'expense',
            desiredAmountMinor: widget.plan.installmentMonthlyMinor,
          );
    final number =
        widget.plan.nextInstallmentNumber ?? widget.plan.paidInstallments + 1;
    return AlertDialog(
      key: const Key('installment-payment-dialog'),
      title: const Text('Record installment payment'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: palette.orangeSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: palette.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.plan.payee?.trim().isNotEmpty == true
                          ? widget.plan.payee!.trim()
                          : widget.plan.category?.name ?? 'Installment plan',
                      style: TextStyle(
                        color: palette.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    MoneyLabel(
                      minorUnits: widget.plan.installmentMonthlyMinor,
                      currencyCode: widget.controller.currencyCode,
                      locale: widget.controller.locale,
                      style: TextStyle(
                        color: palette.ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Payment $number of ${widget.plan.installmentMonths}',
                      style: TextStyle(color: palette.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                key: const Key('installment-payment-account'),
                initialValue:
                    paymentAccounts.any((item) => item.id == accountId)
                    ? accountId
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Pay from'),
                items: paymentAccounts
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(
                          '${item.displayName} · ${Money.format(item.balanceMinor, currencyCode: widget.controller.currencyCode, locale: widget.controller.locale)} balance',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: saving || paymentAttempted
                    ? null
                    : (value) => setState(() => accountId = value),
              ),
              const SizedBox(height: 14),
              InkWell(
                key: const Key('installment-payment-date'),
                onTap: saving || paymentAttempted ? null : _pickPaidOn,
                borderRadius: BorderRadius.circular(11),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Payment date',
                    suffixIcon: Icon(Icons.calendar_today_rounded, size: 18),
                  ),
                  child: Text(DateFormat('EEEE, MMM d, y').format(paidOn)),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                key: const Key('installment-payment-balance-preview'),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: insufficientFunds
                      ? palette.redSoft
                      : retryAfterBalanceChange
                      ? palette.orangeSoft
                      : palette.surfaceMuted,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: insufficientFunds
                        ? palette.red
                        : retryAfterBalanceChange
                        ? palette.orange
                        : palette.border,
                  ),
                ),
                child: account == null
                    ? Text(
                        'No active cash, bank, or e-wallet account is available.',
                        style: TextStyle(color: palette.red),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${Money.format(account.balanceMinor, currencyCode: widget.controller.currencyCode, locale: widget.controller.locale)} now · ${Money.format(after!, currencyCode: widget.controller.currencyCode, locale: widget.controller.locale)} after payment',
                            style: TextStyle(
                              color: insufficientFunds
                                  ? palette.red
                                  : retryAfterBalanceChange
                                  ? palette.orange
                                  : palette.inkSoft,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            insufficientFunds
                                ? 'This account cannot cover the payment. Nothing will be recorded.'
                                : retryAfterBalanceChange
                                ? 'The balance changed after the first attempt. Retry keeps the same payment reference to avoid recording it twice.'
                                : 'This payment will be added to expenses and deducted from the selected account.',
                            style: TextStyle(
                              color: insufficientFunds
                                  ? palette.red
                                  : retryAfterBalanceChange
                                  ? palette.orange
                                  : palette.muted,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
              ),
              if (!widget.controller.hasLiveConnection) ...[
                const SizedBox(height: 12),
                Container(
                  key: const Key('installment-payment-offline-message'),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: palette.orangeSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: palette.border),
                  ),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Reconnect to retry with this same payment reference.',
                        style: TextStyle(
                          color: palette.orange,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      OutlinedButton.icon(
                        key: const Key('installment-payment-reconnect'),
                        onPressed: reconnecting ? null : _reconnect,
                        icon: reconnecting
                            ? const SizedBox.square(
                                dimension: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.wifi_rounded, size: 16),
                        label: Text(
                          reconnecting ? 'Reconnecting…' : 'Reconnect',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
          key: const Key('confirm-installment-payment'),
          onPressed:
              saving ||
                  reconnecting ||
                  account == null ||
                  insufficientFunds ||
                  !widget.controller.hasLiveConnection
              ? null
              : _save,
          child: Text(saving ? 'Recording…' : 'Record payment'),
        ),
      ],
    );
  }

  Future<void> _pickPaidOn() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: paidOn,
      firstDate: DateTime(2000),
      lastDate: today,
    );
    if (picked != null) setState(() => paidOn = picked);
  }

  Future<void> _save() async {
    final selected = selectedAccount;
    final isRetry = paymentAttempted;
    if (selected == null || (!isRetry && currentAccountWouldOverdraw)) return;
    setState(() {
      saving = true;
      paymentAttempted = true;
      attemptedAccount ??= selected;
      attemptedPaidOn ??= paidOn;
    });
    try {
      await widget.controller.recordInstallmentPayment(
        plan: widget.plan,
        clientUuid: clientUuid,
        paidOn: attemptedPaidOn!,
        accountId: selected.id,
        isIdempotentRetry: isRetry,
      );
      if (mounted) {
        showSuccess(context, 'Installment payment recorded.');
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _reconnect() async {
    setState(() => reconnecting = true);
    try {
      await widget.controller.reconnect();
      if (mounted && !widget.controller.hasLiveConnection) {
        showError(
          context,
          widget.controller.errorMessage ?? 'Could not reconnect.',
        );
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) {
        final options = paymentAccounts;
        setState(() {
          if (!paymentAttempted &&
              !options.any((account) => account.id == accountId)) {
            accountId = options.firstOrNull?.id;
          }
          reconnecting = false;
        });
      }
    }
  }
}

Future<void> _confirmArchiveInstallmentPlan(
  BuildContext context,
  AppController controller,
  InstallmentPlan plan,
) async {
  const action = 'Stop plan';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('$action?'),
      content: Text(
        plan.hasPayments
            ? 'Recorded payments remain in transaction history. No more payments can be added to this plan.'
            : 'This removes the reminder without creating or deleting any transaction.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: ValueKey('confirm-installment-plan-archive-${plan.id}'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await controller.archiveInstallmentPlan(plan);
    if (context.mounted) {
      showSuccess(context, 'Plan stopped.');
    }
  } catch (error) {
    if (context.mounted) showError(context, error);
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.title,
    required this.subtitle,
    required this.scope,
    required this.onScopeSelected,
    required this.onRefresh,
    required this.onAddTransaction,
    this.addTransactionDisabledReason,
  });

  final String title;
  final String subtitle;
  final FinanceScope scope;
  final ValueChanged<FinanceScope> onScopeSelected;
  final VoidCallback onRefresh;
  final VoidCallback? onAddTransaction;
  final String? addTransactionDisabledReason;

  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 5),
        Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
    final actions = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FinanceScopeSelector(selected: scope, onSelected: onScopeSelected),
        OutlinedButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded, size: 19),
          label: const Text('Refresh'),
        ),
        Tooltip(
          message: onAddTransaction == null
              ? addTransactionDisabledReason ?? 'Add transaction unavailable'
              : 'Add transaction',
          child: FilledButton.icon(
            onPressed: onAddTransaction,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Add transaction'),
            style: FilledButton.styleFrom(
              backgroundColor: context.palette.greenDark,
              foregroundColor: context.palette.onPrimary,
            ),
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 18), actions],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 24),
            actions,
          ],
        );
      },
    );
  }
}

class _DashboardSectionHeading extends StatelessWidget {
  const _DashboardSectionHeading({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow,
              style: TextStyle(
                color: context.palette.greenDark,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 5),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: context.palette.inkSoft, fontSize: 13),
            ),
          ],
        ),
      ),
      if (trailing case final trailing?) ...[
        const SizedBox(width: 16),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: context.palette.mint,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              trailing,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.palette.greenDark,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

class _CurrentPosition extends StatelessWidget {
  const _CurrentPosition({
    required this.availableMoneyMinor,
    required this.savingsBalanceMinor,
    required this.creditCardDebtMinor,
    required this.netPositionMinor,
    required this.showSavings,
    required this.showCreditCardDebt,
    required this.portfolio,
    required this.hasGoldCostBasis,
    required this.goldGainLossMinor,
    required this.goldGainLossColor,
    required this.currencyCode,
    required this.locale,
    required this.scope,
  });

  final int availableMoneyMinor;
  final int savingsBalanceMinor;
  final int creditCardDebtMinor;
  final int netPositionMinor;
  final bool showSavings;
  final bool showCreditCardDebt;
  final JewelryPortfolioSummary portfolio;
  final bool hasGoldCostBasis;
  final int goldGainLossMinor;
  final Color goldGainLossColor;
  final String currencyCode;
  final String locale;
  final FinanceScope scope;

  @override
  Widget build(BuildContext context) {
    final cash = _CashPositionCard(
      value: availableMoneyMinor,
      currencyCode: currencyCode,
      locale: locale,
      scope: scope,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final cardCount =
            1 +
            (showSavings ? 1 : 0) +
            (showCreditCardDebt ? 1 : 0) +
            (scope == FinanceScope.personal ? 1 : 0);
        final estimatedCardWidth =
            (constraints.maxWidth - math.max(0, cardCount - 1) * 14) /
            cardCount;
        final cards = <Widget>[
          cash,
          if (showSavings)
            _SavingsPositionCard(
              value: savingsBalanceMinor,
              currencyCode: currencyCode,
              locale: locale,
            ),
          if (showCreditCardDebt)
            _CreditCardDebtCard(
              debtMinor: creditCardDebtMinor,
              netPositionMinor: netPositionMinor,
              currencyCode: currencyCode,
              locale: locale,
            ),
          if (scope == FinanceScope.personal)
            _GoldPositionCard(
              portfolio: portfolio,
              hasCostBasis: hasGoldCostBasis,
              gainLossMinor: goldGainLossMinor,
              gainLossColor: goldGainLossColor,
              currencyCode: currencyCode,
              locale: locale,
              compact:
                  constraints.maxWidth < 600 ||
                  textScale > 1.5 ||
                  estimatedCardWidth < 390,
            ),
        ];
        if (cards.length == 1) return cards.single;
        final scaledMinimumCardWidth =
            290 + ((textScale - 1).clamp(0.0, 1.0) * 100);
        final rowMinimumWidth = math.max(
          920.0,
          cards.length * scaledMinimumCardWidth + (cards.length - 1) * 14,
        );
        if (constraints.maxWidth < rowMinimumWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < cards.length; index++) ...[
                if (index > 0) const SizedBox(height: 14),
                cards[index],
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < cards.length; index++) ...[
                if (index > 0) const SizedBox(width: 14),
                Expanded(child: cards[index]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _DashboardAccountRail extends StatelessWidget {
  const _DashboardAccountRail({
    required this.accounts,
    required this.asOf,
    required this.currencyCode,
    required this.locale,
    required this.scope,
  });

  final List<Account> accounts;
  final DateTime asOf;
  final String currencyCode;
  final String locale;
  final FinanceScope scope;

  @override
  Widget build(BuildContext context) => _AccountBalanceCarousel(
    key: const Key('dashboard-account-balances'),
    accounts: accounts,
    asOf: asOf,
    currencyCode: currencyCode,
    locale: locale,
    scope: scope,
  );
}

class _AccountBalanceCarousel extends StatefulWidget {
  const _AccountBalanceCarousel({
    super.key,
    required this.accounts,
    required this.asOf,
    required this.currencyCode,
    required this.locale,
    required this.scope,
  });

  final List<Account> accounts;
  final DateTime asOf;
  final String currencyCode;
  final String locale;
  final FinanceScope scope;

  @override
  State<_AccountBalanceCarousel> createState() =>
      _AccountBalanceCarouselState();
}

class _AccountBalanceCarouselState extends State<_AccountBalanceCarousel> {
  late int selectedAccountId;
  int _shuffleDirection = 1;

  @override
  void initState() {
    super.initState();
    selectedAccountId = _initialAccountId(widget.accounts);
  }

  @override
  void didUpdateWidget(covariant _AccountBalanceCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.accounts.any((account) => account.id == selectedAccountId)) {
      _shuffleDirection = 0;
      selectedAccountId = _initialAccountId(widget.accounts);
    }
  }

  int _initialAccountId(List<Account> accounts) => accounts
      .firstWhere((account) => !account.isSystem, orElse: () => accounts.first)
      .id;

  void _selectIndex(int index) {
    if (index < 0 || index >= widget.accounts.length) return;
    final currentIndex = widget.accounts.indexWhere(
      (account) => account.id == selectedAccountId,
    );
    if (currentIndex == index) return;
    setState(() {
      _shuffleDirection = currentIndex < 0 || index > currentIndex ? 1 : -1;
      selectedAccountId = widget.accounts[index].id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = widget.accounts.indexWhere(
      (account) => account.id == selectedAccountId,
    );
    final safeIndex = selectedIndex < 0 ? 0 : selectedIndex;
    final account = widget.accounts[safeIndex];
    final design = bankCardDesignFor(account.cardDesign);
    final palette = context.palette;
    final visual = AccountCardVisual.forAccount(account, design, palette);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final shuffleKey = ValueKey<String>(
      'dashboard-account-shuffle-${account.id}',
    );
    final formattedBalance = Money.format(
      account.balanceMinor,
      currencyCode: widget.currencyCode,
      locale: widget.locale,
    );
    final asOfLabel = DateFormat('MMM d, y').format(widget.asOf);
    final accountStatus = account.isArchived
        ? 'Archived'
        : account.isSystem
        ? 'System account'
        : 'Active';
    final accountType = accountCardTypeLabel(account.type);
    final institution = design.key == 'other' ? accountType : design.name;
    final shortMark = design.key == 'other'
        ? accountCardShortMark(account.type)
        : design.shortMark;
    final foreground = visual.foreground;
    final subdued = foreground;
    final otherAccounts = widget.accounts
        .where((candidate) => candidate.id != account.id)
        .toList(growable: false);
    final railStart = Color.lerp(
      palette.surface,
      visual.primary,
      isDark ? 0.28 : 0.1,
    )!;
    final railEnd = Color.lerp(
      palette.canvas,
      visual.secondary,
      isDark ? 0.17 : 0.06,
    )!;
    final clampedTextScale = math.min(
      MediaQuery.textScalerOf(context).scale(1),
      1.15,
    );

    return AnimatedContainer(
      key: const Key('dashboard-account-rail'),
      duration: disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 220),
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [railStart, railEnd],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Color.lerp(palette.border, visual.accent, 0.26)!,
        ),
        boxShadow: [
          BoxShadow(
            color: visual.primary.withValues(alpha: isDark ? 0.18 : 0.1),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final cardHeight = (constraints.maxWidth / 1.56).clamp(
                184.0,
                212.0,
              );
              return SizedBox(
                key: const Key('dashboard-account-balance-card-stack'),
                height: cardHeight + 28,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      key: const Key('dashboard-account-card-back-layer-1'),
                      left: 20,
                      right: 2,
                      top: 0,
                      height: cardHeight,
                      child: Transform.rotate(
                        angle: -0.055,
                        alignment: Alignment.bottomLeft,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Color.lerp(
                                  visual.primary,
                                  visual.foreground,
                                  0.24,
                                )!,
                                visual.secondary,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.11),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      key: const Key('dashboard-account-card-back-layer-2'),
                      left: 8,
                      right: 16,
                      top: 12,
                      height: cardHeight,
                      child: Transform.rotate(
                        angle: 0.035,
                        alignment: Alignment.bottomRight,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Color.lerp(visual.primary, visual.accent, 0.2)!,
                                Color.lerp(
                                  visual.secondary,
                                  Colors.black,
                                  0.16,
                                )!,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 20,
                      height: cardHeight,
                      child: Semantics(
                        key: const Key('dashboard-account-balance-card'),
                        container: true,
                        liveRegion: true,
                        label:
                            '${widget.scope.label} account balance. '
                            '${account.displayName}. $accountType. '
                            'Account ${safeIndex + 1} of ${widget.accounts.length}.',
                        value: '$formattedBalance as of $asOfLabel',
                        child: AnimatedSwitcher(
                          key: const Key('dashboard-account-card-shuffle'),
                          duration: disableAnimations
                              ? Duration.zero
                              : const Duration(milliseconds: 320),
                          reverseDuration: disableAnimations
                              ? Duration.zero
                              : const Duration(milliseconds: 280),
                          switchInCurve: Curves.linear,
                          switchOutCurve: Curves.linear,
                          layoutBuilder: (currentChild, previousChildren) =>
                              Stack(
                                fit: StackFit.expand,
                                clipBehavior: Clip.none,
                                children: [...previousChildren, ?currentChild],
                              ),
                          transitionBuilder: (child, animation) {
                            final incoming = child.key == shuffleKey;
                            final readingDirection =
                                Directionality.of(context) == TextDirection.rtl
                                ? -1.0
                                : 1.0;
                            final direction =
                                _shuffleDirection.toDouble() * readingDirection;
                            final hasDirection = _shuffleDirection != 0;
                            final motion = CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                              reverseCurve: Curves.easeInCubic,
                            );
                            final slide = Tween<Offset>(
                              begin: Offset(
                                (incoming ? 0.2 : -0.16) * direction,
                                hasDirection ? (incoming ? -0.045 : 0.035) : 0,
                              ),
                              end: Offset.zero,
                            ).animate(motion);
                            final scale = Tween<double>(
                              begin: incoming ? 0.95 : 0.98,
                              end: 1,
                            ).animate(motion);
                            final startingRotation =
                                (incoming ? 0.045 : -0.035) * direction;
                            return FadeTransition(
                              opacity: motion,
                              child: SlideTransition(
                                position: slide,
                                child: ScaleTransition(
                                  scale: scale,
                                  child: AnimatedBuilder(
                                    animation: motion,
                                    child: child,
                                    builder: (context, child) =>
                                        Transform.rotate(
                                          angle:
                                              startingRotation *
                                              (1 - motion.value),
                                          child: child,
                                        ),
                                  ),
                                ),
                              ),
                            );
                          },
                          child: KeyedSubtree(
                            key: shuffleKey,
                            child: ExcludeSemantics(
                              child: Card(
                                key: ValueKey(
                                  'dashboard-account-balance-card-${account.id}',
                                ),
                                margin: EdgeInsets.zero,
                                color: visual.primary,
                                clipBehavior: Clip.antiAlias,
                                elevation: 18,
                                shadowColor: visual.primary.withValues(
                                  alpha: 0.38,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(22),
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.16),
                                  ),
                                ),
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: DecoratedBox(
                                          key: ValueKey(
                                            'dashboard-account-balance-card-design-${account.id}',
                                          ),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                visual.primary,
                                                visual.secondary,
                                              ],
                                            ),
                                          ),
                                          child: CustomPaint(
                                            key: ValueKey(
                                              'dashboard-account-balance-card-pattern-${account.id}',
                                            ),
                                            painter: BankCardPatternPainter(
                                              pattern: design.pattern,
                                              accent: visual.accent,
                                              foreground: visual.foreground,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: MediaQuery(
                                        data: MediaQuery.of(context).copyWith(
                                          textScaler: TextScaler.linear(
                                            clampedTextScale,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            20,
                                            18,
                                            20,
                                            17,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          account.isSavingsAccount
                                                              ? 'Savings balance'
                                                              : 'Account balance',
                                                          style: TextStyle(
                                                            color: subdued,
                                                            fontSize: 13,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 3,
                                                        ),
                                                        FittedBox(
                                                          fit: BoxFit.scaleDown,
                                                          alignment: Alignment
                                                              .centerLeft,
                                                          child: MoneyLabel(
                                                            minorUnits: account
                                                                .balanceMinor,
                                                            currencyCode: widget
                                                                .currencyCode,
                                                            locale:
                                                                widget.locale,
                                                            compact: true,
                                                            style: TextStyle(
                                                              color: foreground,
                                                              fontSize: 28,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              letterSpacing:
                                                                  -0.7,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 14),
                                                  CustomPaint(
                                                    key: const Key(
                                                      'dashboard-account-card-chip',
                                                    ),
                                                    size: const Size(43, 31),
                                                    painter:
                                                        _DashboardCardChipPainter(
                                                          tint: visual.accent,
                                                          foreground:
                                                              visual.foreground,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                              const Spacer(),
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          shortMark,
                                                          key: ValueKey(
                                                            'dashboard-account-balance-card-mark-${account.id}',
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            color: foreground,
                                                            fontSize: 14,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            letterSpacing: 0.4,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Text(
                                                          account.displayName,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            color: subdued,
                                                            fontSize: 11.5,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Flexible(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .end,
                                                      children: [
                                                        Text(
                                                          account.isSavingsAccount
                                                              ? 'Set aside'
                                                              : account
                                                                    .scope
                                                                    .accountLabel,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            color: foreground,
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Text(
                                                          'As of ${DateFormat('MMM d').format(widget.asOf)}',
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            color: subdued,
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 20 + cardHeight * 0.49 - 24,
                      child: _DashboardCarouselButton(
                        key: const Key('dashboard-account-balance-next'),
                        tooltip: 'Next account',
                        icon: Icons.chevron_right_rounded,
                        foreground: foreground,
                        emphasized: true,
                        onPressed: safeIndex < widget.accounts.length - 1
                            ? () => _selectIndex(safeIndex + 1)
                            : null,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            key: const Key('dashboard-account-pager'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _DashboardCarouselButton(
                key: const Key('dashboard-account-balance-previous'),
                tooltip: 'Previous account',
                icon: Icons.chevron_left_rounded,
                foreground: palette.ink,
                onPressed: safeIndex > 0
                    ? () => _selectIndex(safeIndex - 1)
                    : null,
              ),
              const SizedBox(width: 10),
              for (var index = 0; index < widget.accounts.length; index++) ...[
                AnimatedContainer(
                  key: ValueKey('dashboard-account-page-$index'),
                  duration: disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  width: index == safeIndex ? 28 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: index == safeIndex
                        ? palette.ink
                        : palette.muted.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                if (index < widget.accounts.length - 1)
                  const SizedBox(width: 5),
              ],
              const SizedBox(width: 10),
              Text(
                '${safeIndex + 1}/${widget.accounts.length}',
                style: TextStyle(
                  color: palette.inkSoft,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Account information',
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              Tooltip(
                message: 'Only saved account information is shown',
                child: Icon(
                  Icons.visibility_off_outlined,
                  color: palette.inkSoft,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            key: const Key('dashboard-account-information'),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: palette.border),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cells = [
                  _DashboardAccountInfoCell(
                    label: 'Account name',
                    value: account.displayName,
                  ),
                  _DashboardAccountInfoCell(
                    label: 'Account type',
                    value: accountType,
                  ),
                  _DashboardAccountInfoCell(
                    label: 'Institution / design',
                    value: institution,
                  ),
                  _DashboardAccountInfoCell(
                    label: 'Status',
                    value: accountStatus,
                  ),
                  _DashboardAccountInfoCell(
                    label: 'Scope',
                    value: account.scope.accountLabel,
                  ),
                  _DashboardAccountInfoCell(
                    label: 'Balance date',
                    value: asOfLabel,
                  ),
                ];
                if (constraints.maxWidth < 270) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var index = 0; index < cells.length; index++) ...[
                        if (index > 0) const SizedBox(height: 15),
                        cells[index],
                      ],
                    ],
                  );
                }
                return Column(
                  children: [
                    for (var index = 0; index < cells.length; index += 2) ...[
                      if (index > 0) const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: cells[index]),
                          const SizedBox(width: 16),
                          Expanded(child: cells[index + 1]),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          _DashboardOtherAccountPreviews(
            accounts: otherAccounts,
            selectedAccount: account,
            currencyCode: widget.currencyCode,
            locale: widget.locale,
            onSelect: (selected) {
              final index = widget.accounts.indexWhere(
                (candidate) => candidate.id == selected.id,
              );
              _selectIndex(index);
            },
          ),
        ],
      ),
    );
  }
}

class _DashboardCarouselButton extends StatelessWidget {
  const _DashboardCarouselButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.foreground,
    required this.onPressed,
    this.emphasized = false,
  });

  final String tooltip;
  final IconData icon;
  final Color foreground;
  final VoidCallback? onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 48, height: 48),
    visualDensity: VisualDensity.compact,
    style: IconButton.styleFrom(
      foregroundColor: foreground,
      disabledForegroundColor: foreground.withValues(alpha: 0.28),
      backgroundColor: foreground.withValues(alpha: emphasized ? 0.18 : 0.08),
      shape: const CircleBorder(),
    ),
    icon: Icon(icon, size: emphasized ? 27 : 21),
  );
}

class _DashboardOtherAccountPreviews extends StatelessWidget {
  const _DashboardOtherAccountPreviews({
    required this.accounts,
    required this.selectedAccount,
    required this.currencyCode,
    required this.locale,
    required this.onSelect,
  });

  final List<Account> accounts;
  final Account selectedAccount;
  final String currencyCode;
  final String locale;
  final ValueChanged<Account> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (accounts.isEmpty) {
      return Container(
        key: const Key('dashboard-other-account-previews'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.surface.withValues(alpha: 0.64),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          key: const Key('dashboard-only-account-support'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: palette.successSoft,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                Icons.account_balance_wallet_outlined,
                color: palette.success,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your only account',
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${selectedAccount.displayName} is already shown above. '
                    'Add another account to browse it here.',
                    style: TextStyle(
                      color: palette.inkSoft,
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      key: const Key('dashboard-other-account-previews'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Other accounts',
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: palette.surface.withValues(alpha: 0.68),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: palette.border),
              ),
              child: Text(
                '${accounts.length}',
                style: TextStyle(
                  color: palette.inkSoft,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        for (var index = 0; index < accounts.length; index++) ...[
          if (index > 0) const SizedBox(height: 9),
          _DashboardAccountPreview(
            account: accounts[index],
            currencyCode: currencyCode,
            locale: locale,
            onTap: () => onSelect(accounts[index]),
          ),
        ],
      ],
    );
  }
}

class _DashboardAccountPreview extends StatelessWidget {
  const _DashboardAccountPreview({
    required this.account,
    required this.currencyCode,
    required this.locale,
    required this.onTap,
  });

  final Account account;
  final String currencyCode;
  final String locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final design = bankCardDesignFor(account.cardDesign);
    final visual = AccountCardVisual.forAccount(account, design, palette);
    final type = accountCardTypeLabel(account.type);
    final shortMark = design.key == 'other'
        ? accountCardShortMark(account.type)
        : design.shortMark;
    final formattedBalance = Money.format(
      account.balanceMinor,
      currencyCode: currencyCode,
      locale: locale,
    );
    return Semantics(
      key: ValueKey('dashboard-account-preview-${account.id}'),
      button: true,
      label: 'Show ${account.displayName}, $type',
      value: 'Balance $formattedBalance',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: palette.surface.withValues(alpha: 0.68),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: palette.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      height: 48,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: DecoratedBox(
                          key: ValueKey(
                            'dashboard-account-preview-card-design-${account.id}',
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [visual.primary, visual.secondary],
                            ),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: visual.foreground.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  key: ValueKey(
                                    'dashboard-account-preview-card-pattern-${account.id}',
                                  ),
                                  painter: BankCardPatternPainter(
                                    pattern: design.pattern,
                                    accent: visual.accent,
                                    foreground: visual.foreground,
                                  ),
                                ),
                              ),
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(5),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      shortMark,
                                      key: ValueKey(
                                        'dashboard-account-preview-card-mark-${account.id}',
                                      ),
                                      style: TextStyle(
                                        color: visual.foreground,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            account.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.ink,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            type,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: MoneyLabel(
                              minorUnits: account.balanceMinor,
                              currencyCode: currencyCode,
                              locale: locale,
                              compact: true,
                              style: TextStyle(
                                color: palette.inkSoft,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 5),
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: palette.inkSoft,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardAccountInfoCell extends StatelessWidget {
  const _DashboardAccountInfoCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(color: context.palette.muted, fontSize: 10.5),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: context.palette.ink,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
      ),
    ],
  );
}

class _DashboardCardChipPainter extends CustomPainter {
  const _DashboardCardChipPainter({
    required this.tint,
    required this.foreground,
  });

  final Color tint;
  final Color foreground;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final fill = Paint()..color = tint;
    final stroke = Paint()
      ..color = foreground.withValues(alpha: 0.64)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    final rounded = RRect.fromRectAndRadius(rect, const Radius.circular(5));
    canvas.drawRRect(rounded, fill);
    canvas.drawRRect(rounded, stroke);
    final center = rect.center;
    canvas.drawCircle(center, size.height * 0.2, stroke);
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, center.dy - 6),
      stroke,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy + 6),
      Offset(center.dx, size.height),
      stroke,
    );
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(center.dx - 8, center.dy),
      stroke,
    );
    canvas.drawLine(
      Offset(center.dx + 8, center.dy),
      Offset(size.width, center.dy),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _DashboardCardChipPainter oldDelegate) =>
      oldDelegate.tint != tint || oldDelegate.foreground != foreground;
}

class _CreditCardDebtCard extends StatelessWidget {
  const _CreditCardDebtCard({
    required this.debtMinor,
    required this.netPositionMinor,
    required this.currencyCode,
    required this.locale,
  });

  final int debtMinor;
  final int netPositionMinor;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) => Semantics(
    key: const Key('dashboard-credit-card-debt-card'),
    container: true,
    label: 'Current credit card debt or utang',
    value: Money.format(debtMinor, currencyCode: currencyCode, locale: locale),
    child: Card(
      color: context.palette.redSoft,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: context.palette.red),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 9,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(Icons.credit_card_rounded, color: context.palette.red),
                Text(
                  'CREDIT CARD UTANG',
                  style: TextStyle(
                    color: context.palette.red,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const StatusPill(label: 'Liability', neutral: true),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Total debt',
              style: TextStyle(color: context.palette.inkSoft, fontSize: 13),
            ),
            const SizedBox(height: 5),
            MoneyLabel(
              minorUnits: debtMinor,
              currencyCode: currencyCode,
              locale: locale,
              compact: true,
              style: TextStyle(
                color: context.palette.red,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    'Net cash position',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  flex: 5,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: MoneyLabel(
                      minorUnits: netPositionMinor,
                      currencyCode: currencyCode,
                      locale: locale,
                      compact: true,
                      style: TextStyle(
                        color: netPositionMinor >= 0
                            ? context.palette.greenDark
                            : context.palette.red,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _CashPositionCard extends StatelessWidget {
  const _CashPositionCard({
    required this.value,
    required this.currencyCode,
    required this.locale,
    required this.scope,
  });

  final int value;
  final String currencyCode;
  final String locale;
  final FinanceScope scope;

  @override
  Widget build(BuildContext context) {
    final isJoint = scope == FinanceScope.joint;
    return Semantics(
      key: const Key('dashboard-cash-position-card'),
      container: true,
      excludeSemantics: true,
      label: isJoint
          ? 'Available Joint money, excluding savings and Personal money'
          : 'Available money, excluding savings',
      value: Money.format(value, currencyCode: currencyCode, locale: locale),
      child: Card(
        color: context.palette.heroStart,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: context.palette.heroEnd),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [context.palette.heroStart, context.palette.heroEnd],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -54,
                top: -70,
                child: Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.palette.onHero.withValues(alpha: 0.1),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: context.palette.onHero.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.account_balance_wallet_rounded,
                            size: 21,
                            color: context.palette.onHero,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            isJoint
                                ? 'JOINT AVAILABLE MONEY'
                                : 'AVAILABLE MONEY',
                            style: TextStyle(
                              color: context.palette.onHeroMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: context.palette.onHero.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Cash',
                            style: TextStyle(
                              color: context.palette.onHero,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 27),
                    Text(
                      'Ready to use',
                      style: TextStyle(
                        color: context.palette.onHeroMuted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 5),
                    MoneyLabel(
                      minorUnits: value,
                      currencyCode: currencyCode,
                      locale: locale,
                      compact: true,
                      style: TextStyle(
                        color: context.palette.onHero,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline_rounded,
                          size: 17,
                          color: context.palette.onHero,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            isJoint
                                ? 'Savings excluded · Joint money excluded from your Personal total'
                                : 'Savings set aside and excluded',
                            style: TextStyle(
                              color: context.palette.onHeroMuted,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavingsPositionCard extends StatelessWidget {
  const _SavingsPositionCard({
    required this.value,
    required this.currencyCode,
    required this.locale,
  });

  final int value;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) => Semantics(
    key: const Key('dashboard-savings-position-card'),
    container: true,
    excludeSemantics: true,
    label: 'Savings set aside, excluded from available money',
    value: Money.format(value, currencyCode: currencyCode, locale: locale),
    child: Card(
      color: context.palette.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: context.palette.green.withValues(alpha: 0.48)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -44,
            top: -56,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.palette.mint.withValues(alpha: 0.8),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: context.palette.mint,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.savings_rounded,
                        size: 22,
                        color: context.palette.greenDark,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'SAVINGS SET ASIDE',
                        style: TextStyle(
                          color: context.palette.inkSoft,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: context.palette.mint,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Protected',
                        style: TextStyle(
                          color: context.palette.greenDark,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 27),
                Text(
                  'Savings balance',
                  style: TextStyle(color: context.palette.muted, fontSize: 13),
                ),
                const SizedBox(height: 5),
                MoneyLabel(
                  minorUnits: value,
                  currencyCode: currencyCode,
                  locale: locale,
                  compact: true,
                  style: TextStyle(
                    color: context.palette.ink,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 17,
                      color: context.palette.greenDark,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'Excluded from available money · included in assets and net position',
                        style: TextStyle(
                          color: context.palette.inkSoft,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _GoldPositionCard extends StatelessWidget {
  const _GoldPositionCard({
    required this.portfolio,
    required this.hasCostBasis,
    required this.gainLossMinor,
    required this.gainLossColor,
    required this.currencyCode,
    required this.locale,
    required this.compact,
  });

  final JewelryPortfolioSummary portfolio;
  final bool hasCostBasis;
  final int gainLossMinor;
  final Color gainLossColor;
  final String currencyCode;
  final String locale;
  final bool compact;

  IconData get _trendIcon => !hasCostBasis || gainLossMinor == 0
      ? Icons.trending_flat_rounded
      : gainLossMinor > 0
      ? Icons.trending_up_rounded
      : Icons.trending_down_rounded;

  String _semanticsValue() {
    final heldValue = Money.format(
      portfolio.totalEstimatedValueMinor,
      currencyCode: currencyCode,
      locale: locale,
    );
    final gainLoss = hasCostBasis
        ? Money.format(
            gainLossMinor,
            currencyCode: currencyCode,
            locale: locale,
          )
        : 'not available';
    return 'Held gold value $heldValue. Unrealized gold gain or loss '
        '$gainLoss. ${_goldCostCoverage(portfolio)}. This asset is not cash.';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      key: const Key('dashboard-gold-position-card'),
      container: true,
      excludeSemantics: true,
      label: 'Current held gold portfolio',
      value: _semanticsValue(),
      child: Card(
        color: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: palette.gold),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _GoldPortfolioHeader(compact: compact),
              const SizedBox(height: 20),
              Text(
                'Held gold value',
                style: TextStyle(color: palette.inkSoft, fontSize: 13),
              ),
              const SizedBox(height: 4),
              MoneyLabel(
                minorUnits: portfolio.totalEstimatedValueMinor,
                currencyCode: currencyCode,
                locale: locale,
                compact: true,
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 31,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                key: const Key('dashboard-gold-gain-loss-card'),
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: palette.surfaceMuted,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: palette.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _GoldGainSummary(
                      compact: compact,
                      hasCostBasis: hasCostBasis,
                      gainLossMinor: gainLossMinor,
                      gainLossColor: gainLossColor,
                      trendIcon: _trendIcon,
                      currencyCode: currencyCode,
                      locale: locale,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _goldCostCoverage(portfolio),
                      style: TextStyle(color: palette.inkSoft, fontSize: 11.5),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Current unrealized value · not period cashflow',
                      style: TextStyle(color: palette.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoldPortfolioHeader extends StatelessWidget {
  const _GoldPortfolioHeader({required this.compact});

  final bool compact;

  Widget _icon(AppPalette palette) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: palette.goldSoft,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(Icons.diamond_rounded, color: palette.gold),
  );

  Widget _title(AppPalette palette) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'GOLD PORTFOLIO',
        style: TextStyle(
          color: palette.gold,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        'Current collection value',
        style: TextStyle(color: palette.inkSoft, fontSize: 12.5),
      ),
    ],
  );

  Widget _badge(AppPalette palette) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: palette.goldSoft,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      'Asset · not cash',
      style: TextStyle(
        color: palette.gold,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _icon(palette),
              const SizedBox(width: 12),
              Expanded(child: _title(palette)),
            ],
          ),
          const SizedBox(height: 10),
          _badge(palette),
        ],
      );
    }
    return Row(
      children: [
        _icon(palette),
        const SizedBox(width: 12),
        Expanded(child: _title(palette)),
        _badge(palette),
      ],
    );
  }
}

class _GoldGainSummary extends StatelessWidget {
  const _GoldGainSummary({
    required this.compact,
    required this.hasCostBasis,
    required this.gainLossMinor,
    required this.gainLossColor,
    required this.trendIcon,
    required this.currencyCode,
    required this.locale,
  });

  final bool compact;
  final bool hasCostBasis;
  final int gainLossMinor;
  final Color gainLossColor;
  final IconData trendIcon;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final amount = hasCostBasis
        ? MoneyLabel(
            minorUnits: gainLossMinor,
            currencyCode: currencyCode,
            locale: locale,
            compact: true,
            style: TextStyle(
              color: gainLossColor,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          )
        : Text(
            'Not available',
            style: TextStyle(
              color: context.palette.muted,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          );
    final label = Text(
      'Gold gain / loss',
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(fontWeight: FontWeight.w700),
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label,
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(trendIcon, size: 18, color: gainLossColor),
              const SizedBox(width: 6),
              Expanded(child: amount),
            ],
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: label),
        Icon(trendIcon, size: 18, color: gainLossColor),
        const SizedBox(width: 6),
        amount,
      ],
    );
  }
}

class _PeriodToolbar extends StatelessWidget {
  const _PeriodToolbar({required this.controller, required this.summary});

  final AppController controller;
  final ReportSummary summary;

  static const periods = {
    'week': 'Week',
    'month': 'Month',
    'year': 'Year',
    'cutoff': 'Cutoff',
  };

  @override
  Widget build(BuildContext context) => SectionCard(
    key: const Key('dashboard-period-toolbar'),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final picker = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String>(
            segments: periods.entries
                .map(
                  (entry) =>
                      ButtonSegment(value: entry.key, label: Text(entry.value)),
                )
                .toList(),
            selected: {controller.selectedPeriod},
            onSelectionChanged: (value) =>
                _handleDashboardTransition(controller.setPeriod(value.first)),
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          ),
        );
        final navigation = _PeriodNavigation(
          controller: controller,
          summary: summary,
          refreshing: controller.isDashboardRefreshing,
        );
        if (constraints.maxWidth < 880) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              picker,
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 6),
              navigation,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: picker),
            const SizedBox(width: 16),
            Flexible(child: navigation),
          ],
        );
      },
    ),
  );
}

class _PeriodNavigation extends StatelessWidget {
  const _PeriodNavigation({
    required this.controller,
    required this.summary,
    required this.refreshing,
  });

  final AppController controller;
  final ReportSummary summary;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final Widget label = refreshing
        ? Semantics(
            liveRegion: true,
            label: 'Updating the selected dashboard period',
            child: Text(
              'Updating selected period…',
              key: const Key('dashboard-period-loading-label'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.palette.inkSoft,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                summary.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.palette.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${DateFormat('MMM d').format(summary.startsOn)} – '
                '${DateFormat('MMM d, y').format(summary.endsOn)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.palette.inkSoft,
                  fontSize: 11.5,
                ),
              ),
            ],
          );
    final previous = IconButton(
      onPressed: () => _handleDashboardTransition(controller.moveAnchor(-1)),
      tooltip: 'Previous period',
      icon: const Icon(Icons.chevron_left_rounded),
    );
    final next = IconButton(
      onPressed: () => _handleDashboardTransition(controller.moveAnchor(1)),
      tooltip: 'Next period',
      icon: const Icon(Icons.chevron_right_rounded),
    );
    final today = TextButton(
      onPressed: () => _handleDashboardTransition(controller.goToToday()),
      child: const Text('Today'),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  previous,
                  Expanded(child: label),
                  next,
                ],
              ),
              today,
            ],
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            previous,
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 180),
                child: label,
              ),
            ),
            next,
            const SizedBox(width: 4),
            today,
          ],
        );
      },
    );
  }
}

class _PeriodMetrics extends StatelessWidget {
  const _PeriodMetrics({
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
    final metrics = [
      _PeriodMetricCard(
        key: const Key('dashboard-net-cashflow-metric'),
        label: 'Net cashflow',
        value: summary.netMinor,
        caption: summary.netMinor >= 0
            ? 'Income left after spending'
            : 'Spending above income',
        icon: summary.netMinor >= 0
            ? Icons.trending_up_rounded
            : Icons.trending_down_rounded,
        color: summary.netMinor >= 0 ? palette.greenDark : palette.red,
        currencyCode: currencyCode,
        locale: locale,
      ),
      _PeriodMetricCard(
        key: const Key('dashboard-income-metric'),
        label: 'Income',
        value: summary.incomeMinor,
        caption: 'Money received this period',
        icon: Icons.south_west_rounded,
        color: palette.greenDark,
        currencyCode: currencyCode,
        locale: locale,
      ),
      _PeriodMetricCard(
        key: const Key('dashboard-expenses-metric'),
        label: 'Expenses',
        value: summary.expenseMinor,
        caption: 'Total spending this period',
        icon: Icons.north_east_rounded,
        color: palette.orange,
        currencyCode: currencyCode,
        locale: locale,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 540
            ? 3
            : constraints.maxWidth >= 340
            ? 2
            : 1;
        const gap = 10.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          key: const Key('dashboard-period-metrics'),
          spacing: gap,
          runSpacing: gap,
          children: metrics
              .map((metric) => SizedBox(width: width, child: metric))
              .toList(),
        );
      },
    );
  }
}

class _PeriodMetricCard extends StatelessWidget {
  const _PeriodMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.color,
    required this.currencyCode,
    required this.locale,
  });

  final String label;
  final int value;
  final String caption;
  final IconData icon;
  final Color color;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    excludeSemantics: true,
    label: '$label for the selected period',
    value:
        '${Money.format(value, currencyCode: currencyCode, locale: locale)}. '
        '$caption',
    child: Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: context.palette.surfaceMuted,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 31,
                height: 31,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: color),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: context.palette.inkSoft,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          MoneyLabel(
            minorUnits: value,
            currencyCode: currencyCode,
            locale: locale,
            compact: true,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            style: TextStyle(color: context.palette.inkSoft, fontSize: 11.5),
          ),
        ],
      ),
    ),
  );
}

String _goldCostCoverage(JewelryPortfolioSummary portfolio) {
  if (portfolio.heldCount == 0) return 'No held gold to compare';

  if (portfolio.costKnownCount == 0) {
    return 'No purchase values recorded for '
        '${portfolio.heldCount} held ${_itemLabel(portfolio.heldCount)}';
  }

  if (portfolio.costMissingCount > 0) {
    return 'Based on ${portfolio.costKnownCount} of ${portfolio.heldCount} '
        'held items · ${portfolio.costMissingCount} missing purchase '
        '${portfolio.costMissingCount == 1 ? 'value' : 'values'}';
  }

  return 'Based on all ${portfolio.costKnownCount} held '
      '${_itemLabel(portfolio.costKnownCount)} · all purchase values recorded';
}

String _itemLabel(int count) => count == 1 ? 'item' : 'items';

class _CashflowPanel extends StatelessWidget {
  const _CashflowPanel({
    required this.summary,
    required this.currencyCode,
    required this.locale,
  });

  final ReportSummary summary;
  final String currencyCode;
  final String locale;

  String _chartSemantics() {
    final buckets = summary.buckets
        .map((bucket) {
          final income = Money.format(
            bucket.incomeMinor,
            currencyCode: currencyCode,
            locale: locale,
          );
          final expenses = Money.format(
            bucket.expenseMinor,
            currencyCode: currencyCode,
            locale: locale,
          );
          return '${bucket.label}: income $income, expenses $expenses';
        })
        .join('. ');
    return 'Cashflow chart for ${summary.label}. $buckets.';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SectionCard(
      key: const Key('dashboard-cashflow-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PeriodMetrics(
            summary: summary,
            currencyCode: currencyCode,
            locale: locale,
          ),
          const Divider(height: 38),
          LayoutBuilder(
            builder: (context, constraints) {
              final heading = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cashflow trend',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Income and spending across this period',
                    style: TextStyle(color: palette.inkSoft, fontSize: 12),
                  ),
                ],
              );
              final legend = Wrap(
                spacing: 14,
                runSpacing: 8,
                children: [
                  _Legend(color: palette.green, label: 'Income'),
                  _Legend(color: palette.orange, label: 'Expenses'),
                ],
              );
              if (constraints.maxWidth < 520) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [heading, const SizedBox(height: 10), legend],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 16),
                  legend,
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          if (summary.buckets.isEmpty)
            Semantics(
              label: 'No cashflow chart data for the selected period',
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 220),
                child: const EmptyState(
                  icon: Icons.show_chart_rounded,
                  title: 'No chart data yet',
                  message:
                      'Add your first transaction to begin tracking cashflow.',
                ),
              ),
            )
          else
            Semantics(
              key: const Key('dashboard-cashflow-chart'),
              image: true,
              excludeSemantics: true,
              label: _chartSemantics(),
              child: SizedBox(
                height: 220,
                child: CustomPaint(
                  painter: _CashflowPainter(
                    summary.buckets,
                    gridColor: palette.border,
                    incomeColor: palette.green,
                    expenseColor: palette.orange,
                    labelColor: palette.muted,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: TextStyle(color: context.palette.muted, fontSize: 11.5),
      ),
    ],
  );
}

class _CashflowPainter extends CustomPainter {
  _CashflowPainter(
    this.buckets, {
    required this.gridColor,
    required this.incomeColor,
    required this.expenseColor,
    required this.labelColor,
  });

  final List<CashflowBucket> buckets;
  final Color gridColor;
  final Color incomeColor;
  final Color expenseColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    const chartTop = 8.0;
    const chartBottom = 25.0;
    final plotHeight = size.height - chartTop - chartBottom;
    final barBaseline = size.height - chartBottom;
    final grid = Paint()..color = gridColor.withValues(alpha: 0.75);
    for (var i = 0; i <= 4; i++) {
      final y = chartTop + plotHeight * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final maxValue = buckets
        .map((item) => math.max(item.incomeMinor, item.expenseMinor))
        .fold<int>(1, math.max);
    final slot = size.width / buckets.length;
    final barWidth = math.min(13.0, slot * 0.28);
    for (var i = 0; i < buckets.length; i++) {
      final x = slot * i + slot / 2;
      final incomeHeight = plotHeight * buckets[i].incomeMinor / maxValue;
      final expenseHeight = plotHeight * buckets[i].expenseMinor / maxValue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x - barWidth - 2,
            barBaseline - incomeHeight,
            barWidth,
            incomeHeight,
          ),
          const Radius.circular(4),
        ),
        Paint()..color = incomeColor,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x + 2,
            barBaseline - expenseHeight,
            barWidth,
            expenseHeight,
          ),
          const Radius.circular(4),
        ),
        Paint()..color = expenseColor,
      );
    }
    _paintSampledLabels(canvas, size, slot);
  }

  void _paintSampledLabels(Canvas canvas, Size size, double slot) {
    final sampleCount = math.min(6, buckets.length);
    final indices = <int>{};
    if (sampleCount == 1) {
      indices.add(0);
    } else {
      for (var i = 0; i < sampleCount; i++) {
        indices.add((i * (buckets.length - 1) / (sampleCount - 1)).round());
      }
    }
    final labelWidth = math.max(12.0, size.width / sampleCount - 7);
    for (final index in indices) {
      final painter = TextPainter(
        text: TextSpan(
          text: buckets[index].label,
          style: TextStyle(
            color: labelColor,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        maxLines: 1,
        ellipsis: '…',
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: labelWidth);
      final center = slot * index + slot / 2;
      final x = (center - painter.width / 2).clamp(
        0.0,
        math.max(0.0, size.width - painter.width),
      );
      painter.paint(canvas, Offset(x.toDouble(), size.height - painter.height));
    }
  }

  @override
  bool shouldRepaint(covariant _CashflowPainter oldDelegate) =>
      oldDelegate.buckets != buckets ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.incomeColor != incomeColor ||
      oldDelegate.expenseColor != expenseColor ||
      oldDelegate.labelColor != labelColor;
}

class _BudgetPanel extends StatelessWidget {
  const _BudgetPanel({
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
    final ratio = !summary.hasBudget || summary.budgetMinor == 0
        ? 0.0
        : (summary.expenseMinor / summary.budgetMinor).clamp(0.0, 1.0);
    final overspent = summary.hasBudget && summary.remainingBudgetMinor < 0;
    return SectionCard(
      key: const Key('dashboard-budget-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Budget pulse',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              StatusPill(
                label: !summary.hasBudget || summary.budgetMinor == 0
                    ? 'Not set'
                    : overspent
                    ? 'Over budget'
                    : 'On track',
                positive: !overspent,
                neutral: !summary.hasBudget || summary.budgetMinor == 0,
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            'Available for the selected period',
            style: TextStyle(color: palette.muted, fontSize: 12),
          ),
          const SizedBox(height: 24),
          Semantics(
            label: 'Budget utilization',
            value: !summary.hasBudget || summary.budgetMinor == 0
                ? 'Budget not set'
                : '${(ratio * 100).round()} percent used',
            child: ExcludeSemantics(
              child: Center(
                child: SizedBox(
                  width: 155,
                  height: 155,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: ratio,
                          strokeWidth: 12,
                          strokeCap: StrokeCap.round,
                          backgroundColor: palette.border,
                          color: overspent ? palette.red : palette.green,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(28),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                !summary.hasBudget || summary.budgetMinor == 0
                                    ? '—'
                                    : '${(ratio * 100).round()}%',
                                style: TextStyle(
                                  color: palette.ink,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                'used',
                                style: TextStyle(
                                  color: palette.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _moneyRow(
            'Budget',
            summary.hasBudget ? summary.budgetMinor : null,
            palette: palette,
          ),
          const SizedBox(height: 10),
          _moneyRow('Spent', summary.expenseMinor, palette: palette),
          const Divider(height: 24),
          _moneyRow(
            overspent ? 'Over by' : 'Remaining',
            summary.hasBudget ? summary.remainingBudgetMinor.abs() : null,
            strong: true,
            color: overspent ? palette.red : palette.greenDark,
            palette: palette,
          ),
        ],
      ),
    );
  }

  Widget _moneyRow(
    String label,
    int? value, {
    bool strong = false,
    Color? color,
    required AppPalette palette,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        flex: 3,
        child: Text(label, style: TextStyle(color: palette.muted)),
      ),
      const SizedBox(width: 8),
      Flexible(
        flex: 2,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: value == null
              ? Text('—', style: TextStyle(color: palette.muted))
              : MoneyLabel(
                  minorUnits: value,
                  currencyCode: currencyCode,
                  locale: locale,
                  style: TextStyle(
                    color: color ?? palette.ink,
                    fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
        ),
      ),
    ],
  );
}

class _InstallmentSummaryPanel extends StatelessWidget {
  const _InstallmentSummaryPanel({
    required this.summary,
    required this.controller,
    required this.currencyCode,
    required this.locale,
  });

  final _InstallmentMonthSummary summary;
  final AppController controller;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final monthLabel = DateFormat('MMMM y').format(summary.month);
    final semanticValue = summary.isAvailable
        ? '${Money.format(summary.monthlyTotalMinor!, currencyCode: currencyCode, locale: locale)} per month across ${summary.activeCount} active ${summary.activeCount == 1 ? 'plan' : 'plans'}'
        : 'Unavailable';
    return Semantics(
      key: const Key('dashboard-installment-summary'),
      container: true,
      explicitChildNodes: true,
      label: 'Monthly installment obligation for $monthLabel',
      value: semanticValue,
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: palette.violetSoft,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.calendar_month_outlined,
                    color: palette.violet,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Monthly installments',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Scheduled payment plans for $monthLabel',
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    palette.violetSoft,
                    Color.lerp(palette.surfaceMuted, palette.violetSoft, 0.35)!,
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: palette.violet.withValues(alpha: 0.16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TOTAL MONTHLY OBLIGATION',
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.65,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Container(
                    key: const Key('dashboard-installment-monthly-total'),
                    constraints: const BoxConstraints(minHeight: 38),
                    alignment: Alignment.centerLeft,
                    child: summary.isAvailable
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: MoneyLabel(
                              minorUnits: summary.monthlyTotalMinor!,
                              currencyCode: currencyCode,
                              locale: locale,
                              style: TextStyle(
                                color: palette.ink,
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.8,
                              ),
                            ),
                          )
                        : Text(
                            'Unavailable',
                            style: TextStyle(
                              color: palette.inkSoft,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _InstallmentSummaryChip(
                        icon: Icons.event_available_outlined,
                        label: monthLabel,
                      ),
                      Container(
                        key: const Key('dashboard-installment-active-count'),
                        child: _InstallmentSummaryChip(
                          icon: Icons.receipt_long_outlined,
                          label:
                              '${summary.activeCount} scheduled ${summary.activeCount == 1 ? 'plan' : 'plans'}',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 13),
            if (!summary.isAvailable)
              Text(
                summary.activeCount == 0
                    ? 'Installment history is unavailable.'
                    : 'A monthly amount is unavailable for one or more scheduled plans.',
                key: const Key('dashboard-installment-unavailable-state'),
                style: TextStyle(
                  color: palette.orange,
                  fontSize: 11.5,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              )
            else if (summary.activeCount == 0)
              Text(
                'No installments are scheduled for this month.',
                key: const Key('dashboard-installment-empty-state'),
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              )
            else
              Text(
                'Each scheduled plan contributes its saved monthly amount once. Purchase totals and card debt are not added here.',
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            if (summary.overduePlans.isNotEmpty) ...[
              const SizedBox(height: 20),
              Divider(color: palette.border, height: 1),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'OVERDUE',
                      style: TextStyle(
                        color: palette.red,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.65,
                      ),
                    ),
                  ),
                  Text(
                    '${summary.overduePlans.length}',
                    style: TextStyle(
                      color: palette.red,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Column(
                key: const Key('dashboard-overdue-installment-list'),
                children: [
                  for (
                    var index = 0;
                    index < summary.overduePlans.length;
                    index++
                  ) ...[
                    if (index > 0) const SizedBox(height: 10),
                    _InstallmentPlanRow(
                      plan: summary.overduePlans[index],
                      controller: controller,
                      currencyCode: currencyCode,
                      locale: locale,
                    ),
                  ],
                ],
              ),
            ],
            if (summary.plans.isNotEmpty) ...[
              const SizedBox(height: 20),
              Divider(color: palette.border, height: 1),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'THIS MONTH',
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.65,
                      ),
                    ),
                  ),
                  Text(
                    '${summary.activeCount}',
                    style: TextStyle(
                      color: palette.violet,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Column(
                key: const Key('dashboard-installment-plan-list'),
                children: [
                  for (
                    var index = 0;
                    index < summary.plans.length;
                    index++
                  ) ...[
                    if (index > 0) const SizedBox(height: 10),
                    _InstallmentPlanRow(
                      plan: summary.plans[index],
                      controller: controller,
                      currencyCode: currencyCode,
                      locale: locale,
                    ),
                  ],
                ],
              ),
            ],
            if (summary.upcomingPlans.isNotEmpty) ...[
              const SizedBox(height: 20),
              Divider(color: palette.border, height: 1),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'UPCOMING',
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.65,
                      ),
                    ),
                  ),
                  Text(
                    '${summary.upcomingPlans.length}',
                    style: TextStyle(
                      color: palette.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Column(
                key: const Key('dashboard-upcoming-installment-list'),
                children: [
                  for (
                    var index = 0;
                    index < summary.upcomingPlans.length;
                    index++
                  ) ...[
                    if (index > 0) const SizedBox(height: 10),
                    _InstallmentPlanRow(
                      plan: summary.upcomingPlans[index],
                      controller: controller,
                      currencyCode: currencyCode,
                      locale: locale,
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InstallmentSummaryChip extends StatelessWidget {
  const _InstallmentSummaryChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: context.palette.surface.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: context.palette.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: context.palette.violet),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.palette.inkSoft,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _InstallmentPlanRow extends StatelessWidget {
  const _InstallmentPlanRow({
    required this.plan,
    required this.controller,
    required this.currencyCode,
    required this.locale,
  });

  final _InstallmentPlanSummary plan;
  final AppController controller;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final monthlyLabel = plan.monthlyMinor == null
        ? 'Monthly amount unavailable'
        : '${Money.format(plan.monthlyMinor!, currencyCode: currencyCode, locale: locale)} per month';
    final progressLabel = plan.isUpcomingCreditCardSchedule
        ? 'Billing ${plan.monthNumber} of ${plan.totalMonths} · ${DateFormat('MMM d').format(plan.dueOn)}'
        : plan.isSavedPlan
        ? plan.isOverdue
              ? 'Payment ${plan.monthNumber} overdue since ${DateFormat('MMM d, y').format(plan.dueOn)}'
              : plan.isUpcoming
              ? plan.sourcePlan!.paidInstallments == 0
                    ? 'Starts ${DateFormat('MMM d').format(plan.dueOn)}'
                    : 'Payment ${plan.monthNumber} due ${DateFormat('MMM d').format(plan.dueOn)}'
              : 'Payment ${plan.monthNumber} of ${plan.totalMonths}'
        : 'Month ${plan.monthNumber} of ${plan.totalMonths}';
    final remainingLabel = plan.isUpcomingCreditCardSchedule
        ? plan.remainingAfterCurrent == 0
              ? 'Credit-card billing schedule · final billing'
              : 'Credit-card billing schedule · ${plan.remainingAfterCurrent} later'
        : plan.isSavedPlan
        ? '${plan.remainingInstallments} payments remaining'
        : '${plan.remainingAfterCurrent} remaining after this month';
    final sourcePlan = plan.sourcePlan;
    final downPaymentLabel = sourcePlan?.hasDownPayment == true
        ? 'Down payment ${Money.format(sourcePlan!.downPaymentMinor, currencyCode: currencyCode, locale: locale)} paid${sourcePlan.downPaymentPaidOn == null ? '' : ' ${DateFormat('MMM d, y').format(sourcePlan.downPaymentPaidOn!)}'}'
        : null;
    final progressNumerator = plan.isUpcomingCreditCardSchedule
        ? plan.monthNumber - 1
        : plan.isSavedPlan
        ? plan.paidInstallments
        : plan.monthNumber;
    Widget progressBar = ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: LinearProgressIndicator(
        value: (progressNumerator / plan.totalMonths).clamp(0.0, 1.0),
        minHeight: 6,
        color: plan.visual.accent,
        backgroundColor: palette.border,
      ),
    );
    if (plan.isUpcomingCreditCardSchedule) {
      progressBar = Semantics(
        label: 'Credit-card billing schedule position',
        value:
            'Billing ${plan.monthNumber} of ${plan.totalMonths} is next on the saved schedule',
        child: ExcludeSemantics(child: progressBar),
      );
    }
    return Semantics(
      key: ValueKey(plan.rowKey),
      container: true,
      label: '${plan.name}, ${plan.accountContext}',
      value:
          '$monthlyLabel. $progressLabel. $remainingLabel.${downPaymentLabel == null ? '' : ' $downPaymentLabel.'}',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: palette.surfaceMuted,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked =
                    constraints.maxWidth < 250 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.35;
                final identity = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InstallmentAccountMiniCard(plan: plan),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.ink,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            plan.accountContext,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 10.5,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                final amount = _InstallmentPlanMonthlyAmount(
                  monthlyMinor: plan.monthlyMinor,
                  currencyCode: currencyCode,
                  locale: locale,
                );
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [identity, const SizedBox(height: 11), amount],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: identity),
                    const SizedBox(width: 10),
                    SizedBox(width: 96, child: amount),
                  ],
                );
              },
            ),
            const SizedBox(height: 13),
            progressBar,
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  progressLabel,
                  style: TextStyle(
                    color: palette.inkSoft,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '· $remainingLabel',
                  style: TextStyle(color: palette.muted, fontSize: 10.5),
                ),
              ],
            ),
            if (downPaymentLabel != null) ...[
              const SizedBox(height: 9),
              Container(
                key: ValueKey('dashboard-installment-down-payment-${plan.id}'),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                decoration: BoxDecoration(
                  color: palette.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: palette.success.withValues(alpha: 0.24),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 14,
                      color: palette.success,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        downPaymentLabel,
                        style: TextStyle(
                          color: palette.success,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (plan.isSavedPlan && plan.showActions) ...[
              const SizedBox(height: 11),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (plan.sourcePlan!.isActive)
                    FilledButton.tonalIcon(
                      key: ValueKey(plan.recordPaymentKey),
                      onPressed: controller.hasLiveConnection
                          ? () => showInstallmentPaymentDialog(
                              context,
                              controller,
                              plan: plan.sourcePlan!,
                            )
                          : null,
                      icon: const Icon(Icons.payments_outlined, size: 16),
                      label: const Text('Record payment'),
                    ),
                  PopupMenuButton<String>(
                    key: ValueKey(plan.manageMenuKey),
                    enabled: controller.hasLiveConnection,
                    tooltip: controller.hasLiveConnection
                        ? 'Manage installment plan'
                        : 'Reconnect to manage this plan',
                    onSelected: (action) {
                      if (action == 'edit') {
                        showInstallmentPlanEditor(
                          context,
                          controller,
                          plan: plan.sourcePlan!,
                        );
                      } else if (action == 'archive') {
                        _confirmArchiveInstallmentPlan(
                          context,
                          controller,
                          plan.sourcePlan!,
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      if (plan.sourcePlan!.isActive)
                        PopupMenuItem(
                          value: 'edit',
                          child: Text(
                            plan.sourcePlan!.hasPayments
                                ? 'Edit details'
                                : 'Edit plan',
                          ),
                        ),
                      PopupMenuItem(
                        value: 'archive',
                        child: const Text('Stop plan'),
                      ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: palette.border),
                      ),
                      child: const Icon(Icons.more_horiz_rounded, size: 18),
                    ),
                  ),
                ],
              ),
              if (!controller.hasLiveConnection) ...[
                const SizedBox(height: 8),
                Text(
                  'Reconnect to record a payment or manage this plan.',
                  style: TextStyle(
                    color: palette.orange,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _InstallmentAccountMiniCard extends StatelessWidget {
  const _InstallmentAccountMiniCard({required this.plan});

  final _InstallmentPlanSummary plan;

  @override
  Widget build(BuildContext context) => Container(
    width: 58,
    height: 40,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(9),
      boxShadow: [
        BoxShadow(
          color: plan.visual.primary.withValues(alpha: 0.22),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: DecoratedBox(
        key: ValueKey(
          plan.isSavedPlan
              ? 'dashboard-installment-plan-card-design-${plan.id}'
              : '${plan.legacyCardKeyPrefix}-card-design-${plan.id}',
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [plan.visual.primary, plan.visual.secondary],
          ),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: plan.visual.foreground.withValues(alpha: 0.2),
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: CustomPaint(
                key: ValueKey(
                  plan.isSavedPlan
                      ? 'dashboard-installment-plan-card-pattern-${plan.id}'
                      : '${plan.legacyCardKeyPrefix}-card-pattern-${plan.id}',
                ),
                painter: BankCardPatternPainter(
                  pattern: plan.pattern,
                  accent: plan.visual.accent,
                  foreground: plan.visual.foreground,
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    plan.shortMark,
                    key: ValueKey(
                      plan.isSavedPlan
                          ? 'dashboard-installment-plan-card-mark-${plan.id}'
                          : '${plan.legacyCardKeyPrefix}-card-mark-${plan.id}',
                    ),
                    maxLines: 1,
                    style: TextStyle(
                      color: plan.visual.foreground,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.45,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _InstallmentPlanMonthlyAmount extends StatelessWidget {
  const _InstallmentPlanMonthlyAmount({
    required this.monthlyMinor,
    required this.currencyCode,
    required this.locale,
  });

  final int? monthlyMinor;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (monthlyMinor == null) {
      return Text(
        'Monthly amount unavailable',
        style: TextStyle(
          color: palette.orange,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          height: 1.3,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: MoneyLabel(
            minorUnits: monthlyMinor!,
            currencyCode: currencyCode,
            locale: locale,
            style: TextStyle(
              color: palette.ink,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '/ month',
          style: TextStyle(
            color: palette.muted,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _CategoryPanel extends StatelessWidget {
  const _CategoryPanel({
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
    key: const Key('dashboard-category-panel'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Where your money went',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Top expense categories',
          style: TextStyle(color: context.palette.muted, fontSize: 12),
        ),
        const SizedBox(height: 18),
        if (items.isEmpty)
          const EmptyState(
            icon: Icons.donut_large_rounded,
            title: 'No expenses yet',
            message: 'Expense categories will appear here.',
          )
        else
          ...items.take(6).map((item) {
            final share = total == 0 ? 0.0 : item.amountMinor / total;
            return Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
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
                      Expanded(
                        child: Text(
                          item.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      MoneyLabel(
                        minorUnits: item.amountMinor,
                        currencyCode: currencyCode,
                        locale: locale,
                        style: TextStyle(
                          color: context.palette.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: share.clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor: context.palette.border,
                      color: colorFromHex(
                        item.color,
                        fallback: context.palette.green,
                        legacyReplacement: context.palette.greenDark,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    ),
  );
}

class _NextMonthCreditCardBillingPanel extends StatelessWidget {
  const _NextMonthCreditCardBillingPanel({
    required this.summary,
    required this.currencyCode,
    required this.locale,
  });

  final _NextMonthCreditCardBillingSummary summary;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) => SectionCard(
    key: const Key('dashboard-next-month-credit-card-billing-panel'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Next credit-card billing',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Projected from each active card’s recorded debt at its nearest '
          'upcoming statement close. Installment principal scheduled after '
          'that close is excluded; future purchases and bank fees are not '
          'included.',
          style: TextStyle(
            color: context.palette.muted,
            fontSize: 12,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        _NextMonthCreditCardBillingTotal(
          summary: summary,
          currencyCode: currencyCode,
          locale: locale,
        ),
        const SizedBox(height: 16),
        if (!summary.historyAvailable)
          const EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Card billing unavailable',
            message:
                'Reconnect and load complete account and transaction data before '
                'showing projected card debt.',
          )
        else if (summary.cards.isEmpty)
          EmptyState(
            icon: Icons.credit_card_off_rounded,
            title: 'No credit cards yet',
            message:
                'Add a credit card to see its next projected statement debt.',
          )
        else
          LayoutBuilder(
            key: const Key('dashboard-next-month-credit-card-billing-list'),
            builder: (context, constraints) {
              final useTwoColumns =
                  constraints.maxWidth >= 600 &&
                  MediaQuery.textScalerOf(context).scale(1) <= 1.35;
              const spacing = 12.0;
              final width = useTwoColumns
                  ? (constraints.maxWidth - spacing) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final card in summary.cards)
                    SizedBox(
                      width: width,
                      child: _NextMonthCreditCardBillingCardView(
                        card: card,
                        currencyCode: currencyCode,
                        locale: locale,
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    ),
  );
}

class _NextMonthCreditCardBillingTotal extends StatelessWidget {
  const _NextMonthCreditCardBillingTotal({
    required this.summary,
    required this.currencyCode,
    required this.locale,
  });

  final _NextMonthCreditCardBillingSummary summary;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: context.palette.infoSoft,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: context.palette.greenDark.withValues(alpha: 0.24),
      ),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 330 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.35;
        final label = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TOTAL NEXT STATEMENT DEBT',
              key: const Key(
                'dashboard-next-month-credit-card-billing-total-label',
              ),
              style: TextStyle(
                color: context.palette.greenDark,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Across ${summary.cards.length} '
              '${summary.cards.length == 1 ? 'card' : 'cards'}',
              style: TextStyle(
                color: context.palette.inkSoft,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        );
        final total = summary.isAvailable
            ? FittedBox(
                fit: BoxFit.scaleDown,
                alignment: stacked
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: MoneyLabel(
                  key: const Key(
                    'dashboard-next-month-credit-card-billing-total',
                  ),
                  minorUnits: summary.totalMinor!,
                  currencyCode: currencyCode,
                  locale: locale,
                  style: TextStyle(
                    color: context.palette.ink,
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                  ),
                ),
              )
            : Text(
                'Unavailable',
                key: const Key(
                  'dashboard-next-month-credit-card-billing-total',
                ),
                style: TextStyle(
                  color: context.palette.muted,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [label, const SizedBox(height: 10), total],
          );
        }
        return Row(
          children: [
            Expanded(child: label),
            const SizedBox(width: 16),
            Flexible(child: total),
          ],
        );
      },
    ),
  );
}

class _NextMonthCreditCardBillingCardView extends StatelessWidget {
  const _NextMonthCreditCardBillingCardView({
    required this.card,
    required this.currencyCode,
    required this.locale,
  });

  final _NextMonthCreditCardBillingCard card;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final account = card.account;
    final visual = card.visual;
    final foreground = visual.foreground;
    final shortMark = card.design.key == 'other'
        ? accountCardShortMark(account.type)
        : card.design.shortMark;
    final cutoffLabel = card.cycle.usesMonthEndEstimate
        ? 'Estimated month-end close '
              '${DateFormat('MMM d').format(card.cycle.statementOn)}'
        : 'Statement closes '
              '${DateFormat('MMM d').format(card.cycle.statementOn)}';
    final dueLabel = card.cycle.dueOn == null
        ? 'Due date not set'
        : 'Due ${DateFormat('MMM d').format(card.cycle.dueOn!)}';
    return Semantics(
      container: true,
      label:
          '${account.displayName}. Projected total debt '
          '${card.totalMinor == null ? 'unavailable' : Money.format(card.totalMinor!, currencyCode: currencyCode, locale: locale)}. '
          '$cutoffLabel. $dueLabel.',
      child: Container(
        key: ValueKey(
          'dashboard-next-month-credit-card-billing-card-${account.id}',
        ),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [visual.primary, visual.secondary],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: visual.primary.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  key: ValueKey(
                    'dashboard-next-month-credit-card-billing-design-'
                    '${account.id}',
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [visual.primary, visual.secondary],
                    ),
                  ),
                  child: CustomPaint(
                    key: ValueKey(
                      'dashboard-next-month-credit-card-billing-pattern-'
                      '${account.id}',
                    ),
                    painter: BankCardPatternPainter(
                      pattern: card.design.pattern,
                      accent: visual.accent,
                      foreground: foreground,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shortMark,
                              key: ValueKey(
                                'dashboard-next-month-credit-card-billing-'
                                'mark-${account.id}',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: foreground,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              account.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: foreground.withValues(alpha: 0.82),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      CustomPaint(
                        size: const Size(38, 27),
                        painter: _DashboardCardChipPainter(
                          tint: visual.accent,
                          foreground: foreground,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Projected total debt',
                    style: TextStyle(
                      color: foreground.withValues(alpha: 0.78),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (card.totalMinor case final amount?)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: MoneyLabel(
                        minorUnits: amount,
                        currencyCode: currencyCode,
                        locale: locale,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                    )
                  else
                    Text(
                      'Amount unavailable',
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  const SizedBox(height: 7),
                  Text(
                    '$cutoffLabel · $dueLabel',
                    key: ValueKey(
                      'dashboard-next-month-credit-card-billing-cycle-'
                      '${account.id}',
                    ),
                    style: TextStyle(
                      color: foreground.withValues(alpha: 0.76),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
