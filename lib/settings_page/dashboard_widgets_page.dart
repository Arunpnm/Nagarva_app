import 'package:flutter/material.dart';

import '/app_session.dart';
import '/backend/dashboard_widgets.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';
import '/l10n/gen/app_localizations.dart';

/// Setup › Dashboard widgets (Claude Design handoff, `pf` tab `dw`): the
/// dashboard's sections in order, an arrow to move one up and a switch to
/// hide it. Reads and writes [DashboardWidgets]; HomePage reads the same.
///
/// Owner only, because the `app_settings` write is owner-only in the
/// database; anyone else sees the list without the controls.
class DashboardWidgetsPage extends StatefulWidget {
  const DashboardWidgetsPage({super.key});

  static const routeName = 'DashboardWidgetsPage';
  static const routePath = '/dashboard-widgets';

  @override
  State<DashboardWidgetsPage> createState() => _DashboardWidgetsPageState();
}

class _DashboardWidgetsPageState extends State<DashboardWidgetsPage> {
  final _w = DashboardWidgets.instance;
  bool _busy = false;

  bool get _isOwner => AppSession.instance.currentStaffId == null;

  @override
  void initState() {
    super.initState();
    _w.addListener(_changed);
    _w.load(force: true);
  }

  @override
  void dispose() {
    _w.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<void> Function() f) async {
    final failed = AppLocalizations.of(context).dwSaveFailed;
    setState(() => _busy = true);
    try {
      await f();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(failed)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _label(AppLocalizations l, String id) => switch (id) {
        kDashWidgetToday => l.dwToday,
        kDashWidgetDue => l.ngPaymentsDue,
        kDashWidgetAgenda => l.ngTodaysPlan,
        kDashWidgetMonth => l.ngPeriodThisMonth,
        kDashWidgetLeads => l.ngHotLeads,
        kDashWidgetFleet => l.dwFleet,
        kDashWidgetAttendance => l.dwAttendance,
        _ => id,
      };

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final order = _w.order;
    var pos = 0;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: NgSimpleBar(title: l.dwTitle),
      body: SafeArea(
        top: false,
        child: !_w.loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  Text(l.dwSub,
                      style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
                  const SizedBox(height: 12),
                  NgCard(
                    padding: EdgeInsets.zero,
                    child: Column(children: [
                      for (var j = 0; j < order.length; j++)
                        Container(
                          decoration: BoxDecoration(
                            border: j == 0
                                ? null
                                : Border(top: BorderSide(color: c.w06)),
                          ),
                          child: _row(c, l, order[j], j,
                              _w.isShown(order[j]) ? ++pos : null),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  Text(l.dwNote,
                      style: NgFonts.geist(
                          fontSize: 12.5, height: 1.45, color: c.mute)),
                ],
              ),
      ),
    );
  }

  Widget _row(
      NgPalette c, AppLocalizations l, String id, int index, int? position) {
    final shown = position != null;
    final canEdit = _isOwner && !_busy;
    return NgListRow(
      leading: NgIconTile(
        icon: Icons.dashboard_customize_outlined,
        color: shown ? c.acc : c.faint,
      ),
      title: _label(l, id),
      subtitle: shown ? l.dwShown(position) : l.dwHidden,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (index > 0)
          Tooltip(
            message: l.dwUp,
            child: Material(
              color: c.s2,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: canEdit ? () => _run(() => _w.moveUp(id)) : null,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(Icons.arrow_upward_rounded,
                      size: 20, color: canEdit ? c.soft : c.faint),
                ),
              ),
            ),
          ),
        const SizedBox(width: 8),
        Switch(
          value: shown,
          onChanged:
              canEdit ? (v) => _run(() => _w.setShown(id, v)) : null,
        ),
      ]),
    );
  }
}
