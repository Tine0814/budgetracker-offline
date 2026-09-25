import 'package:intl/intl.dart';

/// Integer-based money helpers. One unit is one centavo/cent.
abstract final class Money {
  static const maxMinorUnits = 999999999999999;
  static final RegExp _inputPattern = RegExp(r'^-?\d+(?:\.\d{1,2})?$');

  static int parse(String input) {
    final normalized = input.trim().replaceAll(',', '');
    if (!_inputPattern.hasMatch(normalized)) {
      throw const FormatException(
        'Enter a valid amount with up to 2 decimals.',
      );
    }

    final negative = normalized.startsWith('-');
    final unsigned = negative ? normalized.substring(1) : normalized;
    final parts = unsigned.split('.');
    final whole = int.parse(parts.first);
    final fraction = parts.length == 1 ? '00' : parts.last.padRight(2, '0');
    final result = whole * 100 + int.parse(fraction);
    return negative ? -result : result;
  }

  static int fromJson(Object? value) {
    if (value == null) return 0;
    if (value is int) return value;
    final raw = value.toString().trim();
    if (raw.isEmpty) return 0;
    if (!RegExp(r'^-?\d+$').hasMatch(raw)) {
      throw FormatException('Expected an integer minor-unit amount.', raw);
    }
    return int.parse(raw);
  }

  static String decimal(int minorUnits) {
    final negative = minorUnits < 0;
    final absolute = minorUnits.abs();
    final result =
        '${absolute ~/ 100}.${(absolute % 100).toString().padLeft(2, '0')}';
    return negative ? '-$result' : result;
  }

  static String format(
    int minorUnits, {
    String currencyCode = 'PHP',
    String locale = 'en_PH',
    bool compact = false,
  }) {
    final amount = minorUnits / 100;
    if (compact && amount.abs() >= 1000) {
      return NumberFormat.compactCurrency(
        locale: locale,
        name: currencyCode,
        symbol: currencyCode == 'PHP' ? '₱' : null,
        decimalDigits: amount.abs() >= 100000 ? 0 : 1,
      ).format(amount);
    }
    return NumberFormat.currency(
      locale: locale,
      name: currencyCode,
      symbol: currencyCode == 'PHP' ? '₱' : null,
      decimalDigits: 2,
    ).format(amount);
  }
}

String apiDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime dateFromJson(Object? value) {
  if (value is DateTime) return DateTime(value.year, value.month, value.day);
  final raw = value?.toString() ?? '';
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
  if (match == null) {
    throw FormatException('Expected an API date in YYYY-MM-DD format.', raw);
  }

  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    throw FormatException('The API date is not a valid calendar date.', raw);
  }
  return parsed;
}
