import '/backend/supabase/supabase.dart';

/// Staff pay types — `staff.pay_type` (migrated 1 Sept 2026).
///
/// From the staff-pay brief §2. Pay type is set on the staff record and
/// decides how that person earns, whether they appear on a crew sheet at
/// all, and whether they carry a running balance:
///
/// | Pay type      | Earns from            | On crew sheet | Carries balance |
/// |---------------|-----------------------|---------------|-----------------|
/// | monthly_fixed | fixed monthly salary  | No            | Yes (advances)  |
/// | dynamic       | per job, typed amount | Yes           | Yes (full)      |
/// | temporary     | per job, same-day     | Yes           | No (closes to 0)|
///
/// The three strings are enforced by `staff_pay_type_check` in Postgres.
/// Never hand-write them at a call site — use these constants, so a future
/// rename is one edit plus a migration rather than a grep.
class StaffPayType {
  StaffPayType._();

  /// Office staff, managers, accountants. Never on a crew sheet and never
  /// earning a job wage on top of salary (brief §2 and validation rule
  /// §11: "a monthly-fixed staff member cannot be added to a crew sheet").
  static const monthlyFixed = 'monthly_fixed';

  /// Loading crew and drivers — the majority of the workforce. Paid per
  /// job at an amount the vendor types; balance carries forward across
  /// months and may go negative.
  static const dynamicPay = 'dynamic';

  /// Casual hands hired for a single shift, paid and closed to zero the
  /// same day. A payment record, not a balance.
  static const temporary = 'temporary';

  static const all = <String>[monthlyFixed, dynamicPay, temporary];

  /// The pay types a crew sheet may show. Deliberately a list of what IS
  /// allowed rather than "everything except monthly_fixed" — a fourth pay
  /// type added later should have to be opted in explicitly, not appear
  /// on every crew sheet in the product by default.
  static const crewSheetEligible = <String>[dynamicPay, temporary];

  /// Defaults to [dynamicPay] when the column is null or unrecognised,
  /// matching the Postgres column default. A staff row predating the
  /// migration is loading crew until someone says otherwise, which is the
  /// safe direction: the alternative default (monthly_fixed) would make
  /// existing crew silently vanish from every crew sheet.
  static String of(StaffRow s) {
    final v = s.payType;
    return all.contains(v) ? v! : dynamicPay;
  }

  static bool isOnCrewSheet(StaffRow s) =>
      crewSheetEligible.contains(of(s));

  static String label(String payType) {
    switch (payType) {
      case monthlyFixed:
        return 'Monthly fixed';
      case temporary:
        return 'Temporary';
      case dynamicPay:
      default:
        return 'Dynamic';
    }
  }
}
