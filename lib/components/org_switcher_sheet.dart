import '/app_session.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Bottom sheet listing every org the signed-in vendor belongs to. Returns
/// the chosen orgId, or null if dismissed / the user tapped the org already
/// active. Callers still need to reload org+plan data and call
/// `AppSession.setVendorSession` — this sheet only picks the target org.
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
              onTap: () => Navigator.of(ctx).pop(isCurrent ? null : org.orgId),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
