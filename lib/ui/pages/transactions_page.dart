import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/offline_transactions.dart';
import '../../models/domain_models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../account_designs.dart';
import '../widgets/common.dart';

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  String filter = 'all';
  String search = '';
  late String period;
  late DateTime periodAnchor;

  @override
  void initState() {
    super.initState();
    period =
        const {
          'week',
          'month',
          'year',
        }.contains(widget.controller.selectedPeriod)
        ? widget.controller.selectedPeriod
        : 'month';
    final anchor = widget.controller.anchor;
    periodAnchor = DateTime(anchor.year, anchor.month, anchor.day);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final scope = widget.controller.selectedFinanceScope;
    final isJoint = scope == FinanceScope.joint;
    final canAdd =
        widget.controller.hasSavedSettings &&
        widget.controller.hasSavedTransactions &&
        (!widget.controller.offlineTransactionsEnabled ||
            widget.controller.canSaveOfflineTransactions);
    final ordinaryActionsBlocked =
        widget.controller.offlineTransactionsEnabled &&
        !widget.controller.canSaveOfflineTransactions;
    final attentionItems = widget.controller.offlineTransactionOperations
        .where(
          (operation) => operation.scope == scope && operation.needsAttention,
        )
        .toList();
    final range = _transactionPeriodRange(
      period,
      periodAnchor,
      widget.controller.settings.weekStartsOn,
    );
    final periodItems = widget.controller.transactions.where((transaction) {
      if (transaction.scope != scope) return false;
      final date = DateTime(
        transaction.occurredOn.year,
        transaction.occurredOn.month,
        transaction.occurredOn.day,
      );
      return !date.isBefore(range.start) && !date.isAfter(range.end);
    }).toList();
    final items = periodItems.where((transaction) {
      if (filter != 'all' && transaction.kind != filter) return false;
      final query = search.trim().toLowerCase();
      if (query.isEmpty) return true;
      return _matchesSearch(transaction, query);
    }).toList();
    final totalIncomeMinor = periodItems
        .where((transaction) => transaction.kind == 'income')
        .fold<int>(0, (total, transaction) => total + transaction.amountMinor);
    final totalExpenseMinor = periodItems
        .where((transaction) => transaction.kind == 'expense')
        .fold<int>(0, (total, transaction) => total + transaction.amountMinor);
    return SingleChildScrollView(
      padding: responsivePagePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: isJoint ? 'Joint transactions' : 'Personal transactions',
            subtitle: isJoint
                ? 'Track the income and expenses you manage together.'
                : 'Track your income and expenses, wherever you are.',
            actions: [
              FinanceScopeSelector(
                selected: scope,
                onSelected: widget.controller.setFinanceScope,
              ),
              OutlinedButton.icon(
                onPressed: widget.controller.refreshTransactions,
                icon: const Icon(Icons.refresh_rounded, size: 19),
                label: const Text('Refresh'),
              ),
              OutlinedButton.icon(
                onPressed: canAdd
                    ? () => showTransactionEditor(context, widget.controller)
                    : null,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add transaction'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FinanceScopeNotice(scope: scope),
          const SizedBox(height: 18),
          _TransactionPeriodToolbar(
            period: period,
            range: range,
            onPeriodSelected: (value) => setState(() => period = value),
            onPrevious: () => _movePeriod(-1),
            onNext: () => _movePeriod(1),
            onToday: () => setState(() {
              final today = DateTime.now();
              periodAnchor = DateTime(today.year, today.month, today.day);
            }),
          ),
          const SizedBox(height: 24),
          if (!widget.controller.hasSavedTransactions) ...[
            SectionCard(
              child: EmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'Transaction history is not saved for this money scope',
                message: 'Your transaction history could not be read. Try refreshing your saved data.',
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (widget.controller.hasSavedSettings &&
              widget.controller.hasSavedTransactions &&
              attentionItems.isNotEmpty) ...[
            _OfflineChangesPanel(
              controller: widget.controller,
              operations: attentionItems,
            ),
            const SizedBox(height: 18),
          ],
          LayoutBuilder(
            builder: (context, pageConstraints) {
              final ledger = SectionCard(
                key: const Key('transaction-ledger'),
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final searchField = TextField(
                            onChanged: (value) =>
                                setState(() => search = value),
                            decoration: const InputDecoration(
                              hintText:
                                  'Search payee, note, account, or category…',
                              prefixIcon: Icon(Icons.search_rounded),
                            ),
                          );
                          final filters = SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'all', label: Text('All')),
                              ButtonSegment(
                                value: 'income',
                                label: Text('Income'),
                              ),
                              ButtonSegment(
                                value: 'expense',
                                label: Text('Expenses'),
                              ),
                            ],
                            selected: {filter},
                            onSelectionChanged: (value) =>
                                setState(() => filter = value.first),
                            showSelectedIcon: false,
                          );
                          if (constraints.maxWidth < 680) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                searchField,
                                const SizedBox(height: 12),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: filters,
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: searchField),
                              const SizedBox(width: 12),
                              filters,
                            ],
                          );
                        },
                      ),
                    ),
                    const Divider(),
                    if (!widget.controller.hasSavedTransactions)
                      const SizedBox.shrink()
                    else if (items.isEmpty)
                      EmptyState(
                        icon: Icons.receipt_long_rounded,
                        title: search.isEmpty && filter == 'all'
                            ? isJoint
                                  ? 'No Joint transactions yet'
                                  : 'No Personal transactions yet'
                            : 'No matching transactions',
                        message: search.isEmpty && filter == 'all'
                            ? 'Record your first income or expense to begin.'
                            : 'Try adjusting your search or filter.',
                        action: search.isEmpty && filter == 'all' && canAdd
                            ? FilledButton.icon(
                                onPressed: () => showTransactionEditor(
                                  context,
                                  widget.controller,
                                ),
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Add transaction'),
                              )
                            : null,
                      )
                    else
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 1040),
                          child: DataTable(
                            horizontalMargin: 18,
                            columnSpacing: 24,
                            headingRowHeight: 46,
                            dataRowMinHeight: 88,
                            dataRowMaxHeight:
                                118 + (textScale - 1).clamp(0.0, 2.0) * 72,
                            headingRowColor: WidgetStateProperty.all(
                              palette.surfaceMuted,
                            ),
                            headingTextStyle: TextStyle(
                              color: palette.muted,
                              fontWeight: FontWeight.w700,
                              fontSize: 11.5,
                            ),
                            dataTextStyle: TextStyle(
                              color: palette.inkSoft,
                              fontSize: 13,
                            ),
                            columns: const [
                              DataColumn(
                                label: SizedBox(
                                  width: 190,
                                  child: Text('AMOUNT'),
                                ),
                              ),
                              DataColumn(
                                label: SizedBox(
                                  width: 150,
                                  child: Text('PAYMENT TYPE'),
                                ),
                              ),
                              DataColumn(
                                label: SizedBox(
                                  width: 330,
                                  child: Text('PAYMENT DETAILS'),
                                ),
                              ),
                              DataColumn(
                                label: SizedBox(
                                  width: 190,
                                  child: Text('STATUS'),
                                ),
                              ),
                              DataColumn(label: SizedBox(width: 48)),
                            ],
                            rows: items.map((transaction) {
                              final offlineOperation = widget.controller
                                  .offlineOperationFor(transaction);
                              final frozen =
                                  offlineOperation?.isFrozen ?? false;
                              final locked =
                                  transaction.isManagedTransaction ||
                                  frozen ||
                                  ordinaryActionsBlocked;
                              return DataRow(
                                key: ValueKey(
                                  'transaction-row-${transaction.id}',
                                ),
                                cells: [
                                  DataCell(
                                    _LedgerAmountCell(
                                      transaction: transaction,
                                      currencyCode:
                                          widget.controller.currencyCode,
                                      locale: widget.controller.locale,
                                    ),
                                  ),
                                  DataCell(
                                    _LedgerPaymentTypeCell(
                                      transaction: transaction,
                                    ),
                                  ),
                                  DataCell(
                                    _LedgerDetailsCell(
                                      transaction: transaction,
                                      currencyCode:
                                          widget.controller.currencyCode,
                                      locale: widget.controller.locale,
                                    ),
                                  ),
                                  DataCell(
                                    _LedgerStatusCell(
                                      transaction: transaction,
                                      operation: offlineOperation,
                                    ),
                                  ),
                                  DataCell(
                                    _LedgerActionCell(
                                      locked: locked,
                                      lockedMessage: locked
                                          ? _lockedTransactionMessage(
                                              transaction,
                                              offlineOperation:
                                                  offlineOperation,
                                              ordinaryActionsBlocked:
                                                  ordinaryActionsBlocked,
                                            )
                                          : null,
                                      onEdit: locked
                                          ? null
                                          : () => showTransactionEditor(
                                              context,
                                              widget.controller,
                                              existing: transaction,
                                            ),
                                      onDelete: locked
                                          ? null
                                          : () => _delete(context, transaction),
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
              final aside = _TransactionAside(
                hasData: widget.controller.hasSavedTransactions,
                scope: scope,
                range: range,
                transactions: periodItems,
                accounts: widget.controller.accounts,
                totalIncomeMinor: totalIncomeMinor,
                totalExpenseMinor: totalExpenseMinor,
                currencyCode: widget.controller.currencyCode,
                locale: widget.controller.locale,
              );
              if (pageConstraints.maxWidth >= 1080) {
                final asideWidth = (pageConstraints.maxWidth * 0.32).clamp(
                  320.0,
                  380.0,
                );
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: ledger),
                    const SizedBox(width: 18),
                    SizedBox(width: asideWidth, child: aside),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [aside, const SizedBox(height: 18), ledger],
              );
            },
          ),
        ],
      ),
    );
  }

  void _movePeriod(int direction) => setState(() {
    periodAnchor = switch (period) {
      'week' => DateTime(
        periodAnchor.year,
        periodAnchor.month,
        periodAnchor.day + 7 * direction,
      ),
      'year' => DateTime(periodAnchor.year + direction, 1, 1),
      _ => DateTime(periodAnchor.year, periodAnchor.month + direction, 1),
    };
  });

  bool _matchesSearch(TransactionRecord transaction, String query) {
    final split = transaction.jointSplitExpense;
    return <String?>[
      split?.payee,
      split?.note,
      split?.categoryNameSnapshot,
      split?.categoryName,
      split?.category?.name,
      split?.firstAccountNameSnapshot,
      split?.firstAccountName,
      split?.firstAccount?.displayName,
      split?.secondAccountNameSnapshot,
      split?.secondAccountName,
      split?.secondAccount?.displayName,
      transaction.payee,
      transaction.note,
      transaction.isInstallment ? 'installment' : null,
      transaction.category?.name,
      transaction.account?.name,
    ].whereType<String>().any((value) => value.toLowerCase().contains(query));
  }

  Future<void> _delete(
    BuildContext context,
    TransactionRecord transaction,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: Text(
          '${transaction.payee?.isNotEmpty == true ? transaction.payee : transaction.category?.name ?? 'Transaction'} · '
          '${Money.format(transaction.amountMinor, currencyCode: widget.controller.currencyCode, locale: widget.controller.locale)} · '
          '${DateFormat('MMM d, y').format(transaction.occurredOn)}\n\n'
          '${widget.controller.offlineTransactionsEnabled ? 'This removal is saved on this device first and stays pending until sync. Once syncing begins, the exact request is locked for safe retry.' : 'This cannot be undone and will update balances, cashflow, and cutoff reports.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.palette.orange,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await widget.controller.deleteTransaction(transaction);
      if (context.mounted) {
        showSuccess(
          context,
          widget.controller.offlineTransactionsEnabled
              ? 'Removal saved on this device — sync pending.'
              : 'Transaction deleted.',
        );
      }
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }
}

typedef _TransactionPeriodRange = ({
  DateTime start,
  DateTime end,
  String label,
});

_TransactionPeriodRange _transactionPeriodRange(
  String period,
  DateTime anchor,
  int configuredWeekStart,
) {
  final date = DateTime(anchor.year, anchor.month, anchor.day);
  if (period == 'year') {
    final start = DateTime(date.year, 1, 1);
    final end = DateTime(date.year, 12, 31);
    return (start: start, end: end, label: DateFormat('y').format(start));
  }
  if (period == 'week') {
    final carbonWeekStart = configuredWeekStart >= 0 && configuredWeekStart <= 6
        ? configuredWeekStart
        : 1;
    final dartWeekStart = carbonWeekStart == 0
        ? DateTime.sunday
        : carbonWeekStart;
    final offset = (date.weekday - dartWeekStart + 7) % 7;
    final start = DateTime(date.year, date.month, date.day - offset);
    final end = DateTime(start.year, start.month, start.day + 6);
    return (start: start, end: end, label: _transactionRangeLabel(start, end));
  }
  final start = DateTime(date.year, date.month, 1);
  final end = DateTime(date.year, date.month + 1, 0);
  return (start: start, end: end, label: DateFormat('MMMM y').format(start));
}

String _transactionRangeLabel(DateTime start, DateTime end) {
  if (start.year != end.year) {
    return '${DateFormat('MMM d, y').format(start)} – ${DateFormat('MMM d, y').format(end)}';
  }
  if (start.month == end.month) {
    return '${DateFormat('MMM d').format(start)} – ${DateFormat('d, y').format(end)}';
  }
  return '${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d, y').format(end)}';
}

String _transactionRangeDates(_TransactionPeriodRange range) =>
    '${DateFormat('MMM d').format(range.start)} – ${DateFormat('MMM d, y').format(range.end)}';

class _TransactionPeriodToolbar extends StatelessWidget {
  const _TransactionPeriodToolbar({
    required this.period,
    required this.range,
    required this.onPeriodSelected,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final String period;
  final _TransactionPeriodRange range;
  final ValueChanged<String> onPeriodSelected;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final picker = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<String>(
        key: const Key('transaction-period-selector'),
        segments: const [
          ButtonSegment(
            value: 'week',
            label: Text('Week', key: Key('transaction-period-week')),
          ),
          ButtonSegment(
            value: 'month',
            label: Text('Month', key: Key('transaction-period-month')),
          ),
          ButtonSegment(
            value: 'year',
            label: Text('Year', key: Key('transaction-period-year')),
          ),
        ],
        selected: {period},
        onSelectionChanged: (value) => onPeriodSelected(value.first),
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
      ),
    );
    Widget rangeDisplay() => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          range.label,
          key: const Key('transaction-period-label'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.ink, fontWeight: FontWeight.w700),
        ),
        Text(
          _transactionRangeDates(range),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.muted, fontSize: 11),
        ),
      ],
    );
    Widget previousButton() => IconButton(
      key: const Key('transaction-period-previous'),
      onPressed: onPrevious,
      tooltip: 'Previous period',
      icon: const Icon(Icons.chevron_left_rounded),
    );
    Widget nextButton() => IconButton(
      key: const Key('transaction-period-next'),
      onPressed: onNext,
      tooltip: 'Next period',
      icon: const Icon(Icons.chevron_right_rounded),
    );
    final navigation = LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  previousButton(),
                  Expanded(child: rangeDisplay()),
                  nextButton(),
                ],
              ),
              TextButton(onPressed: onToday, child: const Text('Today')),
            ],
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            previousButton(),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 150, maxWidth: 230),
                child: rangeDisplay(),
              ),
            ),
            nextButton(),
            const SizedBox(width: 4),
            TextButton(onPressed: onToday, child: const Text('Today')),
          ],
        );
      },
    );
    return SectionCard(
      key: const Key('transaction-period-toolbar'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                picker,
                const SizedBox(height: 10),
                const Divider(),
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
}

class _TransactionAside extends StatelessWidget {
  const _TransactionAside({
    required this.hasData,
    required this.scope,
    required this.range,
    required this.transactions,
    required this.accounts,
    required this.totalIncomeMinor,
    required this.totalExpenseMinor,
    required this.currencyCode,
    required this.locale,
  });

  final bool hasData;
  final FinanceScope scope;
  final _TransactionPeriodRange range;
  final List<TransactionRecord> transactions;
  final List<Account> accounts;
  final int totalIncomeMinor;
  final int totalExpenseMinor;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final accountUsage = _accountUsageSummaries(transactions, accounts, scope);
    final categories = _expenseCategorySummaries(transactions);
    final insightCards = [
      _AccountActivityCard(
        hasData: hasData,
        range: range,
        summaries: accountUsage,
        currencyCode: currencyCode,
        locale: locale,
      ),
      _WhereMoneyWentCard(
        hasData: hasData,
        range: range,
        categories: categories,
        currencyCode: currencyCode,
        locale: locale,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          _TransactionSummaryCard(
            hasData: hasData,
            range: range,
            transactionCount: transactions.length,
            totalIncomeMinor: totalIncomeMinor,
            totalExpenseMinor: totalExpenseMinor,
            currencyCode: currencyCode,
            locale: locale,
          ),
          const SizedBox(height: 18),
          if (constraints.maxWidth >= 700)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: insightCards.first),
                const SizedBox(width: 18),
                Expanded(child: insightCards.last),
              ],
            )
          else ...[
            insightCards.first,
            const SizedBox(height: 18),
            insightCards.last,
          ],
        ],
      ),
    );
  }
}

class _TransactionSummaryCard extends StatelessWidget {
  const _TransactionSummaryCard({
    required this.hasData,
    required this.range,
    required this.transactionCount,
    required this.totalIncomeMinor,
    required this.totalExpenseMinor,
    required this.currencyCode,
    required this.locale,
  });

  final bool hasData;
  final _TransactionPeriodRange range;
  final int transactionCount;
  final int totalIncomeMinor;
  final int totalExpenseMinor;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final netMinor = totalIncomeMinor - totalExpenseMinor;
    final incomeText = Money.format(
      totalIncomeMinor,
      currencyCode: currencyCode,
      locale: locale,
    );
    final expenseText = Money.format(
      totalExpenseMinor,
      currencyCode: currencyCode,
      locale: locale,
    );
    final netText = Money.format(
      netMinor,
      currencyCode: currencyCode,
      locale: locale,
    );
    return SectionCard(
      key: const Key('transaction-period-summary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Period summary',
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  range.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(color: palette.muted, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            hasData
                ? '$transactionCount ${transactionCount == 1 ? 'transaction' : 'transactions'} in this period'
                : 'Saved transaction history is unavailable',
            style: TextStyle(color: palette.muted, fontSize: 11.5),
          ),
          const SizedBox(height: 18),
          if (!hasData)
            const _TransactionDataUnavailable(
              message: 'Refresh saved data to calculate income and expenses.',
            )
          else
            Semantics(
              container: true,
              label:
                  'Selected period totals. Total income $incomeText. Total expenses $expenseText. Net cashflow $netText.',
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final chart = Semantics(
                    key: const Key('transaction-summary-donut'),
                    label: 'Income and expense donut chart',
                    image: true,
                    child: SizedBox.square(
                      dimension: 112,
                      child: CustomPaint(
                        painter: _IncomeExpenseDonutPainter(
                          incomeMinor: totalIncomeMinor,
                          expenseMinor: totalExpenseMinor,
                          trackColor: palette.border,
                          incomeColor: palette.cyan,
                          expenseColor: palette.violet,
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'NET',
                                style: TextStyle(
                                  color: palette.muted,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Icon(
                                netMinor >= 0
                                    ? Icons.trending_up_rounded
                                    : Icons.trending_down_rounded,
                                size: 19,
                                color: netMinor >= 0
                                    ? palette.success
                                    : palette.red,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                  final totals = Column(
                    children: [
                      _SummaryTotal(
                        key: const Key('transaction-total-income'),
                        label: 'Total income',
                        amount: incomeText,
                        color: palette.cyan,
                      ),
                      const SizedBox(height: 13),
                      _SummaryTotal(
                        key: const Key('transaction-total-expense'),
                        label: 'Total expenses',
                        amount: expenseText,
                        color: palette.violet,
                      ),
                      const SizedBox(height: 13),
                      _SummaryTotal(
                        key: const Key('transaction-total-net'),
                        label: 'Net cashflow',
                        amount: netText,
                        color: netMinor >= 0 ? palette.success : palette.red,
                      ),
                    ],
                  );
                  if (constraints.maxWidth < 275) {
                    return Column(
                      children: [chart, const SizedBox(height: 18), totals],
                    );
                  }
                  return Row(
                    children: [
                      chart,
                      const SizedBox(width: 18),
                      Expanded(child: totals),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryTotal extends StatelessWidget {
  const _SummaryTotal({
    super.key,
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final String amount;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(top: 5),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                amount,
                style: TextStyle(
                  color: context.palette.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _AccountUsageSummary {
  const _AccountUsageSummary({
    required this.accountId,
    required this.name,
    required this.type,
    required this.usageCount,
    required this.activityMinor,
    required this.netFlowMinor,
    required this.latestOccurrence,
    this.account,
  });

  final int accountId;
  final String name;
  final String type;
  final int usageCount;
  final int activityMinor;
  final int netFlowMinor;
  final DateTime latestOccurrence;
  final Account? account;
}

class _MutableAccountUsage {
  _MutableAccountUsage({required this.accountId, Account? initialAccount})
    : account = initialAccount,
      name = initialAccount?.displayName ?? '',
      type = initialAccount?.type ?? 'other';

  final int accountId;
  Account? account;
  String name;
  String type;
  int usageCount = 0;
  int activityMinor = 0;
  int netFlowMinor = 0;
  DateTime latestOccurrence = DateTime.fromMillisecondsSinceEpoch(0);

  void add({
    required Account? resolvedAccount,
    required String fallbackName,
    required int amountMinor,
    required int signedFlowMinor,
    required DateTime occurredOn,
  }) {
    usageCount += 1;
    activityMinor += amountMinor.abs();
    netFlowMinor += signedFlowMinor;
    final isLatest = !occurredOn.isBefore(latestOccurrence);
    if (isLatest) {
      latestOccurrence = occurredOn;
      account = resolvedAccount ?? account;
      name = resolvedAccount?.displayName ?? fallbackName;
      type = resolvedAccount?.type ?? type;
    } else if (account == null && resolvedAccount != null) {
      account = resolvedAccount;
      name = resolvedAccount.displayName;
      type = resolvedAccount.type;
    }
  }

  _AccountUsageSummary freeze() => _AccountUsageSummary(
    accountId: accountId,
    name: name.isEmpty ? 'Account #$accountId' : name,
    type: type,
    usageCount: usageCount,
    activityMinor: activityMinor,
    netFlowMinor: netFlowMinor,
    latestOccurrence: latestOccurrence,
    account: account,
  );
}

List<_AccountUsageSummary> _accountUsageSummaries(
  List<TransactionRecord> transactions,
  List<Account> accounts,
  FinanceScope scope,
) {
  final liveAccounts = <int, Account>{
    for (final account in accounts) account.id: account,
  };
  final usageByAccount = <int, _MutableAccountUsage>{
    for (final account in accounts)
      if (account.scope == scope && !account.isArchived)
        account.id: _MutableAccountUsage(
          accountId: account.id,
          initialAccount: account,
        ),
  };

  void addUsage({
    required int accountId,
    required Account? account,
    required String fallbackName,
    required int amountMinor,
    required int signedFlowMinor,
    required DateTime occurredOn,
  }) {
    usageByAccount
        .putIfAbsent(
          accountId,
          () => _MutableAccountUsage(
            accountId: accountId,
            initialAccount: liveAccounts[accountId],
          ),
        )
        .add(
          resolvedAccount: account,
          fallbackName: fallbackName,
          amountMinor: amountMinor,
          signedFlowMinor: signedFlowMinor,
          occurredOn: occurredOn,
        );
  }

  for (final transaction in transactions) {
    if (transaction.isManagedJointSplitExpense &&
        !transaction.isJointSplitExpenseAggregate) {
      continue;
    }
    final split = transaction.jointSplitExpense;
    if (split != null) {
      final signedMultiplier = transaction.kind == 'income' ? 1 : -1;
      if (split.firstAccountId == split.secondAccountId) {
        final combinedShare = split.firstShareMinor + split.secondShareMinor;
        addUsage(
          accountId: split.firstAccountId,
          account:
              liveAccounts[split.firstAccountId] ??
              split.firstAccount ??
              split.secondAccount,
          fallbackName: split.firstDisplayName,
          amountMinor: combinedShare,
          signedFlowMinor: signedMultiplier * combinedShare,
          occurredOn: transaction.occurredOn,
        );
      } else {
        addUsage(
          accountId: split.firstAccountId,
          account: liveAccounts[split.firstAccountId] ?? split.firstAccount,
          fallbackName: split.firstDisplayName,
          amountMinor: split.firstShareMinor,
          signedFlowMinor: signedMultiplier * split.firstShareMinor,
          occurredOn: transaction.occurredOn,
        );
        addUsage(
          accountId: split.secondAccountId,
          account: liveAccounts[split.secondAccountId] ?? split.secondAccount,
          fallbackName: split.secondDisplayName,
          amountMinor: split.secondShareMinor,
          signedFlowMinor: signedMultiplier * split.secondShareMinor,
          occurredOn: transaction.occurredOn,
        );
      }
      continue;
    }
    final accountId = transaction.account?.id ?? transaction.accountId;
    if (accountId == null) continue;
    final amount = transaction.amountMinor;
    addUsage(
      accountId: accountId,
      account: liveAccounts[accountId] ?? transaction.account,
      fallbackName:
          liveAccounts[accountId]?.displayName ??
          transaction.account?.displayName ??
          'Account #$accountId',
      amountMinor: amount,
      signedFlowMinor: transaction.kind == 'income' ? amount : -amount,
      occurredOn: transaction.occurredOn,
    );
  }

  final summaries =
      usageByAccount.values.map((usage) => usage.freeze()).toList()..sort((
        first,
        second,
      ) {
        final byCount = second.usageCount.compareTo(first.usageCount);
        if (byCount != 0) return byCount;
        final byActivity = second.activityMinor.compareTo(first.activityMinor);
        if (byActivity != 0) return byActivity;
        final byLatest = second.latestOccurrence.compareTo(
          first.latestOccurrence,
        );
        if (byLatest != 0) return byLatest;
        final byName = first.name.toLowerCase().compareTo(
          second.name.toLowerCase(),
        );
        return byName != 0
            ? byName
            : first.accountId.compareTo(second.accountId);
      });
  return summaries;
}

class _CategorySpendingSummary {
  const _CategorySpendingSummary({
    required this.categoryId,
    required this.name,
    required this.color,
    required this.amountMinor,
  });

  final int? categoryId;
  final String name;
  final String color;
  final int amountMinor;
}

class _MutableCategorySpending {
  _MutableCategorySpending({required this.categoryId});

  final int? categoryId;
  String name = 'Uncategorized';
  String color = '#8290B1';
  int amountMinor = 0;
  DateTime latestOccurrence = DateTime.fromMillisecondsSinceEpoch(0);

  void add({
    required int amount,
    required String nextName,
    required String nextColor,
    required DateTime occurredOn,
  }) {
    amountMinor += amount;
    if (!occurredOn.isBefore(latestOccurrence)) {
      latestOccurrence = occurredOn;
      name = nextName;
      color = nextColor;
    }
  }

  _CategorySpendingSummary freeze() => _CategorySpendingSummary(
    categoryId: categoryId,
    name: name,
    color: color,
    amountMinor: amountMinor,
  );
}

List<_CategorySpendingSummary> _expenseCategorySummaries(
  List<TransactionRecord> transactions,
) {
  final categories = <String, _MutableCategorySpending>{};
  for (final transaction in transactions) {
    if (transaction.kind != 'expense') continue;
    if (transaction.isManagedJointSplitExpense &&
        !transaction.isJointSplitExpenseAggregate) {
      continue;
    }
    final split = transaction.jointSplitExpense;
    final categoryId = split?.categoryId ?? transaction.categoryId;
    final key = categoryId == null ? 'uncategorized' : 'category:$categoryId';
    final amount = math.max(
      0,
      split?.expenseCountedMinor ?? transaction.amountMinor,
    );
    final category = split?.category ?? transaction.category;
    categories
        .putIfAbsent(
          key,
          () => _MutableCategorySpending(categoryId: categoryId),
        )
        .add(
          amount: amount,
          nextName:
              split?.categoryDisplayName ?? category?.name ?? 'Uncategorized',
          nextColor: category?.color ?? '#8290B1',
          occurredOn: transaction.occurredOn,
        );
  }
  return categories.values.map((category) => category.freeze()).toList()
    ..sort((first, second) {
      final byAmount = second.amountMinor.compareTo(first.amountMinor);
      if (byAmount != 0) return byAmount;
      final byName = first.name.toLowerCase().compareTo(
        second.name.toLowerCase(),
      );
      if (byName != 0) return byName;
      return (first.categoryId ?? -1).compareTo(second.categoryId ?? -1);
    });
}

class _AccountActivityCard extends StatelessWidget {
  const _AccountActivityCard({
    required this.hasData,
    required this.range,
    required this.summaries,
    required this.currencyCode,
    required this.locale,
  });

  final bool hasData;
  final _TransactionPeriodRange range;
  final List<_AccountUsageSummary> summaries;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final summaries = this.summaries;
    final usedCount = summaries
        .where((summary) => summary.usageCount > 0)
        .length;
    return SectionCard(
      key: const Key('transaction-most-used-accounts'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Account activity',
            style: TextStyle(
              color: palette.ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            hasData
                ? '$usedCount of ${summaries.length} ${summaries.length == 1 ? 'account' : 'accounts'} used in ${range.label}'
                : 'Saved transaction history is unavailable',
            style: TextStyle(color: palette.muted, fontSize: 11),
          ),
          const SizedBox(height: 16),
          if (!hasData)
            const _TransactionDataUnavailable(
              message: 'Refresh saved data to calculate account usage.',
            )
          else if (summaries.isEmpty)
            const _TransactionDataUnavailable(
              icon: Icons.account_balance_wallet_outlined,
              message: 'No active accounts are available in this scope.',
            )
          else ...[
            Text(
              'Most used first',
              style: TextStyle(
                color: palette.inkSoft,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Column(
              key: const Key('transaction-used-account-list'),
              children: [
                _MostUsedAccountVisual(
                  summary: summaries.first,
                  rank: 1,
                  totalAccounts: summaries.length,
                  currencyCode: currencyCode,
                  locale: locale,
                ),
                for (var index = 1; index < summaries.length; index++) ...[
                  const SizedBox(height: 10),
                  _CompactAccountActivityVisual(
                    summary: summaries[index],
                    rank: index + 1,
                    totalAccounts: summaries.length,
                    currencyCode: currencyCode,
                    locale: locale,
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MostUsedAccountVisual extends StatelessWidget {
  const _MostUsedAccountVisual({
    required this.summary,
    required this.rank,
    required this.totalAccounts,
    required this.currencyCode,
    required this.locale,
  });

  final _AccountUsageSummary summary;
  final int rank;
  final int totalAccounts;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final account = summary.account;
    final design = account == null
        ? genericBankCardDesign
        : bankCardDesignFor(account.cardDesign);
    final visual = account == null
        ? AccountCardVisual.fromDesign(design)
        : AccountCardVisual.forAccount(account, design, context.palette);
    final mark = design.key == 'other'
        ? accountCardShortMark(summary.type)
        : design.shortMark;
    final typeLabel = accountCardTypeLabel(summary.type);
    final activityText = Money.format(
      summary.activityMinor,
      currencyCode: currencyCode,
      locale: locale,
    );
    final netFlowText = Money.format(
      summary.netFlowMinor,
      currencyCode: currencyCode,
      locale: locale,
    );
    Widget markBadge() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: visual.foreground.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: visual.foreground.withValues(alpha: 0.16)),
      ),
      child: Text(
        mark,
        style: TextStyle(
          color: visual.foreground,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.65,
        ),
      ),
    );
    Widget usageBadge() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: visual.foreground.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            summary.usageCount > 0 ? '#1 MOST USED' : '#1',
            style: TextStyle(
              color: visual.foreground,
              fontSize: 8.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.35,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            '${summary.usageCount} ${summary.usageCount == 1 ? 'use' : 'uses'}',
            key: ValueKey(
              'transaction-most-used-account-count-${summary.accountId}',
            ),
            style: TextStyle(
              color: visual.foreground.withValues(alpha: 0.78),
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
    return Semantics(
      key: ValueKey(
        'transaction-most-used-account-semantics-${summary.accountId}',
      ),
      container: true,
      excludeSemantics: true,
      label:
          'Rank $rank of $totalAccounts. ${summary.name}. ${summary.usageCount} ${summary.usageCount == 1 ? 'transaction' : 'transactions'}. Total activity $activityText. Net flow $netFlowText.',
      child: DecoratedBox(
        key: ValueKey('transaction-most-used-account-${summary.accountId}'),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [visual.primary, visual.secondary],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: visual.foreground.withValues(alpha: 0.16)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x29000000),
              blurRadius: 18,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: CustomPaint(
            painter: BankCardPatternPainter(
              pattern: design.pattern,
              accent: visual.accent,
              foreground: visual.foreground,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final textScale = MediaQuery.textScalerOf(context)
                          .scale(1);
                      if (constraints.maxWidth < 240 || textScale > 1.5) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: markBadge(),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: usageBadge(),
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [markBadge(), const Spacer(), usageBadge()],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Text(
                    summary.name,
                    key: ValueKey(
                      'transaction-most-used-account-name-${summary.accountId}',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: visual.foreground,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    typeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: visual.foreground.withValues(alpha: 0.72),
                      fontSize: 10.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TOTAL ACTIVITY',
                              style: TextStyle(
                                color: visual.foreground.withValues(
                                  alpha: 0.68,
                                ),
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.55,
                              ),
                            ),
                            const SizedBox(height: 3),
                            FittedBox(
                              key: ValueKey(
                                'transaction-most-used-account-amount-${summary.accountId}',
                              ),
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                activityText,
                                style: TextStyle(
                                  color: visual.foreground,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'NET FLOW',
                              style: TextStyle(
                                color: visual.foreground.withValues(
                                  alpha: 0.68,
                                ),
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.55,
                              ),
                            ),
                            const SizedBox(height: 3),
                            FittedBox(
                              key: ValueKey(
                                'transaction-most-used-account-net-flow-${summary.accountId}',
                              ),
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                netFlowText,
                                style: TextStyle(
                                  color: visual.foreground,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
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
      ),
    );
  }
}

class _CompactAccountActivityVisual extends StatelessWidget {
  const _CompactAccountActivityVisual({
    required this.summary,
    required this.rank,
    required this.totalAccounts,
    required this.currencyCode,
    required this.locale,
  });

  final _AccountUsageSummary summary;
  final int rank;
  final int totalAccounts;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final account = summary.account;
    final design = account == null
        ? genericBankCardDesign
        : bankCardDesignFor(account.cardDesign);
    final visual = account == null
        ? AccountCardVisual.fromDesign(design)
        : AccountCardVisual.forAccount(account, design, context.palette);
    final mark = design.key == 'other'
        ? accountCardShortMark(summary.type)
        : design.shortMark;
    final activityText = Money.format(
      summary.activityMinor,
      currencyCode: currencyCode,
      locale: locale,
    );
    final netFlowText = Money.format(
      summary.netFlowMinor,
      currencyCode: currencyCode,
      locale: locale,
    );
    return Semantics(
      key: ValueKey(
        'transaction-most-used-account-semantics-${summary.accountId}',
      ),
      container: true,
      excludeSemantics: true,
      label:
          'Rank $rank of $totalAccounts. ${summary.name}. ${summary.usageCount} ${summary.usageCount == 1 ? 'transaction' : 'transactions'}. Total activity $activityText. Net flow $netFlowText.',
      child: DecoratedBox(
        key: ValueKey('transaction-most-used-account-${summary.accountId}'),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [visual.primary, visual.secondary],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: visual.foreground.withValues(alpha: 0.14)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: CustomPaint(
            painter: BankCardPatternPainter(
              pattern: design.pattern,
              accent: visual.accent,
              foreground: visual.foreground,
            ),
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        constraints: const BoxConstraints(minWidth: 38),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: visual.foreground.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          mark,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: TextStyle(
                            color: visual.foreground,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              summary.name,
                              key: ValueKey(
                                'transaction-most-used-account-name-${summary.accountId}',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: visual.foreground,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              accountCardTypeLabel(summary.type),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: visual.foreground.withValues(
                                  alpha: 0.68,
                                ),
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: visual.foreground.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '#$rank',
                          style: TextStyle(
                            color: visual.foreground,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _CompactAccountMetric(
                          label: 'USES',
                          alignment: CrossAxisAlignment.start,
                          value: '${summary.usageCount}',
                          valueKey: ValueKey(
                            'transaction-most-used-account-count-${summary.accountId}',
                          ),
                          color: visual.foreground,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _CompactAccountMetric(
                          label: 'TOTAL ACTIVITY',
                          alignment: CrossAxisAlignment.start,
                          value: activityText,
                          valueKey: ValueKey(
                            'transaction-most-used-account-amount-${summary.accountId}',
                          ),
                          color: visual.foreground,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _CompactAccountMetric(
                          label: 'NET FLOW',
                          alignment: CrossAxisAlignment.end,
                          value: netFlowText,
                          valueKey: ValueKey(
                            'transaction-most-used-account-net-flow-${summary.accountId}',
                          ),
                          color: visual.foreground,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactAccountMetric extends StatelessWidget {
  const _CompactAccountMetric({
    required this.label,
    required this.value,
    required this.valueKey,
    required this.alignment,
    required this.color,
  });

  final String label;
  final String value;
  final Key valueKey;
  final CrossAxisAlignment alignment;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: alignment,
    children: [
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color.withValues(alpha: 0.62),
          fontSize: 7.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.35,
        ),
      ),
      const SizedBox(height: 2),
      FittedBox(
        key: valueKey,
        fit: BoxFit.scaleDown,
        alignment: alignment == CrossAxisAlignment.end
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ],
  );
}

class _WhereMoneyWentCard extends StatelessWidget {
  const _WhereMoneyWentCard({
    required this.hasData,
    required this.range,
    required this.categories,
    required this.currencyCode,
    required this.locale,
  });

  final bool hasData;
  final _TransactionPeriodRange range;
  final List<_CategorySpendingSummary> categories;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final total = categories.fold<int>(
      0,
      (sum, category) => sum + category.amountMinor,
    );
    final visible = categories.take(6).toList();
    return SectionCard(
      key: const Key('transaction-category-breakdown'),
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
                      'Where your money went',
                      style: TextStyle(
                        color: palette.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Expense categories in ${range.label}',
                      style: TextStyle(color: palette.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (hasData) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topRight,
                    child: Text(
                      Money.format(
                        total,
                        currencyCode: currencyCode,
                        locale: locale,
                      ),
                      key: const Key('transaction-spending-total'),
                      style: TextStyle(
                        color: palette.violet,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          if (!hasData)
            const _TransactionDataUnavailable(
              message: 'Refresh saved data to calculate expense categories.',
            )
          else if (categories.isEmpty)
            _TransactionDataUnavailable(
              icon: Icons.donut_large_rounded,
              message: 'No expenses in ${range.label}.',
            )
          else
            for (var index = 0; index < visible.length; index++) ...[
              _SpendingCategoryRow(
                key: ValueKey(
                  'transaction-category-${visible[index].categoryId ?? 'uncategorized'}',
                ),
                category: visible[index],
                totalMinor: total,
                currencyCode: currencyCode,
                locale: locale,
              ),
              if (index != visible.length - 1) const SizedBox(height: 15),
            ],
          if (categories.length > visible.length) ...[
            const SizedBox(height: 13),
            Text(
              '+${categories.length - visible.length} more ${categories.length - visible.length == 1 ? 'category' : 'categories'}',
              style: TextStyle(
                color: palette.muted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SpendingCategoryRow extends StatelessWidget {
  const _SpendingCategoryRow({
    super.key,
    required this.category,
    required this.totalMinor,
    required this.currencyCode,
    required this.locale,
  });

  final _CategorySpendingSummary category;
  final int totalMinor;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = colorFromHex(
      category.color,
      fallback: palette.violet,
      legacyReplacement: palette.violet,
    );
    final share = totalMinor == 0 ? 0.0 : category.amountMinor / totalMinor;
    final percentage = '${(share * 100).round()}%';
    final amount = Money.format(
      category.amountMinor,
      currencyCode: currencyCode,
      locale: locale,
    );
    return Semantics(
      container: true,
      label: '${category.name}, $amount, $percentage of period expenses.',
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    amount,
                    style: TextStyle(
                      color: palette.inkSoft,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                percentage,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
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
              backgroundColor: palette.border,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionDataUnavailable extends StatelessWidget {
  const _TransactionDataUnavailable({
    required this.message,
    this.icon = Icons.cloud_off_rounded,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: context.palette.muted, size: 20),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          message,
          style: TextStyle(color: context.palette.muted, fontSize: 12),
        ),
      ),
    ],
  );
}

class _IncomeExpenseDonutPainter extends CustomPainter {
  const _IncomeExpenseDonutPainter({
    required this.incomeMinor,
    required this.expenseMinor,
    required this.trackColor,
    required this.incomeColor,
    required this.expenseColor,
  });

  final int incomeMinor;
  final int expenseMinor;
  final Color trackColor;
  final Color incomeColor;
  final Color expenseColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const strokeWidth = 15.0;
    final radius = math.max(
      0.0,
      math.min(size.width, size.height) / 2 - strokeWidth / 2,
    );
    final rect = Rect.fromCircle(center: center, radius: radius);
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, track);

    final total = incomeMinor + expenseMinor;
    if (total <= 0) return;
    final incomeSweep = math.pi * 2 * incomeMinor / total;
    final hasBoth = incomeMinor > 0 && expenseMinor > 0;
    final gap = hasBoth ? 0.045 : 0.0;
    const start = -math.pi / 2;
    final incomePaint = Paint()
      ..color = incomeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;
    final expensePaint = Paint()
      ..color = expenseColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;
    if (incomeMinor > 0) {
      canvas.drawArc(
        rect,
        start + gap / 2,
        math.max(0, incomeSweep - gap),
        false,
        incomePaint,
      );
    }
    if (expenseMinor > 0) {
      canvas.drawArc(
        rect,
        start + incomeSweep + gap / 2,
        math.max(0, math.pi * 2 - incomeSweep - gap),
        false,
        expensePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _IncomeExpenseDonutPainter oldDelegate) =>
      oldDelegate.incomeMinor != incomeMinor ||
      oldDelegate.expenseMinor != expenseMinor ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.incomeColor != incomeColor ||
      oldDelegate.expenseColor != expenseColor;
}

class _LedgerAmountCell extends StatelessWidget {
  const _LedgerAmountCell({
    required this.transaction,
    required this.currencyCode,
    required this.locale,
  });

  final TransactionRecord transaction;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final income = transaction.kind == 'income';
    final accent = income ? palette.cyan : palette.violet;
    final account = transaction.jointSplitExpense == null
        ? transaction.account?.displayName ?? 'Unassigned account'
        : '2 funding accounts';
    return SizedBox(
      width: 190,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              shape: BoxShape.circle,
              border: Border.all(color: accent.withValues(alpha: 0.38)),
            ),
            alignment: Alignment.center,
            child: Icon(
              income ? Icons.south_west_rounded : Icons.north_east_rounded,
              color: accent,
              size: 17,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MoneyLabel(
                  minorUnits: transaction.amountMinor,
                  currencyCode: currencyCode,
                  locale: locale,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$account · $currencyCode',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerPaymentTypeCell extends StatelessWidget {
  const _LedgerPaymentTypeCell({required this.transaction});

  final TransactionRecord transaction;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final income = transaction.kind == 'income';
    final accent = income ? palette.cyan : palette.violet;
    return SizedBox(
      width: 150,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            income ? 'INCOMING ↙' : 'OUTGOING ↗',
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.25,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            transaction.jointSplitExpense != null
                ? 'Expense · 50/50'
                : transaction.isManagedInstallmentDownPayment
                ? 'Expense · down payment'
                : transaction.isManagedInstallmentPayment
                ? 'Expense · payment ${transaction.installmentNumber ?? ''}'
                : transaction.isInstallment
                ? 'Expense · installment'
                : income
                ? 'Income'
                : 'Expense',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _LedgerDetailsCell extends StatelessWidget {
  const _LedgerDetailsCell({
    required this.transaction,
    required this.currencyCode,
    required this.locale,
  });

  final TransactionRecord transaction;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final split = transaction.jointSplitExpense;
    final note = (split?.note ?? transaction.note)?.trim();
    final category =
        split?.categoryDisplayName ??
        transaction.category?.name ??
        'Uncategorized';
    return SizedBox(
      width: 330,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _transactionTitle(transaction),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.ink,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${DateFormat('MMM d, y').format(transaction.occurredOn)} · $category',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.muted, fontSize: 11),
          ),
          if (split != null) ...[
            const SizedBox(height: 4),
            _JointSplitAccountsCell(
              split: split,
              currencyCode: currencyCode,
              locale: locale,
            ),
          ] else if (transaction.isManagedInstallmentDownPayment) ...[
            const SizedBox(height: 4),
            Text(
              'Installment down payment',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.orange,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ] else if (transaction.isManagedInstallmentPayment) ...[
            const SizedBox(height: 4),
            Text(
              'Installment payment ${transaction.installmentNumber ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.orange,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ] else if (transaction.isInstallment) ...[
            const SizedBox(height: 4),
            Text(
              '${Money.format(transaction.installmentMonthlyMinor ?? 0, currencyCode: currencyCode, locale: locale)} / month · ${transaction.installmentMonths} months',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.orange,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ] else if (note?.isNotEmpty == true) ...[
            const SizedBox(height: 3),
            Text(
              note!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.inkSoft, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _LedgerStatusCell extends StatelessWidget {
  const _LedgerStatusCell({required this.transaction, this.operation});

  final TransactionRecord transaction;
  final OfflineTransactionOperation? operation;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final status = _ledgerStatus(transaction, operation, palette);
    return Semantics(
      label: operation == null
          ? '${status.label}, ${status.detail}'
          : _offlineOperationDescription(operation!),
      child: SizedBox(
        width: 190,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: status.color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: status.color.withValues(alpha: 0.32),
                        blurRadius: 7,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    status.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: status.color,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              status.detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.muted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _LedgerActionCell extends StatelessWidget {
  const _LedgerActionCell({
    required this.locked,
    required this.lockedMessage,
    required this.onEdit,
    required this.onDelete,
  });

  final bool locked;
  final String? lockedMessage;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final icon = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: palette.borderStrong),
      ),
      alignment: Alignment.center,
      child: Icon(
        locked ? Icons.lock_clock_outlined : Icons.keyboard_arrow_down_rounded,
        color: locked ? palette.muted : palette.ink,
        size: 19,
      ),
    );
    if (locked) {
      return Tooltip(
        message: lockedMessage!,
        child: Semantics(label: lockedMessage, child: icon),
      );
    }
    return PopupMenuButton<String>(
      tooltip: 'Transaction actions',
      padding: EdgeInsets.zero,
      icon: icon,
      onSelected: (value) {
        if (value == 'edit') {
          onEdit?.call();
        } else if (value == 'delete') {
          onDelete?.call();
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 18),
              SizedBox(width: 10),
              Text('Edit transaction'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 19, color: palette.red),
              const SizedBox(width: 10),
              const Text('Delete transaction'),
            ],
          ),
        ),
      ],
    );
  }
}

String _transactionTitle(TransactionRecord transaction) {
  final splitPayee = transaction.jointSplitExpense?.payee?.trim();
  final payee = transaction.payee?.trim();
  if (splitPayee?.isNotEmpty == true) return splitPayee!;
  if (payee?.isNotEmpty == true) return payee!;
  if (transaction.jointSplitExpense != null) return '50/50 Joint expense';
  if (transaction.isManagedAccountTransferFee) {
    return 'Transfer service charge';
  }
  if (transaction.isManagedCreditCardPaymentFee) {
    return 'Card payment service charge';
  }
  if (transaction.isManagedSavingsInterest) return 'Savings interest';
  if (transaction.isManagedJewelryConversion) return 'Jewelry conversion';
  return transaction.kind == 'income' ? 'Income' : 'Expense';
}

({String label, String detail, Color color}) _ledgerStatus(
  TransactionRecord transaction,
  OfflineTransactionOperation? operation,
  AppPalette palette,
) {
  if (operation != null) {
    return switch (operation.status) {
      OfflineOperationStatus.queued => (
        label: 'PENDING',
        detail: 'Waiting to sync',
        color: palette.gold,
      ),
      OfflineOperationStatus.inFlight => (
        label: 'SYNCING',
        detail: 'Upload in progress',
        color: palette.cyan,
      ),
      OfflineOperationStatus.uncertain when operation.attemptCount >= 5 => (
        label: 'NEEDS ATTENTION',
        detail: 'Automatic retries paused',
        color: palette.orange,
      ),
      OfflineOperationStatus.uncertain => (
        label: 'RETRY PENDING',
        detail: 'Sync result uncertain',
        color: palette.orange,
      ),
      OfflineOperationStatus.applied => (
        label: 'SUCCESS',
        detail: 'Refreshing totals',
        color: palette.success,
      ),
      OfflineOperationStatus.conflict => (
        label: 'CONFLICT',
        detail: 'Review server version',
        color: palette.orange,
      ),
      OfflineOperationStatus.rejected => (
        label: 'REJECTED',
        detail: 'Review saved change',
        color: palette.red,
      ),
    };
  }

  final sourceStatus = transaction.jointSplitExpense?.status.toLowerCase();
  return switch (sourceStatus) {
    'pending' => (
      label: 'PENDING',
      detail: 'Awaiting confirmation',
      color: palette.gold,
    ),
    'denied' || 'rejected' || 'cancelled' => (
      label: 'DENIED',
      detail: 'Unable to execute',
      color: palette.orange,
    ),
    _ => (
      label: 'SUCCESS',
      detail: 'Saved on this phone',
      color: palette.success,
    ),
  };
}

String _lockedTransactionMessage(
  TransactionRecord transaction, {
  required OfflineTransactionOperation? offlineOperation,
  required bool ordinaryActionsBlocked,
}) {
  final frozen = offlineOperation?.isFrozen ?? false;
  if (ordinaryActionsBlocked && !transaction.isManagedTransaction && !frozen) {
    return 'Transaction changes are read-only until saved data and the original Budget Flow database are verified';
  }
  if (frozen) return _offlineOperationDescription(offlineOperation!);
  if (transaction.isManagedAccountTransferFee) {
    return 'Managed by an account transfer service charge';
  }
  if (transaction.isManagedCreditCardPaymentFee) {
    return 'Managed by a credit-card payment service charge';
  }
  if (transaction.isManagedSavingsInterest) {
    return 'Managed by a monthly savings interest credit';
  }
  if (transaction.isManagedJointSplitExpense) {
    return 'Managed by an immutable 50/50 Joint expense; it cannot be edited or deleted in this version';
  }
  if (transaction.isManagedInstallmentDownPayment) {
    return 'Managed by its installment plan as the recorded down payment.';
  }
  if (transaction.isManagedInstallmentPayment) {
    return 'Managed by its installment plan. Record the next payment from the dashboard.';
  }
  return 'Managed by a jewelry conversion';
}

class _OfflineChangesPanel extends StatelessWidget {
  const _OfflineChangesPanel({
    required this.controller,
    required this.operations,
  });

  final AppController controller;
  final List<OfflineTransactionOperation> operations;

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.rule_folder_outlined, color: context.palette.greenDark),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Review offline changes',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'These changes were not applied automatically. Compare the saved local intent with the server before deciding.',
          style: TextStyle(color: context.palette.muted, fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        for (final operation in operations)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.warning_amber_rounded),
            title: Text(_operationTitle(operation)),
            subtitle: Text(
              operation.message ??
                  operation.code ??
                  'This saved change needs attention.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: OutlinedButton(
              onPressed: () =>
                  _showOfflineOperationReview(context, controller, operation),
              child: const Text('Review'),
            ),
          ),
      ],
    ),
  );
}

String _offlineOperationDescription(OfflineTransactionOperation operation) =>
    switch (operation.status) {
      OfflineOperationStatus.queued => 'Saved on this device and waiting to sync; it can still be edited or deleted before the first attempt',
      OfflineOperationStatus.inFlight =>
        'Sync is in progress; this transaction is temporarily locked',
      OfflineOperationStatus.uncertain =>
        operation.attemptCount >= 5
            ? 'Automatic retries stopped after five attempts; use Sync now or review the connection'
            : 'The previous result was uncertain; the exact saved request is locked for a safe retry',
      OfflineOperationStatus.applied => 'The server applied this change; totals are being refreshed before the saved request is retired',
      OfflineOperationStatus.conflict =>
        'The server version changed; review local and server values',
      OfflineOperationStatus.rejected =>
        'The server rejected this saved change; review the details',
    };

String _operationTitle(OfflineTransactionOperation operation) {
  final desired = operation.desiredTransaction ?? operation.baseTransaction;
  final label = desired?.payee?.trim().isNotEmpty == true
      ? desired!.payee!.trim()
      : desired?.category?.name ?? 'Transaction';
  return '${operation.action.name[0].toUpperCase()}${operation.action.name.substring(1)} · $label';
}

Future<void> _showOfflineOperationReview(
  BuildContext context,
  AppController controller,
  OfflineTransactionOperation operation,
) async {
  final local = operation.desiredTransaction;
  final server = operation.serverTransaction;
  final retryPreview = controller.rebasedRetryPreview(operation);
  final uncertain = operation.status == OfflineOperationStatus.uncertain;
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Review saved transaction change'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              operation.message ?? operation.code ?? 'Sync needs attention.',
            ),
            const SizedBox(height: 16),
            _ReviewSnapshot(
              label: 'Saved on this device',
              transaction: local,
              currencyCode: controller.currencyCode,
              locale: controller.locale,
            ),
            const SizedBox(height: 12),
            _ReviewSnapshot(
              label: operation.tombstone != null
                  ? 'Server version was deleted'
                  : 'Current server version',
              transaction: server,
              currencyCode: controller.currencyCode,
              locale: controller.locale,
            ),
            if (operation.status == OfflineOperationStatus.conflict &&
                retryPreview != null) ...[
              const SizedBox(height: 12),
              _ReviewSnapshot(
                label: 'Proposed retry (your changed fields over server)',
                transaction: retryPreview,
                currencyCode: controller.currencyCode,
                locale: controller.locale,
              ),
            ],
            const SizedBox(height: 14),
            Text(
              uncertain
                  ? 'The server outcome is unknown. This exact frozen request must be replayed; it cannot be discarded as if it failed.'
                  : 'Keep server refreshes the complete financial baseline before discarding this local request. Retry applies only fields you originally changed over the returned server version and uses a new request ID.',
              style: TextStyle(color: context.palette.muted, fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (operation.status == OfflineOperationStatus.conflict &&
            retryPreview != null)
          OutlinedButton(
            onPressed: () => Navigator.pop(context, 'retry'),
            child: const Text('Confirm retry'),
          ),
        if (uncertain)
          FilledButton(
            onPressed: controller.hasLiveConnection
                ? () => Navigator.pop(context, 'sync')
                : null,
            child: const Text('Sync exact request'),
          )
        else
          FilledButton(
            onPressed: controller.hasLiveConnection
                ? () => Navigator.pop(context, 'server')
                : null,
            child: Text(
              server == null ? 'Discard local change' : 'Keep server',
            ),
          ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  try {
    if (choice == 'sync') {
      await controller.syncPendingTransactions(manual: true);
      if (context.mounted) {
        showSuccess(context, 'Exact saved request queued for retry.');
      }
    } else if (choice == 'retry') {
      await controller.retryTransactionAgainstServer(operation);
      if (context.mounted) {
        showSuccess(
          context,
          'Saved as a new retry against the current server version.',
        );
      }
    } else {
      await controller.keepServerTransaction(operation);
      if (context.mounted) showSuccess(context, 'Server version kept.');
    }
  } catch (error) {
    if (context.mounted) showError(context, error);
  }
}

class _ReviewSnapshot extends StatelessWidget {
  const _ReviewSnapshot({
    required this.label,
    required this.transaction,
    required this.currencyCode,
    required this.locale,
  });

  final String label;
  final TransactionRecord? transaction;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final value = transaction;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(
            value == null
                ? 'No active transaction snapshot returned.'
                : '${value.kind} · ${Money.format(value.amountMinor, currencyCode: currencyCode, locale: locale)} · ${DateFormat('MMM d, y').format(value.occurredOn)}\n'
                      '${value.account?.name ?? 'Account #${value.accountId}'} · ${value.category?.name ?? 'Category #${value.categoryId}'}\n'
                      'Payee: ${value.payee?.trim().isNotEmpty == true ? value.payee!.trim() : '—'}\n'
                      'Note: ${value.note?.trim().isNotEmpty == true ? value.note!.trim() : '—'}',
            style: TextStyle(color: palette.inkSoft, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _JointSplitAccountsCell extends StatelessWidget {
  const _JointSplitAccountsCell({
    required this.split,
    required this.currencyCode,
    required this.locale,
  });

  final JointSplitExpense split;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final firstAmount = Money.format(
      split.firstShareMinor,
      currencyCode: currencyCode,
      locale: locale,
    );
    final secondAmount = Money.format(
      split.secondShareMinor,
      currencyCode: currencyCode,
      locale: locale,
    );
    final firstCurrent =
        split.firstAccount?.displayName ?? split.firstAccountName;
    final secondCurrent =
        split.secondAccount?.displayName ?? split.secondAccountName;
    final renamed = <String>[
      if (firstCurrent != split.firstDisplayName)
        '${split.firstDisplayName} is now $firstCurrent',
      if (split.firstAccount?.isArchived == true)
        '${split.firstDisplayName} is currently archived',
      if (secondCurrent != split.secondDisplayName)
        '${split.secondDisplayName} is now $secondCurrent',
      if (split.secondAccount?.isArchived == true)
        '${split.secondDisplayName} is currently archived',
    ];
    final tooltip = [
      'First funding account: ${split.firstDisplayName} · $firstAmount',
      'Second funding account: ${split.secondDisplayName} · $secondAmount',
      ...renamed,
    ].join('\n');
    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: tooltip,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 285),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${split.firstDisplayName} · $firstAmount',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.inkSoft,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${split.secondDisplayName} · $secondAmount',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.inkSoft,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showTransactionEditor(
  BuildContext context,
  AppController controller, {
  TransactionRecord? existing,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) =>
      _TransactionDialog(controller: controller, existing: existing),
);

Future<void> showInstallmentPlanEditor(
  BuildContext context,
  AppController controller, {
  required InstallmentPlan plan,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) =>
      _TransactionDialog(controller: controller, existingPlan: plan),
);

class _TransactionDialog extends StatefulWidget {
  const _TransactionDialog({
    required this.controller,
    this.existing,
    this.existingPlan,
  }) : assert(existing == null || existingPlan == null);

  final AppController controller;
  final TransactionRecord? existing;
  final InstallmentPlan? existingPlan;

  @override
  State<_TransactionDialog> createState() => _TransactionDialogState();
}

class _TransactionDialogState extends State<_TransactionDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController amountController;
  late final TextEditingController installmentMonthsController;
  late final TextEditingController downPaymentController;
  late final TextEditingController payeeController;
  late final TextEditingController noteController;
  late String kind;
  late DateTime occurredOn;
  late DateTime installmentStartOn;
  bool installmentEnabled = false;
  bool startInstallmentLater = false;
  bool downPaymentEnabled = false;
  bool planCreateAttempted = false;
  int? accountId;
  int? categoryId;
  int? firstSplitAccountId;
  int? secondSplitAccountId;
  // Nullable backing keeps an already-open dialog safe across hot reload.
  String? _jointExpenseModeV1;
  bool saving = false;
  bool reconnecting = false;
  late final String clientUuid;
  late final FinanceScope transactionScope;

  bool get isPlanEditor => widget.existingPlan != null;

  List<Account> get scopedAccounts {
    final active = widget.controller.accounts
        .where(
          (account) =>
              !account.isArchived &&
              account.scope == transactionScope &&
              !account.isSavingsAccount &&
              (kind == 'expense' || !account.isCreditCard) &&
              (!isPlanEditor ||
                  (!account.isCreditCard && account.isStandardAccount)),
        )
        .toList();
    final current = widget.existingPlan?.account ?? widget.existing?.account;
    if (current != null &&
        current.scope == transactionScope &&
        !current.isSavingsAccount &&
        (kind == 'expense' || !current.isCreditCard) &&
        (!isPlanEditor ||
            (!current.isCreditCard && current.isStandardAccount)) &&
        !active.any((account) => account.id == current.id)) {
      active.add(current);
    }
    return active;
  }

  List<Account> get splitAccounts =>
      widget.controller.jointSplitExpenseAccounts;

  bool get canChooseSplit =>
      widget.existing == null &&
      transactionScope == FinanceScope.joint &&
      kind == 'expense';

  bool get isSplitMode =>
      canChooseSplit && _jointExpenseModeV1 == 'split_50_50';

  Account? get firstSplitAccount => splitAccounts
      .where((account) => account.id == firstSplitAccountId)
      .firstOrNull;

  Account? get secondSplitAccount => splitAccounts
      .where((account) => account.id == secondSplitAccountId)
      .firstOrNull;

  Account? get selectedAccount =>
      scopedAccounts.where((account) => account.id == accountId).firstOrNull;

  bool get canUseInstallment =>
      !isSplitMode &&
      kind == 'expense' &&
      (selectedAccount?.isCreditCard == true ||
          selectedAccount?.isStandardAccount == true);

  bool get isCreditCardInstallment =>
      installmentEnabled && selectedAccount?.isCreditCard == true;

  bool get isAccountFundedInstallment =>
      installmentEnabled && selectedAccount?.isCreditCard == false;

  bool get isFutureInstallmentPlan =>
      isAccountFundedInstallment && (startInstallmentLater || isPlanEditor);

  bool get planTermsLocked => widget.existingPlan?.hasPayments == true;

  List<Account> get secondSplitOptions => splitAccounts
      .where((account) => account.id != firstSplitAccountId)
      .toList();

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final existingPlan = widget.existingPlan;
    transactionScope =
        existingPlan?.scope ??
        existing?.scope ??
        widget.controller.selectedFinanceScope;
    clientUuid =
        existingPlan?.clientUuid ??
        existing?.clientUuid ??
        widget.controller.newClientUuid();
    kind = existingPlan == null ? existing?.kind ?? 'expense' : 'expense';
    occurredOn = existing?.occurredOn ?? DateTime.now();
    installmentStartOn =
        existingPlan?.installmentStartOn ??
        existing?.installmentStartOn ??
        existing?.occurredOn ??
        occurredOn;
    installmentEnabled =
        existingPlan != null || existing?.isInstallment == true;
    startInstallmentLater = existingPlan != null;
    downPaymentEnabled = existingPlan?.hasDownPayment == true;
    final accountOptions = scopedAccounts;
    final existingAccountAvailable = accountOptions.any(
      (account) =>
          account.id == (existingPlan?.accountId ?? existing?.accountId),
    );
    accountId = existingAccountAvailable
        ? existingPlan?.accountId ?? existing?.accountId
        : (accountOptions.isEmpty ? null : accountOptions.first.id);
    if (existingPlan == null &&
        installmentEnabled &&
        selectedAccount?.isCreditCard != true) {
      installmentStartOn = occurredOn;
    }
    final options = _categoriesFor(kind);
    categoryId =
        existingPlan?.categoryId ??
        existing?.categoryId ??
        (options.isEmpty ? null : options.first.id);
    final splitOptions = splitAccounts;
    firstSplitAccountId = splitOptions.firstOrNull?.id;
    secondSplitAccountId = splitOptions.length > 1 ? splitOptions[1].id : null;
    _jointExpenseModeV1 = 'single';
    amountController = TextEditingController(
      text: existingPlan != null
          ? Money.decimal(existingPlan.installmentMonthlyMinor)
          : existing == null
          ? ''
          : Money.decimal(existing.amountMinor),
    );
    installmentMonthsController = TextEditingController(
      text:
          existingPlan?.installmentMonths.toString() ??
          existing?.installmentMonths?.toString() ??
          '12',
    );
    downPaymentController = TextEditingController(
      text: existingPlan?.hasDownPayment == true
          ? Money.decimal(existingPlan!.downPaymentMinor)
          : '',
    );
    payeeController = TextEditingController(
      text: existingPlan?.payee ?? existing?.payee ?? '',
    );
    noteController = TextEditingController(
      text: existingPlan?.note ?? existing?.note ?? '',
    );
    amountController.addListener(_rebuildFundingPreview);
    installmentMonthsController.addListener(_rebuildInstallmentPreview);
    downPaymentController.addListener(_rebuildFundingPreview);
  }

  @override
  void dispose() {
    amountController
      ..removeListener(_rebuildFundingPreview)
      ..dispose();
    installmentMonthsController
      ..removeListener(_rebuildInstallmentPreview)
      ..dispose();
    downPaymentController
      ..removeListener(_rebuildFundingPreview)
      ..dispose();
    payeeController.dispose();
    noteController.dispose();
    super.dispose();
  }

  void _rebuildFundingPreview() {
    if (mounted) setState(() {});
  }

  void _rebuildInstallmentPreview() {
    if (mounted && installmentEnabled) setState(() {});
  }

  List<Category> _categoriesFor(String value) {
    final active = <Category>[
      ...(value == 'income'
          ? widget.controller.standardTransactionIncomeCategories
          : widget.controller.standardTransactionExpenseCategories),
    ];
    final current = widget.existingPlan?.category ?? widget.existing?.category;
    if (current != null &&
        current.kind == value &&
        !current.isSystem &&
        !active.any((category) => category.id == current.id)) {
      active.add(current);
    }
    return active;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final categories = _categoriesFor(kind);
    return AlertDialog(
      title: Text(
        isPlanEditor
            ? 'Edit ${transactionScope.label} installment plan'
            : widget.existing == null
            ? 'Add ${transactionScope.label} transaction'
            : 'Edit ${transactionScope.label} transaction',
      ),
      content: SizedBox(
        width: 570,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                Container(
                  key: Key(
                    'transaction-${transactionScope.apiValue}-scope-notice',
                  ),
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: transactionScope == FinanceScope.joint
                        ? palette.infoSoft
                        : palette.mint,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        transactionScope == FinanceScope.joint
                            ? Icons.people_outline_rounded
                            : Icons.person_outline_rounded,
                        size: 19,
                        color: palette.greenDark,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          transactionScope == FinanceScope.joint
                              ? 'This affects only your Joint balance, cashflow, and budget.'
                              : 'This updates your balance, cashflow, and budget.',
                          style: TextStyle(
                            color: palette.inkSoft,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (isPlanEditor)
                  Container(
                    key: const Key('installment-plan-editor-notice'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: palette.orangeSoft,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      planTermsLocked
                          ? 'Payments already exist. You can change the default payment account and details, while the amount and schedule stay fixed.'
                          : widget.existingPlan?.hasDownPayment == true
                          ? 'The down payment is already recorded and cannot be changed. No monthly payment is deducted until you record it.'
                          : 'This plan is a reminder only. No money is deducted until you record a payment.',
                      style: TextStyle(
                        color: palette.inkSoft,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'expense',
                        icon: Icon(Icons.north_east_rounded),
                        label: Text('Expense'),
                      ),
                      ButtonSegment(
                        value: 'income',
                        icon: Icon(Icons.south_west_rounded),
                        label: Text('Income'),
                      ),
                    ],
                    selected: {kind},
                    onSelectionChanged: (value) {
                      setState(() {
                        kind = value.first;
                        if (kind != 'expense') {
                          _jointExpenseModeV1 = 'single';
                          installmentEnabled = false;
                          startInstallmentLater = false;
                          downPaymentEnabled = false;
                        }
                        final next = _categoriesFor(kind);
                        categoryId = next.isEmpty ? null : next.first.id;
                        final nextAccounts = scopedAccounts;
                        if (!nextAccounts.any(
                          (account) => account.id == accountId,
                        )) {
                          accountId = nextAccounts.firstOrNull?.id;
                        }
                      });
                    },
                    showSelectedIcon: false,
                  ),
                if (canChooseSplit) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    key: const Key('joint-expense-funding-mode'),
                    width: double.infinity,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth < 390) {
                          return Column(
                            children: [
                              _FundingModeTile(
                                selected: !isSplitMode,
                                icon: Icons.account_balance_wallet_outlined,
                                label: 'Single account',
                                onTap: () => setState(
                                  () => _jointExpenseModeV1 = 'single',
                                ),
                              ),
                              const SizedBox(height: 8),
                              _FundingModeTile(
                                selected: isSplitMode,
                                icon: Icons.call_split_rounded,
                                label: 'Split 50/50',
                                onTap: () => setState(
                                  () => _jointExpenseModeV1 = 'split_50_50',
                                ),
                              ),
                            ],
                          );
                        }
                        return SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'single',
                              icon: Icon(Icons.account_balance_wallet_outlined),
                              label: Text('Single account'),
                            ),
                            ButtonSegment(
                              value: 'split_50_50',
                              icon: Icon(Icons.call_split_rounded),
                              label: Text('Split 50/50'),
                            ),
                          ],
                          selected: {isSplitMode ? 'split_50_50' : 'single'},
                          onSelectionChanged: (value) =>
                              setState(() => _jointExpenseModeV1 = value.first),
                          showSelectedIcon: false,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      isSplitMode
                          ? 'Split one new Joint expense across two accounts.'
                          : 'Charge the full Joint expense to one account.',
                      style: TextStyle(color: palette.muted, fontSize: 12),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                TextFormField(
                  key: const Key('transaction-amount'),
                  controller: amountController,
                  autofocus: !isPlanEditor,
                  readOnly: planTermsLocked,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: isCreditCardInstallment
                        ? 'Total purchase amount'
                        : isAccountFundedInstallment
                        ? 'Monthly payment'
                        : 'Amount',
                    prefixText: widget.controller.currencyCode == 'PHP'
                        ? '₱ '
                        : null,
                    hintText: '0.00',
                  ),
                  validator: _validateAmount,
                ),
                const SizedBox(height: 14),
                if (isSplitMode)
                  _buildSplitFundingFields(categories)
                else
                  _buildSingleAccountFields(categories),
                if (!isSplitMode &&
                    kind == 'expense' &&
                    selectedAccount != null) ...[
                  const SizedBox(height: 14),
                  _buildAccountBalancePreview(),
                ],
                if (canUseInstallment) ...[
                  const SizedBox(height: 14),
                  _buildInstallmentFields(),
                ],
                if (isSplitMode) ...[
                  const SizedBox(height: 14),
                  _JointSplitPreview(
                    firstAccount: firstSplitAccount,
                    secondAccount: secondSplitAccount,
                    amountMinor: _parsedAmount,
                    currencyCode: widget.controller.currencyCode,
                    locale: widget.controller.locale,
                  ),
                ],
                if (!isFutureInstallmentPlan) ...[
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(11),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: isAccountFundedInstallment
                            ? 'First payment date'
                            : 'Date',
                        suffixIcon: const Icon(
                          Icons.calendar_today_rounded,
                          size: 18,
                        ),
                      ),
                      child: Text(
                        DateFormat('EEEE, MMM d, y').format(occurredOn),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                TextFormField(
                  controller: payeeController,
                  decoration: InputDecoration(
                    labelText: kind == 'income'
                        ? 'Source (optional)'
                        : 'Payee (optional)',
                    hintText: kind == 'income'
                        ? 'Salary, client…'
                        : 'Store, landlord…',
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('confirm-transaction-save'),
          onPressed:
              saving ||
                  reconnecting ||
                  (isSplitMode && splitAccounts.length < 2) ||
                  _blockingFundingIssue != null ||
                  (isFutureInstallmentPlan &&
                      !widget.controller.hasLiveConnection)
              ? null
              : _save,
          child: Text(
            saving
                ? 'Saving…'
                : isFutureInstallmentPlan
                ? 'Save installment plan'
                : isSplitMode
                ? 'Save split expense'
                : 'Save transaction',
          ),
        ),
      ],
    );
  }

  int? get _parsedAmount {
    try {
      return Money.parse(amountController.text);
    } on FormatException {
      return null;
    }
  }

  String? _validateAmount(String? value) {
    try {
      final amount = Money.parse(value ?? '');
      if (amount <= 0 || amount > Money.maxMinorUnits) {
        return 'Amount must be greater than zero.';
      }
      if (!isSplitMode) {
        final selected = scopedAccounts
            .where((account) => account.id == accountId)
            .firstOrNull;
        if (kind == 'expense' && selected != null && !isFutureInstallmentPlan) {
          final issue = _fundingIssueFor(selected, amount);
          if (issue != null) return issue;
        }
        return null;
      }
      if (amount < 2) return 'A 50/50 split must total at least 0.02.';
      final firstShare = (amount + 1) ~/ 2;
      final secondShare = amount ~/ 2;
      if (firstSplitAccount != null &&
          firstSplitAccount!.balanceMinor < firstShare) {
        return 'First funding account cannot cover its share.';
      }
      if (secondSplitAccount != null &&
          secondSplitAccount!.balanceMinor < secondShare) {
        return 'Second funding account cannot cover its share.';
      }
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  int? get _parsedInstallmentMonths =>
      int.tryParse(installmentMonthsController.text.trim());

  int? get _parsedDownPaymentMinor {
    if (!isFutureInstallmentPlan || !downPaymentEnabled) return 0;
    try {
      return Money.parse(downPaymentController.text);
    } on FormatException {
      return null;
    }
  }

  int get _downPaymentChargeTodayMinor {
    if (isPlanEditor) return 0;
    final parsed = _parsedDownPaymentMinor;
    return parsed != null && parsed > 0 ? parsed : 0;
  }

  String? _validateDownPayment(String? value) {
    if (!isFutureInstallmentPlan || !downPaymentEnabled || isPlanEditor) {
      return null;
    }
    try {
      final amount = Money.parse(value ?? '');
      if (amount <= 0 || amount > Money.maxMinorUnits) {
        return 'Down payment must be greater than zero.';
      }
      final account = selectedAccount;
      if (account != null && !planCreateAttempted) {
        return _fundingIssueFor(account, amount);
      }
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  int? get _installmentMonthlyMinor {
    final amount = _parsedAmount;
    final months = _parsedInstallmentMonths;
    if (!installmentEnabled ||
        amount == null ||
        months == null ||
        months <= 0) {
      return null;
    }
    return selectedAccount?.isCreditCard == true
        ? (amount + months - 1) ~/ months
        : amount;
  }

  String _futureInstallmentPreview(int monthlyMinor, int months) {
    final monthly = Money.format(
      monthlyMinor,
      currencyCode: widget.controller.currencyCode,
      locale: widget.controller.locale,
    );
    final plan = widget.existingPlan;
    final downPayment = plan?.downPaymentMinor ?? _parsedDownPaymentMinor ?? 0;
    final scheduledRemaining =
        plan?.remainingObligationMinor ?? monthlyMinor * months;
    final scheduled = Money.format(
      scheduledRemaining,
      currencyCode: widget.controller.currencyCode,
      locale: widget.controller.locale,
    );
    final start = DateFormat('MMM d, y').format(installmentStartOn);
    if (downPayment <= 0) {
      return '$monthly per month for $months months, starting $start. Nothing is deducted today; record each payment when it is paid.';
    }
    final formattedDownPayment = Money.format(
      downPayment,
      currencyCode: widget.controller.currencyCode,
      locale: widget.controller.locale,
    );
    if (plan != null) {
      final paidOn = plan.downPaymentPaidOn;
      final paidLabel = paidOn == null
          ? 'was already paid'
          : 'was paid on ${DateFormat('MMM d, y').format(paidOn)}';
      return '$formattedDownPayment down payment $paidLabel. $scheduled remains scheduled at $monthly per month; the next payment is checked only when recorded.';
    }
    final total = Money.format(
      downPayment + monthlyMinor * months,
      currencyCode: widget.controller.currencyCode,
      locale: widget.controller.locale,
    );
    return '$formattedDownPayment is charged today. $scheduled remains scheduled at $monthly per month for $months months, starting $start. Total commitment: $total.';
  }

  Widget _buildSingleAccountFields(List<Category> categories) {
    final accountOptions = scopedAccounts;
    final accountField = DropdownButtonFormField<int>(
      key: ValueKey('transaction-account-$kind'),
      initialValue: accountOptions.any((account) => account.id == accountId)
          ? accountId
          : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Account'),
      items: accountOptions
          .map(
            (account) => DropdownMenuItem(
              value: account.id,
              child: Text(
                account.isArchived
                    ? '${account.displayName} · currently archived'
                    : account.isCreditCard
                    ? '${account.displayName} · ${Money.format(account.debtMinor, currencyCode: widget.controller.currencyCode, locale: widget.controller.locale)} debt'
                    : '${account.displayName} · ${Money.format(account.balanceMinor, currencyCode: widget.controller.currencyCode, locale: widget.controller.locale)} balance',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (value) {
        setState(() {
          accountId = value;
          if (!canUseInstallment) {
            installmentEnabled = false;
            startInstallmentLater = false;
            downPaymentEnabled = false;
          } else if (installmentEnabled &&
              selectedAccount?.isCreditCard == true) {
            startInstallmentLater = false;
            downPaymentEnabled = false;
            if (installmentStartOn.isBefore(occurredOn)) {
              installmentStartOn = occurredOn;
            }
          } else if (installmentEnabled && !startInstallmentLater) {
            installmentStartOn = occurredOn;
          }
        });
      },
      validator: (value) {
        if (value == null) {
          return 'Create or choose a ${transactionScope.label} account.';
        }
        final selected = scopedAccounts
            .where((account) => account.id == value)
            .firstOrNull;
        if (selected == null) return 'Choose an available account.';
        if (kind == 'income' && selected.isCreditCard) {
          return 'Use Pay card to reduce credit card debt.';
        }
        return null;
      },
    );
    final categoryField = _categoryField(categories);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 500) {
          return Column(
            children: [accountField, const SizedBox(height: 14), categoryField],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: accountField),
            const SizedBox(width: 12),
            Expanded(child: categoryField),
          ],
        );
      },
    );
  }

  String? get _blockingFundingIssue {
    final amount = _parsedAmount;
    if (amount == null || amount <= 0 || amount > Money.maxMinorUnits) {
      return null;
    }
    if (isSplitMode) {
      if (amount < 2) return null;
      final firstShare = (amount + 1) ~/ 2;
      final secondShare = amount ~/ 2;
      if (firstSplitAccount != null &&
          firstSplitAccount!.balanceMinor < firstShare) {
        return 'First funding account cannot cover its share.';
      }
      if (secondSplitAccount != null &&
          secondSplitAccount!.balanceMinor < secondShare) {
        return 'Second funding account cannot cover its share.';
      }
      return null;
    }
    if (kind != 'expense') return null;
    final account = selectedAccount;
    if (isFutureInstallmentPlan) {
      final downPayment = _downPaymentChargeTodayMinor;
      if (downPayment <= 0 || planCreateAttempted) return null;
      return account == null ? null : _fundingIssueFor(account, downPayment);
    }
    return account == null ? null : _fundingIssueFor(account, amount);
  }

  String? _fundingIssueFor(Account account, int amount) {
    final projected = widget.controller.projectedBalanceAfterTransaction(
      account: account,
      existing: widget.existing,
      desiredAccountId: accountId ?? -1,
      desiredKind: kind,
      desiredAmountMinor: amount,
    );
    if (account.isCreditCard) {
      final limit = account.creditLimitMinor;
      if (limit != null && -projected > limit) {
        return 'Amount exceeds the card’s available credit.';
      }
      return null;
    }
    if (projected < 0 && projected < account.balanceMinor) {
      return 'Amount exceeds the account’s available balance.';
    }
    return null;
  }

  Widget _buildAccountBalancePreview() {
    final account = selectedAccount!;
    final amount = _parsedAmount;
    final downPaymentToday = _downPaymentChargeTodayMinor;
    final projected = isFutureInstallmentPlan
        ? downPaymentToday <= 0
              ? account.balanceMinor
              : widget.controller.projectedBalanceAfterTransaction(
                  account: account,
                  existing: null,
                  desiredAccountId: account.id,
                  desiredKind: 'expense',
                  desiredAmountMinor: downPaymentToday,
                )
        : amount == null || amount <= 0
        ? null
        : widget.controller.projectedBalanceAfterTransaction(
            account: account,
            existing: widget.existing,
            desiredAccountId: accountId ?? -1,
            desiredKind: kind,
            desiredAmountMinor: amount,
          );
    return _TransactionAccountBalancePreview(
      account: account,
      projectedBalanceMinor: projected,
      fundingIssue: amount == null || amount <= 0
          ? null
          : isFutureInstallmentPlan
          ? downPaymentToday <= 0 || planCreateAttempted
                ? null
                : _fundingIssueFor(account, downPaymentToday)
          : _fundingIssueFor(account, amount),
      replacingExisting:
          widget.existing != null && widget.existing!.accountId == account.id,
      currencyCode: widget.controller.currencyCode,
      locale: widget.controller.locale,
      plannedOnly: isFutureInstallmentPlan,
      plannedChargeMinor: downPaymentToday,
      isIdempotentRetry: planCreateAttempted,
    );
  }

  Widget _buildSplitFundingFields(List<Category> categories) {
    final palette = context.palette;
    return Column(
      children: [
        if (splitAccounts.length < 2) ...[
          Container(
            key: const Key('joint-split-account-requirement'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.orangeSoft,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              'Create at least two active standard Joint accounts to use Split 50/50.',
              style: TextStyle(
                color: palette.inkSoft,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final firstField = DropdownButtonFormField<int>(
              key: const Key('joint-split-first-account'),
              initialValue: firstSplitAccountId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'First funding account',
              ),
              items: splitAccounts
                  .map(
                    (account) => DropdownMenuItem(
                      value: account.id,
                      child: Text(
                        '${account.displayName} · ${Money.format(account.balanceMinor, currencyCode: widget.controller.currencyCode, locale: widget.controller.locale)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: saving
                  ? null
                  : (value) {
                      setState(() {
                        firstSplitAccountId = value;
                        if (secondSplitAccountId == value ||
                            !secondSplitOptions.any(
                              (account) => account.id == secondSplitAccountId,
                            )) {
                          secondSplitAccountId =
                              secondSplitOptions.firstOrNull?.id;
                        }
                      });
                    },
              validator: (value) =>
                  value == null ? 'Choose the first funding account.' : null,
            );
            final secondField = DropdownButtonFormField<int>(
              key: ValueKey('joint-split-second-$firstSplitAccountId'),
              initialValue:
                  secondSplitOptions.any(
                    (account) => account.id == secondSplitAccountId,
                  )
                  ? secondSplitAccountId
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Second funding account',
              ),
              items: secondSplitOptions
                  .map(
                    (account) => DropdownMenuItem(
                      value: account.id,
                      child: Text(
                        '${account.displayName} · ${Money.format(account.balanceMinor, currencyCode: widget.controller.currencyCode, locale: widget.controller.locale)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: saving
                  ? null
                  : (value) => setState(() => secondSplitAccountId = value),
              validator: (value) => value == null
                  ? 'Choose a different second funding account.'
                  : null,
            );
            if (constraints.maxWidth < 500) {
              return Column(
                children: [firstField, const SizedBox(height: 14), secondField],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: firstField),
                const SizedBox(width: 12),
                Expanded(child: secondField),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        _categoryField(categories),
      ],
    );
  }

  Widget _buildInstallmentFields() {
    final palette = context.palette;
    final monthly = _installmentMonthlyMinor;
    final months = _parsedInstallmentMonths;
    final account = selectedAccount;
    final isCard = account?.isCreditCard == true;
    return KeyedSubtree(
      key: const Key('transaction-installment-fields'),
      child: Container(
        key: const Key('credit-card-installment-fields'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.orangeSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: KeyedSubtree(
                key: const Key('transaction-installment-toggle'),
                child: SwitchListTile.adaptive(
                  key: const Key('credit-card-installment-toggle'),
                  value: installmentEnabled,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Installment payment'),
                  subtitle: Text(
                    isCard
                        ? 'Tracks monthly card billing. The full purchase becomes card debt now.'
                        : isFutureInstallmentPlan
                        ? 'Saves the schedule now without deducting a payment.'
                        : 'Records this monthly payment now and tracks the remaining plan.',
                  ),
                  secondary: const Icon(Icons.event_repeat_rounded),
                  onChanged: isPlanEditor
                      ? null
                      : (value) => setState(() {
                          installmentEnabled = value;
                          startInstallmentLater = false;
                          downPaymentEnabled = false;
                          installmentStartOn = occurredOn;
                        }),
                ),
              ),
            ),
            if (installmentEnabled) ...[
              const SizedBox(height: 10),
              if (!isCard && !isPlanEditor) ...[
                SizedBox(
                  key: const Key('transaction-installment-timing'),
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'now',
                        icon: Icon(Icons.payments_outlined),
                        label: Text('Pay now'),
                      ),
                      ButtonSegment(
                        value: 'later',
                        icon: Icon(Icons.event_outlined),
                        label: Text('Start later'),
                      ),
                    ],
                    selected: {startInstallmentLater ? 'later' : 'now'},
                    onSelectionChanged: (selection) => setState(() {
                      startInstallmentLater = selection.first == 'later';
                      if (!startInstallmentLater) downPaymentEnabled = false;
                      installmentStartOn = startInstallmentLater
                          ? _defaultNextMonthPaymentDate()
                          : occurredOn;
                    }),
                    showSelectedIcon: false,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (isFutureInstallmentPlan) ...[
                if (!isPlanEditor)
                  Material(
                    key: const Key('installment-down-payment-option'),
                    color: palette.surface.withValues(alpha: 0.7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                      side: BorderSide(color: palette.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: SwitchListTile.adaptive(
                      key: const Key('installment-down-payment-toggle'),
                      value: downPaymentEnabled,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      title: const Text('Down payment today'),
                      subtitle: const Text(
                        'Charge an optional amount now; monthly payments still begin on the selected date.',
                      ),
                      secondary: const Icon(Icons.savings_outlined),
                      onChanged: (value) => setState(() {
                        downPaymentEnabled = value;
                        if (!value) downPaymentController.clear();
                      }),
                    ),
                  ),
                if (downPaymentEnabled) ...[
                  if (!isPlanEditor) const SizedBox(height: 10),
                  TextFormField(
                    key: const Key('installment-down-payment-amount'),
                    controller: downPaymentController,
                    readOnly: isPlanEditor,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: isPlanEditor
                          ? 'Down payment paid'
                          : 'Down payment amount',
                      prefixText: widget.controller.currencyCode == 'PHP'
                          ? '₱ '
                          : null,
                      helperText: isPlanEditor
                          ? 'Already recorded as an expense and cannot be changed.'
                          : 'This is the only amount charged today.',
                    ),
                    validator: _validateDownPayment,
                  ),
                  if (isPlanEditor &&
                      widget.existingPlan?.downPaymentPaidOn != null) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Paid ${DateFormat('MMM d, y').format(widget.existingPlan!.downPaymentPaidOn!)}',
                        key: const Key('installment-down-payment-paid-date'),
                        style: TextStyle(
                          color: palette.success,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                ],
              ],
              LayoutBuilder(
                builder: (context, constraints) {
                  final monthsField = KeyedSubtree(
                    key: const Key('transaction-installment-months'),
                    child: TextFormField(
                      key: const Key('credit-card-installment-months'),
                      controller: installmentMonthsController,
                      readOnly: planTermsLocked,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Months',
                        hintText: '12',
                      ),
                      validator: (value) {
                        if (!installmentEnabled) return null;
                        final parsed = int.tryParse(value?.trim() ?? '');
                        if (parsed == null || parsed < 2 || parsed > 120) {
                          return 'Use 2 to 120 months.';
                        }
                        return null;
                      },
                    ),
                  );
                  if (!isCard && !isFutureInstallmentPlan) return monthsField;
                  final dateField = KeyedSubtree(
                    key: const Key('transaction-installment-start-date'),
                    child: InkWell(
                      onTap: planTermsLocked
                          ? null
                          : isCard
                          ? _pickInstallmentStartDate
                          : _pickFutureInstallmentStartDate,
                      borderRadius: BorderRadius.circular(11),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: isCard
                              ? 'First billing date'
                              : 'First payment date',
                          suffixIcon: const Icon(
                            Icons.calendar_today_rounded,
                            size: 18,
                          ),
                        ),
                        child: Text(
                          DateFormat('MMM d, y').format(installmentStartOn),
                        ),
                      ),
                    ),
                  );
                  if (constraints.maxWidth < 500) {
                    return Column(
                      children: [
                        monthsField,
                        const SizedBox(height: 14),
                        dateField,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: monthsField),
                      const SizedBox(width: 12),
                      Expanded(child: dateField),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              Align(
                key: const Key('transaction-installment-preview'),
                alignment: Alignment.centerLeft,
                child: Text(
                  monthly == null || months == null
                      ? isCard
                            ? 'Enter the total purchase amount and months.'
                            : 'Enter the monthly payment and number of months.'
                      : isCard
                      ? '${Money.format(monthly, currencyCode: widget.controller.currencyCode, locale: widget.controller.locale)} per month for $months months. The full purchase still counts as card debt now.'
                      : isFutureInstallmentPlan
                      ? _futureInstallmentPreview(monthly, months)
                      : '${Money.format(monthly, currencyCode: widget.controller.currencyCode, locale: widget.controller.locale)} per month for $months months. This payment is deducted from ${account?.displayName ?? 'the selected account'} on ${DateFormat('MMM d, y').format(occurredOn)}. Future payments are reminders only and are not deducted automatically.',
                  style: TextStyle(
                    color: palette.inkSoft,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isFutureInstallmentPlan &&
                  !widget.controller.hasLiveConnection) ...[
                const SizedBox(height: 9),
                Container(
                  key: const Key('installment-plan-offline-message'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: palette.border),
                  ),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Reconnect to save this plan. Your current draft and retry ID stay here.',
                        style: TextStyle(
                          color: palette.orange,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      OutlinedButton.icon(
                        key: const Key('installment-plan-reconnect'),
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
          ],
        ),
      ),
    );
  }

  Widget _categoryField(List<Category> categories) =>
      DropdownButtonFormField<int>(
        key: ValueKey('transaction-category-$kind-$isSplitMode'),
        initialValue: categories.any((category) => category.id == categoryId)
            ? categoryId
            : null,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Category'),
        items: categories
            .map(
              (category) => DropdownMenuItem(
                value: category.id,
                child: Text(
                  category.isArchived
                      ? '${category.name} · currently archived'
                      : category.name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: planTermsLocked ? null : (value) => categoryId = value,
        validator: (value) => value == null ? 'Choose a category.' : null,
      );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: occurredOn,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        occurredOn = picked;
        if (isAccountFundedInstallment) {
          installmentStartOn = picked;
        } else if (installmentStartOn.isBefore(picked)) {
          installmentStartOn = picked;
        }
      });
    }
  }

  Future<void> _pickInstallmentStartDate() async {
    if (selectedAccount?.isCreditCard != true) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: installmentStartOn.isBefore(occurredOn)
          ? occurredOn
          : installmentStartOn,
      firstDate: occurredOn,
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => installmentStartOn = picked);
  }

  DateTime _defaultNextMonthPaymentDate() {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month + 1, 1);
    final lastDay = DateTime(now.year, now.month + 2, 0).day;
    return DateTime(first.year, first.month, math.min(now.day, lastDay));
  }

  Future<void> _pickFutureInstallmentStartDate() async {
    if (!isAccountFundedInstallment) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstDate = isPlanEditor ? today : today.add(const Duration(days: 1));
    final initial = installmentStartOn.isBefore(firstDate)
        ? _defaultNextMonthPaymentDate()
        : installmentStartOn;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => installmentStartOn = picked);
  }

  Future<void> _save() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      if (isSplitMode) {
        await widget.controller.saveJointSplitExpense(
          clientUuid: clientUuid,
          firstAccountId: firstSplitAccountId!,
          secondAccountId: secondSplitAccountId!,
          amountMinor: Money.parse(amountController.text),
          occurredOn: occurredOn,
          categoryId: categoryId!,
          payee: payeeController.text,
          note: noteController.text,
        );
      } else if (isFutureInstallmentPlan) {
        final isRetry = widget.existingPlan == null && planCreateAttempted;
        if (widget.existingPlan == null) planCreateAttempted = true;
        await widget.controller.saveInstallmentPlan(
          existing: widget.existingPlan,
          clientUuid: clientUuid,
          accountId: accountId!,
          categoryId: categoryId!,
          installmentMonthlyMinor: Money.parse(amountController.text),
          installmentMonths: _parsedInstallmentMonths!,
          installmentStartOn: installmentStartOn,
          downPaymentMinor:
              widget.existingPlan?.downPaymentMinor ??
              (_parsedDownPaymentMinor ?? 0),
          payee: payeeController.text,
          note: noteController.text,
          isIdempotentRetry: isRetry,
        );
      } else {
        await widget.controller.saveTransaction(
          existing: widget.existing,
          clientUuid: clientUuid,
          kind: kind,
          amountMinor: Money.parse(amountController.text),
          occurredOn: occurredOn,
          accountId: accountId!,
          categoryId: categoryId!,
          payee: payeeController.text,
          note: noteController.text,
          installmentMonths: installmentEnabled
              ? _parsedInstallmentMonths
              : null,
          installmentStartOn: installmentEnabled
              ? selectedAccount?.isCreditCard == true
                    ? installmentStartOn
                    : occurredOn
              : null,
        );
      }
      if (mounted) {
        showSuccess(
          context,
          isSplitMode
              ? '50/50 Joint expense added as one logical expense.'
              : isFutureInstallmentPlan
              ? widget.existingPlan == null
                    ? _downPaymentChargeTodayMinor > 0
                          ? 'Installment plan saved and down payment recorded.'
                          : 'Installment plan saved. No money was deducted.'
                    : 'Installment plan updated.'
              : widget.controller.offlineTransactionsEnabled
              ? 'Saved on this device — sync pending.'
              : widget.existing == null
              ? 'Transaction added.'
              : 'Transaction updated.',
        );
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
        final accountOptions = scopedAccounts;
        final categoryOptions = _categoriesFor(kind);
        setState(() {
          if (!accountOptions.any((account) => account.id == accountId)) {
            accountId = accountOptions.firstOrNull?.id;
          }
          if (!categoryOptions.any((category) => category.id == categoryId)) {
            categoryId = categoryOptions.firstOrNull?.id;
          }
          reconnecting = false;
        });
      }
    }
  }
}

class _TransactionAccountBalancePreview extends StatelessWidget {
  const _TransactionAccountBalancePreview({
    required this.account,
    required this.projectedBalanceMinor,
    required this.fundingIssue,
    required this.replacingExisting,
    required this.currencyCode,
    required this.locale,
    this.plannedOnly = false,
    this.plannedChargeMinor = 0,
    this.isIdempotentRetry = false,
  });

  final Account account;
  final int? projectedBalanceMinor;
  final String? fundingIssue;
  final bool replacingExisting;
  final String currencyCode;
  final String locale;
  final bool plannedOnly;
  final int plannedChargeMinor;
  final bool isIdempotentRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final projected = projectedBalanceMinor;
    final isCard = account.isCreditCard;
    final limit = account.creditLimitMinor;
    final currentAvailable = account.availableCreditMinor;
    final projectedDebt = projected == null ? null : math.max(0, -projected);
    final projectedAvailable = projectedDebt == null || limit == null
        ? null
        : math.max(0, limit - projectedDebt);
    final metrics = <Widget>[
      if (isCard)
        _TransactionBalanceMetric(
          key: const Key('transaction-card-current-debt'),
          label: 'CURRENT DEBT',
          minorUnits: account.debtMinor,
          currencyCode: currencyCode,
          locale: locale,
        )
      else
        _TransactionBalanceMetric(
          key: const Key('transaction-account-current-balance'),
          label: 'CURRENT BALANCE',
          minorUnits: account.balanceMinor,
          currencyCode: currencyCode,
          locale: locale,
        ),
      if (isCard && limit != null)
        _TransactionBalanceMetric(
          key: const Key('transaction-card-available-credit'),
          label: 'AVAILABLE CREDIT',
          minorUnits: currentAvailable ?? 0,
          currencyCode: currencyCode,
          locale: locale,
        ),
      if (isCard && limit != null)
        _TransactionBalanceMetric(
          key: const Key('transaction-card-resulting-credit'),
          label: 'AFTER THIS EXPENSE',
          minorUnits: projectedAvailable,
          currencyCode: currencyCode,
          locale: locale,
          emphasized: true,
          negative: fundingIssue != null,
        )
      else if (isCard)
        _TransactionBalanceMetric(
          key: const Key('transaction-card-resulting-debt'),
          label: 'DEBT AFTER EXPENSE',
          minorUnits: projectedDebt,
          currencyCode: currencyCode,
          locale: locale,
          emphasized: true,
        )
      else
        _TransactionBalanceMetric(
          key: const Key('transaction-account-resulting-balance'),
          label: plannedOnly
              ? plannedChargeMinor > 0
                    ? 'AFTER DOWN PAYMENT'
                    : 'AFTER SAVING PLAN'
              : 'AFTER THIS EXPENSE',
          minorUnits: projected,
          currencyCode: currencyCode,
          locale: locale,
          emphasized: true,
          negative: projected != null && projected < 0,
        ),
    ];

    return Container(
      key: Key(
        isCard
            ? 'transaction-card-credit-preview'
            : 'transaction-account-balance-preview',
      ),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fundingIssue == null ? palette.surfaceMuted : palette.redSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: fundingIssue == null ? palette.border : palette.red,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: isCard ? palette.orangeSoft : palette.infoSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isCard
                      ? Icons.credit_card_rounded
                      : Icons.account_balance_wallet_outlined,
                  size: 18,
                  color: isCard ? palette.orange : palette.cyan,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      isCard
                          ? 'Credit available for this purchase'
                          : 'Available money in the selected account',
                      style: TextStyle(color: palette.muted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 430) {
                return Column(
                  children: [
                    for (var index = 0; index < metrics.length; index++) ...[
                      if (index > 0) const SizedBox(height: 8),
                      metrics[index],
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < metrics.length; index++) ...[
                    if (index > 0) const SizedBox(width: 8),
                    Expanded(child: metrics[index]),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          if (fundingIssue != null)
            _TransactionFundingMessage(
              key: const Key('transaction-account-insufficient-funds'),
              icon: Icons.block_rounded,
              color: palette.red,
              message:
                  '$fundingIssue ${plannedOnly ? 'This installment plan' : 'This transaction'} will not be saved.',
            )
          else if (isCard && limit == null)
            _TransactionFundingMessage(
              key: const Key('transaction-card-no-credit-limit'),
              icon: Icons.info_outline_rounded,
              color: palette.orange,
              message: 'No credit limit is saved, so available credit cannot be checked here. The dated card ledger is still checked when you save.',
            )
          else if (projected == null)
            _TransactionFundingMessage(
              icon: Icons.edit_outlined,
              color: palette.muted,
              message: 'Enter an amount to preview the remaining balance.',
            )
          else if (plannedOnly && isIdempotentRetry)
            _TransactionFundingMessage(
              key: const Key('transaction-installment-down-payment-retry'),
              icon: Icons.replay_rounded,
              color: palette.orange,
              message: 'Retrying this same plan will not charge the down payment twice.',
            )
          else if (plannedOnly && plannedChargeMinor > 0)
            _TransactionFundingMessage(
              key: const Key('transaction-installment-down-payment-funded'),
              icon: Icons.check_circle_outline_rounded,
              color: palette.success,
              message: 'This account can cover the down payment today. Monthly payments are checked only when you record them.',
            )
          else if (plannedOnly)
            _TransactionFundingMessage(
              key: const Key('transaction-installment-no-current-deduction'),
              icon: Icons.event_available_outlined,
              color: palette.success,
              message: 'Nothing is deducted today. The balance is checked when you record each payment.',
            )
          else if (!isCard && projected < 0)
            _TransactionFundingMessage(
              icon: Icons.trending_up_rounded,
              color: palette.orange,
              message: 'This edit improves the account, but its saved balance remains below zero.',
            )
          else
            _TransactionFundingMessage(
              key: const Key('transaction-account-balance-message'),
              icon: Icons.check_circle_outline_rounded,
              color: palette.success,
              message: isCard
                  ? 'The card can cover this full purchase amount.'
                  : 'This account can cover the expense.',
            ),
          if (replacingExisting) ...[
            const SizedBox(height: 6),
            Text(
              'The existing transaction is reversed before this new amount is calculated.',
              style: TextStyle(color: palette.muted, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _TransactionBalanceMetric extends StatelessWidget {
  const _TransactionBalanceMetric({
    super.key,
    required this.label,
    required this.minorUnits,
    required this.currencyCode,
    required this.locale,
    this.emphasized = false,
    this.negative = false,
  });

  final String label;
  final int? minorUnits;
  final String currencyCode;
  final String locale;
  final bool emphasized;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: negative ? palette.red : palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: palette.muted,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.65,
            ),
          ),
          const SizedBox(height: 4),
          if (minorUnits == null)
            Text(
              'Enter amount',
              style: TextStyle(
                color: palette.inkSoft,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            MoneyLabel(
              minorUnits: minorUnits!,
              currencyCode: currencyCode,
              locale: locale,
              compact: true,
              style: TextStyle(
                color: negative
                    ? palette.red
                    : emphasized
                    ? palette.greenDark
                    : palette.ink,
                fontSize: emphasized ? 16 : 14,
                fontWeight: FontWeight.w900,
              ),
            ),
        ],
      ),
    );
  }
}

class _TransactionFundingMessage extends StatelessWidget {
  const _TransactionFundingMessage({
    super.key,
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          message,
          style: TextStyle(
            color: color,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
      ),
    ],
  );
}

class _FundingModeTile extends StatelessWidget {
  const _FundingModeTile({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? context.palette.mint : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? context.palette.green : context.palette.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: selected
                  ? context.palette.greenDark
                  : context.palette.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected
                      ? context.palette.greenDark
                      : context.palette.inkSoft,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 19,
              color: selected ? context.palette.green : context.palette.muted,
            ),
          ],
        ),
      ),
    ),
  );
}

class _JointSplitPreview extends StatelessWidget {
  const _JointSplitPreview({
    required this.firstAccount,
    required this.secondAccount,
    required this.amountMinor,
    required this.currencyCode,
    required this.locale,
  });

  final Account? firstAccount;
  final Account? secondAccount;
  final int? amountMinor;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final amount = amountMinor ?? 0;
    final valid = amount >= 2 && amount <= Money.maxMinorUnits;
    final firstShare = valid ? (amount + 1) ~/ 2 : null;
    final secondShare = valid ? amount ~/ 2 : null;
    final firstAfter = firstAccount == null || firstShare == null
        ? null
        : firstAccount!.balanceMinor - firstShare;
    final secondAfter = secondAccount == null || secondShare == null
        ? null
        : secondAccount!.balanceMinor - secondShare;
    return Container(
      key: const Key('joint-split-preview'),
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
          Row(
            children: [
              Expanded(
                child: Text(
                  '50/50 FUNDING PREVIEW',
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (valid)
                MoneyLabel(
                  key: const Key('joint-split-total'),
                  minorUnits: amount,
                  currencyCode: currencyCode,
                  locale: locale,
                  style: TextStyle(
                    color: palette.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 11),
          LayoutBuilder(
            builder: (context, constraints) {
              final first = _JointSplitShare(
                key: const Key('joint-split-first-preview'),
                label: 'First funding account',
                accountName: firstAccount?.displayName,
                shareMinor: firstShare,
                resultingMinor: firstAfter,
                currencyCode: currencyCode,
                locale: locale,
              );
              final second = _JointSplitShare(
                key: const Key('joint-split-second-preview'),
                label: 'Second funding account',
                accountName: secondAccount?.displayName,
                shareMinor: secondShare,
                resultingMinor: secondAfter,
                currencyCode: currencyCode,
                locale: locale,
              );
              if (constraints.maxWidth < 470) {
                return Column(
                  children: [first, const SizedBox(height: 10), second],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: first),
                  const SizedBox(width: 12),
                  Expanded(child: second),
                ],
              );
            },
          ),
          const SizedBox(height: 11),
          Text(
            valid && amount.isOdd
                ? 'The total has an odd centavo, so the first funding account pays the extra ₱0.01.'
                : 'Each funding account pays an equal share.',
            style: TextStyle(
              color: palette.inkSoft,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'This is one Joint expense. The full total affects cashflow, cutoff spending, and budget once.',
            style: TextStyle(
              color: palette.inkSoft,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'For a backdated expense, each account must cover its share both on that date and today.',
            style: TextStyle(color: palette.muted, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 5),
          Text(
            'After saving, this split expense cannot be edited or deleted. Review both accounts, the date, and the category first.',
            style: TextStyle(
              color: palette.inkSoft,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _JointSplitShare extends StatelessWidget {
  const _JointSplitShare({
    super.key,
    required this.label,
    required this.accountName,
    required this.shareMinor,
    required this.resultingMinor,
    required this.currencyCode,
    required this.locale,
  });

  final String label;
  final String? accountName;
  final int? shareMinor;
  final int? resultingMinor;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(color: context.palette.muted, fontSize: 11.5),
      ),
      const SizedBox(height: 2),
      Text(
        accountName ?? 'Choose an account',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: context.palette.ink,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        shareMinor == null
            ? 'Enter at least 0.02'
            : '−${Money.format(shareMinor!, currencyCode: currencyCode, locale: locale)}',
        style: TextStyle(
          color: context.palette.red,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        resultingMinor == null
            ? 'Resulting balance unavailable'
            : '${Money.format(resultingMinor!, currencyCode: currencyCode, locale: locale)} after',
        style: TextStyle(color: context.palette.muted, fontSize: 11.5),
      ),
    ],
  );
}
