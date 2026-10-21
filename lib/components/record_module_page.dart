import 'package:flutter/material.dart';

import '/backend/edge_function_errors.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/ng_tokens.dart';

/// The shared layout behind the design's list modules (Fuel & FASTag,
/// Credit notes, Cash book, Activity log …): top bar, module header with
/// an optional add button, three stat tiles, filter chips, a search box
/// and a card list. Each module supplies one or more [RmView]s — when
/// there are several, a segmented control switches between them.
///
/// Every read goes through [OrgScope.read] and every insert is stamped
/// with [OrgScope.stamp], so a module written on this cannot forget the
/// tenant filter. Add forms never pre-fill a money field ("No suggested
/// money. Ever." — CLAUDE.md).
typedef RmMap = Map<String, dynamic>;

class RmStat {
  const RmStat(this.label, this.value, {this.mono = true});
  final String label;
  final String value;
  final bool mono;
}

class RmRow {
  const RmRow({
    required this.title,
    this.subtitle,
    this.icon = Icons.description_outlined,
    this.tone = NgStatus.neutral,
    this.amount,
    this.amountColor,
    this.status,
    this.statusTone = NgStatus.neutral,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final NgStatus tone;
  final String? amount;
  final Color? amountColor;
  final String? status;
  final NgStatus statusTone;
  final VoidCallback? onTap;
}

enum RmKind { text, number, date, choice, toggle }

class RmField {
  const RmField(
    this.key,
    this.label, {
    this.kind = RmKind.text,
    this.required = false,
    this.options = const [],
    this.optionLabels,
    this.mono = false,
  });

  final String key;
  final String label;
  final RmKind kind;
  final bool required;

  /// For [RmKind.choice]: the stored values.
  final List<String> options;
  final List<String>? optionLabels;
  final bool mono;
}

class RmFilter {
  const RmFilter(this.label, this.test);
  final String label;
  final bool Function(RmMap row) test;
}

class RmView {
  const RmView({
    required this.label,
    required this.row,
    this.table,
    this.select = '*',
    this.orderBy,
    this.ascending = false,
    this.query,
    this.load,
    this.stats,
    this.filters = const [],
    this.search,
    this.emptyText = 'Nothing recorded yet.',
    this.note,
  });

  final String label;

  /// Read from this table or view, org-scoped. Ignored when [load] is set.
  final String? table;
  final String select;
  final String? orderBy;
  final bool ascending;

  /// Extra filters on top of the org scope (e.g. `is deleted_at null`).
  final dynamic Function(dynamic q)? query;

  /// For views that merge several sources (Cash book, Daily summary).
  final Future<List<RmMap>> Function()? load;

  final List<RmStat> Function(List<RmMap> rows)? stats;
  final List<RmFilter> filters;

  /// Text the search box matches against; no search box when null.
  final String Function(RmMap row)? search;

  final RmRow Function(BuildContext context, RmMap row) row;
  final String emptyText;

  /// A muted line under the stats — used to say plainly what a screen
  /// does NOT do yet (e.g. bank-statement import).
  final String? note;
}

class RmAdd {
  const RmAdd({
    required this.title,
    required this.fields,
    required this.table,
    this.prepare,
    this.saveLabel = 'Save',
  });

  final String title;
  final List<RmField> fields;
  final String table;

  /// Turns the typed values into the insert payload (allocate a number,
  /// rename keys, derive a column). Throw a [String] to refuse with that
  /// message.
  final Future<RmMap> Function(RmMap values)? prepare;
  final String saveLabel;
}

class RecordModulePage extends StatefulWidget {
  const RecordModulePage({
    super.key,
    required this.title,
    this.subtitle,
    required this.views,
    this.add,
  });

  final String title;
  final String? subtitle;
  final List<RmView> views;

  /// Null hides the + button (read-only modules).
  final RmAdd? add;

  @override
  State<RecordModulePage> createState() => _RecordModulePageState();
}

class _RecordModulePageState extends State<RecordModulePage> {
  int _view = 0;
  int _filter = 0;
  String _q = '';
  final _search = TextEditingController();
  final Map<int, List<RmMap>> _rows = {};
  final Map<int, String> _errors = {};
  bool _loading = true;

  RmView get _v => widget.views[_view];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final i = _view;
    final v = widget.views[i];
    try {
      List<RmMap> rows;
      if (v.load != null) {
        rows = await v.load!();
      } else {
        dynamic q = OrgScope.read(SupaFlow.client.from(v.table!).select(v.select));
        if (v.query != null) q = v.query!(q);
        if (v.orderBy != null) q = q.order(v.orderBy!, ascending: v.ascending);
        final res = await (q.limit(500) as Future<dynamic>);
        rows = [for (final r in res as List) Map<String, dynamic>.from(r as Map)];
      }
      _rows[i] = rows;
      _errors.remove(i);
    } catch (e) {
      _errors[i] = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openAdd() async {
    final add = widget.add!;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: NgPalette.of(context).sheet,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(NgRadius.sheet))),
      builder: (_) => _AddSheet(add: add),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final v = _v;
    final all = _rows[_view] ?? const <RmMap>[];
    var rows = all;
    if (v.filters.isNotEmpty) {
      rows = rows.where(v.filters[_filter.clamp(0, v.filters.length - 1)].test).toList();
    }
    if (v.search != null && _q.trim().isNotEmpty) {
      final t = _q.trim().toLowerCase();
      rows = rows.where((r) => v.search!(r).toLowerCase().contains(t)).toList();
    }
    final stats = v.stats?.call(all) ?? const <RmStat>[];
    return Scaffold(
      backgroundColor: c.bg,
      appBar: NgTopBar(onRefresh: _load),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            NgModuleHeader(
              widget.title,
              subtitle: widget.subtitle,
              actions: [
                if (widget.add != null)
                  _AddButton(onTap: _openAdd),
              ],
            ),
            const SizedBox(height: 14),
            if (widget.views.length > 1) ...[
              NgSegmented(
                labels: [for (final x in widget.views) x.label],
                selected: _view,
                onSelect: (i) {
                  setState(() {
                    _view = i;
                    _filter = 0;
                  });
                  if (!_rows.containsKey(i)) _load();
                },
              ),
              const SizedBox(height: 14),
            ],
            if (stats.isNotEmpty) ...[
              Row(children: [
                for (var i = 0; i < stats.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: _StatTile(stats[i])),
                ],
              ]),
              const SizedBox(height: 14),
            ],
            if (v.note != null) ...[
              NgCard(
                child: Row(children: [
                  Icon(Icons.info_outline_rounded, size: 19, color: c.mute),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(v.note!,
                        style: NgFonts.geist(
                            fontSize: 13, height: 1.4, color: c.soft)),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
            ],
            if (v.search != null) ...[
              NgSearchField(
                controller: _search,
                hint: 'Search',
                onChanged: (s) => setState(() => _q = s),
              ),
              const SizedBox(height: 12),
            ],
            if (v.filters.isNotEmpty) ...[
              NgChipRow(edge: 0, chips: [
                for (var i = 0; i < v.filters.length; i++)
                  NgChip(
                    label: v.filters[i].label,
                    selected: i == _filter,
                    count: all.where(v.filters[i].test).length,
                    onTap: () => setState(() => _filter = i),
                  ),
              ]),
              const SizedBox(height: 12),
            ],
            if (_loading && !_rows.containsKey(_view))
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_errors[_view] != null)
              NgCard(
                child: Text('Could not load: ${_errors[_view]}',
                    style: NgFonts.geist(fontSize: 13, color: c.red)),
              )
            else if (rows.isEmpty)
              NgCard(
                padding: const EdgeInsets.all(22),
                child: Text(v.emptyText,
                    textAlign: TextAlign.center,
                    style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
              )
            else
              NgCardList(children: [
                for (final r in rows) _RowTile(v.row(context, r)),
              ]),
          ],
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return Material(
      color: c.accBtn,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.add_rounded, color: NgPalette.onAcc, size: 24),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(this.s);
  final RmStat s;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return NgCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NgFonts.geist(fontSize: 12, color: c.mute)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(s.value,
                style: s.mono
                    ? NgFonts.mono(
                        fontSize: 17, fontWeight: FontWeight.w600, color: c.text)
                    : NgFonts.geist(
                        fontSize: 17, fontWeight: FontWeight.w600, color: c.text)),
          ),
        ],
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile(this.r);
  final RmRow r;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return InkWell(
      onTap: r.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            NgIconTile(icon: r.icon, status: r.tone),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: NgFonts.geist(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: c.text)),
                  if ((r.subtitle ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(r.subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: NgFonts.geist(
                            fontSize: 12.5, height: 1.35, color: c.mute)),
                  ],
                ],
              ),
            ),
            if (r.amount != null || r.status != null) ...[
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (r.amount != null)
                    Text(r.amount!,
                        style: NgFonts.mono(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: r.amountColor ?? c.text)),
                  if (r.status != null) ...[
                    if (r.amount != null) const SizedBox(height: 4),
                    NgPill(r.status!, status: r.statusTone),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AddSheet extends StatefulWidget {
  const _AddSheet({required this.add});
  final RmAdd add;

  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  final Map<String, TextEditingController> _ctrl = {};
  final RmMap _values = {};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final f in widget.add.fields) {
      if (f.kind == RmKind.text || f.kind == RmKind.number) {
        _ctrl[f.key] = TextEditingController();
      }
      if (f.kind == RmKind.toggle) _values[f.key] = false;
      if (f.kind == RmKind.date) {
        final n = DateTime.now();
        _values[f.key] = DateTime(n.year, n.month, n.day);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final out = <String, dynamic>{};
    for (final f in widget.add.fields) {
      dynamic v;
      switch (f.kind) {
        case RmKind.text:
          final t = _ctrl[f.key]!.text.trim();
          v = t.isEmpty ? null : t;
        case RmKind.number:
          final t = _ctrl[f.key]!.text.trim();
          if (t.isNotEmpty) {
            v = num.tryParse(t);
            if (v == null) {
              setState(() => _error = '${f.label}: enter a number.');
              return;
            }
          }
        case RmKind.date:
          final d = _values[f.key] as DateTime?;
          v = d == null ? null : DateFormat('yyyy-MM-dd').format(d);
        case RmKind.choice:
        case RmKind.toggle:
          v = _values[f.key];
      }
      if (f.required && v == null) {
        setState(() => _error = '${f.label} is required.');
        return;
      }
      if (v != null) out[f.key] = v;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final payload =
          widget.add.prepare == null ? out : await widget.add.prepare!(out);
      await SupaFlow.client
          .from(widget.add.table)
          .insert({...OrgScope.stamp(), ...payload});
      if (mounted) Navigator.of(context).pop(true);
    } on String catch (msg) {
      setState(() {
        _saving = false;
        _error = msg;
      });
    } catch (e) {
      setState(() {
        _saving = false;
        _error = extractDbErrorMessage(e, fallback: 'Could not save: $e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 18, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.add.title,
                style: NgFonts.geist(
                    fontSize: 20, fontWeight: FontWeight.w600, color: c.text)),
            const SizedBox(height: 16),
            for (final f in widget.add.fields) ...[
              _field(context, f),
              const SizedBox(height: 12),
            ],
            if (_error != null) ...[
              Text(_error!, style: NgFonts.geist(fontSize: 13, color: c.red)),
              const SizedBox(height: 10),
            ],
            NgPrimaryButton(
              label: widget.add.saveLabel,
              icon: Icons.check_rounded,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(BuildContext context, RmField f) {
    final c = NgPalette.of(context);
    final label = f.required ? '${f.label} *' : f.label;
    switch (f.kind) {
      case RmKind.text:
      case RmKind.number:
        return NgInput(
          controller: _ctrl[f.key]!,
          hint: label,
          mono: f.mono || f.kind == RmKind.number,
          keyboardType: f.kind == RmKind.number
              ? const TextInputType.numberWithOptions(decimal: true)
              : null,
        );
      case RmKind.date:
        final d = _values[f.key] as DateTime?;
        return NgCard(
          onTap: () async {
            final p = await showDatePicker(
              context: context,
              initialDate: d ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2035),
            );
            if (p != null) setState(() => _values[f.key] = p);
          },
          child: Row(children: [
            Icon(Icons.calendar_month_outlined, size: 20, color: c.acc),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: NgFonts.geist(fontSize: 14, color: c.mute)),
            ),
            Text(d == null ? '—' : DateFormat('d MMM yyyy').format(d),
                style: NgFonts.geist(
                    fontSize: 14.5, fontWeight: FontWeight.w600, color: c.text)),
          ]),
        );
      case RmKind.choice:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NgFieldLabel(label),
            if (f.options.isEmpty)
              Text('Nothing to choose from yet.',
                  style: NgFonts.geist(fontSize: 13, color: c.amber))
            else
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (var i = 0; i < f.options.length; i++)
                  NgChip(
                    label: f.optionLabels?[i] ?? f.options[i],
                    selected: _values[f.key] == f.options[i],
                    onTap: () =>
                        setState(() => _values[f.key] = f.options[i]),
                  ),
              ]),
          ],
        );
      case RmKind.toggle:
        return Row(children: [
          Expanded(
            child: Text(f.label,
                style: NgFonts.geist(fontSize: 14.5, color: c.text)),
          ),
          Switch(
            value: _values[f.key] == true,
            onChanged: (v) => setState(() => _values[f.key] = v),
          ),
        ]);
    }
  }
}

/// Small formatting helpers the module definitions share.
String rmMoney(dynamic v) {
  final n = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
  if (n == null) return '—';
  return NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
      .format(n);
}

double rmNum(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

String rmDate(dynamic v, [String pattern = 'd MMM']) {
  final d = v is DateTime ? v : DateTime.tryParse('${v ?? ''}');
  return d == null ? '' : DateFormat(pattern).format(d.toLocal());
}

DateTime? rmParseDate(dynamic v) =>
    v is DateTime ? v : DateTime.tryParse('${v ?? ''}');

bool rmThisMonth(dynamic v) {
  final d = rmParseDate(v);
  final n = DateTime.now();
  return d != null && d.year == n.year && d.month == n.month;
}

/// Indian financial year as number_series stores it, e.g. `2026-27`.
String rmCurrentFy() {
  final now = DateTime.now();
  final y = now.month >= 4 ? now.year : now.year - 1;
  return '$y-${((y + 1) % 100).toString().padLeft(2, '0')}';
}
