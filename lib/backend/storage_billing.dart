/// Warehouse storage charging.
///
/// Storage is a REVENUE LINE INSIDE AN ORDER, not a separate order (brief
/// §37). The same goods flow move-in → stored → move-out, and splitting
/// storage onto its own order would break the link between the inbound
/// job, the storage period and the outbound delivery.
///
/// Every rule below is load-bearing and came from the vendor, not from
/// arithmetic convenience:
///
/// * **Minimum 15 days.** An 8-day stay bills 15 (§38).
/// * **The plan is locked at booking** (§39). A daily stay bills daily for
///   its whole duration however long it runs — it does NOT become monthly
///   at day 30. A monthly stay bills whole months; early collection
///   forfeits the balance of the month with no pro-rata refund.
/// * **Never assume monthly is cheaper than daily.** In the vendor's own
///   rates it is cheaper for a Tata Ace (₹4,500 for 15 days vs ₹4,200 a
///   month) and *dearer* for a Pickup (₹5,250 vs ₹5,300). The two are
///   independent numbers. This file therefore contains no comparison, no
///   "best rate" suggestion and no automatic switching — whatever was
///   agreed at booking is what bills.
/// * **The rate is snapshotted onto the storage record** (§44), never read
///   live from a rate card. A price revision must not silently re-bill
///   goods already in storage.
///
/// Loading and unloading are billed separately as ordinary job lines
/// (§40) — `handling_in_charge` / `handling_out_charge` on the record —
/// and are returned here as their own component so rent and handling are
/// never conflated on a customer's bill.
library;

import 'dart:math' as math;

/// How a stay was agreed to bill. Chosen by the customer at booking
/// because availability drives the decision (§39) — never derived from
/// how long the goods actually stayed.
enum StorageBillingMode {
  /// Per day, with the minimum-days floor applied.
  perDay,

  /// Per calendar month, rounded UP to whole months. Early collection
  /// still pays the full month.
  perMonth,

  /// Anything negotiated. Bills exactly the agreed amount for the stay,
  /// with no day or month arithmetic applied.
  custom,
}

StorageBillingMode storageBillingModeFromWire(String? v) {
  switch ((v ?? '').trim()) {
    case 'per_day':
      return StorageBillingMode.perDay;
    case 'custom':
      return StorageBillingMode.custom;
    case 'per_month':
    default:
      // Matches the column default on storage_jobs.
      return StorageBillingMode.perMonth;
  }
}

String storageBillingModeToWire(StorageBillingMode m) {
  switch (m) {
    case StorageBillingMode.perDay:
      return 'per_day';
    case StorageBillingMode.perMonth:
      return 'per_month';
    case StorageBillingMode.custom:
      return 'custom';
  }
}

String storageBillingModeLabel(StorageBillingMode m) {
  switch (m) {
    case StorageBillingMode.perDay:
      return 'Daily';
    case StorageBillingMode.perMonth:
      return 'Monthly';
    case StorageBillingMode.custom:
      return 'Custom';
  }
}

/// The vendor's default minimum stay. Editable per record — this is the
/// value a NEW storage booking opens on, not a rule the code enforces
/// behind the vendor's back.
const int kStorageDefaultMinDays = 15;

/// A priced storage stay.
class StorageCharge {
  const StorageCharge({
    required this.days,
    required this.billedUnits,
    required this.unitLabel,
    required this.rent,
    required this.handlingIn,
    required this.handlingOut,
    required this.minimumApplied,
  });

  /// Actual days the goods were (or have so far been) in store.
  final int days;

  /// Units actually charged — days for a daily stay, whole months for a
  /// monthly one, 1 for a custom arrangement.
  final int billedUnits;

  /// 'day' / 'days' / 'month' / 'months', for rendering.
  final String unitLabel;

  /// Rent only. Handling is deliberately NOT folded in.
  final double rent;

  final double handlingIn;
  final double handlingOut;

  /// True when the minimum-days floor lifted the bill above the actual
  /// stay. Surfaced so a customer disputing an 8-day bill charged at 15
  /// can be shown why, rather than being told a number.
  final bool minimumApplied;

  double get total => rent + handlingIn + handlingOut;
}

/// Whole days between two dates, floor 0.
///
/// Date-only arithmetic on purpose: a stay is counted in calendar days,
/// and using timestamps would make an intake at 9am and one at 6pm bill
/// differently for the same day.
int storageDays(DateTime inDate, DateTime outDate) {
  final a = DateTime(inDate.year, inDate.month, inDate.day);
  final b = DateTime(outDate.year, outDate.month, outDate.day);
  final d = b.difference(a).inDays;
  return d < 0 ? 0 : d;
}

/// Prices a stay.
///
/// [outDate] null means the goods are still in store — the charge is the
/// accrual to [asOf] (default today). Storage accrues while goods remain
/// (§41); it is not a single bill raised at booking.
///
/// [customAmount] is used only by [StorageBillingMode.custom].
StorageCharge computeStorageCharge({
  required DateTime inDate,
  DateTime? outDate,
  DateTime? asOf,
  required StorageBillingMode mode,
  required double rate,
  int minBillingDays = kStorageDefaultMinDays,
  double handlingIn = 0,
  double handlingOut = 0,
  double customAmount = 0,
}) {
  final end = outDate ?? asOf ?? DateTime.now();
  final actualDays = storageDays(inDate, end);

  switch (mode) {
    case StorageBillingMode.custom:
      // A negotiated arrangement bills what was negotiated. No floor, no
      // rounding — applying either would silently overwrite the deal.
      return StorageCharge(
        days: actualDays,
        billedUnits: 1,
        unitLabel: 'stay',
        rent: customAmount,
        handlingIn: handlingIn,
        handlingOut: handlingOut,
        minimumApplied: false,
      );

    case StorageBillingMode.perDay:
      final floor = minBillingDays < 0 ? 0 : minBillingDays;
      final billedDays = math.max(actualDays, floor);
      return StorageCharge(
        days: actualDays,
        billedUnits: billedDays,
        unitLabel: billedDays == 1 ? 'day' : 'days',
        rent: rate * billedDays,
        handlingIn: handlingIn,
        handlingOut: handlingOut,
        minimumApplied: billedDays > actualDays,
      );

    case StorageBillingMode.perMonth:
      // Whole months, rounded UP: a stay of 31 days is two months, and
      // collecting early does not refund the rest of the month (§39).
      // Day 0 (checked in and out the same day) is still one month —
      // the goods occupied the space and the plan was monthly.
      final months = actualDays <= 0 ? 1 : (actualDays / 30).ceil();
      return StorageCharge(
        days: actualDays,
        billedUnits: months,
        unitLabel: months == 1 ? 'month' : 'months',
        rent: rate * months,
        handlingIn: handlingIn,
        handlingOut: handlingOut,
        // The monthly rounding is not the "minimum days" floor; keeping
        // them distinct stops the UI explaining one with the other.
        minimumApplied: false,
      );
  }
}

/// A storage size and its rates, as a vendor configures them.
///
/// Sizes are a VENDOR-DEFINED list (§44). The vendor prices by vehicle or
/// container here, but another may price by square feet, room count or
/// pallet — so this is a plain label, never an enum.
class StorageSizeRate {
  const StorageSizeRate({
    required this.size,
    required this.perDay,
    required this.perMonth,
    this.minDays = kStorageDefaultMinDays,
    this.handlingIn = 0,
    this.handlingOut = 0,
  });

  final String size;
  final double perDay;
  final double perMonth;
  final int minDays;

  /// Loading in and out, per stay.
  ///
  /// ADDED 3 Sept 2026 (Arun): handling was typed by hand on every single
  /// booking, because the rate card held only rent. It is normally a
  /// standard figure per size, so retyping it per stay is both slower and
  /// a chance to key it wrong on a customer's bill.
  ///
  /// Still stored per stay on `storage_jobs` and still billed as its own
  /// component — these are the DEFAULTS a booking opens on, exactly like
  /// [perDay]. Rent and handling must never be conflated (brief 40).
  ///
  /// 0 is a legitimate value meaning "we do not charge for handling", not
  /// "unset" — the same reason the rest of the card has no fallback.
  final double handlingIn;
  final double handlingOut;

  /// What the minimum stay costs on the daily plan. Shown at booking so
  /// the floor is disclosed rather than discovered on the final bill.
  double get minimumCharge => perDay * minDays;
}

/// Parses the org's storage rates out of `pricing_config.config`.
///
/// THERE IS NO DEFAULT LIST, and that is the point. A shipped rate table
/// would be one vendor's prices pre-filled as another vendor's — the
/// "No suggested money. Ever." rule in CLAUDE.md. An org that has not
/// configured storage rates gets an EMPTY list, the size picker says so,
/// and the rate field opens blank for the vendor to type.
///
/// Stored shape (jsonb, same file as survey_cats / cft_ranges):
///
///     "storage_rates": [
///       {"size": "Tata Ace", "per_day": 300, "per_month": 4200,
///        "min_days": 15}
///     ]
List<StorageSizeRate> parseStorageRates(dynamic raw) {
  if (raw is! List) return const [];
  final out = <StorageSizeRate>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final size = '${e['size'] ?? ''}'.trim();
    if (size.isEmpty) continue;
    out.add(StorageSizeRate(
      size: size,
      perDay: (num.tryParse('${e['per_day']}') ?? 0).toDouble(),
      perMonth: (num.tryParse('${e['per_month']}') ?? 0).toDouble(),
      minDays: (num.tryParse('${e['min_days']}') ?? kStorageDefaultMinDays)
          .toInt(),
      // Absent reads as 0, so every card written before handling existed
      // keeps working and simply offers no handling default.
      handlingIn: (num.tryParse('${e['handling_in']}') ?? 0).toDouble(),
      handlingOut: (num.tryParse('${e['handling_out']}') ?? 0).toDouble(),
    ));
  }
  return out;
}

/// Inverse of [parseStorageRates], for the rates editor.
List<Map<String, dynamic>> storageRatesToConfig(List<StorageSizeRate> rates) =>
    rates
        .map((r) => <String, dynamic>{
              'size': r.size,
              'per_day': r.perDay,
              'per_month': r.perMonth,
              'min_days': r.minDays,
              'handling_in': r.handlingIn,
              'handling_out': r.handlingOut,
            })
        .toList();

/// Suggests a storage size from the goods volume, using the org's own
/// CFT→vehicle slabs so storage and shifting speak the same language.
///
/// Returns null when nothing matches rather than guessing — the same rule
/// `suggestPackage` follows, and for the same reason: a silently wrong
/// size here prices the whole stay wrongly.
String? suggestStorageSize(double totalCft, List<StorageSizeRate> rates,
    String? Function(double cft) vehicleForCft) {
  if (totalCft <= 0 || rates.isEmpty) return null;
  final vehicle = vehicleForCft(totalCft);
  if (vehicle == null || vehicle.trim().isEmpty) return null;
  final wanted = vehicle.trim().toLowerCase();
  for (final r in rates) {
    if (r.size.trim().toLowerCase() == wanted) return r.size;
  }
  return null;
}
