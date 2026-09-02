/// The ONE place an owner's PIN is written.
///
/// Created 28 Aug 2026 alongside the first-run PIN bootstrap
/// (`SetOwnerPinPage`). Before it, `_PinSettingCard` in
/// `settings_page_widget.dart` held this logic privately — including the
/// bound-vs-active org disambiguation, which is subtle and was learned
/// from a live bug on 27 Aug. A second screen that needed the same write
/// would have had to reimplement it, and this codebase's own history is
/// mostly two copies of one rule drifting apart (see CLAUDE.md on
/// `is_org_manager` vs `isOwnerOrManagerSession`, and on the two answers
/// to "which org am I in?"). So it moved here first, and both callers
/// use it.
///
/// **The PIN is never hashed in Dart.** It is written as plaintext to
/// `org_members.pin`, and `org_members_hash_pin_trigger`
/// (20260728_org_pin_login.sql) bcrypts it into `pin_hash` and nulls the
/// plaintext column in the same statement — verified live 28 Aug 2026:
/// every `org_members.pin` is NULL while `pin_hash` holds a `$2a$` hash.
/// Do not add a Dart-side hashing path; one hashing implementation is
/// the whole point.
library;

import 'package:flutter/material.dart';

import '/app_session.dart';
import '/backend/device_org_binding.dart';
import '/backend/supabase/supabase.dart';

/// Outcome of [saveOwnerPin], so callers render their own UI rather than
/// this helper reaching into two different screens' state.
class OwnerPinResult {
  const OwnerPinResult.ok() : saved = true, message = 'PIN updated.';
  const OwnerPinResult.cancelled()
      : saved = false,
        message = null;
  const OwnerPinResult.failed(this.message) : saved = false;

  final bool saved;

  /// Null only when the user cancelled — nothing to report in that case.
  final String? message;
}

/// True when this owner has no PIN on [orgId] yet.
///
/// Filters `pin_hash is null` SERVER-side and does not read the hash in
/// Dart. (The row still travels because `SupabaseTable` selects `*`;
/// narrowing that is a separate change, and `org_members.pin_hash` being
/// column-readable at all is a standing finding — see the 28 Aug 2026
/// note in NAGARVA_MODULE_STATUS.md.)
///
/// Returns false on any error. A failed lookup must not strand a vendor
/// on a PIN screen they did not ask for — the Settings card remains the
/// deliberate path in that case.
Future<bool> ownerNeedsPin({
  required String orgId,
  required String userId,
}) async {
  try {
    final rows = await OrgMembersTable().queryRows(
      queryFn: (q) => q
          .eq('org_id', orgId)
          .eq('user_id', userId)
          .eq('role', 'owner')
          .filter('pin_hash', 'is', null),
    );
    return rows.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Validates, resolves WHICH org the PIN belongs to, and writes it.
///
/// [context] is used only for the disambiguation dialog below; pass a
/// mounted context.
Future<OwnerPinResult> saveOwnerPin(BuildContext context, String rawPin) async {
  final pin = rawPin.trim();
  if (pin.length != 4 || int.tryParse(pin) == null) {
    return const OwnerPinResult.failed('Enter exactly 4 digits.');
  }

  final userId = SupaFlow.client.auth.currentUser?.id;
  final activeOrgId = AppSession.instance.currentOrgId;
  if (userId == null || activeOrgId == null) {
    return const OwnerPinResult.failed(
        'You are not signed in to an organization.');
  }

  // WHICH ORG DOES A PIN BELONG TO? (27 Aug 2026, moved here 28 Aug)
  //
  // The PIN lives on `org_members`, UNIQUE (org_id, user_id) — so it is
  // per (org, user). An owner of three orgs has three separate PINs.
  //
  // Settings used to write against `currentOrgId` unconditionally while
  // the PIN LOGIN screen reads `DeviceOrgBinding.boundOrgId`. Switch org
  // in Settings, set a PIN, and it lands on the active org while the
  // bound device keeps checking the other one — the PIN is correct,
  // stored, and unusable. Found live by exactly that sequence.
  //
  // Resolution: when the device is BOUND, the bound org is the only org
  // this PIN could ever sign into, so that is what we write — but we SAY
  // SO first rather than silently targeting a company the header does
  // not name. Unbound, the active org is right and no notice is needed.
  final boundOrgId = DeviceOrgBinding.boundOrgId;
  var orgId = activeOrgId;
  if (boundOrgId != null &&
      boundOrgId.isNotEmpty &&
      boundOrgId != activeOrgId) {
    if (!context.mounted) return const OwnerPinResult.cancelled();
    final boundName = DeviceOrgBinding.boundOrgName ?? 'another organization';
    final activeName = AppSession.instance.currentOrgName ?? 'the current one';
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Which organization?'),
        content: Text(
          'This device signs in to $boundName. Setting a PIN here will '
          'apply to $boundName, not $activeName.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('Set for $boundName')),
        ],
      ),
    );
    if (proceed != true) return const OwnerPinResult.cancelled();
    orgId = boundOrgId;
  }

  try {
    // returnRows: true is LOAD-BEARING, not diagnostic.
    //
    // 2 Sep 2026: org_members had RLS enabled with only SELECT and INSERT
    // policies and no UPDATE policy at all, so this update matched zero
    // rows. PostgREST does not error on that — it returns success — and
    // this function then reported "PIN updated." having written nothing.
    // Every owner who set a PIN was told it worked and could never
    // PIN-log-in, with no error anywhere to explain it. Found only by
    // reading pin_hash back out of the database afterwards.
    //
    // So the write is verified by what comes back, not assumed from the
    // absence of an exception. A policy change, a revoked grant or a
    // renamed column all fail the same silent way, and this turns every
    // one of them into a message the vendor can act on.
    final rows = await OrgMembersTable().update(
      data: {'pin': pin},
      matchingRows: (q) => q.eq('org_id', orgId).eq('user_id', userId),
      returnRows: true,
    );
    if (rows.isEmpty) {
      return const OwnerPinResult.failed(
          'Your PIN could not be saved — the app was not permitted to '
          'update your membership. Nothing was changed. Please report '
          'this; you can still sign in with your email and password.');
    }
    return const OwnerPinResult.ok();
  } catch (e) {
    return OwnerPinResult.failed('Could not update PIN: $e');
  }
}
