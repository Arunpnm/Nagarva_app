import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/app_session.dart';
import '/backend/session_logout.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/l10n/gen/app_localizations.dart';
import '/nav_items.dart';
import '/permissions.dart';

/// The full module list, grouped — the app's own menu.
///
/// **Moved out of HomePage on 3 Sept 2026.** It had always been declared
/// on HomePage's own `Scaffold`, which meant the drawer existed on the
/// Dashboard and NOWHERE ELSE: from Orders, Leads, Operations or any
/// screen reached from them, the other twenty-odd modules were simply
/// unreachable without first navigating back to the Dashboard. Every
/// other page in this app builds its own `Scaffold` with no `drawer:`
/// (verified by grep — HomePage was the only file in `lib/` with one).
///
/// Arun, 3 Sept 2026: *"the left bar menu button is need in bottom now
/// its only in left top its hard to touch ther when we use mobile in one
/// hand"*. Reach was the complaint; reachability was the larger bug
/// underneath it.
///
/// It now lives on the SHELL `Scaffold` in `main.dart`, so it is one
/// drawer for every destination the shell renders, opened from the
/// bottom bar's Menu button.
///
/// Navigation still goes through `context.pushNamed`, unchanged from the
/// HomePage version. It is heavier than `_selectTab` — it pushes a fresh
/// shell — but `_tabs` only holds the bottom-nav destinations, so
/// switching to tab selection here would silently strip the drawer down
/// to those. Same class of drift this file's own history is a record of.
class AppNavDrawer extends StatelessWidget {
  const AppNavDrawer({super.key, this.currentPageName});

  /// Drives which section starts expanded. The HomePage version tested
  /// `inGroup.any((e) => e.name == 'HomePage')`, so the Sales section
  /// opened no matter where you were — its own comment claimed it opened
  /// "the section holding the CURRENT screen", which it never did.
  final String? currentPageName;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    // Mirrors the bottom nav / rail so the two navs cannot disagree about
    // what a manager may reach. Only ever applies to a MANAGER session:
    // owner never filters, and supervisor/field-staff sets are fixed by
    // role and contain no kPermModules names at all, so filtering them
    // here would empty their drawer.
    final allowed =
        isOwnerOrManagerSession && AppSession.instance.currentStaffId != null
            ? (StaffPermissions.activeStaffPages ??
                const {'HomePage', 'OrdersPage', 'OperationsPage'})
            : null;
    bool visible(String page) => allowed == null || allowed.contains(page);

    final items = navItemsForCurrentSession().where((e) => visible(e.name));

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 10),
              child: Text(
                AppSession.instance.currentOrgName ?? 'Nagarva',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.interTight(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: theme.primaryText,
                ),
              ),
            ),
            const Divider(height: 1),
            for (final group in [...kNavGroups, kNavGroupOther])
              ...(() {
                final inGroup = items
                    .where((e) => kNavGroups.contains(e.group)
                        ? e.group == group
                        // An item with an unknown group still renders,
                        // under Other, rather than disappearing.
                        : group == kNavGroupOther)
                    .toList();
                if (inGroup.isEmpty) return <Widget>[];
                return <Widget>[
                  Theme(
                    // ExpansionTile's own dividers read as separators
                    // between unrelated items, not as section edges.
                    data:
                        Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      initiallyExpanded:
                          inGroup.any((e) => e.name == currentPageName),
                      tilePadding:
                          const EdgeInsetsDirectional.fromSTEB(16, 0, 12, 0),
                      childrenPadding:
                          const EdgeInsetsDirectional.only(bottom: 4),
                      title: Text(
                        group.toUpperCase(),
                        style: GoogleFonts.interTight(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: theme.secondaryText,
                        ),
                      ),
                      children: [
                        for (final item in inGroup)
                          ListTile(
                            leading: Icon(item.icon,
                                color: item.name == currentPageName
                                    ? theme.primary
                                    : null),
                            title: Text(
                              item.label,
                              style: TextStyle(
                                fontWeight: item.name == currentPageName
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: item.name == currentPageName
                                    ? theme.primary
                                    : theme.primaryText,
                              ),
                            ),
                            onTap: () {
                              Navigator.of(context).pop();
                              if (item.name != currentPageName) {
                                context.pushNamed(item.name);
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                ];
              })(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout),
              title: Text(AppLocalizations.of(context).logout),
              onTap: () async {
                // The ONE shared logout sequence. A second, hand-rolled
                // copy on HomePage had already drifted once - it skipped
                // the stored-token clear and hardcoded a route that
                // stranded PIN-only staff on a screen they have no
                // credentials for.
                Navigator.of(context).pop();
                await performLogout(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
