import 'package:flutter/foundation.dart';

class AppSession extends ChangeNotifier {
  AppSession._();
  static final AppSession instance = AppSession._();

  String? authUserId;
  String? currentOrgId;
  String? currentOrgName;
  String? currentOrgSlug;
  String? currentStaffId;
  String? currentStaffName;
  Map<String, dynamic> planLimits = {};
  Map<String, dynamic> planFeatures = {};
  String? planName;
  DateTime? trialEndsAt;

  // A session is "in" once we know which org we're scoped to, and either
  // a Supabase Auth user (vendor login) or a staff row (PIN login) has
  // been established.
  bool get isAuthenticated =>
      currentOrgId != null && (authUserId != null || currentStaffId != null);

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
    Map<String, dynamic> limits = const {},
    Map<String, dynamic> features = const {},
    String? planName,
    DateTime? trialEndsAt,
  }) {
    this.authUserId = authUserId;
    currentOrgId = orgId;
    currentOrgName = orgName;
    currentOrgSlug = orgSlug;
    planLimits = Map<String, dynamic>.from(limits);
    planFeatures = Map<String, dynamic>.from(features);
    this.planName = planName;
    this.trialEndsAt = trialEndsAt;
    notifyListeners();
  }

  void setStaff({required String staffId, required String staffName}) {
    currentStaffId = staffId;
    currentStaffName = staffName;
    notifyListeners();
  }

  // Used by staff (PIN) login: we know the org but there's no Supabase
  // Auth user behind it yet (that arrives with the Phase 0 Edge Function).
  // Any field left null/empty keeps its current value rather than wiping it.
  void setOrgOnly({
    required String orgId,
    String? orgName,
    String? orgSlug,
    Map<String, dynamic> limits = const {},
    Map<String, dynamic> features = const {},
    String? planName,
    DateTime? trialEndsAt,
  }) {
    currentOrgId = orgId;
    if (orgName != null) currentOrgName = orgName;
    if (orgSlug != null) currentOrgSlug = orgSlug;
    if (limits.isNotEmpty) planLimits = Map<String, dynamic>.from(limits);
    if (features.isNotEmpty) {
      planFeatures = Map<String, dynamic>.from(features);
    }
    if (planName != null) this.planName = planName;
    if (trialEndsAt != null) this.trialEndsAt = trialEndsAt;
    notifyListeners();
  }

  void clear() {
    authUserId = null;
    currentOrgId = null;
    currentOrgName = null;
    currentOrgSlug = null;
    currentStaffId = null;
    currentStaffName = null;
    planLimits = {};
    planFeatures = {};
    planName = null;
    trialEndsAt = null;
    notifyListeners();
  }
}
