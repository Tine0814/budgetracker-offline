import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../models/domain_models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../account_designs.dart';
import '../widgets/common.dart';

const _cardLiabilityAccent = Color(0xFFFFA13D);

String _formatMonthlyInterestRate(int basisPoints) {
  final whole = basisPoints ~/ 100;
  final fraction = basisPoints % 100;
  if (fraction == 0) return '$whole';
  if (fraction % 10 == 0) return '$whole.${fraction ~/ 10}';
  return '$whole.${fraction.toString().padLeft(2, '0')}';
}

int _parseMonthlyInterestRateBasisPoints(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw const FormatException(
      'Enter a monthly rate, or use 0 to turn it off.',
    );
  }
  final match = RegExp(r'^(\d{1,3})(?:\.(\d{1,2}))?$').firstMatch(normalized);
  if (match == null) {
    throw const FormatException('Use a percentage with up to 2 decimals.');
  }
  final whole = int.parse(match.group(1)!);
  final fractionText = match.group(2) ?? '';
  final fraction = fractionText.isEmpty
      ? 0
      : int.parse(fractionText.padRight(2, '0'));
  final basisPoints = whole * 100 + fraction;
  if (basisPoints > 10000) {
    throw const FormatException('Monthly rate cannot be above 100%.');
  }
  return basisPoints;
}

String _savingsInterestScheduleLabel(Account account) {
  if (!account.hasConsistentInterestScheduleMetadata) {
    final rate = _formatMonthlyInterestRate(
      account.monthlyInterestRateBasisPoints,
    );
    return '$rate% monthly · schedule needs attention';
  }
  if (!account.hasAutomaticMonthlyInterest) return 'Automatic interest off';
  final rate = _formatMonthlyInterestRate(
    account.monthlyInterestRateBasisPoints,
  );
  final next = account.nextInterestAccrualOn;
  return next == null
      ? '$rate% monthly interest'
      : '$rate% monthly · next ${DateFormat('MMM d').format(next)}';
}

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  AppController get controller => widget.controller;
  bool get hasEnabledAutomaticSavingsInterest => controller.savingsAccounts.any(
    (account) => account.hasAutomaticMonthlyInterest,
  );
  bool get canPayCreditCard =>
      controller.hasLiveConnection &&
      controller.creditCardPaymentSourceAccounts.isNotEmpty &&
      controller.creditCardAccounts.any((account) => account.debtMinor > 0) &&
      !controller.offlineTransactionOperations.any(
        (operation) => operation.scope == controller.selectedFinanceScope,
      );

  @override
  void initState() {
    super.initState();
    _queueTransferHistoryLoad();
  }

  void _queueTransferHistoryLoad() {
    final scope = controller.selectedFinanceScope;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || controller.selectedFinanceScope != scope) return;
      final shouldAccrue = hasEnabledAutomaticSavingsInterest;
      await Future.wait([
        controller.refreshAccountTransfers(silent: true),
        controller.refreshCreditCardPayments(silent: true),
        if (!shouldAccrue)
          controller.refreshSavingsInterestCredits(silent: true),
      ]);
      if (shouldAccrue && mounted && controller.selectedFinanceScope == scope) {
        // Run this last so an accrual/reconciliation warning is not cleared by
        // a successful history read finishing moments later.
        await controller.accrueSavingsInterest(silent: true);
      }
      if (mounted && controller.selectedFinanceScope == scope) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = controller.selectedFinanceScope;
    final isJoint = scope == FinanceScope.joint;
    if (!controller.hasSavedAccounts) {
      return SingleChildScrollView(
        padding: responsivePagePadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: isJoint ? 'Joint accounts' : 'Personal accounts',
              subtitle: 'Account balances have not been saved on this device for this money scope.',
              actions: [
                FinanceScopeSelector(
                  selected: scope,
                  onSelected: controller.setFinanceScope,
                ),
                OutlinedButton.icon(
                  onPressed: controller.refreshAll,
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                  label: const Text('Refresh saved data'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FinanceScopeNotice(scope: scope),
            const SizedBox(height: 24),
            const SectionCard(
              child: EmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'Accounts are not saved on this device',
                message: 'Your account balances could not be read. Try refreshing saved data.',
              ),
            ),
          ],
        ),
      );
    }
    final availableTotal = controller.accounts
        .where((account) => account.countsTowardAvailableMoney)
        .fold<int>(0, (sum, account) => sum + account.balanceMinor);
    final savingsTotal = controller.accounts
        .where((account) => account.isSavingsAccount)
        .fold<int>(0, (sum, account) => sum + account.balanceMinor);
    final totalDebt = controller.accounts
        .where((account) => account.isCreditCard)
        .fold<int>(0, (sum, account) => sum + account.debtMinor);
    return SingleChildScrollView(
      padding: responsivePagePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: isJoint ? 'Joint accounts' : 'Personal accounts',
            subtitle: isJoint
                ? 'Accounts you use for shared savings, income, and expenses.'
                : 'Keep track of your cash, savings, and credit cards.',
            actions: [
              FinanceScopeSelector(
                selected: scope,
                onSelected: controller.setFinanceScope,
              ),
              OutlinedButton.icon(
                key: const Key('transfer-money-button'),
                onPressed: () => _showTransfer(context),
                icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                label: const Text('Transfer money'),
              ),
              if (controller.creditCardAccounts.isNotEmpty)
                OutlinedButton.icon(
                  key: const Key('pay-credit-card-button'),
                  onPressed: canPayCreditCard
                      ? () => _showCardPayment(context)
                      : null,
                  icon: const Icon(Icons.credit_score_rounded, size: 20),
                  label: const Text('Pay card'),
                ),
              FilledButton.icon(
                onPressed: () => _showEditor(context),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add account'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FinanceScopeNotice(scope: scope),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [context.palette.heroStart, context.palette.heroEnd],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: context.palette.onHero.withValues(alpha: 0.18),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final balance = Row(
                  children: [
                    Container(
                      width: 49,
                      height: 49,
                      decoration: BoxDecoration(
                        color: context.palette.onHero.withValues(alpha: 0.11),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        Icons.account_balance_wallet_rounded,
                        color: context.palette.onHero,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isJoint
                                ? 'Joint available money'
                                : 'Personal available money',
                            style: TextStyle(
                              color: context.palette.onHeroMuted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: MoneyLabel(
                              key: const Key('accounts-available-money-total'),
                              minorUnits: availableTotal,
                              currencyCode: controller.currencyCode,
                              locale: controller.locale,
                              style: TextStyle(
                                color: context.palette.onHero,
                                fontSize: 29,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                final count = Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${controller.accounts.length} active ${scope.label.toLowerCase()} account${controller.accounts.length == 1 ? '' : 's'}',
                      style: TextStyle(color: context.palette.onHeroMuted),
                    ),
                    if (controller.savingsAccounts.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${Money.format(savingsTotal, currencyCode: controller.currencyCode, locale: controller.locale)} set aside in savings',
                        key: const Key('accounts-savings-total'),
                        style: TextStyle(
                          color: context.palette.onHero,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (totalDebt > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${Money.format(totalDebt, currencyCode: controller.currencyCode, locale: controller.locale)} credit card debt',
                        key: const Key('accounts-credit-card-debt-total'),
                        style: TextStyle(
                          color: context.palette.onHero,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                );
                if (constraints.maxWidth < 600) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [balance, const SizedBox(height: 12), count],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: balance),
                    const SizedBox(width: 20),
                    count,
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final gallery = _AccountGallery(
                key: const Key('accounts-grid'),
                accounts: controller.accounts,
                controller: controller,
                isJoint: isJoint,
                canPayCreditCard: canPayCreditCard,
                onAdd: () => _showEditor(context),
                onAddCreditCard: () =>
                    _showEditor(context, initialType: 'credit_card'),
                onAddSavings: () =>
                    _showEditor(context, initialType: 'savings'),
                onEdit: (account) => _showEditor(context, account: account),
                onDelete: (account) => _delete(context, account),
                onPay: (account) => _showCardPayment(context, account),
              );
              final histories = Column(
                key: const Key('accounts-history-rail'),
                children: [
                  _TransferHistory(
                    transfers: controller.accountTransfers,
                    controller: controller,
                    available: controller.hasSavedAccountTransfers,
                    onRefresh: () => _refreshTransfers(context),
                  ),
                  const SizedBox(height: 18),
                  _CreditCardPaymentHistory(
                    payments: controller.creditCardPayments,
                    controller: controller,
                    available: controller.hasSavedCreditCardPayments,
                    onRefresh: () => _refreshCardPayments(context),
                  ),
                  const SizedBox(height: 18),
                  _SavingsInterestHistory(
                    credits: controller.savingsInterestCredits,
                    controller: controller,
                    available: controller.hasSavedSavingsInterestCredits,
                    onRefresh: () => _refreshSavingsInterest(context),
                  ),
                ],
              );
              if (constraints.maxWidth < 1080) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [gallery, const SizedBox(height: 24), histories],
                );
              }
              final railWidth = (constraints.maxWidth * 0.30).clamp(
                340.0,
                390.0,
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: gallery),
                  const SizedBox(width: 18),
                  SizedBox(width: railWidth, child: histories),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showEditor(
    BuildContext context, {
    Account? account,
    String? initialType,
  }) => showDialog<void>(
    context: context,
    builder: (context) => _AccountDialog(
      controller: controller,
      existing: account,
      initialType: initialType,
    ),
  );

  Future<void> _showTransfer(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AccountTransferDialog(controller: controller),
    );
    if (mounted) setState(() {});
  }

  Future<void> _showCardPayment(
    BuildContext context, [
    Account? creditCard,
  ]) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CreditCardPaymentDialog(
        controller: controller,
        initialCreditCard: creditCard,
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _refreshTransfers(BuildContext context) async {
    try {
      await controller.refreshAccountTransfers();
      if (mounted) setState(() {});
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _refreshCardPayments(BuildContext context) async {
    try {
      await controller.refreshCreditCardPayments();
      if (mounted) setState(() {});
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _refreshSavingsInterest(BuildContext context) async {
    try {
      if (!hasEnabledAutomaticSavingsInterest) {
        await controller.refreshSavingsInterestCredits();
      } else {
        final accrual = await controller.accrueSavingsInterest();
        if (accrual == null && controller.errorMessage == null) {
          await controller.refreshSavingsInterestCredits();
        }
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _delete(BuildContext context, Account account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${account.name}?'),
        content: const Text(
          'This removes the account from active lists and new transactions. '
          'Past transactions and reports remain intact.',
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
      await controller.deleteAccount(account);
      if (context.mounted) showSuccess(context, 'Account deleted.');
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }
}

class _AccountGallery extends StatelessWidget {
  const _AccountGallery({
    super.key,
    required this.accounts,
    required this.controller,
    required this.isJoint,
    required this.canPayCreditCard,
    required this.onAdd,
    required this.onAddCreditCard,
    required this.onAddSavings,
    required this.onEdit,
    required this.onDelete,
    required this.onPay,
  });

  final List<Account> accounts;
  final AppController controller;
  final bool isJoint;
  final bool canPayCreditCard;
  final VoidCallback onAdd;
  final VoidCallback onAddCreditCard;
  final VoidCallback onAddSavings;
  final ValueChanged<Account> onEdit;
  final ValueChanged<Account> onDelete;
  final ValueChanged<Account> onPay;

  @override
  Widget build(BuildContext context) {
    if (accounts.isEmpty) {
      return SectionCard(
        child: EmptyState(
          icon: Icons.account_balance_wallet_outlined,
          title: isJoint
              ? 'Add your first Joint account'
              : 'Add your first Personal account',
          message: isJoint
              ? 'Create an account for combined funds, shared savings, or either partner’s contribution.'
              : 'Create a cash, bank, or e-wallet account for your own money.',
          action: FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add account'),
          ),
        ),
      );
    }
    final standardAccounts = accounts
        .where((account) => !account.isCreditCard && !account.isSavingsAccount)
        .toList();
    final savingsAccounts = accounts
        .where((account) => account.isSavingsAccount)
        .toList();
    final creditCards = accounts
        .where((account) => account.isCreditCard)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (standardAccounts.isNotEmpty) ...[
          _AccountGroup(
            key: const Key('accounts-standard-section'),
            gridKey: const Key('accounts-standard-grid'),
            title: 'Cash, bank & e-wallets',
            subtitle: 'Available money and everyday accounts.',
            accounts: standardAccounts,
            emptyIcon: Icons.account_balance_wallet_outlined,
            emptyTitle: 'No cash or bank accounts yet',
            emptyMessage:
                'Add cash, bank, e-wallet, or other money accounts here.',
            controller: controller,
            canPayCreditCard: canPayCreditCard,
            onEdit: onEdit,
            onDelete: onDelete,
            onPay: onPay,
          ),
          const SizedBox(height: 28),
        ],
        _AccountGroup(
          key: const Key('accounts-savings-section'),
          gridKey: const Key('accounts-savings-grid'),
          title: 'Savings',
          subtitle: 'Money set aside from your available total, with optional automatic monthly interest.',
          accounts: savingsAccounts,
          emptyIcon: Icons.savings_outlined,
          emptyTitle: 'No savings account yet',
          emptyMessage:
              'Create one to set money aside without counting it as available.',
          controller: controller,
          canPayCreditCard: canPayCreditCard,
          onEdit: onEdit,
          onDelete: onDelete,
          onPay: onPay,
          action: OutlinedButton.icon(
            key: const Key('add-savings-account-button'),
            onPressed: onAddSavings,
            icon: const Icon(Icons.savings_rounded, size: 18),
            label: const Text('Add savings'),
          ),
        ),
        const SizedBox(height: 28),
        _AccountGroup(
          key: const Key('accounts-credit-card-section'),
          gridKey: const Key('accounts-credit-card-grid'),
          title: 'Credit cards',
          subtitle: 'Debt, available credit, statement dates, and due dates.',
          accounts: creditCards,
          emptyIcon: Icons.credit_card_off_outlined,
          emptyTitle: 'No credit cards yet',
          emptyMessage:
              'Add a card to track purchases, debt, and payments separately.',
          controller: controller,
          canPayCreditCard: canPayCreditCard,
          onEdit: onEdit,
          onDelete: onDelete,
          onPay: onPay,
          action: OutlinedButton.icon(
            key: const Key('add-credit-card-button'),
            onPressed: onAddCreditCard,
            icon: const Icon(Icons.add_card_rounded, size: 18),
            label: const Text('Add credit card'),
          ),
        ),
      ],
    );
  }
}

class _AccountGroup extends StatelessWidget {
  const _AccountGroup({
    super.key,
    required this.title,
    required this.subtitle,
    required this.gridKey,
    required this.accounts,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.controller,
    required this.canPayCreditCard,
    required this.onEdit,
    required this.onDelete,
    required this.onPay,
    this.action,
  });

  final String title;
  final String subtitle;
  final Key gridKey;
  final List<Account> accounts;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;
  final AppController controller;
  final bool canPayCreditCard;
  final ValueChanged<Account> onEdit;
  final ValueChanged<Account> onDelete;
  final ValueChanged<Account> onPay;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final heading = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: context.palette.infoSoft,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: context.palette.border),
                    ),
                    child: Text(
                      '${accounts.length}',
                      style: TextStyle(
                        color: context.palette.inkSoft,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(color: context.palette.muted, fontSize: 12),
              ),
            ],
          );
          if (action == null) return heading;
          if (constraints.maxWidth < 480) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [heading, const SizedBox(height: 10), action!],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: heading),
              const SizedBox(width: 12),
              action!,
            ],
          );
        },
      ),
      const SizedBox(height: 12),
      if (accounts.isEmpty)
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: context.palette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.palette.border),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: context.palette.surfaceMuted,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(emptyIcon, color: context.palette.cyan, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      emptyTitle,
                      style: TextStyle(
                        color: context.palette.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      emptyMessage,
                      style: TextStyle(
                        color: context.palette.muted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        )
      else
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1100
                ? 3
                : constraints.maxWidth >= 650
                ? 2
                : 1;
            final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
            return KeyedSubtree(
              key: gridKey,
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                children: accounts
                    .map(
                      (account) => SizedBox(
                        width: width,
                        child: _AccountCard(
                          key: ValueKey('account-card-${account.id}'),
                          account: account,
                          controller: controller,
                          onEdit: () => onEdit(account),
                          onDelete: () => onDelete(account),
                          onPay:
                              account.isCreditCard &&
                                  canPayCreditCard &&
                                  account.debtMinor > 0
                              ? () => onPay(account)
                              : null,
                        ),
                      ),
                    )
                    .toList(),
              ),
            );
          },
        ),
    ],
  );
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    super.key,
    required this.account,
    required this.controller,
    required this.onEdit,
    required this.onDelete,
    this.onPay,
  });

  final Account account;
  final AppController controller;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final design = bankCardDesignFor(account.cardDesign);
    final palette = AccountCardVisual.forAccount(
      account,
      design,
      context.palette,
    );
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final ratioHeight = constraints.maxWidth / 1.586;
        final scaleDelta = (textScale - 1).clamp(0.0, 1.0).toDouble();
        final minimumHeight = 238.0 + (scaleDelta * 82.0);
        final height = ratioHeight > minimumHeight
            ? ratioHeight
            : minimumHeight;
        return Semantics(
          container: true,
          label:
              '${account.displayName}, ${accountCardTypeLabel(account.type)}, ${account.scope.accountLabel}',
          child: SizedBox(
            height: height,
            child: Material(
              color: Colors.transparent,
              elevation: 0,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [palette.primary, palette.secondary],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: account.isCreditCard
                        ? _cardLiabilityAccent.withValues(alpha: 0.78)
                        : palette.foreground.withValues(alpha: 0.15),
                    width: account.isCreditCard ? 1.5 : 1,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 22,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    IgnorePointer(
                      child: CustomPaint(
                        painter: BankCardPatternPainter(
                          pattern: design.pattern,
                          accent: palette.accent,
                          foreground: palette.foreground,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                constraints: const BoxConstraints(
                                  minWidth: 42,
                                  minHeight: 30,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: palette.foreground.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                    color: palette.foreground.withValues(
                                      alpha: 0.16,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  design.key == 'other'
                                      ? accountCardShortMark(account.type)
                                      : design.shortMark,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: palette.foreground,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.7,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  design.key == 'other'
                                      ? accountCardTypeLabel(account.type)
                                      : design.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: palette.foreground.withValues(
                                      alpha: 0.86,
                                    ),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (account.isSystem)
                                Tooltip(
                                  message:
                                      'This account is managed automatically',
                                  child: Icon(
                                    Icons.lock_outline_rounded,
                                    color: palette.foreground,
                                  ),
                                )
                              else
                                PopupMenuButton<String>(
                                  tooltip: 'Account actions',
                                  icon: Icon(
                                    Icons.more_horiz_rounded,
                                    color: palette.foreground,
                                  ),
                                  onSelected: (value) => switch (value) {
                                    'pay' => onPay?.call(),
                                    'edit' => onEdit(),
                                    _ => onDelete(),
                                  },
                                  itemBuilder: (_) => [
                                    if (account.isCreditCard)
                                      PopupMenuItem(
                                        value: 'pay',
                                        enabled: onPay != null,
                                        child: const ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: Icon(
                                            Icons.credit_score_rounded,
                                            size: 19,
                                          ),
                                          title: Text('Pay card'),
                                        ),
                                      ),
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(
                                          Icons.edit_rounded,
                                          size: 19,
                                        ),
                                        title: Text('Edit'),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(
                                          Icons.delete_outline_rounded,
                                          color: context.palette.red,
                                          size: 19,
                                        ),
                                        title: Text(
                                          'Delete',
                                          style: TextStyle(
                                            color: context.palette.red,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _CardChip(
                                foreground: palette.foreground,
                                accent: palette.accent,
                              ),
                              if (account.isCreditCard) ...[
                                const SizedBox(width: 8),
                                _CreditLiabilityBadge(
                                  key: ValueKey(
                                    'credit-card-liability-badge-${account.id}',
                                  ),
                                  foreground: palette.foreground,
                                  compact:
                                      constraints.maxWidth < 400 ||
                                      textScale > 1.15,
                                ),
                              ],
                              if (account.isSavingsAccount) ...[
                                const SizedBox(width: 8),
                                _SavingsBadge(
                                  key: ValueKey(
                                    'savings-excluded-badge-${account.id}',
                                  ),
                                  foreground: palette.foreground,
                                ),
                              ],
                              const Spacer(),
                              Icon(
                                Icons.contactless_rounded,
                                size: 25,
                                color: palette.foreground.withValues(
                                  alpha: 0.78,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            account.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.foreground,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            account.isCreditCard
                                ? 'CURRENT DEBT'
                                : account.isSavingsAccount
                                ? 'SAVINGS BALANCE'
                                : 'CURRENT BALANCE',
                            style: TextStyle(
                              color: palette.foreground.withValues(alpha: 0.68),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: MoneyLabel(
                                minorUnits: account.isCreditCard
                                    ? account.debtMinor
                                    : account.balanceMinor,
                                currencyCode: controller.currencyCode,
                                locale: controller.locale,
                                style: TextStyle(
                                  color: palette.foreground,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: _BankCardMetric(
                                  label: account.isCreditCard
                                      ? 'Opening debt'
                                      : 'Opening balance',
                                  minorUnits: account.isCreditCard
                                      ? account.openingDebtMinor
                                      : account.openingBalanceMinor,
                                  controller: controller,
                                  foreground: palette.foreground,
                                ),
                              ),
                              if (account.isCreditCard &&
                                  account.creditLimitMinor != null) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _BankCardMetric(
                                    label: 'Available credit',
                                    minorUnits:
                                        account.availableCreditMinor ?? 0,
                                    controller: controller,
                                    foreground: palette.foreground,
                                    alignEnd: true,
                                  ),
                                ),
                              ] else
                                Expanded(
                                  child: Text(
                                    account.isDealsPenaltyMoney
                                        ? 'Deals penalty money'
                                        : account.isSavingsAccount
                                        ? _savingsInterestScheduleLabel(account)
                                        : account.scope.accountLabel,
                                    key: account.isSavingsAccount
                                        ? ValueKey(
                                            'savings-interest-rate-${account.id}',
                                          )
                                        : null,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.end,
                                    style: TextStyle(
                                      color: palette.foreground.withValues(
                                        alpha: 0.72,
                                      ),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (account.isCreditCard &&
                              (account.statementDay != null ||
                                  account.dueDay != null)) ...[
                            const SizedBox(height: 5),
                            Text(
                              [
                                if (account.statementDay != null)
                                  'Statement day ${account.statementDay}',
                                if (account.dueDay != null)
                                  'Due day ${account.dueDay}',
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.foreground.withValues(
                                  alpha: 0.68,
                                ),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CardChip extends StatelessWidget {
  const _CardChip({required this.foreground, required this.accent});

  final Color foreground;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    width: 37,
    height: 27,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          accent.withValues(alpha: 0.95),
          foreground.withValues(alpha: 0.8),
        ],
      ),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: foreground.withValues(alpha: 0.34)),
    ),
    child: CustomPaint(painter: _ChipLinePainter(foreground)),
  );
}

class _CreditLiabilityBadge extends StatelessWidget {
  const _CreditLiabilityBadge({
    super.key,
    required this.foreground,
    this.compact = false,
  });

  final Color foreground;
  final bool compact;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 8,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: _cardLiabilityAccent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _cardLiabilityAccent.withValues(alpha: 0.76)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.credit_card_rounded,
            size: compact ? 11 : 12,
            color: _cardLiabilityAccent,
          ),
          const SizedBox(width: 4),
          Text(
            compact ? 'CREDIT' : 'CREDIT · LIABILITY',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: foreground,
              fontSize: compact ? 8 : 8.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.65,
            ),
          ),
        ],
      ),
    ),
  );
}

class _SavingsBadge extends StatelessWidget {
  const _SavingsBadge({super.key, required this.foreground});

  final Color foreground;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      key: const Key('savings-account-set-aside-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foreground.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.savings_rounded, size: 12, color: foreground),
          const SizedBox(width: 4),
          Text(
            'SET ASIDE',
            style: TextStyle(
              color: foreground,
              fontSize: 8.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.65,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ChipLinePainter extends CustomPainter {
  const _ChipLinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.36)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(size.width * 0.34, 0),
      Offset(size.width * 0.34, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.67, 0),
      Offset(size.width * 0.67, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.5),
      Offset(size.width, size.height * 0.5),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ChipLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _BankCardMetric extends StatelessWidget {
  const _BankCardMetric({
    required this.label,
    required this.minorUnits,
    required this.controller,
    required this.foreground,
    this.alignEnd = false,
  });

  final String label;
  final int minorUnits;
  final AppController controller;
  final Color foreground;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: alignEnd
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    children: [
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: foreground.withValues(alpha: 0.62),
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
        child: MoneyLabel(
          minorUnits: minorUnits,
          currencyCode: controller.currencyCode,
          locale: controller.locale,
          style: TextStyle(
            color: foreground.withValues(alpha: 0.9),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ],
  );
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({
    required this.controller,
    this.existing,
    this.initialType,
  });
  final AppController controller;
  final Account? existing;
  final String? initialType;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  final key = GlobalKey<FormState>();
  late final TextEditingController nameController;
  late final TextEditingController balanceController;
  late final TextEditingController interestRateController;
  late final TextEditingController creditLimitController;
  late final TextEditingController statementDayController;
  late final TextEditingController dueDayController;
  late String type;
  late String cardDesign;
  String color = '#43D98B';
  bool saving = false;

  static const colors = [
    '#43D98B',
    '#6F92FF',
    '#55D7E8',
    '#C74AF3',
    '#FFA13D',
    '#FF607B',
  ];

  FinanceScope get scope => FinanceScope.personal;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.existing?.name ?? '');
    balanceController = TextEditingController(
      text: widget.existing == null
          ? ''
          : Money.decimal(
              widget.existing!.isCreditCard
                  ? widget.existing!.openingDebtMinor
                  : widget.existing!.openingBalanceMinor,
            ),
    );
    interestRateController = TextEditingController(
      text: widget.existing?.isSavingsAccount == true
          ? _formatMonthlyInterestRate(
              widget.existing!.monthlyInterestRateBasisPoints,
            )
          : '0',
    );
    creditLimitController = TextEditingController(
      text: widget.existing?.creditLimitMinor == null
          ? ''
          : Money.decimal(widget.existing!.creditLimitMinor!),
    );
    statementDayController = TextEditingController(
      text: widget.existing?.statementDay?.toString() ?? '',
    );
    dueDayController = TextEditingController(
      text: widget.existing?.dueDay?.toString() ?? '',
    );
    nameController.addListener(_rebuildDesignPreview);
    type = widget.existing?.type ?? widget.initialType ?? 'cash';
    cardDesign = bankCardDesignFor(widget.existing?.cardDesign).key;
    color = widget.existing?.color ?? colors.first;
  }

  @override
  void dispose() {
    nameController
      ..removeListener(_rebuildDesignPreview)
      ..dispose();
    balanceController.dispose();
    interestRateController.dispose();
    creditLimitController.dispose();
    statementDayController.dispose();
    dueDayController.dispose();
    super.dispose();
  }

  void _rebuildDesignPreview() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    insetPadding: EdgeInsets.symmetric(
      horizontal: MediaQuery.sizeOf(context).width < 480 ? 16 : 40,
      vertical: 24,
    ),
    title: Text(widget.existing == null ? 'Add account' : 'Edit account'),
    content: SizedBox(
      width: 480,
      child: Form(
        key: key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Account name',
                hintText: scope == FinanceScope.joint
                    ? 'Our savings, My contribution, GF savings…'
                    : 'Wallet, Payroll, Personal savings…',
              ),
              validator: (value) => (value?.trim().isEmpty ?? true)
                  ? 'Enter an account name.'
                  : null,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Account type'),
              items: [
                if (widget.existing?.isCreditCard != true) ...const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'bank', child: Text('Bank')),
                  DropdownMenuItem(value: 'ewallet', child: Text('E-wallet')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                if (widget.existing == null ||
                    widget.existing?.isSavingsAccount == true)
                  const DropdownMenuItem(
                    value: 'savings',
                    child: Text('Savings (set aside)'),
                  ),
                if (widget.existing == null ||
                    widget.existing?.isCreditCard == true)
                  const DropdownMenuItem(
                    value: 'credit_card',
                    child: Text('Credit card (utang)'),
                  ),
              ],
              onChanged:
                  widget.existing?.isCreditCard == true ||
                      widget.existing?.isSavingsAccount == true
                  ? null
                  : (value) => setState(() {
                      type = value ?? type;
                      if (type == 'savings' &&
                          interestRateController.text.trim().isEmpty) {
                        interestRateController.text = '0';
                      }
                    }),
            ),
            const SizedBox(height: 17),
            _AccountDesignPreview(
              key: const Key('account-card-design-preview'),
              design: bankCardDesignFor(cardDesign),
              customColor: colorFromHex(
                color,
                fallback: context.palette.green,
                legacyReplacement: context.palette.greenDark,
              ),
              accountName: nameController.text.trim().isEmpty
                  ? 'Your account'
                  : nameController.text.trim(),
              accountType: type,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('account-card-design-picker'),
                onPressed: saving ? null : _chooseCardDesign,
                icon: const Icon(Icons.style_outlined, size: 19),
                label: Text(
                  '${type == 'credit_card' ? 'Choose credit card design' : 'Choose card design'} · ${bankCardDesignFor(cardDesign).name}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(height: 7),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                type == 'credit_card'
                    ? 'Choose an original credit-card treatment or a Philippine bank color theme. No official issuer artwork or logos are used.'
                    : 'Original in-app themes for Philippine banks and e-wallets. No official logos or issued card artwork are used.',
                style: TextStyle(color: context.palette.muted, fontSize: 11),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: balanceController,
              keyboardType: TextInputType.numberWithOptions(
                decimal: true,
                signed: type != 'credit_card',
              ),
              decoration: InputDecoration(
                labelText: type == 'credit_card'
                    ? 'Opening debt'
                    : 'Opening balance',
                hintText: '0.00',
                helperText: switch (type) {
                  'credit_card' =>
                    'Enter the amount you already owe as a positive number.',
                  'savings' => 'This balance is set aside and excluded from available money.',
                  _ => null,
                },
              ),
              validator: (value) {
                try {
                  final amount = Money.parse(
                    value?.isEmpty == true ? '0' : value ?? '0',
                  );
                  if (type == 'credit_card' && amount < 0) {
                    return 'Opening debt cannot be negative.';
                  }
                  if (type == 'savings' && amount < 0) {
                    return 'Savings opening balance cannot be negative.';
                  }
                  return null;
                } on FormatException catch (error) {
                  return error.message;
                }
              },
            ),
            if (type == 'savings') ...[
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('savings-monthly-interest-rate'),
                controller: interestRateController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Monthly interest rate',
                  suffixText: '%',
                  hintText: '1.00',
                  helperMaxLines: 4,
                  helperText:
                      'Monthly, not annual. Example: 1% adds ${Money.format(1000, currencyCode: widget.controller.currencyCode, locale: widget.controller.locale)} to ${Money.format(100000, currencyCode: widget.controller.currencyCode, locale: widget.controller.locale)} on the first due date. Interest then compounds from the savings balance. Use 0% to turn it off.',
                ),
                validator: (value) {
                  try {
                    _parseMonthlyInterestRateBasisPoints(value ?? '');
                    return null;
                  } on FormatException catch (error) {
                    return error.message;
                  }
                },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'The first credit is due one calendar month after you enable the rate. Opening or refreshing the app safely catches up any missing months once.',
                  style: TextStyle(
                    color: context.palette.inkSoft,
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ),
            ],
            if (type == 'credit_card') ...[
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('credit-card-limit'),
                controller: creditLimitController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Credit limit (optional)',
                  hintText: '0.00',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  try {
                    final limit = Money.parse(value);
                    if (limit <= 0) {
                      return 'Credit limit must be greater than zero.';
                    }
                    final opening = Money.parse(
                      balanceController.text.trim().isEmpty
                          ? '0'
                          : balanceController.text,
                    );
                    if (opening > limit) {
                      return 'Credit limit cannot be below the opening debt.';
                    }
                    return null;
                  } on FormatException catch (error) {
                    return error.message;
                  }
                },
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('credit-card-statement-day'),
                      controller: statementDayController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Statement day (optional)',
                        hintText: '1–31',
                      ),
                      validator: _validateOptionalDay,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      key: const Key('credit-card-due-day'),
                      controller: dueDayController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Due day (optional)',
                        hintText: '1–31',
                      ),
                      validator: _validateOptionalDay,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 17),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                cardDesign == 'other' ? 'Custom card accent' : 'Account accent',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: colors.map((value) {
                final selected = color == value;
                final label =
                    '${_colorName(value)}${selected ? ', selected' : ''}';
                return Semantics(
                  button: true,
                  selected: selected,
                  label: label,
                  excludeSemantics: true,
                  child: Tooltip(
                    message: label,
                    child: InkWell(
                      onTap: () => setState(() {
                        color = value;
                        cardDesign = 'other';
                      }),
                      customBorder: const CircleBorder(),
                      child: SizedBox.square(
                        dimension: 48,
                        child: Center(
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: colorFromHex(
                                value,
                                fallback: context.palette.green,
                                legacyReplacement: context.palette.greenDark,
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected
                                    ? context.palette.ink
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
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
        onPressed: saving ? null : _save,
        child: Text(saving ? 'Saving…' : 'Save account'),
      ),
    ],
  );

  static String _colorName(String value) => switch (value.toUpperCase()) {
    '#6F92FF' => 'Blue',
    '#55D7E8' => 'Cyan',
    '#43D98B' => 'Green',
    '#C74AF3' => 'Purple',
    '#FFA13D' => 'Orange',
    '#FF607B' => 'Red',
    '#1B1B1B' => 'Legacy black',
    '#111111' => 'Legacy charcoal',
    '#159A73' => 'Legacy green',
    '#245C73' => 'Legacy blue',
    '#E9844A' => 'Legacy orange',
    '#7A61C9' => 'Legacy purple',
    '#D75050' => 'Legacy red',
    _ => 'Custom color',
  };

  static String? _validateOptionalDay(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final day = int.tryParse(value.trim());
    return day == null || day < 1 || day > 31
        ? 'Use a day from 1 to 31.'
        : null;
  }

  Future<void> _chooseCardDesign() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => _BankCardDesignDialog(
        selectedKey: cardDesign,
        creditCard: type == 'credit_card',
      ),
    );
    if (selected == null || !mounted) return;
    final design = bankCardDesignFor(selected);
    setState(() {
      cardDesign = design.key;
      if (design.key != 'other') color = _colorToHex(design.accent);
    });
  }

  Future<void> _save() async {
    if (!key.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await widget.controller.saveAccount(
        existing: widget.existing,
        name: nameController.text.trim(),
        type: type,
        openingBalanceMinor: type == 'credit_card'
            ? 0
            : Money.parse(
                balanceController.text.isEmpty ? '0' : balanceController.text,
              ),
        openingDebtMinor: type == 'credit_card'
            ? Money.parse(
                balanceController.text.isEmpty ? '0' : balanceController.text,
              )
            : 0,
        creditLimitMinor:
            type != 'credit_card' || creditLimitController.text.trim().isEmpty
            ? null
            : Money.parse(creditLimitController.text),
        statementDay: type == 'credit_card'
            ? int.tryParse(statementDayController.text.trim())
            : null,
        dueDay: type == 'credit_card'
            ? int.tryParse(dueDayController.text.trim())
            : null,
        cardDesign: cardDesign,
        monthlyInterestRateBasisPoints: type == 'savings'
            ? _parseMonthlyInterestRateBasisPoints(interestRateController.text)
            : null,
        color: color,
        scope: scope,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

String _colorToHex(Color color) {
  final rgb = color.toARGB32() & 0x00FFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

class _AccountDesignPreview extends StatelessWidget {
  const _AccountDesignPreview({
    super.key,
    required this.design,
    required this.customColor,
    required this.accountName,
    required this.accountType,
  });

  final BankCardDesign design;
  final Color customColor;
  final String accountName;
  final String accountType;

  @override
  Widget build(BuildContext context) {
    final isCreditCard = accountType == 'credit_card';
    final isSavings = accountType == 'savings';
    final visual = AccountCardVisual.forCustomDesign(design, customColor);
    final primary = visual.primary;
    final secondary = visual.secondary;
    final accent = visual.accent;
    final foreground = visual.foreground;
    return Semantics(
      label: '${design.name} card design preview',
      image: true,
      child: Container(
        width: double.infinity,
        height: 148,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [primary, secondary],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isCreditCard
                ? _cardLiabilityAccent.withValues(alpha: 0.78)
                : foreground.withValues(alpha: 0.16),
            width: isCreditCard ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: BankCardPatternPainter(
                pattern: design.pattern,
                accent: accent,
                foreground: foreground,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: foreground.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          design.key == 'other'
                              ? accountCardShortMark(accountType)
                              : design.shortMark,
                          style: TextStyle(
                            color: foreground,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (isCreditCard) ...[
                        _CreditLiabilityBadge(
                          key: const Key('credit-card-preview-liability-badge'),
                          foreground: foreground,
                          compact: true,
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (isSavings) ...[
                        _SavingsBadge(foreground: foreground),
                        const SizedBox(width: 8),
                      ],
                      Icon(
                        Icons.contactless_rounded,
                        color: foreground.withValues(alpha: 0.78),
                        size: 23,
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    accountName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    design.key == 'other' ? 'CUSTOM DESIGN' : design.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground.withValues(alpha: 0.7),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7,
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

class _BankCardDesignDialog extends StatefulWidget {
  const _BankCardDesignDialog({
    required this.selectedKey,
    required this.creditCard,
  });

  final String selectedKey;
  final bool creditCard;

  @override
  State<_BankCardDesignDialog> createState() => _BankCardDesignDialogState();
}

class _BankCardDesignDialogState extends State<_BankCardDesignDialog> {
  late final TextEditingController searchController;
  String query = '';

  @override
  void initState() {
    super.initState();
    searchController = TextEditingController();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalized = query.trim().toLowerCase();
    final groups = <MapEntry<BankCardDesignGroup, List<BankCardDesign>>>[];
    for (final entry in bankCardDesignsByGroup.entries) {
      if (widget.creditCard && entry.key == BankCardDesignGroup.eWallet) {
        continue;
      }
      final matches = entry.value
          .where(
            (design) =>
                normalized.isEmpty ||
                design.name.toLowerCase().contains(normalized) ||
                design.shortMark.toLowerCase().contains(normalized) ||
                entry.key.label.toLowerCase().contains(normalized),
          )
          .toList();
      if (matches.isNotEmpty) groups.add(MapEntry(entry.key, matches));
    }
    final availableHeight = MediaQuery.sizeOf(context).height * 0.72;
    return AlertDialog(
      key: Key(
        widget.creditCard
            ? 'credit-card-design-dialog'
            : 'account-card-design-dialog',
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      title: Text(
        widget.creditCard
            ? 'Choose a credit card design'
            : 'Choose a Philippine bank or e-wallet design',
      ),
      content: SizedBox(
        width: 720,
        height: availableHeight.clamp(360.0, 640.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('account-card-design-search'),
              controller: searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: widget.creditCard
                    ? 'Search bank or custom…'
                    : 'Search bank, e-wallet, or custom…',
                prefixIcon: const Icon(Icons.search_rounded),
              ),
              onChanged: (value) => setState(() => query = value),
            ),
            const SizedBox(height: 10),
            Text(
              widget.creditCard
                  ? 'Choose a visual theme only. It does not change your issuer, card network, limit, or rewards.'
                  : 'These are original Budget Flow themes, not official bank, wallet, or card artwork.',
              style: TextStyle(color: context.palette.muted, fontSize: 11.5),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: groups.isEmpty
                  ? const EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No matching preset',
                      message: 'Use Generic / custom for any institution not listed.',
                    )
                  : ListView.separated(
                      itemCount: groups.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 18),
                      itemBuilder: (context, index) {
                        final group = groups[index];
                        return _BankDesignGroup(
                          group: group.key,
                          designs: group.value,
                          selectedKey: widget.selectedKey,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _BankDesignGroup extends StatelessWidget {
  const _BankDesignGroup({
    required this.group,
    required this.designs,
    required this.selectedKey,
  });

  final BankCardDesignGroup group;
  final List<BankCardDesign> designs;
  final String selectedKey;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        group.label.toUpperCase(),
        style: TextStyle(
          color: context.palette.inkSoft,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.9,
        ),
      ),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 600
              ? 3
              : constraints.maxWidth >= 400
              ? 2
              : 1;
          final gap = 10.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: designs
                .map(
                  (design) => SizedBox(
                    width: width,
                    child: _BankDesignOption(
                      design: design,
                      selected: design.key == selectedKey,
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
    ],
  );
}

class _BankDesignOption extends StatelessWidget {
  const _BankDesignOption({required this.design, required this.selected});

  final BankCardDesign design;
  final bool selected;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '${design.name}${selected ? ', selected' : ''}',
    excludeSemantics: true,
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('account-card-design-${design.key}'),
        onTap: () => Navigator.pop(context, design.key),
        child: Ink(
          height: 106,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [design.primary, design.secondary],
            ),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected ? design.accent : context.palette.borderStrong,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: BankCardPatternPainter(
                  pattern: design.pattern,
                  accent: design.accent,
                  foreground: design.foreground,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          design.shortMark,
                          style: TextStyle(
                            color: design.foreground,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Spacer(),
                        if (selected)
                          Icon(
                            Icons.check_circle_rounded,
                            color: design.foreground,
                            size: 18,
                          ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      design.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: design.foreground,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AccountTransferDialog extends StatefulWidget {
  const _AccountTransferDialog({required this.controller});

  final AppController controller;

  @override
  State<_AccountTransferDialog> createState() => _AccountTransferDialogState();
}

class _AccountTransferDialogState extends State<_AccountTransferDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController amountController;
  late final TextEditingController feeController;
  late final TextEditingController noteController;
  late final FinanceScope scope;
  late final String clientUuid;
  DateTime? _transferredOnV1;
  int? sourceAccountId;
  int? destinationAccountId;
  bool saving = false;

  DateTime get transferredOn => _transferredOnV1 ??= DateTime.now();

  List<Account> get accounts => widget.controller.accountTransferAccounts
      .where((account) => account.scope == scope)
      .toList();

  Account? get sourceAccount =>
      accounts.where((account) => account.id == sourceAccountId).firstOrNull;

  Account? get destinationAccount => accounts
      .where((account) => account.id == destinationAccountId)
      .firstOrNull;

  List<Account> get destinationOptions =>
      accounts.where((account) => account.id != sourceAccountId).toList();

  List<Account> get transferSavingsAccounts => [
    if (sourceAccount?.isSavingsAccount == true) sourceAccount!,
    if (destinationAccount?.isSavingsAccount == true) destinationAccount!,
  ];

  DateTime? get earliestTransferOn {
    DateTime? result;
    for (final account in transferSavingsAccounts) {
      final processed = account.interestLastProcessedOn;
      if (processed != null && (result == null || processed.isAfter(result))) {
        result = processed;
      }
    }
    return result;
  }

  bool get isBeforeInterestCheckpoint {
    final earliest = earliestTransferOn;
    return earliest != null && transferredOn.isBefore(earliest);
  }

  int? get parsedAmountMinor => _tryMoney(amountController.text);

  int? get parsedFeeMinor =>
      feeController.text.trim().isEmpty ? 0 : _tryMoney(feeController.text);

  @override
  void initState() {
    super.initState();
    scope = widget.controller.selectedFinanceScope;
    clientUuid = widget.controller.newClientUuid();
    _transferredOnV1 = DateTime.now();
    amountController = TextEditingController();
    feeController = TextEditingController();
    noteController = TextEditingController();
    final options = accounts;
    sourceAccountId = options.firstOrNull?.id;
    destinationAccountId = options.length > 1 ? options[1].id : null;
    _clampTransferDateToInterestCheckpoint();
    amountController.addListener(_rebuildPreview);
    feeController.addListener(_rebuildPreview);
  }

  @override
  void dispose() {
    amountController
      ..removeListener(_rebuildPreview)
      ..dispose();
    feeController
      ..removeListener(_rebuildPreview)
      ..dispose();
    noteController.dispose();
    super.dispose();
  }

  void _rebuildPreview() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final source = sourceAccount;
    final destination = destinationAccount;
    final amount = parsedAmountMinor;
    final fee = parsedFeeMinor;
    return AlertDialog(
      title: Text('Transfer ${scope.label} money'),
      content: SizedBox(
        width: 620,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: scope == FinanceScope.joint
                        ? context.palette.infoSoft
                        : context.palette.mint,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    'Move money between active everyday and savings ${scope.label} accounts. Savings stay set aside and system or archived accounts are excluded.',
                    style: TextStyle(
                      color: context.palette.inkSoft,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (accounts.length < 2) ...[
                  const SizedBox(height: 14),
                  Container(
                    key: const Key('transfer-account-requirement'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: context.palette.orangeSoft,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      'Create at least two active everyday or savings ${scope.label} accounts before transferring money.',
                      style: TextStyle(
                        color: context.palette.inkSoft,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                DropdownButtonFormField<int>(
                  key: const Key('transfer-source-account'),
                  initialValue: sourceAccountId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'From account'),
                  items: accounts
                      .map(
                        (account) => DropdownMenuItem(
                          value: account.id,
                          child: Text(
                            '${account.displayName} · ${Money.format(account.balanceMinor, currencyCode: widget.controller.currencyCode, locale: widget.controller.locale)} balance',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: saving
                      ? null
                      : (value) {
                          setState(() {
                            sourceAccountId = value;
                            if (destinationAccountId == value ||
                                !destinationOptions.any(
                                  (account) =>
                                      account.id == destinationAccountId,
                                )) {
                              destinationAccountId =
                                  destinationOptions.firstOrNull?.id;
                            }
                            _clampTransferDateToInterestCheckpoint();
                          });
                        },
                  validator: (value) =>
                      value == null ? 'Choose an active source account.' : null,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  key: ValueKey('transfer-destination-$sourceAccountId'),
                  initialValue:
                      destinationOptions.any(
                        (account) => account.id == destinationAccountId,
                      )
                      ? destinationAccountId
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'To account'),
                  items: destinationOptions
                      .map(
                        (account) => DropdownMenuItem(
                          value: account.id,
                          child: Text(
                            '${account.displayName} · ${Money.format(account.balanceMinor, currencyCode: widget.controller.currencyCode, locale: widget.controller.locale)} current',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: saving
                      ? null
                      : (value) => setState(() {
                          destinationAccountId = value;
                          _clampTransferDateToInterestCheckpoint();
                        }),
                  validator: (value) => value == null
                      ? 'Choose a different destination account.'
                      : null,
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final amountField = TextFormField(
                      key: const Key('transfer-amount'),
                      controller: amountController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Amount to transfer',
                        prefixText: widget.controller.currencyCode == 'PHP'
                            ? '₱ '
                            : null,
                        hintText: '0.00',
                      ),
                      validator: _validateAmount,
                    );
                    final feeField = TextFormField(
                      key: const Key('transfer-service-charge'),
                      controller: feeController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Service charge (optional)',
                        prefixText: widget.controller.currencyCode == 'PHP'
                            ? '₱ '
                            : null,
                        hintText: '0.00',
                      ),
                      validator: _validateFee,
                    );
                    if (constraints.maxWidth < 500) {
                      return Column(
                        children: [
                          amountField,
                          const SizedBox(height: 14),
                          feeField,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: amountField),
                        const SizedBox(width: 12),
                        Expanded(child: feeField),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                InkWell(
                  key: const Key('transfer-date-picker'),
                  onTap: saving ? null : _pickDate,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Transfer date',
                      suffixIcon: Icon(Icons.calendar_month_rounded),
                    ),
                    child: Text(DateFormat('MMM d, y').format(transferredOn)),
                  ),
                ),
                const SizedBox(height: 7),
                if (earliestTransferOn != null)
                  Container(
                    key: const Key('transfer-interest-date-limit'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: context.palette.orangeSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'This savings transfer cannot be dated before ${DateFormat('MMM d, y').format(earliestTransferOn!)}. Automatic interest through that date is finalized.',
                      style: TextStyle(
                        color: context.palette.inkSoft,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  )
                else
                  Text(
                    'For a backdated transfer, the source must cover the amount and service charge both on that date and today.',
                    style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('transfer-note'),
                  controller: noteController,
                  maxLength: 500,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    hintText: 'Why are you moving this money?',
                  ),
                ),
                const SizedBox(height: 8),
                _TransferPreview(
                  source: source,
                  destination: destination,
                  amountMinor: amount,
                  serviceChargeMinor: fee,
                  currencyCode: widget.controller.currencyCode,
                  locale: widget.controller.locale,
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
        FilledButton.icon(
          key: const Key('confirm-account-transfer'),
          onPressed: saving || accounts.length < 2 || isBeforeInterestCheckpoint
              ? null
              : _submit,
          icon: const Icon(Icons.swap_horiz_rounded, size: 19),
          label: Text(saving ? 'Transferring…' : 'Transfer money'),
        ),
      ],
    );
  }

  String? _validateAmount(String? value) {
    try {
      final amount = Money.parse(value ?? '');
      if (amount <= 0) return 'Amount must be greater than zero.';
      return _validateTotalAndBalance(amount, parsedFeeMinor);
    } on FormatException catch (error) {
      return error.message;
    }
  }

  String? _validateFee(String? value) {
    try {
      final fee = (value?.trim().isEmpty ?? true) ? 0 : Money.parse(value!);
      if (fee < 0) return 'Service charge cannot be negative.';
      return _validateTotalAndBalance(parsedAmountMinor, fee);
    } on FormatException catch (error) {
      return error.message;
    }
  }

  String? _validateTotalAndBalance(int? amount, int? fee) {
    if (amount == null || amount <= 0 || fee == null || fee < 0) return null;
    final total = BigInt.from(amount) + BigInt.from(fee);
    if (total > BigInt.from(Money.maxMinorUnits)) {
      return 'The total source debit is too large.';
    }
    if (sourceAccount != null &&
        BigInt.from(sourceAccount!.balanceMinor) < total) {
      return 'Source balance cannot cover the amount and service charge.';
    }
    return null;
  }

  Future<void> _pickDate() async {
    final minimum = earliestTransferOn ?? DateTime(2000);
    final selected = await showDatePicker(
      context: context,
      initialDate: transferredOn.isBefore(minimum) ? minimum : transferredOn,
      firstDate: minimum,
      // The API validates against the user's configured money timezone, which
      // can be a calendar day ahead of this desktop's local clock.
      lastDate: DateTime(9999, 12, 31),
    );
    if (selected != null && mounted) {
      setState(() => _transferredOnV1 = selected);
    }
  }

  void _clampTransferDateToInterestCheckpoint() {
    final earliest = earliestTransferOn;
    if (earliest != null && transferredOn.isBefore(earliest)) {
      _transferredOnV1 = earliest;
    }
  }

  Future<void> _submit() async {
    if (!formKey.currentState!.validate()) return;
    final source = sourceAccount;
    final destination = destinationAccount;
    final amount = parsedAmountMinor;
    final fee = parsedFeeMinor;
    if (source == null ||
        destination == null ||
        amount == null ||
        fee == null) {
      return;
    }
    setState(() => saving = true);
    try {
      await widget.controller.saveAccountTransfer(
        scope: scope,
        clientUuid: clientUuid,
        sourceAccountId: source.id,
        destinationAccountId: destination.id,
        amountMinor: amount,
        transferredOn: transferredOn,
        serviceChargeMinor: fee,
        note: noteController.text,
      );
      if (!mounted) return;
      final availableChange =
          (destination.countsTowardAvailableMoney ? amount : 0) -
          (source.countsTowardAvailableMoney ? amount + fee : 0);
      final availableCopy = availableChange == 0
          ? 'Available money is unchanged.'
          : availableChange > 0
          ? 'Available money increased by ${Money.format(availableChange, currencyCode: widget.controller.currencyCode, locale: widget.controller.locale)}.'
          : 'Available money decreased by ${Money.format(availableChange.abs(), currencyCode: widget.controller.currencyCode, locale: widget.controller.locale)}.';
      showSuccess(
        context,
        fee > 0
            ? 'Transfer saved. $availableCopy The service charge was recorded as a Transfer Fees expense.'
            : 'Transfer saved. $availableCopy',
      );
      Navigator.pop(context);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  static int? _tryMoney(String value) {
    try {
      return Money.parse(value);
    } on FormatException {
      return null;
    }
  }
}

class _TransferPreview extends StatelessWidget {
  const _TransferPreview({
    required this.source,
    required this.destination,
    required this.amountMinor,
    required this.serviceChargeMinor,
    required this.currencyCode,
    required this.locale,
  });

  final Account? source;
  final Account? destination;
  final int? amountMinor;
  final int? serviceChargeMinor;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final amount = amountMinor ?? 0;
    final fee = serviceChargeMinor ?? 0;
    final sourceDebit = BigInt.from(amount) + BigInt.from(fee);
    final validTotal =
        amount > 0 &&
        fee >= 0 &&
        sourceDebit <= BigInt.from(Money.maxMinorUnits);
    final sourceAfter = source == null || !validTotal
        ? null
        : BigInt.from(source!.balanceMinor) - sourceDebit;
    final destinationAfter = destination == null || !validTotal
        ? null
        : BigInt.from(destination!.balanceMinor) + BigInt.from(amount);
    final sourceAfterMinor =
        sourceAfter != null &&
            sourceAfter >= BigInt.from(-Money.maxMinorUnits) &&
            sourceAfter <= BigInt.from(Money.maxMinorUnits)
        ? sourceAfter.toInt()
        : null;
    final destinationAfterMinor =
        destinationAfter != null &&
            destinationAfter <= BigInt.from(Money.maxMinorUnits)
        ? destinationAfter.toInt()
        : null;
    final availableMoneyChange = !validTotal
        ? null
        : (destination?.countsTowardAvailableMoney == true ? amount : 0) -
              (source?.countsTowardAvailableMoney == true
                  ? sourceDebit.toInt()
                  : 0);
    final availableMoneyCopy = availableMoneyChange == null
        ? 'Available money change will appear after you enter a valid amount.'
        : availableMoneyChange == 0
        ? 'Available money stays unchanged.'
        : availableMoneyChange > 0
        ? 'Available money increases by ${Money.format(availableMoneyChange, currencyCode: currencyCode, locale: locale)}.'
        : 'Available money decreases by ${Money.format(availableMoneyChange.abs(), currencyCode: currencyCode, locale: locale)}.';

    return Container(
      key: const Key('account-transfer-preview'),
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: context.palette.surfaceMuted,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TRANSFER PREVIEW',
            style: TextStyle(
              color: context.palette.muted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 11),
          LayoutBuilder(
            builder: (context, constraints) {
              final sourceItem = _TransferPreviewItem(
                key: const Key('transfer-source-preview'),
                label: source?.displayName ?? 'Source account',
                changeMinor: validTotal ? -sourceDebit.toInt() : null,
                afterMinor: sourceAfterMinor,
                currencyCode: currencyCode,
                locale: locale,
              );
              final destinationItem = _TransferPreviewItem(
                key: const Key('transfer-destination-preview'),
                label: destination?.displayName ?? 'Destination account',
                changeMinor: validTotal ? amount : null,
                afterMinor: destinationAfterMinor,
                currencyCode: currencyCode,
                locale: locale,
              );
              if (constraints.maxWidth < 470) {
                return Column(
                  children: [
                    sourceItem,
                    const SizedBox(height: 10),
                    destinationItem,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: sourceItem),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 12,
                    ),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: context.palette.muted,
                    ),
                  ),
                  Expanded(child: destinationItem),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            '$availableMoneyCopy ${fee > 0
                ? source?.countsTowardAvailableMoney == true
                      ? 'The service charge is a Transfer Fees expense and is included in that available-money decrease.'
                      : 'The service charge is a Transfer Fees expense; because it is funded from savings, it reduces savings without reducing available money.'
                : 'The principal is an internal transfer, not income or an expense.'}',
            key: const Key('transfer-available-money-preview'),
            style: TextStyle(
              color: context.palette.inkSoft,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferPreviewItem extends StatelessWidget {
  const _TransferPreviewItem({
    super.key,
    required this.label,
    required this.changeMinor,
    required this.afterMinor,
    required this.currencyCode,
    required this.locale,
  });

  final String label;
  final int? changeMinor;
  final int? afterMinor;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: context.palette.ink,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        changeMinor == null
            ? 'Enter an amount'
            : '${changeMinor! >= 0 ? '+' : '−'}${Money.format(changeMinor!.abs(), currencyCode: currencyCode, locale: locale)}',
        style: TextStyle(
          color: changeMinor != null && changeMinor! < 0
              ? context.palette.red
              : context.palette.greenDark,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        afterMinor == null
            ? 'Resulting balance unavailable'
            : '${Money.format(afterMinor!, currencyCode: currencyCode, locale: locale)} after',
        style: TextStyle(color: context.palette.muted, fontSize: 11.5),
      ),
    ],
  );
}

class _CreditCardPaymentDialog extends StatefulWidget {
  const _CreditCardPaymentDialog({
    required this.controller,
    this.initialCreditCard,
  });

  final AppController controller;
  final Account? initialCreditCard;

  @override
  State<_CreditCardPaymentDialog> createState() =>
      _CreditCardPaymentDialogState();
}

class _CreditCardPaymentDialogState extends State<_CreditCardPaymentDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController amountController;
  late final TextEditingController feeController;
  late final TextEditingController noteController;
  late final FinanceScope scope;
  late final String clientUuid;
  late DateTime paidOn;
  int? sourceAccountId;
  int? creditCardAccountId;
  bool saving = false;

  List<Account> get sources =>
      widget.controller.creditCardPaymentSourceAccounts;
  List<Account> get cards => widget.controller.creditCardAccounts;
  Account? get source =>
      sources.where((account) => account.id == sourceAccountId).firstOrNull;
  Account? get card =>
      cards.where((account) => account.id == creditCardAccountId).firstOrNull;
  bool get hasPendingScopeTransactions => widget
      .controller
      .offlineTransactionOperations
      .any((operation) => operation.scope == scope);
  bool get canSubmit =>
      widget.controller.hasLiveConnection &&
      !hasPendingScopeTransactions &&
      sources.isNotEmpty &&
      cards.any((account) => account.debtMinor > 0);

  @override
  void initState() {
    super.initState();
    scope = widget.controller.selectedFinanceScope;
    clientUuid = widget.controller.newClientUuid();
    paidOn = DateTime.now();
    sourceAccountId = sources.firstOrNull?.id;
    final initial = widget.initialCreditCard;
    creditCardAccountId =
        initial != null &&
            initial.scope == scope &&
            !initial.isArchived &&
            initial.isCreditCard
        ? initial.id
        : cards.where((account) => account.debtMinor > 0).firstOrNull?.id ??
              cards.firstOrNull?.id;
    amountController = TextEditingController();
    amountController.addListener(_rebuildPreview);
    feeController = TextEditingController();
    feeController.addListener(_rebuildPreview);
    noteController = TextEditingController();
  }

  @override
  void dispose() {
    amountController
      ..removeListener(_rebuildPreview)
      ..dispose();
    feeController
      ..removeListener(_rebuildPreview)
      ..dispose();
    noteController.dispose();
    super.dispose();
  }

  void _rebuildPreview() {
    if (mounted) setState(() {});
  }

  int? get parsedAmount {
    try {
      return Money.parse(amountController.text);
    } on FormatException {
      return null;
    }
  }

  int? get parsedFee {
    try {
      return feeController.text.trim().isEmpty
          ? 0
          : Money.parse(feeController.text);
    } on FormatException {
      return null;
    }
  }

  int? get parsedTotalDebit {
    final amount = parsedAmount;
    final fee = parsedFee;
    if (amount == null || amount <= 0 || fee == null || fee < 0) return null;
    final total = BigInt.from(amount) + BigInt.from(fee);
    return total <= BigInt.from(Money.maxMinorUnits) ? total.toInt() : null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text('Pay ${scope.label} credit card'),
    content: SizedBox(
      width: 540,
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: const Key('credit-card-payment-explanation'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.palette.mint,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                'The payment principal moves existing money to your card, so cash and utang both go down. Only an optional service charge is recorded as a new expense.',
                style: TextStyle(
                  color: context.palette.inkSoft,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!widget.controller.hasLiveConnection ||
                hasPendingScopeTransactions) ...[
              const SizedBox(height: 12),
              Container(
                key: const Key('credit-card-payment-online-required'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.palette.orangeSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  !widget.controller.hasLiveConnection
                      ? 'Reconnect to pay a card. Card purchases can still be saved offline as ordinary expenses.'
                      : 'Sync or resolve pending ${scope.label} transactions before paying a card.',
                  style: TextStyle(
                    color: context.palette.inkSoft,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            if (sources.isEmpty || cards.isEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.palette.orangeSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  cards.isEmpty ? 'Create a ${scope.label} credit card first.' : 'Create an active cash, bank, or e-wallet account to fund the payment.',
                  style: TextStyle(color: context.palette.inkSoft),
                ),
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              key: const Key('card-payment-source-account'),
              initialValue: sourceAccountId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Pay from'),
              items: sources
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
                  : (value) => setState(() => sourceAccountId = value),
              validator: (value) =>
                  value == null ? 'Choose the payment account.' : null,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              key: const Key('card-payment-credit-card'),
              initialValue: creditCardAccountId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Credit card'),
              items: cards
                  .map(
                    (account) => DropdownMenuItem(
                      value: account.id,
                      child: Text(
                        '${account.displayName} · ${Money.format(account.debtMinor, currencyCode: widget.controller.currencyCode, locale: widget.controller.locale)} debt',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: saving
                  ? null
                  : (value) => setState(() => creditCardAccountId = value),
              validator: (value) {
                if (value == null) return 'Choose the credit card.';
                final selected = cards
                    .where((account) => account.id == value)
                    .firstOrNull;
                if (selected == null || selected.debtMinor <= 0) {
                  return 'This credit card has no debt to pay.';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('card-payment-amount'),
              controller: amountController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Payment amount',
                hintText: '0.00',
              ),
              validator: (value) {
                try {
                  final amount = Money.parse(value ?? '');
                  if (amount <= 0) return 'Enter an amount greater than zero.';
                  if (card != null && card!.debtMinor < amount) {
                    return 'Payment cannot be greater than the card debt.';
                  }
                  final totalError = _validateTotalAndBalance(
                    amount,
                    parsedFee,
                  );
                  if (totalError != null) return totalError;
                  return null;
                } on FormatException catch (error) {
                  return error.message;
                }
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('card-payment-service-charge'),
              controller: feeController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Service charge (optional)',
                prefixText: widget.controller.currencyCode == 'PHP'
                    ? '₱ '
                    : null,
                hintText: '0.00',
              ),
              validator: (value) {
                try {
                  final fee = (value?.trim().isEmpty ?? true)
                      ? 0
                      : Money.parse(value!);
                  if (fee < 0) return 'Service charge cannot be negative.';
                  return _validateTotalAndBalance(parsedAmount, fee);
                } on FormatException catch (error) {
                  return error.message;
                }
              },
            ),
            if (parsedAmount case final amount?)
              if (parsedFee case final fee?)
                if (parsedTotalDebit case final totalDebit?) ...[
                  const SizedBox(height: 14),
                  Container(
                    key: const Key('card-payment-preview'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.palette.surfaceMuted,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: context.palette.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          source == null
                              ? 'Choose a payment account'
                              : '${source!.displayName}: ${Money.format(source!.balanceMinor, currencyCode: widget.controller.currencyCode, locale: widget.controller.locale)} − ${Money.format(totalDebit, currencyCode: widget.controller.currencyCode, locale: widget.controller.locale)} = ${Money.format(source!.balanceMinor - totalDebit, currencyCode: widget.controller.currencyCode, locale: widget.controller.locale)} cash',
                          style: TextStyle(
                            color: context.palette.inkSoft,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          card == null
                              ? 'Choose a credit card'
                              : '${card!.displayName}: ${Money.format(card!.debtMinor, currencyCode: widget.controller.currencyCode, locale: widget.controller.locale)} − ${Money.format(amount, currencyCode: widget.controller.currencyCode, locale: widget.controller.locale)} = ${Money.format(card!.debtMinor - amount, currencyCode: widget.controller.currencyCode, locale: widget.controller.locale)} utang',
                          style: TextStyle(
                            color: context.palette.inkSoft,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          fee > 0
                              ? '${Money.format(fee, currencyCode: widget.controller.currencyCode, locale: widget.controller.locale)} service charge is a Transfer Fees expense that affects cashflow, cutoff spending, budget, and net position.'
                              : 'Net position stays unchanged · not a second expense',
                          style: TextStyle(
                            color: fee > 0
                                ? context.palette.orange
                                : context.palette.greenDark,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
            const SizedBox(height: 14),
            InkWell(
              key: const Key('card-payment-date-picker'),
              onTap: saving ? null : _pickDate,
              borderRadius: BorderRadius.circular(11),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Payment date',
                  suffixIcon: Icon(Icons.calendar_today_rounded, size: 18),
                ),
                child: Text(DateFormat('EEEE, MMM d, y').format(paidOn)),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'For a backdated payment, the source must cover the payment and service charge both on that date and today.',
              style: TextStyle(
                color: context.palette.muted,
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('card-payment-note'),
              controller: noteController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
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
        key: const Key('confirm-card-payment'),
        onPressed: saving || !canSubmit ? null : _save,
        child: Text(saving ? 'Paying…' : 'Pay card'),
      ),
    ],
  );

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: paidOn,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (selected != null) setState(() => paidOn = selected);
  }

  String? _validateTotalAndBalance(int? amount, int? fee) {
    if (amount == null || amount <= 0 || fee == null || fee < 0) return null;
    final total = BigInt.from(amount) + BigInt.from(fee);
    if (total > BigInt.from(Money.maxMinorUnits)) {
      return 'The total source debit is too large.';
    }
    if (source != null && BigInt.from(source!.balanceMinor) < total) {
      return 'Payment account cannot cover the payment and service charge.';
    }
    return null;
  }

  Future<void> _save() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await widget.controller.saveCreditCardPayment(
        scope: scope,
        clientUuid: clientUuid,
        sourceAccountId: sourceAccountId!,
        creditCardAccountId: creditCardAccountId!,
        amountMinor: Money.parse(amountController.text),
        paidOn: paidOn,
        serviceChargeMinor: parsedFee ?? 0,
        note: noteController.text,
      );
      if (mounted) {
        final refreshWarning =
            widget.controller.errorMessage?.startsWith(
              'Card payment saved, but',
            ) ==
            true;
        showSuccess(
          context,
          refreshWarning
              ? 'Card payment saved. Refresh to load the latest cash and utang balances.'
              : (parsedFee ?? 0) > 0
              ? 'Card payment posted. The service charge was recorded as a Transfer Fees expense.'
              : 'Card payment posted. Cash and utang updated.',
        );
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class _CreditCardPaymentHistory extends StatelessWidget {
  const _CreditCardPaymentHistory({
    required this.payments,
    required this.controller,
    required this.available,
    required this.onRefresh,
  });

  final List<CreditCardPayment> payments;
  final AppController controller;
  final bool available;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    if (controller.creditCardAccounts.isEmpty && payments.isEmpty) {
      return const SizedBox.shrink();
    }
    final scope = controller.selectedFinanceScope;
    final scoped = payments
        .where((payment) => payment.scope == scope)
        .take(5)
        .toList();
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recent ${scope.label} card payments',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Payments reduce cash and utang. Only service charges become a new expense.',
                      style: TextStyle(
                        color: context.palette.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('refresh-credit-card-payments'),
                tooltip: 'Refresh card payments',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!available)
            const EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Card payment history is not saved',
              message: 'Your payment history could not be read. Try refreshing saved data.',
            )
          else if (scoped.isEmpty)
            EmptyState(
              icon: Icons.credit_score_outlined,
              title: 'No ${scope.label} card payments yet',
              message:
                  'Use Pay card when you move existing money to a credit card.',
            )
          else
            ...scoped.map(
              (payment) => _CardPaymentHistoryRow(
                payment: payment,
                controller: controller,
              ),
            ),
        ],
      ),
    );
  }
}

class _CardPaymentHistoryRow extends StatelessWidget {
  const _CardPaymentHistoryRow({
    required this.payment,
    required this.controller,
  });

  final CreditCardPayment payment;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${payment.sourceDisplayName}  →  ${payment.creditCardDisplayName}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.palette.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          [
            DateFormat('MMM d, y').format(payment.paidOn),
            if (payment.note?.isNotEmpty == true) payment.note!,
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: context.palette.muted, fontSize: 11.5),
        ),
      ],
    );
    final amount = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        MoneyLabel(
          minorUnits: payment.amountMinor,
          currencyCode: controller.currencyCode,
          locale: controller.locale,
          style: TextStyle(
            color: context.palette.greenDark,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (payment.hasServiceCharge)
          Text(
            '${Money.format(payment.serviceChargeMinor, currencyCode: controller.currencyCode, locale: controller.locale)} service charge',
            style: TextStyle(color: context.palette.orange, fontSize: 11.5),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        key: ValueKey('credit-card-payment-${payment.id}'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.palette.surfaceMuted,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: context.palette.border),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 360) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.credit_score_rounded,
                        color: context.palette.greenDark,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: details),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Align(alignment: Alignment.centerRight, child: amount),
                ],
              );
            }
            return Row(
              children: [
                Icon(
                  Icons.credit_score_rounded,
                  color: context.palette.greenDark,
                ),
                const SizedBox(width: 11),
                Expanded(child: details),
                const SizedBox(width: 10),
                amount,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SavingsInterestHistory extends StatelessWidget {
  const _SavingsInterestHistory({
    required this.credits,
    required this.controller,
    required this.available,
    required this.onRefresh,
  });

  final List<SavingsInterestCredit> credits;
  final AppController controller;
  final bool available;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (controller.savingsAccounts.isEmpty && credits.isEmpty) {
      return const SizedBox.shrink();
    }
    final scope = controller.selectedFinanceScope;
    final scoped = credits
        .where((credit) => credit.scope == scope)
        .take(5)
        .toList(growable: false);
    return SectionCard(
      key: const Key('savings-interest-history'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Automatic ${scope.label} savings interest',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Monthly credits are added when the app opens or refreshes, and remain set aside.',
                      style: TextStyle(
                        color: context.palette.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('refresh-savings-interest'),
                tooltip: 'Refresh savings interest',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!available)
            const EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Savings interest history is not saved',
              message: 'Refresh saved data to load monthly interest history.',
            )
          else if (scoped.isEmpty)
            EmptyState(
              icon: Icons.savings_outlined,
              title: 'No ${scope.label} savings interest yet',
              message: 'Set a monthly rate on a savings account. The first automatic credit is due one calendar month after it is enabled.',
            )
          else
            ...scoped.map(
              (credit) => _SavingsInterestHistoryRow(
                credit: credit,
                currencyCode: controller.currencyCode,
                locale: controller.locale,
              ),
            ),
        ],
      ),
    );
  }
}

class _SavingsInterestHistoryRow extends StatelessWidget {
  const _SavingsInterestHistoryRow({
    required this.credit,
    required this.currencyCode,
    required this.locale,
  });

  final SavingsInterestCredit credit;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final rateBasisPoints = credit.monthlyInterestRateBasisPoints;
    final calculationBalance = credit.calculationBalanceMinor;
    final method =
        credit.isAutomatic &&
            rateBasisPoints != null &&
            calculationBalance != null
        ? '${_formatMonthlyInterestRate(rateBasisPoints)}% automatic on ${Money.format(calculationBalance, currencyCode: currencyCode, locale: locale)}'
        : 'Legacy manual entry';
    final details = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: context.palette.mint,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.add_chart_rounded,
            color: context.palette.greenDark,
            size: 20,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                credit.savingsAccountDisplayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.palette.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  method,
                  DateFormat('MMM d, y').format(credit.creditedOn),
                  if (credit.note?.isNotEmpty == true) credit.note!,
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.palette.muted, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ],
    );
    final amount = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: MoneyLabel(
              minorUnits: credit.amountMinor,
              currencyCode: currencyCode,
              locale: locale,
              style: TextStyle(
                color: context.palette.greenDark,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        Text(
          credit.creditedMonth,
          style: TextStyle(color: context.palette.muted, fontSize: 11),
        ),
      ],
    );
    return Container(
      key: ValueKey('savings-interest-credit-${credit.id}'),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.palette.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 360 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.35;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                const SizedBox(height: 9),
                Align(alignment: Alignment.centerRight, child: amount),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: details),
              const SizedBox(width: 10),
              amount,
            ],
          );
        },
      ),
    );
  }
}

class _TransferHistory extends StatelessWidget {
  const _TransferHistory({
    required this.transfers,
    required this.controller,
    required this.available,
    required this.onRefresh,
  });

  final List<AccountTransfer> transfers;
  final AppController controller;
  final bool available;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final scope = controller.selectedFinanceScope;
    final scoped = transfers
        .where((transfer) => transfer.scope == scope)
        .take(5)
        .toList();
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recent ${scope.label} transfers',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Posted transfers are immutable account-movement records.',
                    style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              );
              final refresh = OutlinedButton.icon(
                key: const Key('refresh-account-transfers'),
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh'),
              );
              if (constraints.maxWidth < 520) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, const SizedBox(height: 12), refresh],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  refresh,
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.palette.surfaceMuted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Need a correction? Create a new opposite transfer. The original service charge remains a real expense.',
              style: TextStyle(
                color: context.palette.inkSoft,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (!available)
            const EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Transfer history is not saved on this device',
              message: 'Your transfer history could not be read. Try refreshing saved data.',
            )
          else if (scoped.isEmpty)
            EmptyState(
              icon: Icons.swap_horiz_rounded,
              title: 'No ${scope.label} transfers yet',
              message:
                  'Use Transfer money to move funds between two ${scope.label} accounts.',
            )
          else
            ...scoped.map(
              (transfer) => _TransferHistoryRow(
                transfer: transfer,
                currencyCode: controller.currencyCode,
                locale: controller.locale,
              ),
            ),
        ],
      ),
    );
  }
}

class _TransferHistoryRow extends StatelessWidget {
  const _TransferHistoryRow({
    required this.transfer,
    required this.currencyCode,
    required this.locale,
  });

  final AccountTransfer transfer;
  final String currencyCode;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final route = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${transfer.sourceDisplayName}  →  ${transfer.destinationDisplayName}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.palette.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (_hasCurrentNameChange) ...[
          const SizedBox(height: 2),
          Text(
            _currentNameCopy,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.palette.muted, fontSize: 11.5),
          ),
        ],
        if (transfer.note?.isNotEmpty == true) ...[
          const SizedBox(height: 2),
          Text(
            transfer.note!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.palette.muted, fontSize: 11.5),
          ),
        ],
      ],
    );
    final amounts = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        MoneyLabel(
          minorUnits: transfer.amountMinor,
          currencyCode: currencyCode,
          locale: locale,
          style: TextStyle(
            color: context.palette.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (transfer.hasServiceCharge)
          Text(
            '${Money.format(transfer.serviceChargeMinor, currencyCode: currencyCode, locale: locale)} service charge',
            style: TextStyle(color: context.palette.orange, fontSize: 11.5),
          )
        else
          Text(
            'No service charge',
            style: TextStyle(color: context.palette.muted, fontSize: 11.5),
          ),
      ],
    );
    return Container(
      key: ValueKey('account-transfer-${transfer.id}'),
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.palette.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final date = Text(
            DateFormat('MMM d, y').format(transfer.transferredOn),
            style: TextStyle(color: context.palette.inkSoft, fontSize: 12),
          );
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    date,
                    const Spacer(),
                    const StatusPill(label: 'Posted', positive: true),
                  ],
                ),
                const SizedBox(height: 9),
                route,
                const SizedBox(height: 9),
                Align(alignment: Alignment.centerLeft, child: amounts),
              ],
            );
          }
          return Row(
            children: [
              SizedBox(width: 105, child: date),
              const SizedBox(width: 12),
              Expanded(child: route),
              const SizedBox(width: 14),
              amounts,
              const SizedBox(width: 14),
              const StatusPill(label: 'Posted', positive: true),
            ],
          );
        },
      ),
    );
  }

  bool get _hasCurrentNameChange =>
      (transfer.sourceAccount != null &&
          transfer.sourceAccount!.displayName != transfer.sourceAccountName) ||
      (transfer.destinationAccount != null &&
          transfer.destinationAccount!.displayName !=
              transfer.destinationAccountName) ||
      transfer.sourceAccount?.isArchived == true ||
      transfer.destinationAccount?.isArchived == true;

  String get _currentNameCopy {
    final details = <String>[];
    final source = transfer.sourceAccount;
    final destination = transfer.destinationAccount;
    if (source != null && source.displayName != transfer.sourceAccountName) {
      details.add('Source now ${source.displayName}');
    }
    if (destination != null &&
        destination.displayName != transfer.destinationAccountName) {
      details.add('Destination now ${destination.displayName}');
    }
    if (source?.isArchived == true) details.add('Source archived');
    if (destination?.isArchived == true) details.add('Destination archived');
    return details.join(' · ');
  }
}
