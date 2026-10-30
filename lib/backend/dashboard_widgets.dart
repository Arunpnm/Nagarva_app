import 'package:flutter/foundation.dart';

import '/app_session.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';

/// Setup › Dashboard widgets (Claude Design handoff, `pf` tab `dw`): the
/// order of the dashboard's sections and which of them show.
///
/// One `app_settings` row per company (category `dashboard`, key
/// `widgets`), value `{"order": [...ids], "hidden": [...ids]}`, so every
/// phone signed into the company shows the same dashboard. Writing it is
/// owner-only in the database (the 16 Sept 2026 policy split), which is
/// the design's rule too.
///
/// Absent means the design's default: the first five shown in
/// [kDashWidgets] order, Fleet status and Staff attendance hidden. An id
/// the stored order does not mention (a widget added after the owner last
/// saved) is appended in its default position and default visibility.
///
/// This decides order and visibility only. Each section keeps its own
/// permission check on the dashboard, so turning a widget on never shows
/// money to someone who may not see it.
class DashboardWidgets extends ChangeNotifier {
  DashboardWidgets._();
  static final DashboardWidgets instance = DashboardWidgets._();

  static const _category = 'dashboard';
  static const _key = 'widgets';

  List<String> order = [...kDashWidgets];
  Set<String> hidden = {...kDashWidgetsHiddenByDefault};
  bool loaded = false;
  String? _loadedFor;

  bool isShown(String id) => !hidden.contains(id);

  /// Shown ids in display order.
  List<String> get shownInOrder => [for (final id in order) if (isShown(id)) id];

  Future<void> load({bool force = false}) async {
    final orgId = AppSession.instance.currentOrgId;
    if (orgId == null) return;
    if (!force && loaded && _loadedFor == orgId) return;
    try {
      final row = await OrgScope.read(
              SupaFlow.client.from('app_settings').select('value'))
          .eq('category', _category)
          .eq('key', _key)
          .maybeSingle();
      _apply(row?['value']);
      loaded = true;
      _loadedFor = orgId;
      notifyListeners();
    } catch (e) {
      // A failed read keeps the default dashboard rather than an empty one.
      debugPrint('DashboardWidgets.load failed: $e');
    }
  }

  void _apply(Object? v) {
    final storedOrder = <String>[];
    Set<String>? storedHidden;
    if (v is Map) {
      final o = v['order'];
      if (o is List) {
        for (final x in o) {
          final id = x.toString();
          if (kDashWidgets.contains(id) && !storedOrder.contains(id)) {
            storedOrder.add(id);
          }
        }
      }
      final h = v['hidden'];
      if (h is List) {
        storedHidden = {
          for (final x in h)
            if (kDashWidgets.contains(x.toString())) x.toString()
        };
      }
    }
    final known = storedOrder.toSet();
    order = [
      ...storedOrder,
      for (final id in kDashWidgets)
        if (!known.contains(id)) id,
    ];
    hidden = {
      ...?storedHidden,
      // A widget the stored value never mentioned takes its default.
      for (final id in kDashWidgetsHiddenByDefault)
        if (!known.contains(id)) id,
    };
  }

  Future<void> moveUp(String id) async {
    final i = order.indexOf(id);
    if (i <= 0) return;
    final next = [...order];
    next[i] = next[i - 1];
    next[i - 1] = id;
    await _save(next, hidden);
  }

  Future<void> setShown(String id, bool shown) async {
    final next = {...hidden};
    shown ? next.remove(id) : next.add(id);
    await _save(order, next);
  }

  Future<void> _save(List<String> nextOrder, Set<String> nextHidden) async {
    await SupaFlow.client.from('app_settings').upsert({
      ...OrgScope.stamp(),
      'category': _category,
      'key': _key,
      'value': {
        'order': nextOrder,
        'hidden': nextHidden.toList(),
      },
    }, onConflict: 'org_id,category,key');
    order = nextOrder;
    hidden = nextHidden;
    notifyListeners();
  }

  void clear() {
    order = [...kDashWidgets];
    hidden = {...kDashWidgetsHiddenByDefault};
    loaded = false;
    _loadedFor = null;
    notifyListeners();
  }
}

const kDashWidgetToday = 'today';
const kDashWidgetDue = 'due';
const kDashWidgetAgenda = 'agenda';
const kDashWidgetMonth = 'rev';
const kDashWidgetLeads = 'leads';
const kDashWidgetFleet = 'fleet';
const kDashWidgetAttendance = 'att';

/// The design's WID0, in its default order.
const kDashWidgets = <String>[
  kDashWidgetToday,
  kDashWidgetDue,
  kDashWidgetAgenda,
  kDashWidgetMonth,
  kDashWidgetLeads,
  kDashWidgetFleet,
  kDashWidgetAttendance,
];

const kDashWidgetsHiddenByDefault = <String>{
  kDashWidgetFleet,
  kDashWidgetAttendance,
};
