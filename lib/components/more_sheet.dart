import 'package:flutter/material.dart';

import '/app_session.dart';
import '/backend/approval_queue.dart';
import '/backend/module_navigation.dart';
import '/backend/org_switch.dart';
import '/backend/session_logout.dart';
import '/backend/vendor_identity.dart';
import '/components/ng_widgets.dart';
import '/components/quick_entry_dialog.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/ng_tokens.dart';
import '/l10n/gen/app_localizations.dart';
import '/nav_items.dart';
import '/permissions.dart';
import '/settings_page/help_about_page.dart';

/// The "More" sheet — the redesign's replacement for the module drawer on
/// phones (Claude Design handoff, "MENU SHEET").
///
/// Same destinations, same filtering and the same navigation contract as
/// [AppNavDrawer] — it reads [navItemsForCurrentSession] and opens modules
/// through [openModule] — only the presentation changes: an 86%-height
/// sheet with the org header (doubling as the switcher), a search field,
/// and each group as a 4-column icon grid. Settings, Help and Log out sit
/// in a fixed footer.
///
/// Quick Entry has no slot in the redesign's bottom bar (each list screen
/// has its own "new" button), but Arun asked for it to be reachable from
/// everywhere (3 Sept 2026), so it is the first tile here rather than
/// gone.
class MoreSheet extends StatefulWidget {
  const MoreSheet({super.key, this.currentPageName, required this.host});

  final String? currentPageName;

  /// The screen that opened the sheet. Every action closes the sheet
  /// first, and the sheet's own context is dead the moment it closes, so
  /// navigation must run on this one. Using the sheet's context is why no
  /// menu tile opened anything (Arun, 21 Oct 2026: "in menu those icons
  /// were not working when i click") — the route lookup threw on a
  /// deactivated widget and the tap did nothing.
  final BuildContext host;

  static Future<void> show(BuildContext context, {String? currentPageName}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        builder: (_) =>
            MoreSheet(currentPageName: currentPageName, host: context),
      );

  @override
  State<MoreSheet> createState() => _MoreSheetState();
}

class _MoreSheetState extends State<MoreSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Same rule as the drawer: only a MANAGER session is filtered by the
  /// per-person matrix; owner never is, and supervisor/field sets are
  /// fixed by role.
  List<NavItem> _visibleItems() {
    final allowed =
        isOwnerOrManagerSession && AppSession.instance.currentStaffId != null
            ? (StaffPermissions.activeStaffPages ??
                const {'HomePage', 'OrdersPage', 'OperationsPage'})
            : null;
    final q = _query.text.trim().toLowerCase();
    return navItemsForCurrentSession()
        .where((e) => allowed == null || allowed.contains(e.name))
        // Matches the English name or the label in the app's language,
        // so a Tamil user can type either.
        .where((e) =>
            q.isEmpty ||
            e.label.toLowerCase().contains(q) ||
            localizedNavLabel(context, e).toLowerCase().contains(q))
        .toList();
  }

  void _open(String name) {
    final host = widget.host;
    Navigator.of(context).pop();
    if (name != widget.currentPageName && host.mounted) openModule(host, name);
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final items = _visibleItems();
    final q = _query.text.trim().toLowerCase();
    final l = AppLocalizations.of(context);
    final showQuick = isOwnerOrManagerSession &&
        (q.isEmpty ||
            'quick entry'.contains(q) ||
            l.ngQuickEntry.toLowerCase().contains(q));

    final groups = <({String name, List<_Tile> tiles})>[];
    for (final group in [...kNavGroups, kNavGroupOther]) {
      final inGroup = items
          .where((e) => kNavGroups.contains(e.group)
              ? e.group == group
              : group == kNavGroupOther)
          .map((e) => _Tile(
                icon: e.icon,
                label: localizedNavLabel(context, e),
                badge: e.name == 'OperationsPage',
                onTap: () => _open(e.name),
              ))
          .toList();
      if (group == kNavGroups.first && showQuick) {
        inGroup.insert(
          0,
          _Tile(
            icon: Icons.add_circle_outline_rounded,
            label: l.ngQuickEntry,
            onTap: () {
              Navigator.of(context).pop();
              if (widget.host.mounted) QuickEntryDialog.show(widget.host);
            },
          ),
        );
      }
      if (inGroup.isNotEmpty) groups.add((name: group, tiles: inGroup));
    }

    return FractionallySizedBox(
      heightFactor: 0.86,
      alignment: Alignment.bottomCenter,
      child: Container(
        decoration: BoxDecoration(
          color: c.sheet,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(NgRadius.sheet)),
          border: Border(top: BorderSide(color: c.w08)),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                color: c.w15,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _header(context, c),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: c.inset,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: c.w07),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, size: 20, color: c.faint),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _query,
                        onChanged: (_) => setState(() {}),
                        style: NgFonts.geist(fontSize: 14, color: c.text),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintText: l.ngSearchModules,
                          hintStyle:
                              NgFonts.geist(fontSize: 14, color: c.faint),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
                children: [
                  for (final g in groups) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
                      child: Text(
                        localizedNavGroup(context, g.name).toUpperCase(),
                        style: NgFonts.geist(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.96,
                          color: c.faint,
                        ),
                      ),
                    ),
                    GridView.count(
                      crossAxisCount: 4,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 6,
                      childAspectRatio: 0.78,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      children: g.tiles,
                    ),
                  ],
                  if (groups.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Center(
                        child: Text(
                          l.ngNoModuleMatches,
                          style: NgFonts.geist(fontSize: 13.5, color: c.mute),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                  18, 12, 18, 12 + MediaQuery.of(context).padding.bottom),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.w06)),
              ),
              child: Row(
                children: [
                  if (isOwnerOrManagerSession) ...[
                    Expanded(
                      child: _FooterButton(
                        icon: Icons.settings_rounded,
                        label: l.ngMenuSettings,
                        onTap: () => _open('SettingsPage'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: _FooterButton(
                      icon: Icons.support_agent_rounded,
                      label: l.ngHelp,
                      onTap: () {
                        Navigator.of(context).pop();
                        if (widget.host.mounted) {
                          widget.host.pushNamed(HelpAboutPage.routeName);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _FooterButton(
                      icon: Icons.logout_rounded,
                      label: AppLocalizations.of(context).logout,
                      danger: true,
                      onTap: () async {
                        // The ONE shared logout sequence — see the
                        // drawer's note on why there is no second copy.
                        Navigator.of(context).pop();
                        if (widget.host.mounted) {
                          await performLogout(widget.host);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Org name + switcher. Tappable only with more than one org — an
  /// affordance that leads to a list of one is noise (drawer, 3 Sept).
  Widget _header(BuildContext context, NgPalette c) {
    final orgs = AppSession.instance.availableOrgs.length;
    final multi = orgs > 1;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset('assets/images/nagarva_logo.png',
                fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  VendorIdentity.forDocument,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NgFonts.geist(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: c.text,
                  ),
                ),
                if (multi)
                  Row(
                    children: [
                      Icon(Icons.swap_horiz_rounded, size: 15, color: c.mute),
                      const SizedBox(width: 4),
                      Text(
                        AppLocalizations.of(context).ngOrgsSwitch('$orgs'),
                        style: NgFonts.geist(fontSize: 12.5, color: c.mute),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            customBorder: const CircleBorder(),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: c.s3, shape: BoxShape.circle),
              child: Icon(Icons.close_rounded, size: 20, color: c.soft),
            ),
          ),
        ],
      ),
    );
    if (!multi) return header;
    return InkWell(
      onTap: () async {
        Navigator.of(context).pop();
        if (widget.host.mounted) await switchOrgFlow(widget.host);
      },
      child: header,
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Shows the approval-queue count — the badge that used to sit on the
  /// Operations bar slot follows Operations into the sheet too.
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final tile = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: c.s3,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, size: 24, color: c.acc),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            badge
                ? ValueListenableBuilder<int>(
                    valueListenable: ApprovalQueue.instance.pendingCount,
                    builder: (context, n, _) => NgCountBadge(
                      count: n,
                      child: tile,
                    ),
                  )
                : tile,
            const SizedBox(height: 7),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: NgFonts.geist(fontSize: 11.5, height: 1.2, color: c.soft),
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterButton extends StatelessWidget {
  const _FooterButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final fg = danger ? c.red : c.text;
    return Material(
      color: danger ? c.redBg : c.s3,
      borderRadius: BorderRadius.circular(NgRadius.button),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NgRadius.button),
        child: SizedBox(
          height: 46,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: danger ? c.red : c.mute),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NgFonts.geist(
                      fontSize: 14, fontWeight: FontWeight.w500, color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
