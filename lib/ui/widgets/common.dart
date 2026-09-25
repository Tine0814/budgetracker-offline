import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../models/domain_models.dart';
import '../../theme/app_theme.dart';

bool isCompactLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 720;

EdgeInsets responsivePagePadding(BuildContext context) =>
    isCompactLayout(context)
    ? const EdgeInsets.fromLTRB(16, 16, 16, 32)
    : const EdgeInsets.fromLTRB(30, 28, 30, 42);

class ResponsivePair extends StatelessWidget {
  const ResponsivePair({
    super.key,
    required this.first,
    required this.second,
    this.spacing = 12,
    this.breakpoint = 520,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  final Widget first;
  final Widget second;
  final double spacing;
  final double breakpoint;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < breakpoint) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            first,
            SizedBox(height: spacing),
            second,
          ],
        );
      }
      return Row(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          Expanded(child: first),
          SizedBox(width: spacing),
          Expanded(child: second),
        ],
      );
    },
  );
}

class FinanceScopeSelector extends StatelessWidget {
  const FinanceScopeSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final FinanceScope selected;
  final ValueChanged<FinanceScope> onSelected;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class FinanceScopeNotice extends StatelessWidget {
  const FinanceScopeNotice({super.key, required this.scope});
  final FinanceScope scope;
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;

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
    final actionRow = Wrap(spacing: 10, runSpacing: 10, children: actions);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 780) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 18),
                actionRow,
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: heading),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 24),
              Flexible(child: actionRow),
            ],
          ],
        );
      },
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [context.palette.surfaceRaised, context.palette.surface],
        ),
      ),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 44),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [context.palette.greenDark, context.palette.violet],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: context.palette.greenDark.withValues(alpha: 0.24),
                  blurRadius: 18,
                ),
              ],
            ),
            child: Icon(icon, color: context.palette.onPrimary),
          ),
          const SizedBox(height: 15),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.positive = true,
    this.neutral = false,
  });

  final String label;
  final bool positive;
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final background = neutral
        ? context.palette.surfaceRaised
        : positive
        ? context.palette.successSoft
        : context.palette.orangeSoft;
    final foreground = neutral
        ? context.palette.muted
        : positive
        ? context.palette.success
        : context.palette.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class MoneyLabel extends StatelessWidget {
  const MoneyLabel({
    super.key,
    required this.minorUnits,
    required this.currencyCode,
    required this.locale,
    this.style,
    this.compact = false,
  });

  final int minorUnits;
  final String currencyCode;
  final String locale;
  final TextStyle? style;
  final bool compact;

  @override
  Widget build(BuildContext context) => Text(
    Money.format(
      minorUnits,
      currencyCode: currencyCode,
      locale: locale,
      compact: compact,
    ),
    style: style,
  );
}

Color colorFromHex(
  String value, {
  required Color fallback,
  required Color legacyReplacement,
}) {
  final normalized = value.replaceAll('#', '').toUpperCase();
  if (normalized == '159A73' ||
      normalized == '245C73' ||
      normalized == '18A57B' ||
      normalized == '000000' ||
      normalized == '1B1B1B' ||
      normalized == '111111' ||
      normalized == '181818') {
    return legacyReplacement;
  }
  final expanded = normalized.length == 6 ? 'FF$normalized' : normalized;
  return Color(int.tryParse(expanded, radix: 16) ?? fallback.toARGB32());
}

String friendlyError(Object error) {
  final raw = error.toString();
  return raw.startsWith('ApiException: ') ? raw.substring(14) : raw;
}

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        friendlyError(error),
        style: TextStyle(color: context.palette.onPrimary),
      ),
      backgroundColor: context.palette.red,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

void showSuccess(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: context.palette.successSoft,
      behavior: SnackBarBehavior.floating,
    ),
  );
}
