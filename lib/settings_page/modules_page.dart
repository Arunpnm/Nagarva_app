import 'package:flutter/material.dart';

import '/app_session.dart';
import '/backend/business_modules.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';
import '/l10n/gen/app_localizations.dart';
import '/nav_items.dart';

/// Settings › Modules (Claude Design handoff): the business type, and an
/// on/off switch per module grouped Packers & Movers / Transport /
/// Advanced. Off only hides a module from the menu — its data stays.
///
/// Owner only, because both stores are owner-only in the database; a
/// manager sees the screen read-only rather than switches that fail.
class ModulesPage extends StatefulWidget {
  const ModulesPage({super.key});

  static const routeName = 'ModulesPage';
  static const routePath = '/modules';

  @override
  State<ModulesPage> createState() => _ModulesPageState();
}

class _ModulesPageState extends State<ModulesPage> {
  final _m = BusinessModules.instance;
  bool _busy = false;

  bool get _isOwner => AppSession.instance.currentStaffId == null;

  @override
  void initState() {
    super.initState();
    _m.addListener(_changed);
    _m.load(force: true);
  }

  @override
  void dispose() {
    _m.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<void> Function() f, String done) async {
    if (!_isOwner) {
      _toast(AppLocalizations.of(context).mdOwnerOnly);
      return;
    }
    final failed = AppLocalizations.of(context).mdSaveFailed;
    setState(() => _busy = true);
    try {
      await f();
      _toast(done);
    } catch (e) {
      _toast(failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final all = [...kPackersModules, ...kTransportModules, ...kAdvancedModules];
    final onCount = all.where(_m.isOn).length;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: NgSimpleBar(title: l.mdTitle),
      body: SafeArea(
        top: false,
        child: !_m.loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  NgSectionHeader(l.mdType),
                  const SizedBox(height: 8),
                  BusinessTypeChoices(
                    selected: _m.effectiveType,
                    enabled: !_busy,
                    onPick: (t) {
                      if (t == _m.businessType) return;
                      _run(() => _m.setType(t),
                          l.mdTypeSet(bizTypeLabel(context, t)));
                    },
                  ),
                  const SizedBox(height: 18),
                  Text(l.mdCount(onCount, all.length),
                      style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
                  const SizedBox(height: 10),
                  _group(c, l.btPm, kPackersModules),
                  _group(c, l.btTr, kTransportModules),
                  _group(c, l.mdAdv, kAdvancedModules),
                  const SizedBox(height: 4),
                  Text(l.mdNote,
                      style: NgFonts.geist(
                          fontSize: 12.5, height: 1.45, color: c.mute)),
                  const SizedBox(height: 14),
                  NgSecondaryButton(
                    label: l.mdReset,
                    onPressed: _busy
                        ? null
                        : () => _run(
                            _m.resetModules,
                            l.mdResetDone(
                                bizTypeLabel(context, _m.effectiveType))),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _group(NgPalette c, String title, List<String> pages) {
    final l = AppLocalizations.of(context);
    final items = {for (final i in kOwnerManagerNavItems) i.name: i};
    final rows = [
      for (final p in pages)
        if (items[p] != null) items[p]!,
    ];
    final on = rows.where((i) => _m.isOn(i.name)).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: NgSectionHeader(title)),
            Text(l.mdGroupOn(on, rows.length),
                style: NgFonts.geist(fontSize: 12, color: c.mute)),
          ]),
          const SizedBox(height: 8),
          NgCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (var j = 0; j < rows.length; j++)
                Container(
                  decoration: BoxDecoration(
                    border:
                        j == 0 ? null : Border(top: BorderSide(color: c.w06)),
                  ),
                  child: SwitchListTile(
                    value: _m.isOn(rows[j].name),
                    onChanged: _busy
                        ? null
                        : (v) => _run(() => _m.setModule(rows[j].name, v),
                            localizedNavLabel(context, rows[j])),
                    secondary: Icon(rows[j].icon,
                        color: _m.isOn(rows[j].name) ? c.acc : c.faint),
                    title: Text(localizedNavLabel(context, rows[j]),
                        style: NgFonts.geist(fontSize: 14.5, color: c.text)),
                  ),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}

String bizTypeLabel(BuildContext context, String t) {
  final l = AppLocalizations.of(context);
  return switch (t) {
    kBizPackers => l.btPm,
    kBizTransport => l.btTr,
    _ => l.btBoth,
  };
}

/// The three cards: Packers & Movers / Transport / Both. Shared by
/// [ModulesPage] and [BusinessTypeSheet].
class BusinessTypeChoices extends StatelessWidget {
  const BusinessTypeChoices({
    super.key,
    required this.selected,
    required this.onPick,
    this.enabled = true,
  });

  final String? selected;
  final ValueChanged<String> onPick;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final opts = [
      (kBizPackers, Icons.local_shipping_rounded, l.btPm, l.btPmS),
      (kBizTransport, Icons.fire_truck_rounded, l.btTr, l.btTrS),
      (kBizBoth, Icons.hub_rounded, l.btBoth, l.btBothS),
    ];
    return Column(children: [
      for (final (k, icon, title, sub) in opts)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: c.s1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(NgRadius.card),
              side: BorderSide(
                  color: selected == k ? c.acc : c.w06,
                  width: selected == k ? 1.5 : 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? () => onPick(k) : null,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color:
                          selected == k ? c.acc.withValues(alpha: 0.16) : c.s3,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon,
                        color: selected == k ? c.acc : c.faint, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: NgFonts.geist(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: c.text)),
                        const SizedBox(height: 2),
                        Text(sub,
                            style:
                                NgFonts.geist(fontSize: 12.5, color: c.mute)),
                      ],
                    ),
                  ),
                  Icon(
                    selected == k
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selected == k ? c.acc : c.faint,
                    size: 22,
                  ),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// The one-time "What does your business do?" sheet the design shows an
/// owner after their first login, until they answer.
class BusinessTypeSheet extends StatefulWidget {
  const BusinessTypeSheet({super.key});

  static bool _shownThisRun = false;

  /// Shows the sheet once per app run, only for an owner whose company
  /// has not chosen. Dismissing it is allowed; it asks again next launch.
  static Future<void> maybeShow(BuildContext context) async {
    final m = BusinessModules.instance;
    if (_shownThisRun) return;
    if (AppSession.instance.currentStaffId != null) return;
    await m.load();
    if (!m.needsChoice || !context.mounted) return;
    _shownThisRun = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const BusinessTypeSheet(),
    );
  }

  @override
  State<BusinessTypeSheet> createState() => _BusinessTypeSheetState();
}

class _BusinessTypeSheetState extends State<BusinessTypeSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _pick(String t) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await BusinessModules.instance.setType(t);
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      final msg = l.mdTypeSet(bizTypeLabel(context, t));
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = AppLocalizations.of(context).mdSaveFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.sheet,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(NgRadius.sheet)),
        border: Border(top: BorderSide(color: c.w08)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: c.w15, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(l.btTitle,
                style: NgFonts.geist(
                    fontSize: 20, fontWeight: FontWeight.w600, color: c.text)),
            const SizedBox(height: 6),
            Text(l.btSub,
                style:
                    NgFonts.geist(fontSize: 13, height: 1.45, color: c.mute)),
            const SizedBox(height: 16),
            BusinessTypeChoices(selected: null, onPick: _pick, enabled: !_busy),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: NgFonts.geist(fontSize: 13, color: c.red)),
            ],
            const SizedBox(height: 6),
            Text(l.btLater,
                textAlign: TextAlign.center,
                style: NgFonts.geist(fontSize: 12, color: c.faint)),
          ],
        ),
      ),
    );
  }
}
