import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../models/domain_models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';

const _commonGoldKarats = [9, 10, 14, 16, 18, 20, 21, 22, 24];

class JewelryPage extends StatelessWidget {
  const JewelryPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.hasSavedJewelry) {
      return SingleChildScrollView(
        padding: responsivePagePadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: 'Gold & jewelry',
              subtitle: 'Jewelry records have not been saved on this device.',
              actions: [
                OutlinedButton.icon(
                  onPressed: controller.refreshJewelry,
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                  label: const Text('Refresh saved data'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const SectionCard(
              child: EmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'Jewelry is not saved on this device',
                message: 'Your jewelry records could not be read. Try refreshing saved data.',
              ),
            ),
          ],
        ),
      );
    }
    final held =
        controller.jewelryItems
            .where((item) => item.status.toLowerCase() != 'converted')
            .toList()
          ..sort(
            (first, second) =>
                second.estimatedValueMinor.compareTo(first.estimatedValueMinor),
          );
    final converted =
        controller.jewelryItems
            .where((item) => item.status.toLowerCase() == 'converted')
            .toList()
          ..sort(
            (first, second) =>
                _dateOrOldest(second.convertedOn)
                    .compareTo(_dateOrOldest(first.convertedOn)),
          );
    final heldValue = held.fold<int>(
      0,
      (sum, item) => sum + item.estimatedValueMinor,
    );
    final convertedProceeds = converted.fold<int>(
      0,
      (sum, item) => sum + (item.conversionAmountMinor ?? 0),
    );
    final heldWithKnownCost = held
        .where((item) => item.purchaseValueMinor != null)
        .toList();
    final heldGainLoss = heldWithKnownCost.fold<int>(
      0,
      (sum, item) => sum + item.unrealizedGainLossMinor!,
    );
    final missingCostCount = held.length - heldWithKnownCost.length;

    return SingleChildScrollView(
      padding: responsivePagePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Gold & jewelry',
            subtitle: 'Track your gold collection, saved prices, and resale proceeds.',
            actions: [
              OutlinedButton.icon(
                key: const Key('manage-saved-gold-prices-button'),
                onPressed:
                    controller.isBusy || !controller.hasSavedManualGoldPrices
                    ? null
                    : () => _showManualGoldPrices(context),
                icon: const Icon(Icons.price_change_outlined, size: 19),
                label: const Text('Manage saved prices'),
              ),
              OutlinedButton.icon(
                onPressed: controller.isBusy ? null : controller.refreshJewelry,
                icon: const Icon(Icons.refresh_rounded, size: 19),
                label: const Text('Refresh'),
              ),
              FilledButton.icon(
                onPressed: controller.isBusy
                    ? null
                    : () => _showEditor(context),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add jewelry'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _GoldPriceBanner(controller: controller),
          if (!controller.hasSavedManualGoldPrices) ...[
            const SizedBox(height: 12),
            SectionCard(
              child: Text(
                'Your saved gold prices could not be read. Try refreshing saved data.',
                style: TextStyle(
                  color: context.palette.inkSoft,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final metrics = [
                _SummaryMetric(
                  icon: Icons.diamond_rounded,
                  label: 'ESTIMATED GOLD VALUE',
                  value: Money.format(
                    heldValue,
                    currencyCode: controller.currencyCode,
                    locale: controller.locale,
                  ),
                  detail: 'Asset estimate — not available cash',
                  emphasized: true,
                ),
                _SummaryMetric(
                  icon: heldWithKnownCost.isEmpty || heldGainLoss == 0
                      ? Icons.trending_flat_rounded
                      : heldGainLoss > 0
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  label: 'UNREALIZED GAIN / LOSS',
                  value: heldWithKnownCost.isEmpty
                      ? 'Not available'
                      : Money.format(
                          heldGainLoss,
                          currencyCode: controller.currencyCode,
                          locale: controller.locale,
                        ),
                  detail: heldWithKnownCost.isEmpty
                      ? 'Add purchase values to calculate your gain'
                      : '${heldWithKnownCost.length} item${heldWithKnownCost.length == 1 ? '' : 's'} with recorded cost${missingCostCount == 0 ? '' : ' · $missingCostCount missing'}',
                  valueColor: heldWithKnownCost.isEmpty
                      ? context.palette.muted
                      : _gainColor(context.palette, heldGainLoss),
                ),
                _SummaryMetric(
                  icon: Icons.inventory_2_outlined,
                  label: 'ITEMS HELD',
                  value: '${held.length}',
                  detail:
                      '${_formatWeight(held.fold<int>(0, (sum, item) => sum + item.weightMg))} total recorded weight',
                ),
                _SummaryMetric(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'CONVERTED PROCEEDS',
                  value: Money.format(
                    convertedProceeds,
                    currencyCode: controller.currencyCode,
                    locale: controller.locale,
                  ),
                  detail:
                      '${converted.length} converted item${converted.length == 1 ? '' : 's'} deposited to accounts',
                ),
              ];
              final columns = constraints.maxWidth >= 1120
                  ? 4
                  : constraints.maxWidth >= 650
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 14) / columns;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: metrics
                    .map((metric) => SizedBox(width: width, child: metric))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 30),
          _SectionHeading(
            title: 'Gold currently held',
            subtitle: 'Estimated values help monitor the collection and are kept separate from cash balances.',
            count: held.length,
          ),
          const SizedBox(height: 14),
          if (held.isEmpty)
            SectionCard(
              child: EmptyState(
                icon: Icons.diamond_outlined,
                title: 'No gold jewelry recorded',
                message: 'Add a piece to track its weight, karat, purchase value, and current estimated value.',
                action: FilledButton.icon(
                  onPressed: () => _showEditor(context),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add jewelry'),
                ),
              ),
            )
          else
            _JewelryGrid(
              items: held,
              builder: (item) => _HeldJewelryCard(
                item: item,
                controller: controller,
                onEdit: () => _showEditor(context, item),
                onDelete: () => _delete(context, item),
                onConvert: () => _showConversion(context, item),
              ),
            ),
          const SizedBox(height: 32),
          _SectionHeading(
            title: 'Conversion history',
            subtitle: 'Items sold or converted to money, with proceeds and destination accounts.',
            count: converted.length,
          ),
          const SizedBox(height: 14),
          if (converted.isEmpty)
            const SectionCard(
              child: EmptyState(
                icon: Icons.currency_exchange_rounded,
                title: 'No jewelry converted yet',
                message: 'When you convert an item, its proceeds will be recorded in the account you choose.',
              ),
            )
          else
            _JewelryGrid(
              items: converted,
              builder: (item) => _ConvertedJewelryCard(
                item: item,
                controller: controller,
                onEdit: () => _showEditor(context, item),
                onDelete: () => _delete(context, item),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showEditor(BuildContext context, [JewelryItem? item]) =>
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            _JewelryEditorDialog(controller: controller, existing: item),
      );

  Future<void> _showManualGoldPrices(BuildContext context) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ManualGoldPricesDialog(controller: controller),
  );

  Future<void> _showConversion(BuildContext context, JewelryItem item) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _ConversionDialog(controller: controller, item: item),
    );
  }

  Future<void> _delete(BuildContext context, JewelryItem item) async {
    final converted = item.status.toLowerCase() == 'converted';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${item.name}?'),
        content: Text(
          converted
              ? 'This removes the converted jewelry record from your collection. The deposited income transaction and account balance remain unchanged.'
              : 'This removes the item and its estimated value from your active gold collection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: context.palette.orange,
            ),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Delete jewelry'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.deleteJewelry(item);
      if (context.mounted) showSuccess(context, 'Jewelry deleted.');
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }
}

class _ManualGoldPricesDialog extends StatefulWidget {
  const _ManualGoldPricesDialog({required this.controller});

  final AppController controller;

  @override
  State<_ManualGoldPricesDialog> createState() =>
      _ManualGoldPricesDialogState();
}

class _ManualGoldPricesDialogState extends State<_ManualGoldPricesDialog> {
  final formKey = GlobalKey<FormState>();
  final scrollController = ScrollController();
  late List<int> karats;
  late Map<int, TextEditingController> priceControllers;
  bool saving = false;
  bool retrying = false;

  @override
  void initState() {
    super.initState();
    _populateControllers();
  }

  void _populateControllers({bool disposeExisting = false}) {
    if (disposeExisting) {
      for (final controller in priceControllers.values) {
        controller.dispose();
      }
    }
    karats = {
      ..._commonGoldKarats,
      ...widget.controller.manualGoldPrices.rates.map((rate) => rate.karat),
    }.toList()..sort();
    priceControllers = {
      for (final karat in karats)
        karat: TextEditingController(text: _existingRateText(karat)),
    };
  }

  @override
  void dispose() {
    for (final controller in priceControllers.values) {
      controller.dispose();
    }
    scrollController.dispose();
    super.dispose();
  }

  ManualGoldPriceRate? _existingRate(int karat) =>
      widget.controller.manualGoldPrices.rateFor(karat);

  String _existingRateText(int karat) {
    final rate = _existingRate(karat);
    return rate == null ? '' : Money.decimal(rate.pricePerGramMinor);
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.68;
    return AlertDialog(
      title: const Text('Manage saved gold prices'),
      content: SizedBox(
        width: 610,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: context.palette.goldSoft.withValues(alpha: 0.58),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: context.palette.gold.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    'Enter your buying or reference price for each karat. Saved prices calculate jewelry values directly on your phone.',
                    style: TextStyle(
                      color: context.palette.gold,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (!widget.controller.manualGoldPricesLoaded) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.palette.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: context.palette.red.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.controller.manualGoldPriceError ??
                              'Saved prices could not be loaded.',
                          style: TextStyle(
                            color: context.palette.red,
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          key: const Key('retry-saved-gold-prices-button'),
                          onPressed: retrying ? null : _retry,
                          icon: retrying
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded, size: 17),
                          label: Text(retrying ? 'Loading…' : 'Retry loading'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  'Leave a price blank to remove that saved rate.',
                  style: TextStyle(color: context.palette.muted, fontSize: 11),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: Scrollbar(
                    controller: scrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      key: const Key('saved-gold-price-list'),
                      controller: scrollController,
                      padding: const EdgeInsets.only(right: 12),
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < karats.length;
                            index++
                          ) ...[
                            _buildRateRow(context, karats[index]),
                            if (index != karats.length - 1)
                              const SizedBox(height: 10),
                          ],
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
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const Key('save-gold-prices-button'),
          onPressed: saving || !widget.controller.manualGoldPricesLoaded
              ? null
              : _save,
          icon: saving
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.palette.onPrimary,
                  ),
                )
              : const Icon(Icons.save_outlined, size: 18),
          label: Text(saving ? 'Saving…' : 'Save prices'),
        ),
      ],
    );
  }

  Widget _buildRateRow(BuildContext context, int karat) {
    final rate = _existingRate(karat);
    final provenance = _rateProvenance(rate);
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${karat}K gold',
          style: TextStyle(
            color: context.palette.ink,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (provenance != null)
          Text(
            provenance,
            key: Key('saved-gold-provenance-$karat'),
            style: TextStyle(color: context.palette.muted, fontSize: 9.5),
          ),
      ],
    );
    final field = TextFormField(
      key: Key('saved-gold-rate-$karat'),
      controller: priceControllers[karat],
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        labelText: 'PHP per gram',
        prefixText: '₱ ',
        hintText: '0.00',
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) return null;
        try {
          final amount = Money.parse(value);
          if (amount <= 0) return 'Enter a price greater than zero.';
          if (amount > Money.maxMinorUnits) return 'This price is too large.';
          return null;
        } on FormatException catch (error) {
          return error.message;
        }
      },
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 430) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 7), field],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: heading,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: field),
          ],
        );
      },
    );
  }

  String? _rateProvenance(ManualGoldPriceRate? rate) {
    if (rate == null) return null;
    final updated = rate.updatedAt;
    return updated == null
        ? 'Manual reference'
        : 'Manual · updated ${DateFormat('MMM d, y h:mm a').format(updated.toLocal())}';
  }

  Future<void> _retry() async {
    setState(() => retrying = true);
    await widget.controller.refreshManualGoldPrices();
    if (!mounted) return;
    setState(() {
      retrying = false;
      if (widget.controller.manualGoldPricesLoaded) {
        _populateControllers(disposeExisting: true);
      }
    });
  }

  Future<void> _save() async {
    if (!widget.controller.manualGoldPricesLoaded) return;
    if (!formKey.currentState!.validate()) return;
    final rates = <ManualGoldPriceRate>[];
    for (final karat in karats) {
      final value = priceControllers[karat]!.text.trim();
      if (value.isEmpty) continue;
      rates.add(
        ManualGoldPriceRate(
          karat: karat,
          pricePerGramMinor: Money.parse(value),
        ),
      );
    }
    if (rates.isEmpty && widget.controller.manualGoldPrices.rates.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Clear all saved prices?'),
          content: const Text(
            'Automatic offline estimates will no longer be available until you save at least one price again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear prices'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => saving = true);
    try {
      await widget.controller.saveManualGoldPrices(rates);
      if (mounted) {
        Navigator.pop(context);
        showSuccess(context, 'Saved gold prices updated.');
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class _GoldPriceBanner extends StatelessWidget {
  const _GoldPriceBanner({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final prices = controller.manualGoldPrices;
    final compatible = prices.currencyCode == controller.currencyCode;
    return SectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.price_change_outlined, color: context.palette.gold),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  prices.rates.isEmpty
                      ? 'Add your gold reference prices'
                      : '${prices.rates.length} saved ${prices.currencyCode} prices',
                  key: const Key('gold-price-value'),
                  style: TextStyle(
                    color: context.palette.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  prices.rates.isEmpty
                      ? 'Use Manage saved prices to enter a price per gram for each karat, or enter jewelry estimates manually.'
                      : !compatible
                      ? 'Saved prices use ${prices.currencyCode}. Enter estimates manually when using ${controller.currencyCode}.'
                      : 'Jewelry estimates use your saved prices on this phone. Update them whenever your reference prices change.',
                  style: TextStyle(
                    color: context.palette.muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Actual resale proceeds may differ from your estimate.',
                  style: TextStyle(
                    color: context.palette.inkSoft,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    this.emphasized = false,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final bool emphasized;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final foreground = context.palette.ink;
    final secondary = emphasized
        ? context.palette.inkSoft
        : context.palette.muted;
    return Container(
      constraints: const BoxConstraints(minHeight: 145),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: emphasized ? null : context.palette.surface,
        gradient: emphasized
            ? LinearGradient(
                colors: [context.palette.violetSoft, context.palette.goldSoft],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        borderRadius: BorderRadius.circular(18),
        border: emphasized ? null : Border.all(color: context.palette.border),
        boxShadow: emphasized
            ? [
                BoxShadow(
                  color: context.palette.gold.withValues(alpha: 0.16),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: emphasized
                  ? context.palette.surface.withValues(alpha: 0.3)
                  : context.palette.goldSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: emphasized ? context.palette.ink : context.palette.gold,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: secondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.35,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: valueColor ?? foreground,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: secondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.subtitle,
    required this.count,
  });

  final String title;
  final String subtitle;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(color: context.palette.muted, fontSize: 12.5),
            ),
          ],
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: context.palette.goldSoft,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '$count item${count == 1 ? '' : 's'}',
          style: TextStyle(
            color: context.palette.gold,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}

class _JewelryGrid extends StatelessWidget {
  const _JewelryGrid({required this.items, required this.builder});

  final List<JewelryItem> items;
  final Widget Function(JewelryItem item) builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1140
          ? 3
          : constraints.maxWidth >= 680
          ? 2
          : 1;
      final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: items
            .map((item) => SizedBox(width: width, child: builder(item)))
            .toList(),
      );
    },
  );
}

class _HeldJewelryCard extends StatelessWidget {
  const _HeldJewelryCard({
    required this.item,
    required this.controller,
    required this.onEdit,
    required this.onDelete,
    required this.onConvert,
  });

  final JewelryItem item;
  final AppController controller;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onConvert;

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _JewelryTitle(item: item, converted: false),
        const SizedBox(height: 22),
        Text(
          'ESTIMATED ASSET VALUE',
          style: TextStyle(
            color: context.palette.muted,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 5),
        MoneyLabel(
          minorUnits: item.estimatedValueMinor,
          currencyCode: controller.currencyCode,
          locale: controller.locale,
          style: TextStyle(
            color: context.palette.gold,
            fontSize: 25,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Collection value only — not part of cash balance',
          style: TextStyle(color: context.palette.muted, fontSize: 10.5),
        ),
        const Divider(height: 27),
        Row(
          children: [
            Expanded(
              child: _Detail(
                label: 'WEIGHT',
                value: _formatWeight(item.weightMg),
              ),
            ),
            Expanded(
              child: _Detail(
                label: 'ACQUIRED',
                value: item.acquiredOn == null
                    ? 'Not set'
                    : DateFormat('MMM d, y').format(item.acquiredOn!),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _Detail(
          label: 'AGE',
          value: item.ageAt(DateTime.now())?.label ?? 'Not set',
        ),
        if (item.purchaseValueMinor != null) ...[
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _MoneyDetail(
                  label: 'PURCHASE VALUE',
                  amountMinor: item.purchaseValueMinor!,
                  controller: controller,
                ),
              ),
              Expanded(
                child: _MoneyDetail(
                  label: 'UNREALIZED GAIN / LOSS',
                  amountMinor: item.unrealizedGainLossMinor!,
                  controller: controller,
                  color: _gainColor(
                    context.palette,
                    item.unrealizedGainLossMinor!,
                  ),
                ),
              ),
            ],
          ),
        ] else ...[
          const SizedBox(height: 14),
          const _Detail(
            label: 'GAIN / LOSS',
            value: 'Purchase value not recorded',
          ),
        ],
        if (item.notes?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 14),
          Text(
            item.notes!.trim(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.palette.inkSoft,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ],
        const Divider(height: 28),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 17),
              label: const Text('Edit'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: 17),
              label: const Text('Delete'),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.palette.red,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: onConvert,
              icon: const Icon(Icons.currency_exchange_rounded, size: 17),
              label: const Text('Convert to money'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 11,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ConvertedJewelryCard extends StatelessWidget {
  const _ConvertedJewelryCard({
    required this.item,
    required this.controller,
    required this.onEdit,
    required this.onDelete,
  });

  final JewelryItem item;
  final AppController controller;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _JewelryTitle(item: item, converted: true),
        const SizedBox(height: 22),
        Text(
          'PROCEEDS DEPOSITED',
          style: TextStyle(
            color: context.palette.muted,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 5),
        MoneyLabel(
          minorUnits: item.conversionAmountMinor ?? 0,
          currencyCode: controller.currencyCode,
          locale: controller.locale,
          style: TextStyle(
            color: context.palette.greenDark,
            fontSize: 25,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Divider(height: 27),
        _Detail(
          label: 'DESTINATION ACCOUNT',
          value: item.conversionAccount?.name ?? 'Account unavailable',
          icon: Icons.account_balance_wallet_outlined,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _Detail(
                label: 'CONVERTED',
                value: item.convertedOn == null
                    ? 'Not set'
                    : DateFormat('MMM d, y').format(item.convertedOn!),
              ),
            ),
            Expanded(
              child: _Detail(
                label: 'WEIGHT',
                value: _formatWeight(item.weightMg),
              ),
            ),
          ],
        ),
        if (item.acquiredOn != null && item.convertedOn != null) ...[
          const SizedBox(height: 14),
          _Detail(
            label: 'HELD FOR',
            value: item.ageAt(item.convertedOn!)?.label ?? 'Not set',
          ),
        ],
        if (item.realizedGainLossMinor != null) ...[
          const SizedBox(height: 14),
          _MoneyDetail(
            label: 'REALIZED GAIN / LOSS',
            amountMinor: item.realizedGainLossMinor!,
            controller: controller,
            color: _gainColor(context.palette, item.realizedGainLossMinor!),
          ),
        ] else ...[
          const SizedBox(height: 14),
          _Detail(
            label: 'REALIZED GAIN / LOSS',
            value: item.purchaseValueMinor == null
                ? 'Purchase value not recorded'
                : 'Conversion proceeds unavailable',
          ),
        ],
        const Divider(height: 28),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 17),
              label: const Text('Edit details'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: 17),
              label: const Text('Delete'),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.palette.red,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _JewelryTitle extends StatelessWidget {
  const _JewelryTitle({required this.item, required this.converted});

  final JewelryItem item;
  final bool converted;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: converted ? context.palette.mint : context.palette.goldSoft,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(
          _jewelryIcon(item.jewelryType),
          color: converted ? context.palette.greenDark : context.palette.gold,
          size: 23,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 2),
            Text(
              '${item.karat}K gold · ${_jewelryTypeLabel(item.jewelryType)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.palette.muted, fontSize: 11.5),
            ),
          ],
        ),
      ),
      StatusPill(
        label: converted ? 'Converted' : 'Held',
        positive: converted,
        neutral: !converted,
      ),
    ],
  );
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value, this.icon});

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          color: context.palette.muted,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.25,
        ),
      ),
      const SizedBox(height: 4),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: context.palette.greenDark),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.palette.ink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

class _MoneyDetail extends StatelessWidget {
  const _MoneyDetail({
    required this.label,
    required this.amountMinor,
    required this.controller,
    this.color,
  });

  final String label;
  final int amountMinor;
  final AppController controller;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          color: context.palette.muted,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.25,
        ),
      ),
      const SizedBox(height: 4),
      MoneyLabel(
        minorUnits: amountMinor,
        currencyCode: controller.currencyCode,
        locale: controller.locale,
        style: TextStyle(
          color: color ?? context.palette.ink,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _GoldEstimateSource {
  const _GoldEstimateSource(this.savedRate);
  final ManualGoldPriceRate savedRate;
  int estimateMinor({required int weightMg, required int karat}) =>
      savedRate.estimateMinor(weightMg: weightMg);
}

_GoldEstimateSource? _goldEstimateSource(AppController controller, int karat) {
  final savedPrices = controller.manualGoldPrices;
  if (savedPrices.currencyCode.toUpperCase() !=
      controller.currencyCode.toUpperCase()) {
    return null;
  }
  final rate = savedPrices.rateFor(karat);
  return rate == null ? null : _GoldEstimateSource(rate);
}

class _JewelryEditorDialog extends StatefulWidget {
  const _JewelryEditorDialog({required this.controller, this.existing});

  final AppController controller;
  final JewelryItem? existing;

  @override
  State<_JewelryEditorDialog> createState() => _JewelryEditorDialogState();
}

class _JewelryEditorDialogState extends State<_JewelryEditorDialog> {
  static const _types = [
    'ring',
    'necklace',
    'bracelet',
    'earrings',
    'pendant',
    'watch',
    'coin',
    'bar',
    'other',
  ];
  static const _karats = _commonGoldKarats;

  final formKey = GlobalKey<FormState>();
  late final TextEditingController nameController;
  late final TextEditingController weightController;
  late final TextEditingController purchaseController;
  late final TextEditingController estimateController;
  late final TextEditingController notesController;
  late String jewelryType;
  late int karat;
  late DateTime? acquiredOn;
  late bool automaticEstimate;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.existing;
    nameController = TextEditingController(text: item?.name ?? '');
    weightController = TextEditingController(
      text: item == null ? '' : _weightDecimal(item.weightMg),
    );
    purchaseController = TextEditingController(
      text: item?.purchaseValueMinor == null
          ? ''
          : Money.decimal(item!.purchaseValueMinor!),
    );
    estimateController = TextEditingController(
      text: item == null ? '' : Money.decimal(item.estimatedValueMinor),
    );
    notesController = TextEditingController(text: item?.notes ?? '');
    jewelryType = item?.jewelryType ?? _types.first;
    karat = item?.karat ?? 18;
    acquiredOn = item?.acquiredOn ?? DateTime.now();
    automaticEstimate = item == null && estimateSource != null;
    weightController.addListener(_weightChanged);
  }

  @override
  void dispose() {
    weightController.removeListener(_weightChanged);
    nameController.dispose();
    weightController.dispose();
    purchaseController.dispose();
    estimateController.dispose();
    notesController.dispose();
    super.dispose();
  }

  _GoldEstimateSource? get estimateSource =>
      _goldEstimateSource(widget.controller, karat);

  void _weightChanged() {
    if (!automaticEstimate || !mounted) return;
    setState(_applyAutomaticEstimate);
  }

  void _toggleAutomaticEstimate(bool value) {
    setState(() {
      automaticEstimate = value && estimateSource != null;
      if (automaticEstimate) _applyAutomaticEstimate();
    });
  }

  void _applyAutomaticEstimate() {
    final source = estimateSource;
    if (!automaticEstimate || source == null) return;
    try {
      final weightMg = _parseWeightMg(weightController.text);
      final estimate = source.estimateMinor(weightMg: weightMg, karat: karat);
      estimateController.text = estimate <= 0 ? '' : Money.decimal(estimate);
    } on FormatException {
      estimateController.clear();
    }
  }

  String _estimateModeDescription() {
    final source = estimateSource;
    final savedPrices = widget.controller.manualGoldPrices;
    if (source == null) {
      if (savedPrices.rates.isNotEmpty &&
          savedPrices.currencyCode.toUpperCase() !=
              widget.controller.currencyCode.toUpperCase()) {
        return 'Manual entry required: saved prices use ${savedPrices.currencyCode}, but the app uses ${widget.controller.currencyCode}.';
      }
      if (savedPrices.rates.isNotEmpty) {
        return 'No saved ${karat}K price is available — enter an estimate manually or add this karat in Manage saved prices.';
      }
      return 'Add a saved price for this karat or enter an estimate manually.';
    }
    if (!automaticEstimate) {
      return 'Manual estimate selected. Turn this on to calculate using your saved ${karat}K price.';
    }
    final weight = _tryParseWeightMg(weightController.text);
    final weightText = weight == null
        ? 'Recorded grams'
        : _formatWeight(weight);
    final rate = source.savedRate;
    final price = Money.format(
      rate.pricePerGramMinor,
      currencyCode: savedPrices.currencyCode,
      locale: widget.controller.locale,
    );
    return '$weightText × saved ${rate.karat}K price of $price/g.';
  }

  @override
  Widget build(BuildContext context) {
    final availableTypes = {
      ..._types,
      if (!_types.contains(jewelryType)) jewelryType,
    }.toList();
    final availableKarats = {
      ..._karats,
      if (!_karats.contains(karat)) karat,
    }.toList()..sort();
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Add gold jewelry' : 'Edit jewelry',
      ),
      content: SizedBox(
        width: 620,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: context.palette.goldSoft.withValues(alpha: 0.58),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: context.palette.gold.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: context.palette.gold,
                        size: 19,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'Estimated gold value is tracked as an asset and does not increase any cash account until you convert the item.',
                          style: TextStyle(
                            color: context.palette.gold,
                            fontSize: 11.5,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 17),
                TextFormField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Item name',
                    hintText: 'Wedding ring, gold chain…',
                  ),
                  validator: (value) => value?.trim().isEmpty ?? true
                      ? 'Enter a name for this item.'
                      : null,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: jewelryType,
                        decoration: const InputDecoration(
                          labelText: 'Jewelry type',
                        ),
                        items: availableTypes
                            .map(
                              (type) => DropdownMenuItem(
                                value: type,
                                child: Text(_jewelryTypeLabel(type)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            jewelryType = value ?? jewelryType,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: const Key('jewelry-karat-field'),
                        initialValue: karat,
                        decoration: const InputDecoration(
                          labelText: 'Gold purity',
                        ),
                        items: availableKarats
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text('$value karat'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            karat = value;
                            if (automaticEstimate && estimateSource == null) {
                              automaticEstimate = false;
                              estimateController.clear();
                            } else {
                              _applyAutomaticEstimate();
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const Key('jewelry-weight-field'),
                        controller: weightController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Weight in grams',
                          hintText: '0.000',
                          suffixText: 'g',
                        ),
                        validator: (value) {
                          try {
                            return _parseWeightMg(value ?? '') <= 0
                                ? 'Weight must be greater than zero.'
                                : null;
                          } on FormatException catch (error) {
                            return error.message;
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: _pickAcquiredDate,
                        borderRadius: BorderRadius.circular(11),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Date acquired (optional)',
                            suffixIcon: acquiredOn == null
                                ? const Icon(
                                    Icons.calendar_today_rounded,
                                    size: 18,
                                  )
                                : IconButton(
                                    tooltip: 'Clear date',
                                    onPressed: () =>
                                        setState(() => acquiredOn = null),
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                    ),
                                  ),
                          ),
                          child: Text(
                            acquiredOn == null
                                ? 'Not specified'
                                : DateFormat('MMM d, y').format(acquiredOn!),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Material(
                  color: automaticEstimate
                      ? context.palette.goldSoft.withValues(alpha: 0.48)
                      : context.palette.canvas,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                    side: BorderSide(
                      color: automaticEstimate
                          ? context.palette.gold.withValues(alpha: 0.28)
                          : context.palette.border,
                    ),
                  ),
                  child: SwitchListTile.adaptive(
                    key: const Key('jewelry-auto-estimate-switch'),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 2,
                    ),
                    value: automaticEstimate,
                    onChanged: estimateSource == null
                        ? null
                        : _toggleAutomaticEstimate,
                    title: Text(
                      'Use automatic estimate',
                      style: TextStyle(
                        color: context.palette.ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      _estimateModeDescription(),
                      style: TextStyle(
                        color: context.palette.muted,
                        fontSize: 10.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: purchaseController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Purchase value (optional)',
                          hintText: '0.00',
                          prefixText: widget.controller.currencyCode == 'PHP'
                              ? '₱ '
                              : null,
                        ),
                        validator: _optionalMoneyValidator,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const Key('jewelry-estimate-field'),
                        controller: estimateController,
                        readOnly: automaticEstimate,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Current estimated gold value',
                          hintText: '0.00',
                          prefixText: widget.controller.currencyCode == 'PHP'
                              ? '₱ '
                              : null,
                          suffixIcon: automaticEstimate
                              ? const Icon(Icons.auto_graph_rounded, size: 18)
                              : null,
                          helperText: automaticEstimate
                              ? 'Calculated from grams, karat, and the current reference price.'
                              : 'Enter a manual estimate.',
                        ),
                        validator: (value) {
                          try {
                            final amount = Money.parse(value ?? '');
                            if (amount <= 0) {
                              return 'Estimate must be greater than zero.';
                            }
                            if (amount > Money.maxMinorUnits) {
                              return automaticEstimate
                                  ? 'The calculated estimate is too large.'
                                  : 'This estimate is too large.';
                            }
                            return null;
                          } on FormatException catch (error) {
                            return error.message;
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: notesController,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    hintText: 'Description, appraisal details, storage…',
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
        FilledButton.icon(
          onPressed: saving ? null : _save,
          icon: saving
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.palette.onPrimary,
                  ),
                )
              : const Icon(Icons.save_outlined, size: 18),
          label: Text(saving ? 'Saving…' : 'Save jewelry'),
        ),
      ],
    );
  }

  String? _optionalMoneyValidator(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      final amount = Money.parse(value);
      if (amount < 0) return 'Value cannot be negative.';
      if (amount > Money.maxMinorUnits) return 'This value is too large.';
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  Future<void> _pickAcquiredDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: acquiredOn ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => acquiredOn = picked);
  }

  Future<void> _save() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      final purchaseText = purchaseController.text.trim();
      await widget.controller.saveJewelry(
        existing: widget.existing,
        name: nameController.text.trim(),
        jewelryType: jewelryType,
        karat: karat,
        weightMg: _parseWeightMg(weightController.text),
        acquiredOn: acquiredOn,
        purchaseValueMinor: purchaseText.isEmpty
            ? null
            : Money.parse(purchaseText),
        estimatedValueMinor: Money.parse(estimateController.text),
        notes: notesController.text.trim().isEmpty
            ? null
            : notesController.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context);
        showSuccess(
          context,
          widget.existing == null
              ? 'Jewelry added to your collection.'
              : 'Jewelry details updated.',
        );
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class _ConversionDialog extends StatefulWidget {
  const _ConversionDialog({required this.controller, required this.item});

  final AppController controller;
  final JewelryItem item;

  @override
  State<_ConversionDialog> createState() => _ConversionDialogState();
}

class _ConversionDialogState extends State<_ConversionDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController amountController;
  late final String clientUuid;
  DateTime? _firstConversionDate;
  DateTime? _lastConversionDate;
  late DateTime convertedOn;
  int? accountId;
  bool saving = false;
  // Nullable additions keep an already-open dialog safe across hot reload.
  FinanceScope? _destinationScope;
  bool? _loadingDestinationAccounts;

  FinanceScope get destinationScope =>
      _destinationScope ?? widget.controller.selectedFinanceScope;
  bool get loadingDestinationAccounts => _loadingDestinationAccounts ?? false;

  List<Account> get destinationAccounts => widget.controller.accounts
      .where(
        (account) =>
            !account.isArchived &&
            account.scope == destinationScope &&
            account.isStandardAccount &&
            !account.isCreditCard,
      )
      .toList();

  @override
  void initState() {
    super.initState();
    _destinationScope = widget.controller.selectedFinanceScope;
    final accounts = destinationAccounts;
    clientUuid = widget.controller.newClientUuid();
    accountId = accounts.isEmpty ? null : accounts.first.id;
    _lastConversionDate = _dateOnly(DateTime.now());
    final acquiredOn = widget.item.acquiredOn == null
        ? null
        : _dateOnly(widget.item.acquiredOn!);
    _firstConversionDate = acquiredOn == null
        ? DateTime(1900)
        : acquiredOn.isAfter(lastConversionDate)
        ? lastConversionDate
        : acquiredOn;
    convertedOn = lastConversionDate.isBefore(firstConversionDate)
        ? firstConversionDate
        : lastConversionDate;
    amountController = TextEditingController(
      text: Money.decimal(widget.item.estimatedValueMinor),
    );
  }

  DateTime get lastConversionDate =>
      _lastConversionDate ?? _dateOnly(DateTime.now());

  DateTime get firstConversionDate {
    final stored = _firstConversionDate;
    if (stored != null) return stored;
    final acquiredOn = widget.item.acquiredOn;
    if (acquiredOn == null) return DateTime(1900);
    final acquiredDate = _dateOnly(acquiredOn);
    final today = lastConversionDate;
    return acquiredDate.isAfter(today) ? today : acquiredDate;
  }

  @override
  void dispose() {
    amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = destinationAccounts;
    return AlertDialog(
      title: const Text('Convert gold to money'),
      content: SizedBox(
        width: 540,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: context.palette.goldSoft.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: context.palette.gold.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: context.palette.surfaceRaised,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          _jewelryIcon(widget.item.jewelryType),
                          color: context.palette.gold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.item.name,
                              style: TextStyle(
                                color: context.palette.ink,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${widget.item.karat}K · ${_formatWeight(widget.item.weightMg)} · estimated ${Money.format(widget.item.estimatedValueMinor, currencyCode: widget.controller.currencyCode, locale: widget.controller.locale)}',
                              style: TextStyle(
                                color: context.palette.gold,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: amountController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Actual proceeds received',
                    hintText: '0.00',
                    prefixText: widget.controller.currencyCode == 'PHP'
                        ? '₱ '
                        : null,
                    helperText:
                        'This amount will be added to the chosen account.',
                  ),
                  validator: (value) {
                    try {
                      return Money.parse(value ?? '') <= 0
                          ? 'Proceeds must be greater than zero.'
                          : null;
                    } on FormatException catch (error) {
                      return error.message;
                    }
                  },
                ),
                const SizedBox(height: 14),
                if (loadingDestinationAccounts)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text('Loading destination accounts…'),
                      ],
                    ),
                  )
                else if (accounts.isEmpty)
                  Container(
                    key: const Key('conversion-no-destination-accounts'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.palette.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: context.palette.red.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Text(
                      'No active ${destinationScope.label} account. Create one in Accounts, then return here.',
                      style: TextStyle(
                        color: context.palette.inkSoft,
                        fontSize: 11.5,
                      ),
                    ),
                  )
                else
                  DropdownButtonFormField<int>(
                    key: ValueKey(destinationScope),
                    initialValue: accountId,
                    decoration: const InputDecoration(
                      labelText: 'Deposit proceeds into',
                      prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                    ),
                    items: accounts
                        .map(
                          (account) => DropdownMenuItem(
                            value: account.id,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 300,
                                  ),
                                  child: Text(
                                    account.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                StatusPill(
                                  label: account.scope.label,
                                  neutral:
                                      account.scope == FinanceScope.personal,
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => accountId = value,
                    validator: (value) =>
                        value == null ? 'Choose a destination account.' : null,
                  ),
                const SizedBox(height: 14),
                InkWell(
                  key: const Key('conversion-date-picker'),
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(11),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Conversion date',
                      suffixIcon: Icon(Icons.calendar_today_rounded, size: 18),
                    ),
                    child: Text(
                      DateFormat('EEEE, MMM d, y').format(convertedOn),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: context.palette.greenDark,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Confirming creates an income transaction in the selected account and moves this item from your held collection to conversion history.',
                        style: TextStyle(
                          color: context.palette.inkSoft,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
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
          onPressed: saving || loadingDestinationAccounts || accounts.isEmpty
              ? null
              : _convert,
          icon: saving
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.palette.onPrimary,
                  ),
                )
              : const Icon(Icons.currency_exchange_rounded, size: 18),
          label: Text(saving ? 'Converting…' : 'Confirm conversion'),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: convertedOn,
      firstDate: firstConversionDate,
      lastDate: lastConversionDate,
    );
    if (picked != null) setState(() => convertedOn = picked);
  }

  Future<void> _convert() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await widget.controller.convertJewelry(
        item: widget.item,
        clientUuid: clientUuid,
        accountId: accountId!,
        amountMinor: Money.parse(amountController.text),
        convertedOn: convertedOn,
      );
      if (mounted) {
        Navigator.pop(context);
        showSuccess(context, 'Jewelry converted and proceeds deposited.');
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

DateTime _dateOrOldest(DateTime? value) => value ?? DateTime(1900);

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

Color _gainColor(AppPalette palette, int amountMinor) => amountMinor > 0
    ? palette.greenDark
    : amountMinor < 0
    ? palette.red
    : palette.muted;

String _formatWeight(int weightMg) {
  final value = _weightDecimal(weightMg);
  return '$value g';
}

String _weightDecimal(int weightMg) {
  final whole = weightMg ~/ 1000;
  final fraction = (weightMg % 1000).toString().padLeft(3, '0');
  final trimmed = fraction.replaceFirst(RegExp(r'0+$'), '');
  return trimmed.isEmpty ? '$whole' : '$whole.$trimmed';
}

int _parseWeightMg(String input) {
  final normalized = input.trim().replaceAll(',', '');
  final match = RegExp(r'^(\d+)(?:\.(\d{1,3}))?$').firstMatch(normalized);
  if (match == null) {
    throw const FormatException(
      'Enter a valid gram weight with up to 3 decimals.',
    );
  }
  final whole = int.parse(match.group(1)!);
  final fraction = (match.group(2) ?? '').padRight(3, '0');
  return whole * 1000 + (fraction.isEmpty ? 0 : int.parse(fraction));
}

int? _tryParseWeightMg(String input) {
  try {
    return _parseWeightMg(input);
  } on FormatException {
    return null;
  }
}

String _jewelryTypeLabel(String value) => switch (value.toLowerCase()) {
  'ring' => 'Ring',
  'necklace' => 'Necklace',
  'bracelet' => 'Bracelet',
  'earrings' => 'Earrings',
  'pendant' => 'Pendant',
  'watch' => 'Watch',
  'coin' => 'Gold coin',
  'bar' => 'Gold bar',
  _ =>
    value.isEmpty ? 'Other' : '${value[0].toUpperCase()}${value.substring(1)}',
};

IconData _jewelryIcon(String value) => switch (value.toLowerCase()) {
  'watch' => Icons.watch_outlined,
  'coin' => Icons.monetization_on_outlined,
  'bar' => Icons.view_agenda_outlined,
  'bracelet' => Icons.circle_outlined,
  _ => Icons.diamond_outlined,
};
