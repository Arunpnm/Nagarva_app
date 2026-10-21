import 'package:flutter/material.dart';

import '/l10n/gen/app_localizations.dart';

import '/app_session.dart';
import '/components/global_search_delegate.dart';
import '/components/language_quick_button.dart';
import '/components/notification_bell.dart';
import '/components/theme_quick_button.dart';
import '/flutter_flow/ng_tokens.dart';

/// The redesign's shared top bar ("APP HEADER (shared)" in the handoff):
/// business logo and name on the left with the signed-in role under it,
/// then a row of 36×40 s1 icon buttons — notifications, language, theme,
/// search.
///
/// The org name is a SAFETY NET, not decoration (27 Aug 2026): Nagarva is
/// org-per-location and the last-used org is restored silently, so this
/// line is how an owner knows which company's books are open. It renders
/// only when a name is actually known — a placeholder company name would
/// be worse than none.
class NgTopBar extends StatelessWidget implements PreferredSizeWidget {
  const NgTopBar({
    super.key,
    this.showBack = false,
    this.extraActions = const [],
    this.onRefresh,
  });

  /// Reloads the screen's data. The refresh button only renders when a
  /// screen passes this, so it never appears as a button that does nothing.
  final VoidCallback? onRefresh;

  /// For non-tab screens that adopt the bar; tab screens leave it off.
  final bool showBack;

  /// Screen-specific buttons placed before the shared ones.
  final List<Widget> extraActions;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  static String _roleLabel(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = AppSession.instance;
    if (s.currentStaffId == null) return l.ngRoleOwner;
    final role = s.currentStaffRole ?? '';
    final pretty =
        role.isEmpty ? l.ngRoleStaff : role[0].toUpperCase() + role.substring(1);
    final name = (s.currentStaffName ?? '').trim();
    return name.isEmpty ? pretty : '$name · $pretty';
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final org = (AppSession.instance.currentOrgName ?? '').trim();
    final logo = (AppSession.instance.currentOrgLogoUrl ?? '').trim();
    return Material(
      color: c.bg,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: preferredSize.height,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 14, 6),
            child: Row(
              children: [
                if (showBack) ...[
                  NgHeaderButton(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Icon(Icons.arrow_back_rounded,
                        size: 21, color: c.soft),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: logo.isNotEmpty
                      ? Image.network(
                          logo,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Image.asset(
                              'assets/images/nagarva_logo.png',
                              fit: BoxFit.cover),
                        )
                      : Image.asset('assets/images/nagarva_logo.png',
                          fit: BoxFit.cover),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (org.isNotEmpty)
                        Text(
                          org,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NgFonts.geist(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: c.text,
                          ),
                        ),
                      Text(
                        _roleLabel(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NgFonts.geist(fontSize: 11.5, color: c.faint),
                      ),
                    ],
                  ),
                ),
                for (final a in extraActions) ...[a, const SizedBox(width: 4)],
                // Handoff order: refresh, theme, language, search,
                // notifications.
                if (onRefresh != null) ...[
                  NgHeaderButton(
                    onTap: onRefresh,
                    child: Icon(Icons.refresh_rounded, size: 20, color: c.soft),
                  ),
                  const SizedBox(width: 4),
                ],
                NgHeaderButton(
                  child: ThemeQuickButton(iconColor: c.soft),
                ),
                const SizedBox(width: 4),
                NgHeaderButton(
                  child: LanguageQuickButton(iconColor: c.soft),
                ),
                const SizedBox(width: 4),
                // Global customer search (orders + leads by name or phone).
                NgHeaderButton(
                  onTap: () => showSearch(
                      context: context, delegate: GlobalSearchDelegate()),
                  child: Icon(Icons.search_rounded, size: 21, color: c.soft),
                ),
                const SizedBox(width: 4),
                NgHeaderButton(
                  child: NotificationBell(iconSize: 21, iconColor: c.soft),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 36×40 s1 rounded button used across the top bar. Wraps an existing
/// interactive widget (bell, theme menu) or an icon with [onTap].
class NgHeaderButton extends StatelessWidget {
  const NgHeaderButton({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return SizedBox(
      width: 36,
      height: 40,
      child: Material(
        color: c.s1,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? Center(child: child)
            : InkWell(onTap: onTap, child: Center(child: child)),
      ),
    );
  }
}
