import '/app_session.dart';
import '/backend/edge_function_errors.dart';
import '/backend/platform_admin_status.dart';
import '/backend/supabase/org_session_loader.dart';
import '/backend/supabase/supabase.dart';
import '/staff_auth.dart';

/// Resolves a signed-in Supabase Auth [user]'s vendor org(s) — the same
/// create-org recovery path (NG-BRIEF-vendor-auth-flow.md §2a/§2b)
/// login_page_widget.dart's `_handleVendorLogin` used inline. Extracted
/// 17 Aug 2026 so the email-confirmation deep-link auto-login path
/// (main.dart) can share it instead of duplicating this org_members
/// lookup + create-org fallback logic a second time.
///
/// Looks up `org_members` first; if that comes back empty — the
/// confirmation-gap case, where `signUp()`'s own immediate-session
/// `create-org` call never ran because "Confirm email" was on — reads
/// `org_name`/`phone`/`owner_name` back out of the user's own auth
/// metadata (stashed there at signup for exactly this) and calls
/// `create-org` to finish the job now. `create_org_with_owner()` is
/// idempotent, so this doubles as the one-time repair for any
/// already-orphaned account, not just a fresh confirmation.
///
/// Throws on failure — callers decide how to surface that (an error
/// banner, routing to login, ...), never silently swallowed here.
///
/// [promptForOrgName], if given, is called ONLY when `org_name` metadata
/// is itself missing (an account that signed up before that
/// metadata-stashing fix existed) — the caller supplies its own UI (a
/// dialog needs a `BuildContext`) to ask for one. Omitted by the
/// deep-link path (no natural place for a blocking dialog before the
/// router even exists, and every real self-signup already has this
/// metadata by construction) — missing org_name there throws instead of
/// prompting.
Future<List<OrgMembershipInfo>> resolveVendorOrgs(
  User user, {
  Future<String?> Function()? promptForOrgName,
}) async {
  var members = await OrgMembersTable().queryRows(
    queryFn: (q) => q.eq('user_id', user.id),
  );
  var orgIds = members.map((m) => m.orgId).whereType<String>().toList();

  if (orgIds.isEmpty) {
    final meta = user.userMetadata ?? const <String, dynamic>{};
    var orgName = (meta['org_name'] as String?)?.trim();
    final metaPhone = (meta['phone'] as String?)?.trim();
    final metaOwnerName = (meta['owner_name'] as String?)?.trim();
    // Closed-beta gate (16 Aug 2026) — a code entered on SignupPage is
    // stashed in auth metadata precisely so this confirmation-gap retry,
    // which never saw that form, can still finish create-org for a
    // gated signup.
    final metaInviteCode = (meta['invite_code'] as String?)?.trim();

    if (orgName == null || orgName.isEmpty) {
      if (promptForOrgName == null) {
        throw Exception(
            'A business name is required to finish setting up your account.');
      }
      final prompted = await promptForOrgName();
      if (prompted == null || prompted.trim().isEmpty) {
        throw Exception(
            'A business name is required to finish setting up your account.');
      }
      orgName = prompted.trim();
    }

    Map data;
    try {
      final res = await SupaFlow.client.functions.invoke(
        'create-org',
        body: {
          'org_name': orgName,
          if (metaPhone != null && metaPhone.isNotEmpty) 'phone': metaPhone,
          if (metaOwnerName != null && metaOwnerName.isNotEmpty)
            'owner_name': metaOwnerName,
          if (metaInviteCode != null && metaInviteCode.isNotEmpty)
            'invite_code': metaInviteCode,
        },
      );
      // `invoke` throws on any non-2xx status (confirmed 17 Aug 2026 —
      // see edge_function_errors.dart) rather than returning here, so a
      // successful reach of this line always means create-org's `ok:
      // true` response, not an error one — the `data is! Map || ...`
      // check below is defensive, not the real error path anymore.
      data = res.data is Map ? res.data as Map : const {};
    } catch (e) {
      // This is what closed-beta signup's "stranded, no org" recovery
      // path actually surfaces (16 Aug 2026 invite-code gate) — a user
      // who confirmed email with an invalid/missing code lands back here
      // on next login, and this is the message they see.
      throw Exception(extractFunctionErrorMessage(e,
          fallback: 'Could not set up your organization. Please try again.'));
    }
    if (data['ok'] != true) {
      throw Exception('Could not set up your organization. Please try again.');
    }
    // caller_role is the one field allowed to gate a vendor session out
    // of this recovery path — never combined with any other flag (a
    // staff/manager account at someone else's org hitting this endpoint
    // also gets a plausible-looking response; caller_role is what tells
    // them apart).
    if (data['caller_role'] != 'owner') {
      throw Exception('This account is not linked to any organization.');
    }

    members = await OrgMembersTable().queryRows(
      queryFn: (q) => q.eq('user_id', user.id),
    );
    orgIds = members.map((m) => m.orgId).whereType<String>().toList();
    if (orgIds.isEmpty) {
      // create-org just reported ok:true — this would mean the
      // immediately-following read raced or failed independently. Never
      // trust a round-trip blindly; fail loudly instead of silently
      // re-entering the same dead end.
      throw Exception('Could not set up your organization. Please try again.');
    }
  }

  final orgRows = await OrganizationsTable().queryRows(
    queryFn: (q) => q.inFilter('id', orgIds),
  );
  final orgNameById = {for (final o in orgRows) o.id!: o.name};
  final roleByOrgId = {
    for (final m in members)
      if (m.orgId != null) m.orgId!: m.role,
  };
  return orgIds
      .map((id) => OrgMembershipInfo(
            orgId: id,
            orgName: orgNameById[id] ?? '(unnamed org)',
            role: roleByOrgId[id],
          ))
      .toList();
}

/// Finishes setting up AppSession/StaffAuth/platform-admin status for a
/// chosen vendor org — the tail end both `login_page_widget.dart`'s
/// vendor login and the deep-link auto-login path share once they have
/// the user and a resolved orgId (from [resolveVendorOrgs], or the
/// user's pick out of its result when there's more than one).
Future<void> establishVendorSession(
  User user,
  String orgId,
  List<OrgMembershipInfo> availableOrgs,
) async {
  final sessionData = await loadOrgSessionData(orgId);
  AppSession.instance.setVendorSession(
    authUserId: user.id,
    orgId: sessionData.orgId,
    orgName: sessionData.orgName,
    orgSlug: sessionData.orgSlug,
    logoUrl: sessionData.logoUrl,
    limits: sessionData.limits,
    features: sessionData.features,
    planName: sessionData.planName,
    planStatus: sessionData.planStatus,
    trialEndsAt: sessionData.trialEndsAt,
    graceDays: sessionData.graceDays,
    orgActive: sessionData.orgActive,
    availableOrgs: availableOrgs,
  );
  // Remember this vendor session so a later staff PIN unlock can be
  // Locked back to it without re-entering email/password (Option A).
  await StaffAuth.saveVendorRefreshToken();
  await refreshPlatformAdminStatus();
}
