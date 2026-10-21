

/// Good Morning/Afternoon/Evening based on current hour.
String? timeGreeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good Morning';
  if (h < 17) return 'Good Afternoon';
  return 'Good Evening';
}

/// Returns formatted today date e.g.
///
/// Tuesday, 13 May 2026.
String? todayLabel() {
  final now = DateTime.now();
  const days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}';
}

/// Returns today as YYYY-MM-DD ISO string for date filters.
String? todayIso() {
  return DateTime.now().toIso8601String().substring(0, 10);
}

/// Formats a double as Indian currency: Rs1.2L, Rs50K, Rs999.
String? inrFormat(double? amount) {
  final amt = amount ?? 0.0;
  final a = amt.abs();
  final sign = amt < 0 ? '-' : '';
  // The handoff writes on-screen money as "₹23.4k" / "₹1.85L". Geist
  // carries the ₹ glyph (checked 21 Oct 2026). PDFs do not use this
  // helper, so their "Rs" formatting is unaffected.
  if (a < 1000) return '$sign₹${a.toStringAsFixed(0)}';
  if (a < 100000) return '$sign₹${(a / 1000).toStringAsFixed(1)}k';
  return '$sign₹${(a / 100000).toStringAsFixed(2)}L';
}

/// Full rupee amount with Indian grouping, no decimals: "₹42,000",
/// "₹1,42,350". The handoff uses this on cards and totals, and the short
/// [inrFormat] ("₹23.4k") on tiles.
String inrFull(double? amount) {
  final amt = amount ?? 0.0;
  final sign = amt < 0 ? '-' : '';
  final digits = amt.abs().round().toString();
  if (digits.length <= 3) return '$sign₹$digits';
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '$sign₹${parts.join(',')},$last3';
}

/// Converts a double to integer string for count display.
String? numStr(double? n) {
  return (n ?? 0.0).toInt().toString();
}

/// Safe division returning 0.0-1.0 progress fraction.
double? divideDouble(
  double? a,
  double? b,
) {
  final numA = a ?? 0.0;
  final numB = b ?? 0.0;
  return numB == 0.0 ? 0.0 : (numA / numB).clamp(0.0, 1.0);
}

/// Returns progress label: X to go or Target achieved.
String? progressLabel(
  double? current,
  double? target,
) {
  final cur = current ?? 0.0;
  final tgt = target ?? 0.0;
  if (tgt <= 0) return 'Target not set';
  if (cur >= tgt) return 'Target achieved!';
  final remaining = tgt - cur;
  final a = remaining.abs();
  if (a < 1000) return '₹${a.toStringAsFixed(0)} to go';
  if (a < 100000) return '₹${(a / 1000).toStringAsFixed(1)}k to go';
  return '₹${(a / 100000).toStringAsFixed(2)}L to go';
}

/// Parses a string to double, defaults to 200000.
double? parseDouble(String? s) {
  return double.tryParse(s ?? '') ?? 200000.0;
}

/// Returns "from -> to" route string.
String? concatRoute(
  String? from,
  String? to,
) {
  return '${from ?? ''} -> ${to ?? ''}';
}

/// Formats DateTime as "15 May" short date.
String? formatDate(DateTime? d) {
  if (d == null) return '';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${d.day} ${months[d.month - 1]}';
}

/// Returns margin percentage string.
String? marginPct(
  double? netProfit,
  double? revenue,
) {
  final profit = netProfit ?? 0.0;
  final rev = revenue ?? 0.0;
  if (rev <= 0) return '0%';
  return '${(profit / rev * 100).toStringAsFixed(1)}%';
}
