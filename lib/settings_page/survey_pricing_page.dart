import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/pricing_defaults.dart';
import '/backend/storage_billing.dart';
import '/flutter_flow/flutter_flow_theme.dart';

/// Settings → Survey & Pricing (Item 12, 17 Aug 2026).
///
/// Two tabs:
///  - **Vehicle & Crew Slabs** (12B — the new work): the vendor's "CFT
///    in, package/vehicle/crew out" table, edited as ONE table even
///    though it's stored as two joined lists (`config.cft_ranges` +
///    `config.packages` — see [CftSlab]'s doc comment). From CFT is
///    derived (first row 0, then previous ceiling + 1), so overlaps and
///    gaps can't be created through this UI at all; [validateSlabs]
///    still runs at save as defense against a hand-edited config.
///  - **Item Catalogue** (12A): moved here from the Survey & Quote hub
///    (Arun, 17 Aug 2026: "a vendor setting up their fleet shouldn't
///    have to know these live in different menus"). Same jsonb shape
///    (`config.survey_cats`), same read-merge-write save.
///
/// Both tabs write through [PricingConfig.saveConfigKeys], which merges
/// into the org's existing config so neither tab's save can clobber the
/// other's keys.
class SurveyPricingPage extends StatefulWidget {
  const SurveyPricingPage({super.key});

  static String routeName = 'SurveyPricingPage';
  static String routePath = '/survey-pricing';

  @override
  State<SurveyPricingPage> createState() => _SurveyPricingPageState();
}

class _SurveyPricingPageState extends State<SurveyPricingPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  bool _loading = true;
  String? _loadError;

  // ---- Slabs tab state. One entry per row; controllers owned here so a
  // rebuild doesn't lose in-progress typing.
  final List<_SlabRowCtrl> _rows = [];
  bool _savingSlabs = false;
  List<SlabValidationError> _slabErrors = [];

  // ---- Catalogue tab state (moved from survey_quote_hub_page).
  Map<String, List<SurveyItem>> _catalogue = {};
  bool _savingCatalogue = false;

  // ---- Storage rates tab. Added 3 Sept 2026: before this, storage
  // rates were settable ONLY by SQL, so a vendor could not use the
  // warehouse module at all — the size picker came up empty and stayed
  // empty. PricingConfig.storageRates deliberately has no default (one
  // vendor's prices must never be another's), which makes an editor the
  // only way to fill it.
  final List<_RateRowCtrl> _rateRows = [];
  bool _savingRates = false;
  String? _rateError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    for (final r in _rateRows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final config = await PricingConfig.loadForCurrentOrg();
      for (final r in _rows) {
        r.dispose();
      }
      _rows
        ..clear()
        ..addAll(config.slabs.map(_SlabRowCtrl.from));
      _catalogue = {
        for (final e in config.surveyCats.entries) e.key: List.of(e.value),
      };
      for (final r in _rateRows) {
        r.dispose();
      }
      _rateRows
        ..clear()
        ..addAll(config.storageRates.map(_RateRowCtrl.from));
    } catch (e) {
      _loadError = 'Could not load pricing settings: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ------------------------------------------------------------------
  // Slabs
  // ------------------------------------------------------------------

  /// Rebuild the derived From CFT chain: row 0 starts at 0, each
  /// subsequent row at the previous ceiling + 1. Called after any To CFT
  /// edit, add, or remove.
  List<CftSlab> _currentSlabs() {
    num from = 0;
    final out = <CftSlab>[];
    for (var i = 0; i < _rows.length; i++) {
      final r = _rows[i];
      final isLast = i == _rows.length - 1;
      final to = isLast ? null : num.tryParse(r.toCtrl.text.trim());
      final slab = CftSlab(
        cftFrom: from,
        cftTo: to,
        packageName: r.nameCtrl.text.trim(),
        vehicle: r.vehicleCtrl.text.trim(),
        crew: int.tryParse(r.crewCtrl.text.trim()) ?? 0,
        vehicleCft: r.vehicleCft ?? to ?? from,
      );
      out.add(slab);
      if (to != null) from = to + 1;
    }
    return out;
  }

  Future<void> _saveSlabs() async {
    // A non-last row with an unparseable ceiling breaks the From chain —
    // catch it before validateSlabs (which would see a misleading shape).
    for (var i = 0; i < _rows.length - 1; i++) {
      if (num.tryParse(_rows[i].toCtrl.text.trim()) == null) {
        setState(() => _slabErrors = [
              SlabValidationError(
                  'Row ${i + 1} needs a numeric "up to" CFT value.'),
            ]);
        return;
      }
    }
    final slabs = _currentSlabs();
    final errors = validateSlabs(slabs);
    if (errors.isNotEmpty) {
      setState(() => _slabErrors = errors);
      return;
    }
    setState(() {
      _slabErrors = [];
      _savingSlabs = true;
    });
    try {
      await PricingConfig.saveConfigKeys(PricingConfig.slabsToConfig(slabs));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Slabs saved. New quotes will use them.')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save slabs: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingSlabs = false);
    }
  }

  void _addSlab() {
    setState(() {
      // Insert above the open-ended last row, seeded with a ceiling one
      // step past the current second-to-last so the chain stays valid.
      final insertAt = _rows.isEmpty ? 0 : _rows.length - 1;
      num seedTo = 100;
      if (insertAt > 0) {
        final prevTo =
            num.tryParse(_rows[insertAt - 1].toCtrl.text.trim()) ?? 0;
        seedTo = prevTo + 100;
      }
      _rows.insert(
        insertAt,
        _SlabRowCtrl.from(CftSlab(
          cftFrom: 0, // derived at save/preview, not stored on the row
          cftTo: seedTo,
          packageName: '',
          vehicle: '',
          crew: 0,
          vehicleCft: seedTo,
        )),
      );
    });
  }

  void _removeSlab(int i) {
    if (_rows.length <= 1) return;
    setState(() {
      _rows.removeAt(i).dispose();
      // If the open-ended last row was removed, the new last row becomes
      // open-ended by construction (last row's ceiling is ignored).
    });
  }

  // ------------------------------------------------------------------
  // Catalogue (moved from survey_quote_hub_page_widget.dart)
  // ------------------------------------------------------------------

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Rename preserves position — rebuilding the map in order rather than
  /// remove-then-add, which would drop the category to the bottom.
  Future<void> _renameCategory(String cat) async {
    final name = await _promptText(context, 'Rename category', initial: cat);
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == cat) return;
    if (_catalogue.containsKey(trimmed)) {
      _toast('A category called "$trimmed" already exists.');
      return;
    }
    setState(() {
      _catalogue = {
        for (final e in _catalogue.entries)
          if (e.key == cat) trimmed: e.value else e.key: e.value,
      };
    });
  }

  Future<void> _deleteCategory(String cat, int itemCount) async {
    if (itemCount > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Delete "$cat"?'),
          content: Text(
            'This removes $itemCount item(s) from the catalogue for future '
            'surveys. Quotes already saved keep their items and CFT — they '
            'never look the catalogue up again.',
            style: GoogleFonts.inter(fontSize: 13, height: 1.35),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _catalogue.remove(cat));
  }

  Future<void> _saveCatalogue() async {
    setState(() => _savingCatalogue = true);
    try {
      final payload = {
        for (final e in _catalogue.entries)
          e.key: [
            for (final item in e.value)
              {
                'name': item.name,
                'subs': [
                  for (final s in item.subs) {'label': s.label, 'cft': s.cft},
                ],
                // Only written when false — an absent key reads as active
                // (see _parseSurveyCats), so this keeps the stored config
                // small and unchanged for the common case.
                if (!item.active) 'active': false,
              },
          ],
      };
      await PricingConfig.saveConfigKeys({'survey_cats': payload});
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Catalogue saved.')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save catalogue: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingCatalogue = false);
    }
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        title: Text('Survey & Pricing',
            style: theme.titleLarge.override(
                font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                fontSize: 22)),
        centerTitle: true,
        elevation: 0,
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Vehicle & Crew Slabs'),
            Tab(text: 'Item Catalogue'),
            Tab(text: 'Storage Rates'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _errorState(theme)
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _slabsTab(theme),
                    _catalogueTab(theme),
                    _storageTab(theme),
                  ],
                ),
    );
  }

  Widget _errorState(FlutterFlowTheme theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: theme.error),
              const SizedBox(height: 12),
              Text(_loadError!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 13)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );

  Widget _slabsTab(FlutterFlowTheme theme) {
    // Derived From values for display.
    final froms = <num>[];
    num from = 0;
    for (var i = 0; i < _rows.length; i++) {
      froms.add(from);
      final to = num.tryParse(_rows[i].toCtrl.text.trim());
      if (to != null) from = to + 1;
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            children: [
              Text(
                'When a survey\'s total CFT lands in a range, the quote '
                'suggests that package, vehicle and crew. The surveyor can '
                'always override on the quote itself. Each range starts '
                'where the previous one ends, so there are no gaps.',
                style: GoogleFonts.inter(
                    fontSize: 12.5, height: 1.4, color: theme.secondaryText),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < _rows.length; i++)
                _slabCard(theme, i, froms[i]),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _addSlab,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Slab'),
              ),
              if (_slabErrors.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: theme.error.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in _slabErrors)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('• ${e.message}',
                              style: GoogleFonts.inter(
                                  fontSize: 12.5, color: theme.error)),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton.icon(
              onPressed: _savingSlabs ? null : _saveSlabs,
              icon: _savingSlabs
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save, size: 18),
              label: const Text('Save Slabs'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _slabCard(FlutterFlowTheme theme, int i, num fromCft) {
    final r = _rows[i];
    final isLast = i == _rows.length - 1;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isLast ? 'From $fromCft CFT and up' : 'From $fromCft CFT',
                    style: GoogleFonts.interTight(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: theme.primary),
                  ),
                ),
                if (_rows.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    tooltip: 'Remove slab',
                    onPressed: () => _removeSlab(i),
                  ),
              ],
            ),
            Row(
              children: [
                if (!isLast) ...[
                  Expanded(
                    child: TextField(
                      controller: r.toCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Up to CFT', isDense: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: r.nameCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Package name', isDense: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: r.vehicleCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Vehicle (free text)', isDense: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: r.crewCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Crew', isDense: true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }


  // ------------------------------------------------------------------
  // Storage rates
  // ------------------------------------------------------------------

  /// Saves the storage rate card.
  ///
  /// Every figure here is THE VENDOR'S price. Nothing is pre-filled and
  /// there is no template — a shipped rate table is one vendor's prices
  /// wearing another vendor's authority ("No suggested money. Ever.").
  /// A new row opens empty except `Minimum days`, which carries the
  /// documented default because 0 there would silently switch the
  /// minimum-stay floor off rather than mean anything.
  Future<void> _saveRates() async {
    final seen = <String>{};
    for (final r in _rateRows) {
      final size = r.sizeCtrl.text.trim();
      if (size.isEmpty) {
        setState(() => _rateError = 'Every row needs a size name.');
        return;
      }
      if (!seen.add(size.toLowerCase())) {
        setState(() => _rateError = 'Duplicate size: "$size".');
        return;
      }
      if (r.perDay <= 0 && r.perMonth <= 0) {
        setState(() => _rateError =
            '"$size" has no price. Set a daily rate, a monthly rate, or both.');
        return;
      }
    }
    setState(() {
      _savingRates = true;
      _rateError = null;
    });
    try {
      await PricingConfig.saveConfigKeys({
        'storage_rates':
            storageRatesToConfig(_rateRows.map((r) => r.toRate()).toList()),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Storage rates saved.')));
      }
    } catch (e) {
      if (mounted) setState(() => _rateError = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _savingRates = false);
    }
  }

  Widget _storageTab(FlutterFlowTheme theme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text('Your storage prices',
            style: GoogleFonts.interTight(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: theme.primaryText)),
        const SizedBox(height: 4),
        Text(
          'Sizes and prices are yours to set - nothing is filled in for '
          'you. A stay bills on whichever plan was agreed at booking, and '
          'the rate is copied onto that record, so changing a price here '
          'never re-bills goods already in store.',
          style: GoogleFonts.inter(fontSize: 12, color: theme.secondaryText),
        ),
        const SizedBox(height: 14),
        if (_rateRows.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.secondaryBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'No storage prices set yet. Until you add a size, the picker '
              'on a booking stays empty and the rate has to be typed by '
              'hand every time.',
              style:
                  GoogleFonts.inter(fontSize: 13, color: theme.secondaryText),
            ),
          ),
        for (var i = 0; i < _rateRows.length; i++) _rateCard(theme, i),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => setState(() => _rateRows.add(_RateRowCtrl.empty())),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add size'),
        ),
        if (_rateError != null) ...[
          const SizedBox(height: 12),
          Text(_rateError!,
              style: GoogleFonts.inter(fontSize: 12, color: theme.error)),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _savingRates ? null : _saveRates,
          child: Text(_savingRates ? 'Saving...' : 'Save storage rates'),
        ),
      ],
    );
  }

  Widget _rateCard(FlutterFlowTheme theme, int i) {
    final r = _rateRows[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: r.sizeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Size',
                    hintText: 'e.g. Tata Ace, 10x10 room, 1 pallet',
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove size',
                icon: Icon(Icons.delete_outline, color: theme.error, size: 20),
                onPressed: () =>
                    setState(() => _rateRows.removeAt(i).dispose()),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _rateField(r.perDayCtrl, 'Per day')),
            const SizedBox(width: 10),
            Expanded(child: _rateField(r.perMonthCtrl, 'Per month')),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _rateField(r.minDaysCtrl, 'Min days')),
            const SizedBox(width: 10),
            Expanded(child: _rateField(r.handlingInCtrl, 'Handling in')),
            const SizedBox(width: 10),
            Expanded(child: _rateField(r.handlingOutCtrl, 'Handling out')),
          ]),
          const SizedBox(height: 6),
          Text(
            'Daily and monthly are independent prices. The app never '
            'compares them or picks the cheaper - whichever plan was '
            'agreed at booking is what bills.',
            style: GoogleFonts.inter(fontSize: 11, color: theme.secondaryText),
          ),
        ],
      ),
    );
  }

  Widget _rateField(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, isDense: true),
      );

  Widget _catalogueTab(FlutterFlowTheme theme) {
    final cats = _catalogue.keys.toList();
    return Column(
      children: [
        Expanded(
          child: ReorderableListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            // Item 12A: order IS sort_order. In the relational schema the
            // master brief sketched, a `sort_order int` column would be
            // needed because rows have no inherent order; in the jsonb
            // shape this is actually stored as, the array's own order is
            // the sort order — so dragging a row IS the edit, and there's
            // no second field that can drift out of sync with it. Same
            // reasoning as the jsonb-over-tables decision (CLAUDE.md).
            onReorder: (oldIndex, newIndex) => setState(() {
              if (newIndex > oldIndex) newIndex -= 1;
              final reordered = List.of(cats);
              final moved = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, moved);
              _catalogue = {
                for (final c in reordered) c: _catalogue[c]!,
              };
            }),
            footer: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: () async {
                  final name = await _promptText(context, 'New category name');
                  final trimmed = name?.trim() ?? '';
                  if (trimmed.isEmpty) return;
                  if (_catalogue.containsKey(trimmed)) {
                    _toast('A category called "$trimmed" already exists.');
                    return;
                  }
                  setState(() => _catalogue[trimmed] = []);
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Category'),
              ),
            ),
            children: [
              for (final cat in cats)
                _categoryTile(theme, cat, key: ValueKey('cat:$cat')),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton.icon(
              onPressed: _savingCatalogue ? null : _saveCatalogue,
              icon: _savingCatalogue
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save, size: 18),
              label: const Text('Save Catalogue'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _categoryTile(FlutterFlowTheme theme, String cat, {required Key key}) {
    final items = _catalogue[cat] ?? [];
    final hidden = items.where((i) => !i.active).length;
    return Card(
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(cat, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        subtitle: Text(hidden == 0
            ? '${items.length} item(s)'
            : '${items.length} item(s) · $hidden hidden'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.drive_file_rename_outline, size: 19),
              tooltip: 'Rename category',
              onPressed: () => _renameCategory(cat),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: 'Delete category',
              onPressed: () => _deleteCategory(cat, items.length),
            ),
          ],
        ),
        children: [
          for (var i = 0; i < items.length; i++)
            _itemTile(theme, cat, i, items[i]),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final name = await _promptText(context, 'New item name');
                  if (name == null || name.trim().isEmpty) return;
                  setState(() => _catalogue[cat] = [
                        ...items,
                        SurveyItem(name.trim(), const []),
                      ]);
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Item'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemTile(
      FlutterFlowTheme theme, String cat, int itemIndex, SurveyItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(item.name,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: item.active ? null : theme.secondaryText,
                      decoration:
                          item.active ? null : TextDecoration.lineThrough,
                    )),
              ),
              // Item 12A: hiding beats deleting for anything already used
              // on a quote. Old quotes are unaffected either way (they
              // store CFT on the line), but a hidden item can be brought
              // back without re-typing its variants.
              IconButton(
                icon: Icon(
                    item.active
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 17),
                tooltip: item.active ? 'Hide from new surveys' : 'Show again',
                onPressed: () => setState(() {
                  final list = List.of(_catalogue[cat]!);
                  list[itemIndex] = item.copyWith(active: !item.active);
                  _catalogue[cat] = list;
                }),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                tooltip: 'Delete item',
                onPressed: () => setState(() {
                  final list = List.of(_catalogue[cat]!)..removeAt(itemIndex);
                  _catalogue[cat] = list;
                }),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (var s = 0; s < item.subs.length; s++)
                InputChip(
                  label: Text('${item.subs[s].label}: ${item.subs[s].cft} cft'),
                  onDeleted: () => setState(() {
                    final subs = List.of(item.subs)..removeAt(s);
                    final list = List.of(_catalogue[cat]!);
                    list[itemIndex] = SurveyItem(item.name, subs);
                    _catalogue[cat] = list;
                  }),
                  onPressed: () async {
                    final result = await _promptSub(context,
                        initialLabel: item.subs[s].label,
                        initialCft: item.subs[s].cft);
                    if (result == null) return;
                    setState(() {
                      final subs = List.of(item.subs);
                      subs[s] = SurveySubItem(result.$1, result.$2);
                      final list = List.of(_catalogue[cat]!);
                      list[itemIndex] = SurveyItem(item.name, subs);
                      _catalogue[cat] = list;
                    });
                  },
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 14),
                label: const Text('Add'),
                onPressed: () async {
                  final result = await _promptSub(context);
                  if (result == null) return;
                  setState(() {
                    final subs = [
                      ...item.subs,
                      SurveySubItem(result.$1, result.$2)
                    ];
                    final list = List.of(_catalogue[cat]!);
                    list[itemIndex] = SurveyItem(item.name, subs);
                    _catalogue[cat] = list;
                  });
                },
              ),
            ],
          ),
          const Divider(),
        ],
      ),
    );
  }

  Future<String?> _promptText(BuildContext context, String label,
      {String? initial}) {
    final ctrl = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        content: TextField(
            controller: ctrl,
            decoration: InputDecoration(labelText: label),
            autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(ctrl.text),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Future<(String, num)?> _promptSub(BuildContext context,
      {String? initialLabel, num? initialCft}) {
    final labelCtrl = TextEditingController(text: initialLabel ?? '');
    final cftCtrl = TextEditingController(text: initialCft?.toString() ?? '');
    return showDialog<(String, num)?>(
      context: context,
      builder: (_) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: labelCtrl,
                decoration:
                    const InputDecoration(labelText: 'Variant label'),
                autofocus: true),
            TextField(
                controller: cftCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'CFT')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final label = labelCtrl.text.trim();
              final cft = num.tryParse(cftCtrl.text.trim());
              if (label.isEmpty || cft == null) return;
              Navigator.of(context).pop((label, cft));
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// Controllers for one editable slab row.
class _SlabRowCtrl {
  _SlabRowCtrl.from(CftSlab s)
      : toCtrl = TextEditingController(text: s.cftTo?.toString() ?? ''),
        nameCtrl = TextEditingController(text: s.packageName),
        vehicleCtrl = TextEditingController(text: s.vehicle),
        crewCtrl =
            TextEditingController(text: s.crew > 0 ? s.crew.toString() : ''),
        vehicleCft = s.vehicleCft;

  final TextEditingController toCtrl;
  final TextEditingController nameCtrl;
  final TextEditingController vehicleCtrl;
  final TextEditingController crewCtrl;

  /// Preserved through edits, not shown — see [CftSlab.vehicleCft].
  final num? vehicleCft;

  void dispose() {
    toCtrl.dispose();
    nameCtrl.dispose();
    vehicleCtrl.dispose();
    crewCtrl.dispose();
  }
}


/// Controllers for one storage-rate row.
///
/// Owned by the page rather than rebuilt per frame so in-progress typing
/// survives a setState - same reason as _SlabRowCtrl above.
class _RateRowCtrl {
  _RateRowCtrl({
    required this.sizeCtrl,
    required this.perDayCtrl,
    required this.perMonthCtrl,
    required this.minDaysCtrl,
    required this.handlingInCtrl,
    required this.handlingOutCtrl,
  });

  factory _RateRowCtrl.from(StorageSizeRate r) => _RateRowCtrl(
        sizeCtrl: TextEditingController(text: r.size),
        perDayCtrl: TextEditingController(text: _n(r.perDay)),
        perMonthCtrl: TextEditingController(text: _n(r.perMonth)),
        minDaysCtrl: TextEditingController(text: '${r.minDays}'),
        handlingInCtrl: TextEditingController(text: _n(r.handlingIn)),
        handlingOutCtrl: TextEditingController(text: _n(r.handlingOut)),
      );

  /// A new row opens EMPTY on every money field. The one seeded value is
  /// the minimum-stay default, which is an identity rather than a price:
  /// 0 there switches the floor off instead of meaning anything - the
  /// same reasoning as rate_card_multipliers opening at 100.
  factory _RateRowCtrl.empty() => _RateRowCtrl(
        sizeCtrl: TextEditingController(),
        perDayCtrl: TextEditingController(),
        perMonthCtrl: TextEditingController(),
        minDaysCtrl: TextEditingController(text: '$kStorageDefaultMinDays'),
        handlingInCtrl: TextEditingController(),
        handlingOutCtrl: TextEditingController(),
      );

  final TextEditingController sizeCtrl;
  final TextEditingController perDayCtrl;
  final TextEditingController perMonthCtrl;
  final TextEditingController minDaysCtrl;
  final TextEditingController handlingInCtrl;
  final TextEditingController handlingOutCtrl;

  /// Trailing '.0' dropped so a saved 300 comes back as "300" - a vendor
  /// should not see their own price restyled.
  static String _n(double v) =>
      v == 0 ? '' : (v == v.roundToDouble() ? '${v.toInt()}' : '$v');

  double get perDay => double.tryParse(perDayCtrl.text.trim()) ?? 0;
  double get perMonth => double.tryParse(perMonthCtrl.text.trim()) ?? 0;

  StorageSizeRate toRate() => StorageSizeRate(
        size: sizeCtrl.text.trim(),
        perDay: perDay,
        perMonth: perMonth,
        minDays:
            int.tryParse(minDaysCtrl.text.trim()) ?? kStorageDefaultMinDays,
        handlingIn: double.tryParse(handlingInCtrl.text.trim()) ?? 0,
        handlingOut: double.tryParse(handlingOutCtrl.text.trim()) ?? 0,
      );

  void dispose() {
    sizeCtrl.dispose();
    perDayCtrl.dispose();
    perMonthCtrl.dispose();
    minDaysCtrl.dispose();
    handlingInCtrl.dispose();
    handlingOutCtrl.dispose();
  }
}
