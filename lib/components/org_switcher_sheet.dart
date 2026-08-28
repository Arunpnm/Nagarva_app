import '/app_session.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Bottom sheet listing every org the signed-in vendor belongs to.
///
/// Returns the tapped orgId, or **null only when the sheet was
/// dismissed without choosing**. Tapping the currently-active org
/// returns that org's id like any other — see the `onTap` comment for
/// why (28 Aug 2026: returning null there signed multi-org owners out
/// of the app at login).
///
/// A caller that treats re-selecting the current org as a no-op must
/// say so itself, as `settings_page_widget.dart` does. Callers still
/// need to reload org+plan data and call `AppSession.setVendorSession`
/// — this sheet only picks the target org.
Future<String?> showOrgSwitcherSheet(BuildContext context) {
  final theme = FlutterFlowTheme.of(context);
  final orgs = AppSession.instance.availableOrgs;
  final currentOrgId = AppSession.instance.currentOrgId;

  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: theme.primaryBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text(
              'Switch organization',
              style: GoogleFonts.interTight(
                color: theme.primaryText,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ...orgs.map((org) {
            final isCurrent = org.orgId == currentOrgId;
            return ListTile(
              leading: Icon(Icons.business, color: theme.primary),
              title: Text(
                org.orgName,
                style: GoogleFonts.inter(
                  color: theme.primaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: org.role != null
                  ? Text(
                      org.role!,
                      style: GoogleFonts.inter(color: theme.secondaryText),
                    )
                  : null,
              trailing: isCurrent
                  ? Icon(Icons.check_circle, color: theme.success)
                  : null,
              // Always return the tapped org, even when it is the one
              // already active. `null` here means "the user chose
              // nothing", and exactly one caller can distinguish that
              // from "the user chose the org they are already in".
              //
              // This used to pop null when isCurrent, which is right for
              // a SWITCHER and wrong for a CHOOSER, and the sheet is
              // both. resolveActiveOrg() reads null as declined: it
              // re-shows the sheet 5 times and then signs the user out
              // with "Choose an organization to continue". So a
              // multi-org owner whose currentOrgId was already set could
              // tap their own company, five times, and be ejected —
              // with no way to tell why.
              //
              // Settings already no-ops on `chosen == currentOrgId`
              // (settings_page_widget.dart), so it never relied on this
              // and is unaffected. Keep that guard at the call site: a
              // caller knows whether re-selecting is a no-op; a shared
              // widget does not.
              onTap: () => Navigator.of(ctx).pop(org.orgId),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
