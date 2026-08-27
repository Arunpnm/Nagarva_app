import '/app_session.dart';
import 'last_selected_org.dart';

/// Why a session ended up in a particular org. Carried on
/// [OrgResolution] so a wrong landing can be diagnosed from a log line
/// instead of re-derived from four different call sites.
enum OrgChoiceMode {
  /// Device is bound to this org and the PIN was verified against it.
  bound,

  /// Restored silently from [LastSelectedOrg].
  stored,

  /// The user picked it from the switcher sheet.
  picker,

  /// The user belongs to exactly one org.
  only,
}

class OrgResolution {
  const OrgResolution(this.orgId, this.mode);
  final String orgId;
  final OrgChoiceMode mode;
}

/// Thrown when a PIN-bound device's org is not one the caller actually
/// belongs to. Deliberately fatal — see [resolveActiveOrg].
class BoundOrgNotAMembershipException implements Exception {
  const BoundOrgNotAMembershipException(this.boundOrgId);
  final String boundOrgId;

  @override
  String toString() =>
      'This device is set up for an organization your account no longer '
      'has access to. Ask the owner to re-bind it.';
}

/// **The single place the "which org am I in?" decision is made.**
///
/// Four entry points used to answer it four different ways, three of
/// them via `availableOrgs.first` — a row whose order is not even
/// deterministic, since neither membership query had an `ORDER BY`.
/// See `NAGARVA_MODULE_STATUS.md` section 10.4c.
///
/// Precedence:
///  1. [boundOrgId] — PIN path only. See the invariant below.
///  2. [LastSelectedOrg] — used SILENTLY when still a valid membership.
///  3. The picker, when there is more than one org AND [showPicker] is
///     supplied.
///  4. The single org, when there is exactly one.
///  5. Otherwise null — the caller reports "no organization" rather
///     than guessing.
///
/// **THE PIN INVARIANT: you land in the org you authenticated against.**
/// When [boundOrgId] is given, the stored choice is not consulted AT
/// ALL — not consulted-then-overridden, which would leave the
/// precedence readable as a mere preference. It is the only input.
///
/// `pin_login_page_widget.dart` verified the PIN against
/// `DeviceOrgBinding.boundOrgId` and then established the session for
/// `availableOrgs.first` — an unrelated variable. With several orgs
/// live an owner could verify against one legal entity and be dropped
/// into another's books. Making [boundOrgId] the sole input is what
/// turns that from unlikely into impossible.
///
/// **It fails closed.** If [boundOrgId] is not among [availableOrgs]
/// this THROWS rather than falling back, because falling back to
/// another org is the original defect in slower motion.
///
/// Modes 2-4 persist their result via [LastSelectedOrg.set] — one
/// writer, rather than call sites that can drift apart. Mode 4 matters
/// more than it looks: a single-org user gets their org stored on first
/// login and therefore never sees a picker even once.
Future<OrgResolution?> resolveActiveOrg({
  required List<OrgMembershipInfo> availableOrgs,
  String? boundOrgId,
  Future<String?> Function()? showPicker,
}) async {
  if (availableOrgs.isEmpty) return null;
  final ids = availableOrgs.map((o) => o.orgId).toSet();

  // 1. Bound device — sole input, fails closed.
  if (boundOrgId != null && boundOrgId.isNotEmpty) {
    if (!ids.contains(boundOrgId)) {
      throw BoundOrgNotAMembershipException(boundOrgId);
    }
    // Sync the one memory: after a PIN login the stored choice agrees
    // with the bound org, so a later email login on this device lands
    // in the same place rather than somewhere the user last switched to
    // and has since forgotten about.
    await LastSelectedOrg.set(boundOrgId);
    return OrgResolution(boundOrgId, OrgChoiceMode.bound);
  }

  // 2. Stored choice, silently, when it is still a real membership.
  final saved = await LastSelectedOrg.get();
  if (saved != null && ids.contains(saved)) {
    return OrgResolution(saved, OrgChoiceMode.stored);
  }

  // 3. More than one org and no stored choice: the app genuinely does
  //    not know which company the user means, and MUST NOT GUESS.
  //
  //    An earlier draft fell through to the oldest membership when the
  //    picker was dismissed. That is `.first` wearing a different name
  //    (Arun, 27 Aug 2026): the owner dismisses and silently lands in
  //    whichever org happens to sort oldest — the exact bug this file
  //    exists to remove, only narrowed to one branch. These are separate
  //    legal entities with separate books; a silent pick is never
  //    acceptable.
  //
  //    So the picker is re-shown. The only escape is to sign out, which
  //    the caller handles on null.
  if (availableOrgs.length > 1) {
    if (showPicker == null) {
      // No UI to ask with (cold-start restore, deep link). Resolve to
      // nothing and let the caller route to a screen that CAN ask,
      // rather than picking on the user's behalf.
      return null;
    }
    // Bounded rather than `while (true)`: if the sheet cannot be
    // presented at all it returns null instantly, and an unbounded loop
    // would spin forever instead of failing.
    for (var attempt = 0; attempt < 5; attempt++) {
      AppSession.instance.availableOrgs = availableOrgs;
      final chosen = await showPicker();
      if (chosen != null && ids.contains(chosen)) {
        await LastSelectedOrg.set(chosen);
        return OrgResolution(chosen, OrgChoiceMode.picker);
      }
    }
    return null;
  }

  // 4. Exactly one org. Stored so this user never sees a picker even
  //    once — the common case, handled by construction.
  final only = availableOrgs.first.orgId;
  await LastSelectedOrg.set(only);
  return OrgResolution(only, OrgChoiceMode.only);
}
