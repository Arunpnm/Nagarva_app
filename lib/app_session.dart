import 'package:flutter/foundation.dart';

/// One row of `org_members` for the signed-in vendor, resolved at login.
/// Most vendors have exactly one; a consultant/owner linked to more than
/// one org sees a switcher (Settings page + LoginPage) built from this list.
class OrgMembershipInfo {
  const OrgMembershipInfo(
      {required this.orgId, required this.orgName, this.role});
  final String orgId;
  final String orgName;
  final String? role;
}

class AppSession extends ChangeNotifier {
  AppSession._();
  static final AppSession instance = AppSession._();

  String? authUserId;
  String? currentOrgId;
  String? currentOrgName;
  String? currentOrgSlug;

  /// Every org this vendor's auth user has an `org_members` row for.
  /// Populated on vendor login; empty for staff (PIN) sessions, which have
  /// no membership concept — a staff row belongs to exactly one org. A
  /// length > 1 is what gates the "Switch Organization" UI.
  List<OrgMembershipInfo> availableOrgs = [];

  /// Per-tenant branding: `organizations.logo_url` (Supabase Storage public
  /// URL). Shown in the sidebar header; falls back to the truck icon when
  /// null. Requires the `logo_url` column migration
  /// (supabase/20260717_org_logo_url.sql) before it can be set.
  String? currentOrgLogoUrl;
  String? currentStaffId;
  String? currentStaffName;
  String? currentStaffRole;
  Map<String, dynamic> planLimits = {};
  Map<String, dynamic> planFeatures = {};
  String? planName;
  String? planStatus;
  DateTime? trialEndsAt;

  // A session is "in" once we know which org we're scoped to, and either
  // a Supabase Auth user (vendor login) or a staff row (PIN login) has
  // been established.
  bool get isAuthenticated =>
      currentOrgId != null && (authUserId != null || currentStaffId != null);

  /// Item 11 (NAGARVA_STATUS.md) — trial-expiry lock. True once the org's
  /// trial window has passed and it was never upgraded (plan_status is
  /// still 'trial' — an org that upgraded keeps whatever status the
  /// upgrade set, e.g. 'active', and is never locked by this check even
  /// if trial_ends_at is in the past). No Razorpay dependency: this is
  /// pure app-side gating, independent of the actual checkout flow (which
  /// IS blocked on real Razorpay API keys — see PlanPageWidget).
  bool get isTrialExpired =>
      planStatus == 'trial' &&
      trialEndsAt != null &&
      trialEndsAt!.isBefore(DateTime.now());

  bool hasFeature(String key) => planFeatures[key] == true;

  // Returns true if the current count has hit the plan limit.
  // -1 means unlimited.
  bool isOverLimit(String key, int currentCount) {
    final limit = planLimits[key];
    if (limit == null) return false;
    final max = limit is int ? limit : (limit as num).toInt();
    if (max == -1) return false;
    return currentCount >= max;
  }

  int getLimit(String key) {
    final limit = planLimits[key];
    if (limit == null) return -1;
    return limit is int ? limit : (limit as num).toInt();
  }

  void setVendorSession({
    required String authUserId,
    required String orgId,
    required String orgName,
    required String orgSlug,
    String? logoUrl,
    Map<String, dynamic> limits = const {},
    Map<String, dynamic> features = const {},
    String? planName,
    String? planStatus,
    DateTime? trialEndsAt,
    List<OrgMembershipInfo>? availableOrgs,
  }) {
    this.authUserId = authUserId;
    currentOrgId = orgId;
    currentOrgName = orgName;
    currentOrgSlug = orgSlug;
    currentOrgLogoUrl = logoUrl;
    planLimits = Map<String, dynamic>.from(limits);
    planFeatures = Map<String, dynamic>.from(features);
    this.planName = planName;
    this.planStatus = planStatus;
    this.trialEndsAt = trialEndsAt;
    // Switching orgs (not logging in fresh) calls this again with
    // availableOrgs left null — keep the membership list as-is rather than
    // wiping it back to empty.
    if (availableOrgs != null) this.availableOrgs = availableOrgs;
    notifyListeners();
  }

  void setStaff(
      {required String staffId, required String staffName, String? role}) {
    currentStaffId = staffId;
    currentStaffName = staffName;
    currentStaffRole = role?.toLowerCase();
    notifyListeners();
  }

  /// True when the active session is a staff PIN login with role
  /// supervisor. Used for privacy gating: supervisors must not see
  /// customer name/phone on orders that are already completed.
  bool get isSupervisorSession =>
      currentStaffId != null && currentStaffRole == 'supervisor';

  // Used by staff (PIN) login: we know the org but there's no Supabase
  // Auth user behind it yet (that arrives with the Phase 0 Edge Function).
  // Any field left null/empty keeps its current value rather than wiping it.
  void setOrgOnly({
    required String orgId,
    String? orgName,
    String? orgSlug,
    String? logoUrl,
    Map<String, dynamic> limits = const {},
    Map<String, dynamic> features = const {},
    String? planName,
    String? planStatus,
    DateTime? trialEndsAt,
  }) {
    currentOrgId = orgId;
    if (orgName != null) currentOrgName = orgName;
    if (orgSlug != null) currentOrgSlug = orgSlug;
    if (logoUrl != null) currentOrgLogoUrl = logoUrl;
    if (limits.isNotEmpty) planLimits = Map<String, dynamic>.from(limits);
    if (features.isNotEmpty) {
      planFeatures = Map<String, dynamic>.from(features);
    }
    if (planName != null) this.planName = planName;
    if (planStatus != null) this.planStatus = planStatus;
    if (trialEndsAt != null) this.trialEndsAt = trialEndsAt;
    notifyListeners();
  }

  void clear() {
    authUserId = null;
    currentOrgId = null;
    currentOrgName = null;
    currentOrgSlug = null;
    currentOrgLogoUrl = null;
    currentStaffId = null;
    currentStaffName = null;
    currentStaffRole = null;
    planLimits = {};
    planFeatures = {};
    planName = null;
    planStatus = null;
    trialEndsAt = null;
    availableOrgs = [];
    notifyListeners();
  }
}
