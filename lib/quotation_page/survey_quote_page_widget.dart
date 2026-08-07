import 'dart:math';

import '/backend/gst_state_codes.dart';
import '/backend/pricing_defaults.dart';
import '/components/survey_response_section.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

/// Survey & Quote builder (parity brief Part 3a-3d, 28 Jul 2026).
///
/// Ported from reference/APC Web App JSX/App.jsx's SurveyQuotation
/// component (~line 2660): itemized CFT survey with +/- counters per
/// category/item/variant, a live package suggestion, the full charges
/// section (billing-mode toggle on the 5 bundleable charges, other
/// charges, add-on services, discount), and GST (rate/type/show-in-PDF).
///
/// Distinct from the existing lightweight "Create Quote" dialog on
/// LeadDetailPage (single subtotal + gst_pct, already live-verified as
/// part of the shipped Survey->Quote->Order flow) — that flow is left
/// untouched. This is the fuller itemized builder the brief asks for,
/// reachable as an additional path.
///
/// Per the brief's multi-tenancy rule: CFT values, packages, and charge
/// defaults all come from [PricingConfig] (per-org, `pricing_config`
/// table) — nothing here is hardcoded.
class SurveyQuotePageWidget extends StatefulWidget {
  const SurveyQuotePageWidget({
    super.key,
    this.surveyId,
    this.leadId,
    this.leadCustomer,
    this.leadPhone,
    this.leadFromCity,
    this.leadToCity,
    this.leadFromFloor,
    this.leadToFloor,
  });

  /// When set, the builder seeds its item lines from that survey's
  /// submitted selections instead of starting empty — so a vendor never
  /// re-keys what the customer already entered on the public page.
  final String? surveyId;

  final String? leadId;
  final String? leadCustomer;
  final String? leadPhone;
  final String? leadFromCity;
  final String? leadToCity;
  final int? leadFromFloor;
  final int? leadToFloor;

  static String routeName = 'SurveyQuotePage';
  static String routePath = '/survey-quote';

  @override
  State<SurveyQuotePageWidget> createState() => _SurveyQuotePageWidgetState();
}

String _hexToken() {
  final r = Random.secure();
  return List<int>.generate(24, (_) => r.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

class _SurveyQuotePageWidgetState extends State<SurveyQuotePageWidget> {
  PricingConfig? _config;
  bool _loading = true;
  bool _saving = false;

  /// Quote lines, keyed "cat|item|sub".
  ///
  /// **CFT is captured on the line when it is added, never resolved at
  /// total time.** This replaced a `Map<String,int>` of quantities whose
  /// CFT was looked up by walking `_config.surveyCats` every time a total
  /// was computed. That lookup returned 0 for anything not in the
  /// catalogue — which is every custom item — so custom items silently
  /// contributed nothing to the CFT total and under-sized the suggested
  /// package and vehicle on live quotes.
  ///
  /// Storing per line also means a quote keeps the numbers it was
  /// actually quoted at: editing a catalogue CFT later re-prices history
  /// under the old model, but not under this one.
  final _lines = <String, _QuoteLine>{};
  late final Map<String, TextEditingController> _amountCtrl;

  int _qtyOf(String key) => _lines[key]?.qty ?? 0;

  /// Adds [delta] to a line, creating it (capturing [cft]) if needed and
  /// dropping it at zero so empty lines never reach the payload.
  void _bump(String key,
      {required int delta,
      required String cat,
      required String item,
      required String sub,
      required num cft}) {
    setState(() {
      final existing = _lines[key];
      final next = (existing?.qty ?? 0) + delta;
      if (next <= 0) {
        _lines.remove(key);
        return;
      }
      if (existing == null) {
        _lines[key] = _QuoteLine(
            cat: cat, item: item, sub: sub, cft: cft, qty: next);
      } else {
        existing.qty = next;
      }
    });
  }

  /// Search over the item list. Matches category, item and variant names,
  /// so typing "sofa" or "washing" jumps straight to it instead of
  /// scrolling five collapsed categories.
  final _itemSearch = TextEditingController();
  String _search = '';

  /// Custom (one-off) items the surveyor adds on site for anything the
  /// configured catalogue doesn't cover. The CFT here seeds the line at
  /// add-time; the line owns it from then on.
  static const String _kCustomCat = 'Custom Items';
  final List<({String name, num cft})> _customItems = [];

  bool _matchesSearch(String cat, String item, String sub) {
    if (_search.isEmpty) return true;
    final q = _search.toLowerCase();
    return cat.toLowerCase().contains(q) ||
        item.toLowerCase().contains(q) ||
        sub.toLowerCase().contains(q);
  }

  /// Variants of [item] that survive the current search. An item whose
  /// own name matches keeps all of its variants, so searching "sofa"
  /// shows every sofa size rather than none.
  List<SurveySubItem> _visibleSubs(SurveyItem item) {
    if (_search.isEmpty) return item.subs;
    final q = _search.toLowerCase();
    if (item.name.toLowerCase().contains(q)) return item.subs;
    return item.subs
        .where((s) => s.label.toLowerCase().contains(q))
        .toList();
  }
  final _billingMode = <String, String>{}; // billable key -> included/additional

  // ---- Part 8 Rev B item 4: per-line charge basis -----------------------
  // Only these 6 keys are real charge fields today that Rev B's basis
  // list also names (transport, packing, unpacking, loading, unloading,
  // materials) - rearrangement/toll-parking/insurance are in the SQL
  // migration's default map for forward-compatibility but aren't real
  // fields in kDefaultChargeFields yet, so they get no UI here.
  static const _basisAwareKeys = {
    'transport', 'packing', 'unpacking', 'loading', 'unloading', 'materials',
  };
  final _basis = <String, String>{}; // key -> one of kChargeBasisOptions
  final _rateCtrl = <String, TextEditingController>{}; // per_cft/per_floor/per_trip/per_km
  final _qtyCtrl = <String, TextEditingController>{}; // per_floor/per_trip/per_km only (per_cft uses _totalCft live)
  final _declaredValueCtrl = <String, TextEditingController>{}; // percent_of_declared_value
  final _pctCtrl = <String, TextEditingController>{}; // percent_of_declared_value

  double _gstPct = kGstDefaultPct.toDouble();
  String _gstType = 'auto'; // auto | intra | inter
  bool _gstShowInPdf = true;

  late final TextEditingController _customer;
  late final TextEditingController _phone;
  late final TextEditingController _fromAddr;
  late final TextEditingController _toAddr;

  @override
  void initState() {
    super.initState();
    _customer = TextEditingController(text: widget.leadCustomer ?? '');
    _phone = TextEditingController(text: widget.leadPhone ?? '');
    _fromAddr = TextEditingController(text: widget.leadFromCity ?? '');
    _toAddr = TextEditingController(text: widget.leadToCity ?? '');
    _amountCtrl = {
      for (final f in kDefaultChargeFields)
        f.key: TextEditingController(text: '')
    };
    for (final f in kDefaultChargeFields.where((f) => f.billable)) {
      _billingMode[f.key] = 'included';
    }
    for (final key in _basisAwareKeys) {
      _rateCtrl[key] = TextEditingController();
      _qtyCtrl[key] = TextEditingController();
      _declaredValueCtrl[key] = TextEditingController();
      _pctCtrl[key] = TextEditingController();
    }
    PricingConfig.loadForCurrentOrg().then((c) {
      if (!mounted) return;
      setState(() {
        _config = c;
        _gstPct = kGstRateOptions.contains(kGstDefaultPct)
            ? kGstDefaultPct.toDouble()
            : 5.0;
        // Org-configured default per key, from pricing_config - never a
        // Dart-hardcoded default per Rev B's decision. PricingConfig
        // already merges in kDefaultChargeBasis key-by-key when an org
        // hasn't customized a given key, so this is always a real value.
        for (final key in _basisAwareKeys) {
          _basis[key] = c.chargeBasis[key] ?? 'lumpsum';
        }
        _loading = false;
      });
      if (widget.surveyId != null) _seedFromSurvey();
    });
  }


  /// Seeds the item lines from a submitted customer survey.
  ///
  /// `surveys.rooms` carries cat/item/sub/cft/qty per selection, which maps
  /// 1:1 onto _QuoteLine — including the CFT, which is taken FROM THE
  /// SURVEY rather than re-resolved against the catalogue. That preserves
  /// the same rule as the custom-item fix: the number quoted is the number
  /// captured, and a later catalogue edit cannot rewrite it.
  ///
  /// Best-effort: a failure here leaves the builder empty and usable, which
  /// is strictly better than blocking the vendor from quoting at all.
  Future<void> _seedFromSurvey() async {
    try {
      final rows = await SurveysTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('id', widget.surveyId!),
      );
      if (rows.isEmpty || !mounted) return;
      final survey = rows.first;
      final lines = parseSurveyRooms(survey.rooms);
      if (lines.isEmpty) return;

      setState(() {
        for (final l in lines) {
          final key = '${l.cat}|${l.item}|${l.sub}';
          // Merge rather than overwrite, in case the same selection
          // appears twice in the submission.
          final existing = _lines[key];
          _lines[key] = _QuoteLine(
            cat: l.cat,
            item: l.item,
            sub: l.sub,
            cft: l.cft,
            qty: (existing?.qty ?? 0) + l.qty,
          );
          // A survey line whose category isn't in this org's catalogue
          // still has to be visible and editable, so surface it in the
          // custom list.
          final known = (_config?.surveyCats[l.cat] ?? const <SurveyItem>[])
              .any((i) => i.name == l.item);
          if (!known && !_customItems.any((c) => c.name == l.item)) {
            _customItems.add((name: l.item, cft: l.cft));
          }
        }
        if ((survey.fromAddress ?? '').isNotEmpty) {
          _fromAddr.text = survey.fromAddress!;
        }
        if ((survey.toAddress ?? '').isNotEmpty) {
          _toAddr.text = survey.toAddress!;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Prefilled ${lines.length} item'
                '${lines.length == 1 ? '' : 's'} from the customer survey '
                '($_totalCft CFT). Adjust before quoting.'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (_) {
      // Leave the builder empty rather than failing the screen.
    }
  }

  @override
  void dispose() {
    _customer.dispose();
    _phone.dispose();
    _fromAddr.dispose();
    _toAddr.dispose();
    _itemSearch.dispose();
    for (final c in _amountCtrl.values) {
      c.dispose();
    }
    for (final c in [
      ..._rateCtrl.values,
      ..._qtyCtrl.values,
      ..._declaredValueCtrl.values,
      ..._pctCtrl.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Basis-aware for the 6 keys Rev B's item 4 covers: computes the
  /// amount from qty x rate (or declared-value x pct) instead of reading
  /// a plain typed-in amount, for every basis except lumpsum/at_actuals
  /// (which have no such breakdown and keep the plain field).
  double _amount(String key) {
    if (!_basisAwareKeys.contains(key)) {
      return double.tryParse(_amountCtrl[key]!.text) ?? 0;
    }
    switch (_basis[key] ?? 'lumpsum') {
      case 'per_cft':
        final rate = double.tryParse(_rateCtrl[key]!.text) ?? 0;
        return (_totalCft * rate).roundToDouble();
      case 'per_floor':
      case 'per_trip':
      case 'per_km':
        final qty = double.tryParse(_qtyCtrl[key]!.text) ?? 0;
        final rate = double.tryParse(_rateCtrl[key]!.text) ?? 0;
        return (qty * rate).roundToDouble();
      case 'percent_of_declared_value':
        final declared = double.tryParse(_declaredValueCtrl[key]!.text) ?? 0;
        final pct = double.tryParse(_pctCtrl[key]!.text) ?? 0;
        return (declared * pct / 100).roundToDouble();
      case 'lumpsum':
      case 'at_actuals':
      default:
        return double.tryParse(_amountCtrl[key]!.text) ?? 0;
    }
  }

  /// The jsonb value written for one charge line (Rev B item 4's shape
  /// upgrade). Plain number for lumpsum - matches the legacy shape
  /// exactly, so an org that never touches basis writes identical data to
  /// before. Any other basis writes the full breakdown object so the PDF
  /// (and any future reader) can show qty/rate, not just a total.
  dynamic _chargeValue(String key) {
    final amount = _amount(key);
    if (!_basisAwareKeys.contains(key)) return amount;
    final basis = _basis[key] ?? 'lumpsum';
    if (basis == 'lumpsum') return amount;
    final obj = <String, dynamic>{'amount': amount, 'basis': basis};
    switch (basis) {
      case 'per_cft':
        obj['qty'] = _totalCft;
        obj['rate'] = double.tryParse(_rateCtrl[key]!.text) ?? 0;
        break;
      case 'per_floor':
      case 'per_trip':
      case 'per_km':
        obj['qty'] = double.tryParse(_qtyCtrl[key]!.text) ?? 0;
        obj['rate'] = double.tryParse(_rateCtrl[key]!.text) ?? 0;
        break;
      case 'percent_of_declared_value':
        obj['declaredValue'] =
            double.tryParse(_declaredValueCtrl[key]!.text) ?? 0;
        obj['rate'] = double.tryParse(_pctCtrl[key]!.text) ?? 0;
        break;
      case 'at_actuals':
      default:
        break;
    }
    return obj;
  }

  int get _totalItems => _lines.values.fold(0, (s, l) => s + l.qty);

  /// Sums the CFT stored on each line. No catalogue lookup — see
  /// [_lines]' doc comment for why that lookup was the bug.
  num get _totalCft =>
      _lines.values.fold<num>(0, (s, l) => s + l.cft * l.qty);

  /// Lines that would be persisted with cft == 0. Surfaced in the UI and
  /// confirmed at save, rather than silently producing a quote whose
  /// suggested package is too small.
  List<_QuoteLine> get _zeroCftLines =>
      _lines.values.where((l) => l.cft <= 0).toList();

  PackageInfo? get _suggestedPackage => _config == null
      ? null
      : packageInfoForCft(_totalCft, _config!.cftRanges, _config!.packages);

  double get _subtotal {
    double s = 0;
    for (final f in kDefaultChargeFields) {
      if (f.key == 'discount') continue;
      if (f.billable && (_billingMode[f.key] ?? 'included') == 'included') {
        continue;
      }
      s += _amount(f.key);
    }
    return s - _amount('discount');
  }

  bool get _isInterstate {
    if (_gstType == 'intra') return false;
    if (_gstType == 'inter') return true;
    return isInterState(_fromAddr.text, _toAddr.text);
  }

  double get _gstAmount => (_subtotal * (_gstPct / 100)).roundToDouble();
  double get _total => _subtotal + _gstAmount;

  Future<void> _save() async {
    if (_customer.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter customer name first.')));
      return;
    }

    // Block a save that would persist 0-CFT lines unless explicitly
    // confirmed — those are what silently under-sized the package before.
    final zeros = _zeroCftLines;
    if (zeros.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Some items have no CFT'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'These lines will be saved with 0 CFT, so they will not '
                'count towards the suggested package or vehicle size:',
              ),
              const SizedBox(height: 10),
              for (final l in zeros.take(6))
                Text('•  ${l.item}${l.sub == 'Qty' ? '' : ' — ${l.sub}'}'),
              if (zeros.length > 6) Text('…and ${zeros.length - 6} more'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Go back and fix'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Save anyway'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _saving = true);
    try {
      // CFT comes off the line, captured when it was added. No catalogue
      // lookup here — that lookup is exactly what returned 0 for custom
      // items and mis-priced live quotes.
      final items = <Map<String, dynamic>>[
        for (final l in _lines.values)
          {
            'cat': l.cat,
            'item': l.item,
            'sub': l.sub,
            'qty': l.qty,
            'cft': l.cft,
            'totalCftItem': l.cft * l.qty,
            if (l.cat == _kCustomCat) 'custom': true,
          },
      ];
      final charges = <String, dynamic>{
        for (final f in kDefaultChargeFields) f.key: _chargeValue(f.key),
      };
      charges['_billingMode'] = _billingMode;
      charges['_gstType'] = _gstType;
      charges['_gstShowInPdf'] = _gstShowInPdf;
      charges['_suggestedPackage'] = _suggestedPackage?.type;
      charges['_totalCft'] = _totalCft;
      charges['_totalItems'] = _totalItems;

      await QuotationsTable().insert({
        'id': const Uuid().v4(),
        'token': _hexToken(),
        ...OrgScope.stamp(),
        'lead_id': widget.leadId,
        'customer': _customer.text.trim(),
        'phone': _phone.text.trim(),
        'from_address': _fromAddr.text.trim(),
        'to_address': _toAddr.text.trim(),
        'items': items,
        'charges': charges,
        'subtotal': _subtotal,
        'gst_pct': _gstPct,
        'gst_amount': _gstAmount,
        'total': _total,
        'status': 'draft',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quotation saved.')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save quotation: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        title: Text('Survey & Quote',
            style: GoogleFonts.interTight(
                fontWeight: FontWeight.w700, color: theme.primaryText)),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _customerCard(theme),
                  const SizedBox(height: 14),
                  _packageCard(theme),
                  const SizedBox(height: 14),
                  _itemSearchBar(theme),
                  const SizedBox(height: 10),
                  _customItemsSection(theme),
                  ..._config!.surveyCats.entries
                      .map((e) => _categorySection(theme, e.key, e.value)),
                  if (_search.isNotEmpty && !_anySearchMatch())
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Column(
                        children: [
                          Text('No items match "$_search"',
                              style: GoogleFonts.inter(
                                  fontSize: 13.5,
                                  color: theme.secondaryText)),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => _addCustomItem(preset: _search),
                            icon: const Icon(Icons.add, size: 18),
                            label: Text('Add "$_search" as a custom item'),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),
                  _chargesCard(theme),
                  const SizedBox(height: 14),
                  _gstCard(theme),
                  const SizedBox(height: 14),
                  _summaryCard(theme),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: theme.primary,
                          foregroundColor: Colors.white),
                      child:
                          Text(_saving ? 'Saving...' : 'Save Quotation'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _card(FlutterFlowTheme theme, String title, Widget child) => Container(
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: GoogleFonts.interTight(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: theme.primary)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      );

  Widget _customerCard(FlutterFlowTheme theme) => _card(
        theme,
        'Customer',
        Column(
          children: [
            TextField(
                controller: _customer,
                decoration: const InputDecoration(labelText: 'Customer name')),
            const SizedBox(height: 10),
            TextField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Phone')),
            const SizedBox(height: 10),
            TextField(
                controller: _fromAddr,
                decoration:
                    const InputDecoration(labelText: 'From city/address')),
            const SizedBox(height: 10),
            TextField(
                controller: _toAddr,
                decoration:
                    const InputDecoration(labelText: 'To city/address')),
          ],
        ),
      );

  Widget _packageCard(FlutterFlowTheme theme) {
    final pkg = _suggestedPackage;
    return Container(
      decoration: BoxDecoration(
        color: theme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.primary.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$_totalItems items · $_totalCft CFT',
                    style: GoogleFonts.interTight(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: theme.primaryText)),
                const SizedBox(height: 4),
                Text(
                  pkg == null
                      ? 'Add items to see a suggested package'
                      : 'Suggested: ${pkg.type} · ${pkg.crew} crew · ${pkg.vehicle}',
                  style: GoogleFonts.inter(
                      fontSize: 12.5, color: theme.secondaryText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemSearchBar(FlutterFlowTheme theme) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _itemSearch,
            onChanged: (v) => setState(() => _search = v.trim()),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search items…',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _itemSearch.clear();
                        setState(() => _search = '');
                      },
                    ),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: () => _addCustomItem(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Custom'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.primary,
              side: BorderSide(color: theme.primary),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }

  /// True if anything in the catalogue (or the custom list) survives the
  /// current search — drives the "no matches, add it as custom" prompt.
  bool _anySearchMatch() {
    for (final c in _customItems) {
      if (_matchesSearch(_kCustomCat, c.name, 'Qty')) return true;
    }
    for (final entry in _config!.surveyCats.entries) {
      for (final item in entry.value) {
        if (_visibleSubs(item).isNotEmpty) return true;
      }
    }
    return false;
  }

  Widget _customItemsSection(FlutterFlowTheme theme) {
    final visible = _customItems
        .where((c) => _matchesSearch(_kCustomCat, c.name, 'Qty'))
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 10),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(_kCustomCat,
                style: GoogleFonts.interTight(
                    fontWeight: FontWeight.w700, color: theme.primaryText)),
          ),
          for (final c in visible)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _customItemRow(theme, c),
            ),
        ],
      ),
    );
  }

  Widget _customItemRow(FlutterFlowTheme theme, ({String name, num cft}) c) {
    final key = '$_kCustomCat|${c.name}|Qty';
    final qty = _qtyOf(key);
    final zeroCft = c.cft <= 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: qty > 0
            ? theme.primary.withValues(alpha: 0.12)
            : theme.primaryBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: zeroCft && qty > 0
                ? theme.warning
                : qty > 0
                    ? theme.primary
                    : theme.secondaryText.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text('${c.name} (${c.cft} cft)',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          fontSize: 12.5, color: theme.primaryText)),
                ),
                // Make a 0-CFT line obvious at the point of entry, not
                // only at save time.
                if (zeroCft) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'No CFT — will not count towards the package',
                    child: Icon(Icons.warning_amber_rounded,
                        size: 16, color: theme.warning),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            width: 36,
            height: 40,
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: 'Remove custom item',
              icon: Icon(Icons.delete_outline, size: 18, color: theme.error),
              onPressed: () => setState(() {
                _customItems.removeWhere((x) => x.name == c.name);
                _lines.remove(key);
              }),
            ),
          ),
          _stepper(
            theme,
            qty: qty,
            onMinus: qty > 0
                ? () => _bump(key,
                    delta: -1,
                    cat: _kCustomCat,
                    item: c.name,
                    sub: 'Qty',
                    cft: c.cft)
                : null,
            onPlus: () => _bump(key,
                delta: 1,
                cat: _kCustomCat,
                item: c.name,
                sub: 'Qty',
                cft: c.cft),
          ),
        ],
      ),
    );
  }

  /// Adds a one-off item not in the configured catalogue. [preset]
  /// pre-fills the name when launched from the "no matches" prompt.
  Future<void> _addCustomItem({String? preset}) async {
    final nameCtrl = TextEditingController(text: preset ?? '');
    final cftCtrl = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add custom item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Item name',
                hintText: 'e.g. Piano, Aquarium',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: cftCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'CFT per unit',
                hintText: 'e.g. 30',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    final name = nameCtrl.text.trim();
    final cft = num.tryParse(cftCtrl.text.trim()) ?? 0;
    nameCtrl.dispose();
    cftCtrl.dispose();
    if (added != true || name.isEmpty) return;
    if (!mounted) return;
    if (_customItems.any((c) => c.name.toLowerCase() == name.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$name" is already in the list.')),
      );
      return;
    }
    setState(() {
      _customItems.add((name: name, cft: cft));
      // Start at 1 — the surveyor just told us this item exists. CFT is
      // baked onto the line here and never re-resolved.
      _lines['$_kCustomCat|$name|Qty'] = _QuoteLine(
        cat: _kCustomCat,
        item: name,
        sub: 'Qty',
        cft: cft,
        qty: 1,
      );
      // Clear the search so the new row isn't hidden by a filter that no
      // longer matches anything.
      _itemSearch.clear();
      _search = '';
    });
  }

  Widget _categorySection(
      FlutterFlowTheme theme, String cat, List<SurveyItem> items) {
    // Hide a whole category when nothing in it matches the search.
    final visibleItems =
        items.where((i) => _visibleSubs(i).isNotEmpty).toList();
    if (visibleItems.isEmpty) return const SizedBox.shrink();
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ExpansionTile(
          // Auto-expand while searching so matches are visible without
          // having to open each category by hand. The ValueKey forces
          // ExpansionTile to rebuild its state when the search toggles,
          // since initiallyExpanded is only read on first build.
          key: ValueKey('$cat-${_search.isNotEmpty}'),
          initiallyExpanded: _search.isNotEmpty,
          title: Text(cat,
              style: GoogleFonts.interTight(
                  fontWeight: FontWeight.w700, color: theme.primaryText)),
          children: [
            for (final item in visibleItems) _itemRow(theme, cat, item),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _itemRow(FlutterFlowTheme theme, String cat, SurveyItem item) {
    // When a search is active, show only the variants that match, so the
    // list collapses to just the relevant lines.
    final subs = _visibleSubs(item);
    if (subs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.name,
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: theme.primaryText)),
          const SizedBox(height: 6),
          // Was a `Wrap` of intrinsic-width pills. Because each pill sized
          // itself to its own label ("Top Load (15 cft)" vs "Small (5
          // cft)"), the rows came out ragged and the +/- controls sat at a
          // different x on every line — the misalignment reported from the
          // phone. Now every variant is a full-width row: label flexes on
          // the left, the stepper is a fixed-width cluster pinned right,
          // so all the controls line up in one column.
          for (final sub in subs) _variantRow(theme, cat, item.name, sub),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _variantRow(
      FlutterFlowTheme theme, String cat, String itemName, SurveySubItem sub) {
    final key = '$cat|$itemName|${sub.label}';
    final qty = _qtyOf(key);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: qty > 0
            ? theme.primary.withValues(alpha: 0.12)
            : theme.primaryBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: qty > 0
                ? theme.primary
                : theme.secondaryText.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${sub.label} (${sub.cft} cft)',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  GoogleFonts.inter(fontSize: 12.5, color: theme.primaryText),
            ),
          ),
          const SizedBox(width: 8),
          _stepper(
            theme,
            qty: qty,
            // sub.cft is read here, at add time, and stored on the line.
            onMinus: qty > 0
                ? () => _bump(key,
                    delta: -1,
                    cat: cat,
                    item: itemName,
                    sub: sub.label,
                    cft: sub.cft)
                : null,
            onPlus: () => _bump(key,
                delta: 1,
                cat: cat,
                item: itemName,
                sub: sub.label,
                cft: sub.cft),
          ),
        ],
      ),
    );
  }

  /// Fixed-width so every row's controls align on one vertical grid.
  /// 40x40 tap targets (parity brief Part 5e).
  // Corrections session, B5 (7 Aug 2026): both buttons were 40x40, below
  // the 48x48 Material minimum touch target — outstanding since before
  // the last APK build per the brief. This is the one shared stepper
  // both the custom-item rows and the catalogue sub-item rows call, so
  // fixing it here covers every CFT +/- control in the survey builder,
  // not just one spot.
  Widget _stepper(
    FlutterFlowTheme theme, {
    required int qty,
    required VoidCallback? onMinus,
    required VoidCallback onPlus,
  }) {
    return SizedBox(
      width: 118,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              onPressed: onMinus,
            ),
          ),
          SizedBox(
            width: 22,
            child: Text('$qty',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700, color: theme.primaryText)),
          ),
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.add_circle_outline, size: 20),
              onPressed: onPlus,
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountField(FlutterFlowTheme theme, String key, String label,
      {bool enabled = true}) {
    return TextField(
      controller: _amountCtrl[key],
      enabled: enabled,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, isDense: true),
    );
  }

  Widget _chargesCard(FlutterFlowTheme theme) {
    final billable = kDefaultChargeFields.where((f) => f.billable).toList();
    final other = kDefaultChargeFields
        .where((f) => !f.billable && f.key != 'discount' && f.key != 'advanceOnQuote')
        .toList();
    return _card(
      theme,
      'Charges',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Freight / Transport',
              style: GoogleFonts.inter(fontSize: 13, color: theme.primaryText)),
          const SizedBox(height: 6),
          _basisRow(theme, 'transport'),
          const SizedBox(height: 10),
          _amountField(theme, 'advanceOnQuote', 'Advance Paid'),
          const SizedBox(height: 14),
          Text('Packing & Labour (bundle in freight, or bill separately)',
              style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: theme.secondaryText)),
          const SizedBox(height: 8),
          for (final f in billable) _billableRow(theme, f),
          const SizedBox(height: 14),
          Text('Other Charges',
              style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: theme.secondaryText)),
          const SizedBox(height: 8),
          for (final f in other.where((f) =>
              ['storage', 'carTransport', 'misc', 'stCharge', 'otherCharges']
                  .contains(f.key)))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _amountField(theme, f.key, f.label),
            ),
          const SizedBox(height: 6),
          Text('Add-on Services',
              style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: theme.secondaryText)),
          const SizedBox(height: 8),
          for (final f in other.where((f) => ![
                'storage',
                'carTransport',
                'misc',
                'stCharge',
                'otherCharges'
              ].contains(f.key)))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _amountField(theme, f.key, f.label),
            ),
          const SizedBox(height: 6),
          _amountField(theme, 'discount', 'Discount'),
        ],
      ),
    );
  }

  Widget _billableRow(FlutterFlowTheme theme, ChargeField f) {
    final included = (_billingMode[f.key] ?? 'included') == 'included';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                  flex: 2,
                  child: Text(f.label,
                      style: GoogleFonts.inter(
                          fontSize: 13, color: theme.primaryText))),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: _billingMode[f.key] ?? 'included',
                  isDense: true,
                  items: const [
                    DropdownMenuItem(
                        value: 'included', child: Text('Incl. in Freight')),
                    DropdownMenuItem(
                        value: 'additional', child: Text('Additional')),
                  ],
                  onChanged: (v) =>
                      setState(() => _billingMode[f.key] = v ?? 'included'),
                ),
              ),
            ],
          ),
          // Basis + amount only matter once this line is actually charged
          // separately — a line bundled into freight has nothing to price
          // on its own (Part 8 Rev B item 4).
          if (!included) ...[
            const SizedBox(height: 6),
            _basisRow(theme, f.key),
          ],
        ],
      ),
    );
  }

  /// Basis dropdown + whatever value fields that basis needs (Part 8 Rev
  /// B item 4). Shared between the 5 billable rows above and the
  /// transport row below — transport has no included/additional toggle
  /// (it's never bundled into itself) but still gets a basis.
  Widget _basisRow(FlutterFlowTheme theme, String key) {
    final basis = _basis[key] ?? 'lumpsum';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<String>(
            initialValue: basis,
            isDense: true,
            decoration: const InputDecoration(labelText: 'Basis', isDense: true),
            items: [
              for (final b in kChargeBasisOptions)
                DropdownMenuItem(
                  value: b,
                  child: Text(kChargeBasisLabels[b]!,
                      style: const TextStyle(fontSize: 12)),
                ),
            ],
            onChanged: (v) => setState(() => _basis[key] = v ?? 'lumpsum'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(flex: 3, child: _basisValueFields(theme, key, basis)),
      ],
    );
  }

  Widget _basisValueFields(FlutterFlowTheme theme, String key, String basis) {
    switch (basis) {
      case 'per_cft':
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text('$_totalCft CFT',
                  style: GoogleFonts.inter(
                      fontSize: 12.5, color: theme.secondaryText)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _rateCtrl[key],
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: '₹/CFT', isDense: true),
              ),
            ),
          ],
        );
      case 'per_floor':
      case 'per_trip':
      case 'per_km':
        final unitLabel = basis == 'per_floor'
            ? 'Floors'
            : basis == 'per_trip'
                ? 'Trips'
                : 'KM';
        return Row(
          children: [
            Expanded(
              child: TextField(
                controller: _qtyCtrl[key],
                keyboardType: TextInputType.number,
                decoration:
                    InputDecoration(labelText: unitLabel, isDense: true),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _rateCtrl[key],
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Rate', isDense: true),
              ),
            ),
          ],
        );
      case 'percent_of_declared_value':
        return Row(
          children: [
            Expanded(
              child: TextField(
                controller: _declaredValueCtrl[key],
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Declared ₹', isDense: true),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _pctCtrl[key],
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '%', isDense: true),
              ),
            ),
          ],
        );
      case 'lumpsum':
      case 'at_actuals':
      default:
        return _amountField(theme, key, '₹');
    }
  }

  Widget _gstCard(FlutterFlowTheme theme) => _card(
        theme,
        'GST (SAC $kGstSac)',
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<double>(
                    initialValue: _gstPct,
                    decoration: const InputDecoration(labelText: 'Rate'),
                    items: [
                      for (final r in kGstRateOptions)
                        DropdownMenuItem(
                            value: r.toDouble(), child: Text('$r%'))
                    ],
                    onChanged: (v) =>
                        setState(() => _gstPct = v ?? kGstDefaultPct.toDouble()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _gstType,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(
                          value: 'auto', child: Text('Auto-detect')),
                      DropdownMenuItem(
                          value: 'intra', child: Text('CGST+SGST')),
                      DropdownMenuItem(value: 'inter', child: Text('IGST')),
                    ],
                    onChanged: (v) => setState(() => _gstType = v ?? 'auto'),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show GST in PDF'),
              value: _gstShowInPdf,
              onChanged: (v) => setState(() => _gstShowInPdf = v),
            ),
            Text(
              _isInterstate
                  ? 'Interstate → IGST ₹${_gstAmount.toStringAsFixed(0)}'
                  : 'Intrastate → CGST ₹${(_gstAmount / 2).toStringAsFixed(0)} '
                      '+ SGST ₹${(_gstAmount / 2).toStringAsFixed(0)}',
              style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: theme.primary),
            ),
          ],
        ),
      );

  Widget _summaryCard(FlutterFlowTheme theme) {
    final rows = <(String, double)>[
      ('Subtotal', _subtotal),
      ('GST (${_gstPct.toStringAsFixed(0)}%)', _gstAmount),
    ];
    return Container(
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(r.$1, style: GoogleFonts.inter(color: theme.secondaryText)),
                  Text('₹${r.$2.toStringAsFixed(0)}',
                      style: GoogleFonts.inter(color: theme.primaryText)),
                ],
              ),
            ),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total',
                  style: GoogleFonts.interTight(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: theme.primaryText)),
              Text('₹${_total.toStringAsFixed(0)}',
                  style: GoogleFonts.interTight(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: theme.primary)),
            ],
          ),
        ],
      ),
    );
  }
}

/// One line on a quote.
///
/// [cft] is captured when the line is created and is never recomputed
/// from the catalogue. That is the whole point: the previous model kept
/// only quantities and resolved CFT by walking `_config.surveyCats` at
/// total time, which returned 0 for any item not in the catalogue — i.e.
/// every custom item — so custom items contributed nothing to the CFT
/// total and under-sized the suggested package on live quotes.
///
/// Storing it per line also means a saved quote keeps the numbers it was
/// actually quoted at, rather than silently re-pricing if someone edits
/// the org's catalogue CFT values later.
class _QuoteLine {
  _QuoteLine({
    required this.cat,
    required this.item,
    required this.sub,
    required this.cft,
    required this.qty,
  });

  final String cat;
  final String item;
  final String sub;
  final num cft;
  int qty;
}
