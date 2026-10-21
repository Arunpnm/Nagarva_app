import 'database/database.dart';

/// Resolved org + plan data ready to hand to `AppSession.setVendorSession`.
/// Shared by LoginPage (initial sign-in) and the org switcher (Settings /
/// LoginPage multi-org picker) so the plan-lookup logic lives in one place.
class OrgSessionData {
  const OrgSessionData({
    required this.orgId,
    required this.orgName,
    required this.orgSlug,
    this.logoUrl,
    this.limits = const {},
    this.features = const {},
    this.planName,
    this.planStatus,
    this.trialEndsAt,
    this.graceDays = 7,
    this.orgActive = true,
    this.trialFallsBackToFree = false,
    this.trialEndedToFree = false,
  });

  final String orgId;
  final String orgName;
  final String orgSlug;
  final String? logoUrl;
  final Map<String, dynamic> limits;
  final Map<String, dynamic> features;
  final String? planName;
  final String? planStatus;
  final DateTime? trialEndsAt;

  /// `subscription_plans.grace_days` — how long after `trialEndsAt`
  /// before the account goes read-only (Item 32). Defaults to 7 only
  /// when the plan lookup below fails; the DB is the real authority
  /// (`assert_org_writable()`), so this value drives banner timing, not
  /// the block itself.
  final int graceDays;

  final bool orgActive;

  /// The org is on a trial that drops to a fallback plan (Free) when it
  /// ends instead of locking — vendor signup, 21 Oct 2026. Drives the
  /// last-3-days banner; the DB (org_effective_plan) is the real gate.
  final bool trialFallsBackToFree;

  /// That trial has ended: the limits/features/planName above are
  /// already the fallback plan's, and planStatus reads 'active'.
  final bool trialEndedToFree;
}

Future<OrgSessionData> loadOrgSessionData(String orgId) async {
  final orgs = await OrganizationsTable().queryRows(
    queryFn: (q) => q.eq('id', orgId).limit(1),
  );
  final org = orgs.isNotEmpty ? orgs.first : null;

  Map<String, dynamic> limits = {};
  Map<String, dynamic> features = {};
  String? planName;
  // Item 32: only overwritten if the plan lookup succeeds AND the column
  // has a value, so an org on a plan predating grace_days still gets a
  // sane window rather than 0 (which would skip grace entirely and lock
  // the moment the trial ends).
  int graceDays = 7;
  try {
    final planId = org?.planId;
    final plans = planId != null
        ? await SubscriptionPlansTable()
            .queryRows(queryFn: (q) => q.eq('id', planId).limit(1))
        : await SubscriptionPlansTable().queryRows(
            queryFn: (q) => q.eq('is_default_trial', true).limit(1),
          );
    if (plans.isNotEmpty) {
      final plan = plans.first;
      limits = (plan.limits is Map)
          ? Map<String, dynamic>.from(plan.limits as Map)
          : {};
      features = (plan.features is Map)
          ? Map<String, dynamic>.from(plan.features as Map)
          : {};
      planName = plan.name;
      graceDays = plan.graceDays ?? graceDays;
    }
  } catch (_) {
    // Plan lookup is best-effort — don't block login/switch on it.
  }

  // Trial with a fallback plan (vendor signup, 21 Oct 2026). Mirrors
  // org_effective_plan(): once the trial has ended the org IS on the
  // fallback plan, not in grace and not read-only.
  final fallbackId = org?.trialFallbackPlanId;
  final onTrial = org?.planStatus == 'trial' && org?.trialEndsAt != null;
  var planStatus = org?.planStatus;
  DateTime? trialEndsAt = org?.trialEndsAt;
  var fallsBack = false;
  var endedToFree = false;
  if (fallbackId != null && onTrial) {
    if (trialEndsAt!.isAfter(DateTime.now())) {
      fallsBack = true;
    } else {
      try {
        final fb = await SubscriptionPlansTable()
            .queryRows(queryFn: (q) => q.eq('id', fallbackId).limit(1));
        if (fb.isNotEmpty) {
          final plan = fb.first;
          limits = (plan.limits is Map)
              ? Map<String, dynamic>.from(plan.limits as Map)
              : {};
          features = (plan.features is Map)
              ? Map<String, dynamic>.from(plan.features as Map)
              : {};
          planName = plan.name;
        }
      } catch (_) {}
      planStatus = 'active';
      trialEndsAt = null;
      endedToFree = true;
    }
  }

  return OrgSessionData(
    orgId: orgId,
    orgName: org?.name ?? '',
    orgSlug: org?.slug ?? '',
    logoUrl: org?.logoUrl,
    limits: limits,
    features: features,
    planName: planName,
    planStatus: planStatus,
    trialEndsAt: trialEndsAt,
    graceDays: graceDays,
    orgActive: org?.active ?? true,
    trialFallsBackToFree: fallsBack,
    trialEndedToFree: endedToFree,
  );
}
