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
    this.orgActive = true,
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
  final bool orgActive;
}

Future<OrgSessionData> loadOrgSessionData(String orgId) async {
  final orgs = await OrganizationsTable().queryRows(
    queryFn: (q) => q.eq('id', orgId).limit(1),
  );
  final org = orgs.isNotEmpty ? orgs.first : null;

  Map<String, dynamic> limits = {};
  Map<String, dynamic> features = {};
  String? planName;
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
    }
  } catch (_) {
    // Plan lookup is best-effort — don't block login/switch on it.
  }

  return OrgSessionData(
    orgId: orgId,
    orgName: org?.name ?? '',
    orgSlug: org?.slug ?? '',
    logoUrl: org?.logoUrl,
    limits: limits,
    features: features,
    planName: planName,
    planStatus: org?.planStatus,
    trialEndsAt: org?.trialEndsAt,
    orgActive: org?.active ?? true,
  );
}
