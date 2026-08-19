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

  /// organizations.active — defaults true so a null/missing column (or a
  /// session that hasn't loaded it yet) never wrongly locks someone out.
  /// Threaded through the same three call sites as planStatus (login,
  /// org-switch, session-restore).
  bool orgActive = true;

  /// Whether this session's Supabase Auth user has a `platform_admins`
  /// row — the same check `is_platform_admin()` makes at the DB level
  /// (see `/backend/platform_admin_status.dart`'s own doc comment for why
  /// this is cached rather than checked live at nav build time). Gates
  /// the Platform Admin nav entry (nav_items.dart). Vendor sessions only
  /// — never populated for a staff PIN session, since a platform admin is
  /// always Nagarva's own operator account, not a per-org staff identity.
  bool isPlatformAdmin = false;

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

  /// Grace window between trial expiry and the write-lock, in days.
  /// Comes from `subscription_plans.grace_days` (Item 32) — NOT a
  /// constant, per the no-hardcoded-plan-values rule. Falls back to 7
  /// only when a session hasn't loaded plan data yet; the DB is the
  /// authority either way (see `assert_org_writable()`), so a stale
  /// client value can only make the UI more permissive than the server,
  /// never less — the write still fails server-side with a clear message.
  int graceDays = 7;

  /// Item 32 / Arun's decision 18 Aug 2026: read-only, not a hard lock.
  /// An expired trial keeps full read access — a business locked out of
  /// its own live job data doesn't become a customer, it becomes a
  /// complaint — and loses the ability to CREATE records once grace has
  /// also passed.
  ///
  /// Ladder: banner while the trial runs down -> [isInTrialGrace] (full
  /// access, escalating banner) -> [isReadOnly] (view and export only).
  bool get isInTrialGrace {
    if (!isTrialExpired) return false;
    return DateTime.now()
        .isBefore(trialEndsAt!.add(Duration(days: graceDays)));
  }

  /// True once the trial AND its grace window have both passed. Mirrors
  /// `org_effective_plan().is_locked`; the server enforces it for real.
  bool get isReadOnly => isTrialExpired && !isInTrialGrace;

  /// Days left before writes stop. Negative once read-only.
  int get daysUntilReadOnly {
    if (trialEndsAt == null || planStatus != 'trial') return 9999;
    return trialEndsAt!
        .add(Duration(days: graceDays))
        .difference(DateTime.now())
        .inDays;
  }

  /// Days left in the trial proper (before grace starts).
  int get trialDaysRemaining {
    if (trialEndsAt == null || planStatus != 'trial') return 9999;
    return trialEndsAt!.difference(DateTime.now()).inDays;
  }

  /// Super-admin console, Step 3 (NAGARVA_STATUS.md) — a platform admin
  /// suspended this tenant via organizations.active. Deliberately a
  /// separate getter from isTrialExpired (different cause, different
  /// message) even though NavBarPage's lock screen shows both the same
  /// way — see main.dart.
  bool get isSuspended => !orgActive;

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
    int? graceDays,
    bool orgActive = true,
    List<OrgMembershipInfo>? availableOrgs,
  }) {
    if (graceDays != null) this.graceDays = graceDays;
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
    this.orgActive = orgActive;
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
    int? graceDays,
    bool? orgActive,
  }) {
    if (graceDays != null) this.graceDays = graceDays;
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
    if (orgActive != null) this.orgActive = orgActive;
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
    graceDays = 7;
    orgActive = true;
    isPlatformAdmin = false;
    availableOrgs = [];
    notifyListeners();
  }
}
