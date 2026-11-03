import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/app_session.dart';
import '/backend/approval_queue.dart';
import '/flutter_flow/ng_tokens.dart';
import '/l10n/gen/app_localizations.dart';
import '/nav_items.dart';
import '/permissions.dart';
import 'mobile_bottom_nav.dart';
import 'more_sheet.dart';

/// Global, hideable bottom bar (Arun, 4 Nov 2026).
///
/// "The bottom bar should be available across all pages/screens ... with
/// an option to hide and reappear ... implement this as a global feature
/// rather than developing it separately for individual pages."
///
/// Before this the bar lived inside `NavBarPage` (the app shell), so every
/// screen pushed on top of a shell — Lead Details, Order Details, the
/// journey, a rate card — had no bar at all, and the shell hid it on
/// every downward scroll. Now:
///
///  * [GlobalBottomBarHost] wraps the WHOLE router output once, in
///    `MaterialApp.router(builder:)`, so every route gets the same bar
///    with no per-page code.
///  * Hide/show is manual and remembered ([BottomBarVisibility]); the
///    scroll auto-hide is gone so the bar never moves on its own.
///  * Hidden = zero height, so the page below gets the full screen. A
///    small handle at the bottom centre brings it back.
///  * The shell registers itself with [ShellTabBridge]. Tapping a tab
///    from a pushed screen pops back to that shell and switches tab
///    there; hiding or showing never touches navigation at all.

/// Remembered visible/hidden state. Default visible.
class BottomBarVisibility {
  BottomBarVisibility._() {
    SharedPreferences.getInstance().then((p) {
      try {
        final saved = p.getBool(_key);
        if (saved != null) visible.value = saved;
      } catch (_) {}
    }).catchError((_) {});
  }
  static final instance = BottomBarVisibility._();
  static const _key = '__bottom_bar_visible__';

  final visible = ValueNotifier<bool>(true);

  void set(bool v) {
    if (visible.value == v) return;
    visible.value = v;
    SharedPreferences.getInstance()
        .then((p) => p.setBool(_key, v))
        .catchError((_) => false);
  }

  void hide() => set(false);
  void show() => set(true);
}

/// What the global bar needs from an app shell (`NavBarPage`).
abstract class ShellTabHost {
  bool get mounted;
  BuildContext get context;

  /// All destinations this session may open (permission-filtered).
  List<NavItem> get shellNavItems;

  /// The tab the shell is showing.
  String get shellCurrentPageName;

  void selectShellTab(String name);

  void openShellMore();
}

/// The shells currently in the navigator, top-most last.
class ShellTabBridge extends ChangeNotifier {
  ShellTabBridge._();
  static final instance = ShellTabBridge._();

  final List<ShellTabHost> _shells = [];

  ShellTabHost? get top {
    for (var i = _shells.length - 1; i >= 0; i--) {
      if (_shells[i].mounted) return _shells[i];
    }
    return null;
  }

  void attach(ShellTabHost s) {
    _shells.remove(s);
    _shells.add(s);
    _notifySoon();
  }

  void detach(ShellTabHost s) {
    _shells.remove(s);
    _notifySoon();
  }

  /// The shell's tab changed.
  void changed() => _notifySoon();

  bool _scheduled = false;
  void _notifySoon() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      notifyListeners();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }
}

/// Routes that never show the bar: sign-in, setup and customer-facing
/// pages, plus the platform admin panel (its own chrome).
const _kNoBarPrefixes = [
  '/login',
  '/signup',
  '/signup-mobile',
  '/survey',
  '/quote',
  '/sign',
  '/track',
  '/pin-login',
  '/bind-org',
  '/admin-login',
  '/org-setup',
  '/set-owner-pin',
  '/set-new-password',
  '/super-admin',
];

/// Whole path segments only: '/survey' (the customer's survey page) must
/// not swallow '/survey-quote' or '/survey-new', which are vendor screens.
bool _barAllowedOn(String path) =>
    path != '/' &&
    !_kNoBarPrefixes.any((p) => path == p || path.startsWith('$p/'));

/// Same permission filter `NavBarPage._navItems` applies, for the rare
/// case where no shell is in the navigator (a deep link straight to a
/// detail screen).
List<NavItem> _sessionNavItems() {
  final base = navItemsForCurrentSession();
  if (AppSession.instance.currentStaffId == null) return base;
  if (!isOwnerOrManagerSession) return base;
  final allowed = StaffPermissions.activeStaffPages ?? const <String>{};
  return base.where((e) => allowed.contains(e.name)).toList();
}

/// Wraps the router output once (MaterialApp.router `builder:`).
///
/// Built so that NOTHING the bar listens to can rebuild the pages: this
/// widget is stateless toward the router/session, the page subtree only
/// re-lays-out when the bar is shown or hidden, and all the bar's own
/// listening lives in [_BarArea], which rebuilds just itself — and only
/// when what it would draw actually changed.
class GlobalBottomBarHost extends StatelessWidget {
  const GlobalBottomBarHost({
    super.key,
    required this.router,
    required this.navigatorKey,
    required this.child,
  });

  final GoRouter router;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  /// True while the bar takes up space at the bottom (eligible screen,
  /// visible, keyboard closed). Written only by [_BarArea], after a frame.
  static final _occupies = ValueNotifier<bool>(false);

  @override
  Widget build(BuildContext context) {
    final page = ValueListenableBuilder<bool>(
      valueListenable: _occupies,
      // The page is passed through as `child`, so a show/hide only
      // swaps the MediaQuery above it; the page itself is not rebuilt.
      child: child,
      builder: (context, occupies, page) => MediaQuery.removePadding(
        context: context,
        // While the bar shows it owns the bottom safe area, so the page
        // must not pad for it a second time.
        removeBottom: occupies,
        child: page!,
      ),
    );
    return Column(
      children: [
        Expanded(child: page),
        _BarArea(router: router, navigatorKey: navigatorKey),
      ],
    );
  }
}

/// What the bar would draw; rebuild only when this changes.
class _BarModel {
  _BarModel(this.eligible, this.items, this.current, this.hasShell);
  final bool eligible;
  final List<NavItem> items;
  final String? current;
  final bool hasShell;

  @override
  bool operator ==(Object o) =>
      o is _BarModel &&
      o.eligible == eligible &&
      o.current == current &&
      o.hasShell == hasShell &&
      o.items.length == items.length &&
      Iterable.generate(items.length)
          .every((i) => o.items[i].name == items[i].name);

  @override
  int get hashCode => Object.hash(eligible, current, hasShell, items.length);
}

/// Routes and session state decide whether the bar may show; the
/// handle reads the same answer.
final _eligibleNow = ValueNotifier<bool>(false);

class _BarArea extends StatefulWidget {
  const _BarArea({required this.router, required this.navigatorKey});
  final GoRouter router;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<_BarArea> createState() => _BarAreaState();
}

class _BarAreaState extends State<_BarArea>
    with SingleTickerProviderStateMixin {
  final _vis = BottomBarVisibility.instance;
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: _vis.visible.value ? 1 : 0,
  );
  _BarModel? _model;
  bool _checkScheduled = false;

  @override
  void initState() {
    super.initState();
    _vis.visible.addListener(_onVisibility);
    widget.router.routerDelegate.addListener(_scheduleCheck);
    ShellTabBridge.instance.addListener(_scheduleCheck);
    AppSession.instance.addListener(_scheduleCheck);
    _scheduleCheck();
  }

  @override
  void dispose() {
    _vis.visible.removeListener(_onVisibility);
    widget.router.routerDelegate.removeListener(_scheduleCheck);
    ShellTabBridge.instance.removeListener(_scheduleCheck);
    AppSession.instance.removeListener(_scheduleCheck);
    _anim.dispose();
    super.dispose();
  }

  void _onVisibility() {
    if (_vis.visible.value) {
      _anim.forward();
    } else {
      _anim.reverse();
    }
    if (mounted) setState(() {});
    _publishOccupies();
  }

  /// Never rebuild from inside someone else's build: wait for the frame
  /// to finish, then compare and rebuild only on a real change.
  void _scheduleCheck() {
    if (_checkScheduled || !mounted) return;
    _checkScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (!mounted) return;
      final next = _compute();
      _eligibleNow.value = next.eligible && next.items.isNotEmpty;
      if (next != _model) setState(() => _model = next);
      _publishOccupies();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _publishOccupies() {
    final m = _model;
    final kb = (WidgetsBinding.instance.platformDispatcher.views.isNotEmpty
            ? WidgetsBinding.instance.platformDispatcher.views.first
                .viewInsets.bottom
            : 0) >
        0;
    // Shown bar or hidden strip: either way something sits under the page
    // and owns the bottom safe area.
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final narrow = views.isEmpty ||
        views.first.physicalSize.width / views.first.devicePixelRatio < 600;
    GlobalBottomBarHost._occupies.value =
        m != null && m.eligible && m.items.isNotEmpty && !kb && narrow;
  }

  String get _path {
    try {
      final config = widget.router.routerDelegate.currentConfiguration;
      final last = config.last;
      final list = last is ImperativeRouteMatch ? last.matches : config;
      return list.uri.path;
    } catch (_) {
      return '/';
    }
  }

  _BarModel _compute() {
    final session = AppSession.instance;
    final shell = ShellTabBridge.instance.top;
    final eligible = session.isAuthenticated &&
        _barAllowedOn(_path) &&
        !(isOwnerOrManagerSession &&
            session.currentStaffId != null &&
            StaffPermissions.activeStaffPages == null);
    final items = eligible
        ? primaryNavItems(shell?.shellNavItems ?? _sessionNavItems())
        : const <NavItem>[];
    return _BarModel(
        eligible, items, shell?.shellCurrentPageName, shell != null);
  }

  /// Tab tap: back to the shell underneath (if a detail screen is on
  /// top), then switch tab there. Never touches the hide/show state.
  void _goTab(String name) {
    final shell = ShellTabBridge.instance.top;
    final nav = widget.navigatorKey.currentState;
    if (shell == null) {
      try {
        widget.router.goNamed(name);
      } catch (_) {}
      return;
    }
    final shellRoute = ModalRoute.of(shell.context);
    if (nav != null && shellRoute != null && !shellRoute.isCurrent) {
      nav.popUntil((r) => r == shellRoute || r.isFirst);
    }
    if (shell.mounted) shell.selectShellTab(name);
  }

  void _openMore() {
    final shell = ShellTabBridge.instance.top;
    if (shell != null && shell.mounted) {
      shell.openShellMore();
      return;
    }
    final navContext = widget.navigatorKey.currentContext;
    if (navContext != null) MoreSheet.show(navContext);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final m = _model;
    final keyboardOpen = mq.viewInsets.bottom > 0;
    if (m == null ||
        !m.eligible ||
        m.items.isEmpty ||
        mq.size.width >= 600 ||
        keyboardOpen) {
      return const SizedBox(width: double.infinity, height: 0);
    }
    final items = m.items;
    final idx = items.indexWhere((e) => e.name == m.current);
    final bar = SizeTransition(
      sizeFactor: _anim,
      axisAlignment: -1,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HideHandle(onHide: _vis.hide),
            ValueListenableBuilder<int>(
              valueListenable: ApprovalQueue.instance.pendingCount,
              builder: (context, pending, _) => MobileBottomNav(
                items: items,
                currentIndex: idx,
                onTap: (i) => _goTab(items[i].name),
                // More on every screen, not only where a shell sits
                // underneath: a module opened from More replaces the
                // shell (openModule), and the bar there used to lose More.
                actions: isOwnerOrManagerSession
                    ? [
                        (
                          icon: Icons.apps_rounded,
                          label: AppLocalizations.of(context).ngNavMore,
                          badge: pending,
                          onTap: _openMore,
                        ),
                      ]
                    : const [],
              ),
            ),
          ],
        ),
      ),
    );
    // Hidden: a thin strip of its own below the page instead of a handle
    // floating over it, so it can never cover a button the page has at
    // the bottom (Save, Log call...). The page gets everything above it.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!_vis.visible.value) _ShowStrip(onShow: _vis.show),
        bar,
      ],
    );
  }
}

/// Thin strip on top of the bar: tap (or swipe down) to hide.
class _HideHandle extends StatelessWidget {
  const _HideHandle({required this.onHide});
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return Semantics(
      button: true,
      label: 'Hide bottom bar',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onHide,
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 0) onHide();
        },
        child: Container(
          height: 18,
          width: double.infinity,
          decoration: BoxDecoration(
            color: c.nav,
            border: Border(top: BorderSide(color: c.w06)),
          ),
          alignment: Alignment.center,
          child: Icon(Icons.keyboard_arrow_down_rounded,
              size: 18, color: c.mute),
        ),
      ),
    );
  }
}

/// Thin strip under the page while the bar is hidden: tap anywhere on it
/// (or swipe up) to bring the bar back.
class _ShowStrip extends StatelessWidget {
  const _ShowStrip({required this.onShow});
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return Semantics(
      button: true,
      label: 'Show bottom bar',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onShow,
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) < 0) onShow();
        },
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: c.nav,
            border: Border(top: BorderSide(color: c.w06)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 20,
              child: Center(
                child: Icon(Icons.keyboard_arrow_up_rounded,
                    size: 20, color: c.acc),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
