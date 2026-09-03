import 'package:flutter/material.dart';

import '/app_session.dart';
import '/backend/last_selected_org.dart';
import '/backend/supabase/org_session_loader.dart';
import '/components/org_switcher_sheet.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';

/// Switching the active organisation — the one implementation.
///
/// Extracted from `settings_page_widget.dart` on 3 Sept 2026 when Arun
/// asked for the control to move: *"this switch org also try to keep in
/// top somewhere or in menu directly not inside settings modules"*.
///
/// He is right that Settings was the wrong home for it. Nagarva is
/// org-per-location — an owner's Tamil Nadu, Karnataka and Andhra
/// operations are separate legal entities with separate books — so
/// switching org is not a preference, it is *which company am I working
/// in right now*. That belongs beside the company name, not three taps
/// into a settings screen.
///
/// Returns true when the org actually changed.
///
/// What makes the switch take effect is NOT the navigation at the end —
/// it is the `KeyedSubtree` keyed on `currentOrgId` in `main.dart`, which
/// disposes every page's State so each one re-queries against the new
/// org. The `go()` only decides where the person lands, and the
/// Dashboard is the sensible place to arrive.
Future<bool> switchOrgFlow(BuildContext context) async {
  final chosen = await showOrgSwitcherSheet(context);
  if (chosen == null || chosen == AppSession.instance.currentOrgId) {
    return false;
  }
  final data = await loadOrgSessionData(chosen);
  AppSession.instance.setVendorSession(
    authUserId: AppSession.instance.authUserId!,
    orgId: data.orgId,
    orgName: data.orgName,
    orgSlug: data.orgSlug,
    logoUrl: data.logoUrl,
    limits: data.limits,
    features: data.features,
    planName: data.planName,
    planStatus: data.planStatus,
    trialEndsAt: data.trialEndsAt,
    graceDays: data.graceDays,
    orgActive: data.orgActive,
  );
  // So a later cold start restores this org rather than whichever
  // org_members row comes back first.
  await LastSelectedOrg.set(data.orgId);
  if (context.mounted) context.go(HomePageWidget.routePath);
  return true;
}
