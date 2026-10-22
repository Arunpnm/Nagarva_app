import '/components/ng_widgets.dart';
import 'dart:math';

import '/backend/gst_state_codes.dart';
import '/backend/pricing_defaults.dart';
import '/components/survey_response_section.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/edge_function_errors.dart';
import '/flutter_flow/ng_tokens.dart';
// Item 12B-b: the package card links to Settings -> Survey & Pricing when
// the slab table can't resolve a suggestion.
import '/index.dart';
import 'package:flutter/material.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '/config/app_config.dart';

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
    this.quotationId,
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

  /// EDIT MODE (Part 1, 11 Sept 2026). When set, the builder loads that
  /// quotation, seeds every control from it, and saves through the
  /// `revise_quote()` RPC instead of inserting a new row.
  ///
  /// Until this existed the builder was INSERT-ONLY and the whole app
  /// contained exactly one `quotations` UPDATE — the accept flip at
  /// conversion. So a vendor renegotiating a price had no path but to
  /// build a second quote, which is how a lead ends up carrying two rows
  /// that disagree.
  ///
  /// The RPC takes the WHOLE priced snapshot or nothing, which is why
  /// edit mode lives here rather than as an inline field editor
  /// somewhere: there is no endpoint that writes items without writing
  /// price, by construction.
  ///
  /// Customer identity (name, phone, addresses) is NOT revisable —
  /// correcting a name is not a quote revision and must not consume a
  /// version number. Those fields render read-only in edit mode.
  final String? quotationId;

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

  /// Item 12C — the surveyor's override of the suggested package/vehicle/
  /// crew, null until they actually change something.
  ///
  /// Both the suggestion and the override are persisted to real columns on
  /// `quotations` (see [_save]) rather than re-derived at render. Real jobs
  /// have narrow staircases and long carries no CFT table predicts; and
  /// re-deriving would let a later slab edit silently rewrite an already
  /// dispatched job. Keeping the suggestion alongside the override is
  /// deliberate too — the gap between them over time is what tells the
  /// vendor their slabs need adjusting.
  String? _chosenPackage;
  String? _chosenVehicle;
  int? _chosenCrew;

  // ---- Edit mode (Part 1) ------------------------------------------------
  /// The quotation being revised, once loaded. Null in create mode.
  QuotationsRow? _editing;

  /// Set when edit mode could not load its quote. A blank builder is a
  /// valid NEW quote and a destructive REVISION, so the save button
  /// refuses while this is set rather than letting an empty form
  /// overwrite a real one.
  String? _loadFailed;

  bool get _isEditing => widget.quotationId != null;

  bool get _hasOverride =>
      _chosenPackage != null || _chosenVehicle != null || _chosenCrew != null;

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
      // Edit mode wins over survey prefill: a quote being REVISED already
      // holds the surveyor's adjustments, and re-seeding from the raw
      // survey on top would silently undo them.
      if (widget.quotationId != null) {
        _seedFromQuotation();
      } else if (widget.surveyId != null) {
        _seedFromSurvey();
      }
    });
  }

  /// Loads an existing quotation into the builder for revision.
  ///
  /// LOSSLESS BY CONSTRUCTION, and that is not luck: `_chargeValue`
  /// already persists the full breakdown object (basis, qty, rate,
  /// declaredValue) for every non-lumpsum charge rather than just the
  /// computed amount, so a charge entered on a per-CFT rate comes back as
  /// a per-CFT rate instead of collapsing to a lump sum the vendor can no
  /// longer explain. Line CFT likewise comes off the stored line, never
  /// re-resolved against today's catalogue — the same rule that fixed the
  /// 0-CFT custom-item bug.
  ///
  /// UNLIKE `_seedFromSurvey`, A FAILURE HERE IS FATAL TO THE SCREEN.
  /// An empty builder is a fine starting point for a NEW quote; for a
  /// revision it is a blank form that, if saved, would wipe the quote it
  /// was meant to amend. So this sets [_loadFailed] and the save button
  /// refuses rather than leaving a loaded-looking form holding nothing.
  Future<void> _seedFromQuotation() async {
    try {
      final rows = await QuotationsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('id', widget.quotationId!),
      );
      if (!mounted) return;
      if (rows.isEmpty) {
        setState(() => _loadFailed =
            'That quotation could not be loaded. It may have been deleted.');
        return;
      }
      final q = rows.first;

      setState(() {
        _editing = q;
        if ((q.customer ?? '').isNotEmpty) _customer.text = q.customer!;
        if ((q.phone ?? '').isNotEmpty) _phone.text = q.phone!;
        if ((q.fromAddress ?? '').isNotEmpty) _fromAddr.text = q.fromAddress!;
        if ((q.toAddress ?? '').isNotEmpty) _toAddr.text = q.toAddress!;

        // ---- items ----
        final items = q.items;
        if (items is List) {
          for (final raw in items) {
            if (raw is! Map) continue;
            final cat = (raw['cat'] ?? '').toString();
            final item = (raw['item'] ?? '').toString();
            final sub = (raw['sub'] ?? '').toString();
            final cft = _num(raw['cft']) ?? 0;
            final qty = (_num(raw['qty']) ?? 0).toInt();
            if (item.isEmpty || qty <= 0) continue;
            _lines['$cat|$item|$sub'] =
                _QuoteLine(cat: cat, item: item, sub: sub, cft: cft, qty: qty);
            // Same reasoning as _seedFromSurvey: a line whose category is
            // no longer in the catalogue must still be visible and
            // editable, or the vendor cannot change what they quoted.
            final known = (_config?.surveyCats[cat] ?? const <SurveyItem>[])
                .any((i) => i.name == item);
            if (!known && !_customItems.any((c) => c.name == item)) {
              _customItems.add((name: item, cft: cft));
            }
          }
        }

        // ---- charges ----
        final charges = q.charges is Map
            ? Map<String, dynamic>.from(q.charges as Map)
            : <String, dynamic>{};
        for (final f in kDefaultChargeFields) {
          final v = charges[f.key];
          if (v == null) continue;
          if (v is Map) {
            // Full breakdown object — restore the basis inputs too.
            final m = Map<String, dynamic>.from(v);
            _amountCtrl[f.key]?.text = _money(_num(m['amount']) ?? 0);
            final basis = (m['basis'] ?? 'lumpsum').toString();
            if (_basisAwareKeys.contains(f.key)) {
              _basis[f.key] = basis;
              if (basis == 'percent_of_declared_value') {
                _declaredValueCtrl[f.key]?.text =
                    _money(_num(m['declaredValue']) ?? 0);
                _pctCtrl[f.key]?.text = _money(_num(m['rate']) ?? 0);
              } else {
                _rateCtrl[f.key]?.text = _money(_num(m['rate']) ?? 0);
                // per_cft reads _totalCft live, so its qty is derived and
                // must NOT be restored — writing it would pin a stale CFT.
                if (basis != 'per_cft') {
                  _qtyCtrl[f.key]?.text = _money(_num(m['qty']) ?? 0);
                }
              }
            }
          } else {
            final n = _num(v);
            if (n != null && n != 0) _amountCtrl[f.key]?.text = _money(n);
          }
        }

        final modes = charges['_billingMode'];
        if (modes is Map) {
          for (final e in modes.entries) {
            _billingMode[e.key.toString()] = e.value.toString();
          }
        }
        final gstType = charges['_gstType'];
        if (gstType is String && gstType.isNotEmpty) _gstType = gstType;
        final pct = q.gstPct;
        if (pct != null) _gstPct = pct.toDouble();

        // ---- package ----
        // Restored as an OVERRIDE, not as a suggestion. The stored values
        // are what this quote was actually issued with; re-deriving them
        // from today's slab table would let a slab edit rewrite a quote
        // that is already in a customer's hands.
        _chosenPackage = q.chosenPackage;
        _chosenVehicle = q.chosenVehicle;
        _chosenCrew = q.chosenCrew;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loadFailed =
            'That quotation could not be loaded. Check your connection and '
            'try again — saving now would overwrite it with an empty quote.');
      }
    }
  }

  /// Controller text for a stored number: trims a pointless `.0` so a
  /// reloaded field reads the way the vendor typed it.
  /// Tolerant number read for jsonb that may hold a number or a string.
  static num? _num(dynamic v) => v is num ? v : num.tryParse('$v');

  static String _money(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();


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

  /// Item 12B-b: this used to be `packageInfoForCft(...)`, which fell back
  /// to `packages.first` when a slab's package name didn't resolve — a
  /// renamed package silently suggested a 7 Ft tempo and 2 crew for a
  /// 400 CFT move, and nothing errored. [suggestPackage] reports that case
  /// instead; [_packageCard] renders it as the configuration fault it is.
  PackageSuggestion get _suggestion => _config == null
      ? const PackageSuggestion.empty()
      : suggestPackage(_totalCft, _config!.cftRanges, _config!.packages);

  /// What the quote will actually be saved with: the override where the
  /// surveyor set one, otherwise the suggestion.
  String? get _effectivePackage =>
      _chosenPackage ?? _suggestion.info?.type;
  String? get _effectiveVehicle =>
      _chosenVehicle ?? _suggestion.info?.vehicle;
  int? get _effectiveCrew => _chosenCrew ?? _suggestion.info?.crew;

  double get _subtotal {
    double s = 0;
    for (final f in kDefaultChargeFields) {
      if (f.key == 'discount') continue;
      // An advance is money the customer has ALREADY PAID. It is not a
      // charge, and adding it here billed them for it a second time and
      // then charged GST on top: 28,000 freight + 8,000 advance produced a
      // 36,000 taxable value and a 37,800 total (found 2 Sep 2026, live).
      // The field was already excluded from the "other charges" list in
      // _chargesCard - only the total had never been told.
      if (f.key == 'advanceOnQuote') continue;
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
    // Edit mode that never loaded must not be saveable: an empty form
    // written through revise_quote() would replace a real quote's items
    // and price with nothing, and consume a version number saying so.
    if (_loadFailed != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_loadFailed!)));
      return;
    }
    if (_isEditing && _editing == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Still loading this quotation — try again in a '
              'moment.')));
      return;
    }
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
      // `_gstShowInPdf` was written here until 10 Sept 2026. Nothing ever
      // read the key — see the note at the removed switch. Existing quotes
      // keep whatever value they were saved with; it is inert either way.
      // Item 12C: the package now lives in real columns (below). This key
      // is still written because existing readers depend on it —
      // quote_pdf.dart and lead_detail_page's order snapshot — and older
      // quotes only have this. It carries the EFFECTIVE value (override
      // where set), which is what those readers have always meant by it.
      charges['_suggestedPackage'] = _effectivePackage;
      charges['_totalCft'] = _totalCft;
      charges['_totalItems'] = _totalItems;

      final suggestion = _suggestion;

      // ---- EDIT MODE: one action, one version row --------------------
      // Everything above this point is identical for a new quote and a
      // revision, deliberately: the snapshot a revision sends is the
      // same complete priced state a new quote would be saved with.
      // There is no partial-patch path here and there must not be one —
      // the RPC takes the whole snapshot or nothing.
      if (_isEditing) {
        await _saveRevision(items: items, charges: charges);
        return;
      }

      await QuotationsTable().insert({
        'id': const Uuid().v4(),
        'token': _hexToken(),
        ...OrgScope.stamp(),
        'lead_id': widget.leadId,
        // Which survey this quote came from. Gated: until the FK is
        // repointed at `surveys` this must stay absent, or the insert is
        // rejected outright — see kQuotationSurveyIdFkRepointed.
        if (kQuotationSurveyIdFkRepointed && widget.surveyId != null)
          'survey_id': widget.surveyId,
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
        // Item 12C — suggestion and choice, both frozen at save time so a
        // later slab edit can never rewrite a quote that's already out.
        'total_cft': _totalCft,
        'suggested_package': suggestion.info?.type,
        'suggested_vehicle': suggestion.info?.vehicle,
        'suggested_crew': suggestion.info?.crew,
        'chosen_package': _effectivePackage,
        'chosen_vehicle': _effectiveVehicle,
        'chosen_crew': _effectiveCrew,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quotation saved.')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        // revise_quote() raises P0001 with a real sentence — "This quote
        // already has an order against it, so a revision needs a reason."
        // Surfaced verbatim; anything else falls back, so Postgres
        // internals never reach a vendor.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(extractDbErrorMessage(e,
              fallback: _isEditing
                  ? 'Could not save the revision: $e'
                  : 'Could not save quotation: $e')),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Saves a revision through `revise_quote()`.
  ///
  /// THE RPC OWNS THE RULES, NOT THIS SCREEN. Whether a reason is
  /// mandatory, what changed, how the change is summarised, which version
  /// number this becomes and whether the quote's status moves are all
  /// decided in Postgres. Nothing here re-implements any of them — two
  /// places deciding one rule is how they come to disagree, and the
  /// database is the half that cannot be bypassed by a stale build.
  ///
  /// So the reason is asked for OPTIONALLY and sent as typed. If the RPC
  /// requires one and none was given it refuses with a real sentence,
  /// which is surfaced verbatim.
  Future<void> _saveRevision({
    required List<Map<String, dynamic>> items,
    required Map<String, dynamic> charges,
  }) async {
    final reason = await _askReason();
    // Cancelled the prompt — not an error, just a change of mind.
    if (reason == null) return;

    final snapshot = <String, dynamic>{
      'items': items,
      'charges': charges,
      'subtotal': _subtotal,
      'gst_pct': _gstPct,
      'gst_amount': _gstAmount,
      'total': _total,
      'total_cft': _totalCft,
      'chosen_package': _effectivePackage,
      'chosen_vehicle': _effectiveVehicle,
      'chosen_crew': _effectiveCrew,
    };

    final res = await SupaFlow.client.rpc('revise_quote', params: {
      'p_quote_id': widget.quotationId,
      'p_snapshot': snapshot,
      'p_reason': reason.isEmpty ? null : reason,
    });

    if (!mounted) return;
    final map = res is Map ? Map<String, dynamic>.from(res) : const {};
    final version = map['version'];
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(version == null
          ? 'Quotation revised.'
          : 'Saved as v$version. ${map['change_summary'] ?? ''}'.trim()),
      duration: const Duration(seconds: 4),
    ));
    Navigator.of(context).pop(true);
  }

  /// Asks for the revision reason. Returns null if the vendor backed out,
  /// '' if they chose to give none.
  ///
  /// Always offered, never conditionally shown. The screen cannot know
  /// whether a reason is required — that depends on whether a live order
  /// references this quote, which is a database question — and a prompt
  /// that appears only sometimes trains people to dismiss it.
  Future<String?> _askReason() async {
    final ctrl = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Why is this quote changing?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recorded against this revision, permanently. Required once '
              'the job has been booked.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'e.g. customer added a fridge and a two-wheeler',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(ctrl.text.trim()),
            child: const Text('Save revision'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final ng = NgPalette.of(context);
    return Scaffold(
      backgroundColor: ng.bg,
      appBar: NgSimpleBar(title: _isEditing ? 'Revise Quotation' : 'Survey & Quote', close: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // A revision that failed to load says so at the top and
                  // the save button refuses. Silence here would leave a
                  // blank form that looks ready to save over a real quote.
                  if (_loadFailed != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: ng.redBg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_rounded,
                              size: 18, color: ng.red),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(_loadFailed!,
                                  style: NgFonts.geist(
                                      fontSize: 13, color: ng.red))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  _customerCard(ng),
                  const SizedBox(height: 14),
                  _packageCard(ng),
                  const SizedBox(height: 18),
                  NgGroupTitle('Items',
                      actionLabel: 'Custom item',
                      onAction: () => _addCustomItem()),
                  _itemSearchBar(ng),
                  const SizedBox(height: 10),
                  _customItemsSection(ng),
                  // Item 12A: the picker shows active items only. Items
                  // already on this quote resolve through `surveyCats`
                  // (unfiltered) elsewhere, so hiding one never breaks a
                  // quote in progress.
                  ..._config!.activeSurveyCats.entries
                      .map((e) => _categorySection(ng, e.key, e.value)),
                  if (_search.isNotEmpty && !_anySearchMatch())
                    NgEmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No items match "$_search"',
                      action: NgLinkButton('Add "$_search" as a custom item',
                          icon: Icons.add_rounded,
                          onTap: () => _addCustomItem(preset: _search)),
                    ),
                  const SizedBox(height: 14),
                  _chargesCard(ng),
                  const SizedBox(height: 14),
                  _gstCard(ng),
                  const SizedBox(height: 14),
                  _summaryCard(ng),
                ],
              ),
            ),
      bottomNavigationBar: _loading
          ? null
          : NgBottomActionBar(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$_totalItems items · $_totalCft CFT',
                            style:
                                NgFonts.geist(fontSize: 12, color: ng.mute)),
                        Text(functions.inrFull(_total.toDouble()),
                            style: NgFonts.mono(
                                fontSize: 19,
                                fontWeight: FontWeight.w600,
                                color: ng.text)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 170,
                    child: NgPrimaryButton(
                      icon: Icons.check_rounded,
                      label: _saving
                          ? 'Saving…'
                          : _isEditing
                              ? 'Save revision'
                              : 'Save quote',
                      onPressed: _saving ? null : _save,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _card(NgPalette ng, String title, Widget child) => NgCard(
        radius: 20,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: NgFonts.geist(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: ng.text)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );

  Widget _customerCard(NgPalette ng) => _card(
        ng,
        'Customer',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // IDENTITY IS READ-ONLY WHILE REVISING, and this is the UI
            // half of a rule enforced in the database: revise_quote()'s
            // explicit column list does not include customer, phone or
            // either address, so a change typed here would be silently
            // discarded. Showing an editable field that cannot save is
            // worse than showing a locked one — the vendor would believe
            // the correction had been made.
            //
            // Correcting a customer's name is also not a quote revision
            // and must not consume a version number. It belongs on the
            // lead, which is where the fields came from.
            if (_isEditing)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  Icon(Icons.lock_outline_rounded, size: 15, color: ng.mute),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Customer details are fixed while revising — change '
                      'them on the lead.',
                      style: NgFonts.geist(fontSize: 12.5, color: ng.mute),
                    ),
                  ),
                ]),
              ),
            NgInput(
                controller: _customer,
                readOnly: _isEditing,
                label: 'Customer name'),
            const SizedBox(height: 10),
            NgInput(
                controller: _phone,
                readOnly: _isEditing,
                label: 'Phone',
                keyboardType: TextInputType.phone,
                mono: true),
            const SizedBox(height: 10),
            NgInput(
                controller: _fromAddr,
                readOnly: _isEditing,
                label: 'From city / address',
                icon: Icons.trip_origin_rounded),
            const SizedBox(height: 10),
            NgInput(
                controller: _toAddr,
                readOnly: _isEditing,
                label: 'To city / address',
                icon: Icons.place_outlined),
          ],
        ),
      );

  Widget _packageCard(NgPalette ng) {
    final s = _suggestion;
    final isError = s.isConfigError;
    // A broken slab table is a configuration fault, not a quoting problem —
    // it gets the error treatment and a route to the fix, but never blocks
    // the quote (the surveyor still knows what truck they need; the app
    // just can't tell them).
    final accent = isError ? ng.red : ng.acc;

    return Container(
      decoration: BoxDecoration(
        color: isError ? ng.redBg : ng.status(NgStatus.accent).bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isError) ...[
                Icon(Icons.warning_amber_rounded, size: 18, color: ng.red),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text('$_totalItems items · $_totalCft CFT',
                    style: NgFonts.geist(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: ng.text)),
              ),
              if (!isError && !s.empty)
                NgLinkButton(_hasOverride ? 'Change' : 'Override',
                    icon: Icons.edit_rounded, onTap: _editSuggestion),
            ],
          ),
          const SizedBox(height: 4),
          if (s.empty)
            Text('Add items to see a suggested package',
                style: NgFonts.geist(
                    fontSize: 12.5, color: ng.mute))
          else if (isError) ...[
            Text(
              '$_totalCft CFT falls in the slab named '
              '"${s.unresolvedPackageName}", but no vehicle and crew are '
              'defined for it. This quote can still be saved — it just '
              'won\'t carry a suggestion.',
              style: NgFonts.geist(
                  fontSize: 12.5, height: 1.35, color: ng.text),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                NgLinkButton('Fix in Settings',
                    icon: Icons.settings_outlined,
                    onTap: () =>
                        context.pushNamed(SurveyPricingPage.routeName)),
                NgLinkButton('Set manually',
                    icon: Icons.edit_rounded, onTap: _editSuggestion),
              ],
            ),
          ] else ...[
            Text(
              'Suggested: ${s.info!.type} · ${s.info!.crew} crew · ${s.info!.vehicle}',
              style: NgFonts.geist(
                  fontSize: 12.5,
                  color: ng.mute,
                  decoration:
                      _hasOverride ? TextDecoration.lineThrough : null),
            ),
          ],
          if (_hasOverride) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.check_circle, size: 14, color: ng.acc),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Using: ${_effectivePackage ?? '—'} · '
                    '${_effectiveCrew ?? '—'} crew · '
                    '${_effectiveVehicle?.isNotEmpty == true ? _effectiveVehicle : '—'}',
                    style: NgFonts.geist(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: ng.text),
                  ),
                ),
                NgLinkButton('Reset',
                    onTap: () => setState(() {
                          _chosenPackage = null;
                          _chosenVehicle = null;
                          _chosenCrew = null;
                        })),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Item 12C — the override affordance. Seeded from the suggestion so
  /// tweaking one field (usually crew) doesn't mean re-typing the rest.
  Future<void> _editSuggestion() async {
    final s = _suggestion;
    final pkgCtrl =
        TextEditingController(text: _chosenPackage ?? s.info?.type ?? '');
    final vehCtrl =
        TextEditingController(text: _chosenVehicle ?? s.info?.vehicle ?? '');
    final crewCtrl = TextEditingController(
        text: '${_chosenCrew ?? s.info?.crew ?? ''}');

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Package, vehicle & crew'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Overrides the suggestion for this quote only. The suggested '
              'values are kept alongside, so the vendor can see where the '
              'slabs need adjusting.',
              style: NgFonts.geist(fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pkgCtrl,
              decoration: const InputDecoration(labelText: 'Package'),
            ),
            TextField(
              controller: vehCtrl,
              decoration: const InputDecoration(labelText: 'Vehicle'),
            ),
            TextField(
              controller: crewCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Crew'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Use these')),
        ],
      ),
    );
    if (saved != true) return;

    setState(() {
      // Only record a field as overridden where it actually differs from
      // the suggestion — otherwise a surveyor who opens the dialog and
      // presses "Use these" would mark an override that changed nothing.
      final pkg = pkgCtrl.text.trim();
      final veh = vehCtrl.text.trim();
      final crew = int.tryParse(crewCtrl.text.trim());
      _chosenPackage = (pkg.isEmpty || pkg == s.info?.type) ? null : pkg;
      _chosenVehicle = (veh.isEmpty || veh == s.info?.vehicle) ? null : veh;
      _chosenCrew = (crew == null || crew == s.info?.crew) ? null : crew;
    });
  }

  Widget _itemSearchBar(NgPalette ng) {
    return Row(
      children: [
        Expanded(
          child: NgSearchField(
            controller: _itemSearch,
            hint: 'Search items…',
            onChanged: (v) => setState(() => _search = v.trim()),
          ),
        ),
        if (_search.isNotEmpty) ...[
          const SizedBox(width: 8),
          NgHeaderButtonBox(
            icon: Icons.close_rounded,
            tooltip: 'Clear search',
            onTap: () {
              _itemSearch.clear();
              setState(() => _search = '');
            },
          ),
        ],
      ],
    );
  }

  /// True if anything in the catalogue (or the custom list) survives the
  /// current search — drives the "no matches, add it as custom" prompt.
  bool _anySearchMatch() {
    for (final c in _customItems) {
      if (_matchesSearch(_kCustomCat, c.name, 'Qty')) return true;
    }
    for (final entry in _config!.activeSurveyCats.entries) {
      for (final item in entry.value) {
        if (_visibleSubs(item).isNotEmpty) return true;
      }
    }
    return false;
  }

  Widget _customItemsSection(NgPalette ng) {
    final visible = _customItems
        .where((c) => _matchesSearch(_kCustomCat, c.name, 'Qty'))
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NgCard(
        radius: 20,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
              child: Text(_kCustomCat,
                  style: NgFonts.geist(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: ng.text)),
            ),
            for (final c in visible) _customItemRow(ng, c),
          ],
        ),
      ),
    );
  }

  Widget _customItemRow(NgPalette ng, ({String name, num cft}) c) {
    final key = '$_kCustomCat|${c.name}|Qty';
    final qty = _qtyOf(key);
    final zeroCft = c.cft <= 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
      decoration: BoxDecoration(
        color: qty > 0 ? ng.status(NgStatus.accent).bg : ng.inset,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: zeroCft && qty > 0
                ? ng.amber
                : qty > 0
                    ? ng.acc.withValues(alpha: 0.6)
                    : ng.w06),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: c.name),
                        TextSpan(
                            text: '  ${c.cft} CFT',
                            style: NgFonts.mono(fontSize: 12, color: ng.mute)),
                      ]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: NgFonts.geist(fontSize: 13.5, color: ng.text)),
                ),
                // Make a 0-CFT line obvious at the point of entry, not
                // only at save time.
                if (zeroCft) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'No CFT — will not count towards the package',
                    child: Icon(Icons.warning_amber_rounded,
                        size: 16, color: ng.amber),
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
              icon: Icon(Icons.delete_outline, size: 18, color: ng.red),
              onPressed: () => setState(() {
                _customItems.removeWhere((x) => x.name == c.name);
                _lines.remove(key);
              }),
            ),
          ),
          _stepper(
            ng,
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
      NgPalette ng, String cat, List<SurveyItem> items) {
    // Hide a whole category when nothing in it matches the search.
    final visibleItems =
        items.where((i) => _visibleSubs(i).isNotEmpty).toList();
    if (visibleItems.isEmpty) return const SizedBox.shrink();
    final picked = _lines.entries
        .where((e) => e.value.cat == cat && e.value.qty > 0)
        .fold<int>(0, (s, e) => s + e.value.qty);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: ng.s1,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ng.w06),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(16, 2, 12, 2),
          iconColor: ng.mute,
          collapsedIconColor: ng.mute,
          trailing: picked > 0
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  NgPill('$picked', status: NgStatus.accent),
                  const SizedBox(width: 4),
                  Icon(Icons.expand_more_rounded, color: ng.mute),
                ])
              : null,
          // Auto-expand while searching so matches are visible without
          // having to open each category by hand. The ValueKey forces
          // ExpansionTile to rebuild its state when the search toggles,
          // since initiallyExpanded is only read on first build.
          key: ValueKey('$cat-${_search.isNotEmpty}'),
          initiallyExpanded: _search.isNotEmpty,
          title: Text(cat,
              style: NgFonts.geist(
                  fontSize: 15, fontWeight: FontWeight.w600, color: ng.text)),
          children: [
            for (final item in visibleItems) _itemRow(ng, cat, item),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _itemRow(NgPalette ng, String cat, SurveyItem item) {
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
              style: NgFonts.geist(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  color: ng.soft)),
          const SizedBox(height: 6),
          // Was a `Wrap` of intrinsic-width pills. Because each pill sized
          // itself to its own label ("Top Load (15 cft)" vs "Small (5
          // cft)"), the rows came out ragged and the +/- controls sat at a
          // different x on every line — the misalignment reported from the
          // phone. Now every variant is a full-width row: label flexes on
          // the left, the stepper is a fixed-width cluster pinned right,
          // so all the controls line up in one column.
          for (final sub in subs) _variantRow(ng, cat, item.name, sub),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _variantRow(
      NgPalette ng, String cat, String itemName, SurveySubItem sub) {
    final key = '$cat|$itemName|${sub.label}';
    final qty = _qtyOf(key);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
      decoration: BoxDecoration(
        color: qty > 0 ? ng.status(NgStatus.accent).bg : ng.inset,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: qty > 0 ? ng.acc.withValues(alpha: 0.6) : ng.w06),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: sub.label),
                TextSpan(
                    text: '  ${sub.cft} CFT',
                    style: NgFonts.mono(fontSize: 12, color: ng.mute)),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: NgFonts.geist(fontSize: 13.5, color: ng.text),
            ),
          ),
          const SizedBox(width: 8),
          _stepper(
            ng,
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
    NgPalette ng, {
    required int qty,
    required VoidCallback? onMinus,
    required VoidCallback onPlus,
  }) {
    Widget btn(IconData icon, VoidCallback? onTap) => SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Material(
              color: onTap == null ? Colors.transparent : ng.s2,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Icon(icon,
                      size: 18, color: onTap == null ? ng.faint : ng.text),
                ),
              ),
            ),
          ),
        );
    return SizedBox(
      width: 118,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          btn(Icons.remove_rounded, onMinus),
          SizedBox(
            width: 26,
            child: Text('$qty',
                textAlign: TextAlign.center,
                style: NgFonts.mono(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: qty > 0 ? ng.text : ng.faint)),
          ),
          btn(Icons.add_rounded, onPlus),
        ],
      ),
    );
  }

  Widget _amountField(NgPalette ng, String key, String label,
      {bool enabled = true}) {
    return TextField(
      controller: _amountCtrl[key],
      enabled: enabled,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, isDense: true),
      // Was missing — Subtotal/GST/Total are getters read straight off
      // these controllers at build time, so with no onChanged the typed
      // figure only appeared once some UNRELATED control (the GST
      // toggle, a dropdown) happened to trigger a rebuild. A vendor
      // could type a freight amount, see Total stay ₹0, and have no way
      // to know the number was actually being recorded correctly.
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _chargesCard(NgPalette ng) {
    final billable = kDefaultChargeFields.where((f) => f.billable).toList();
    final other = kDefaultChargeFields
        .where((f) => !f.billable && f.key != 'discount' && f.key != 'advanceOnQuote')
        .toList();
    return _card(
      ng,
      'Charges',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Freight / Transport',
              style: NgFonts.geist(fontSize: 13, color: ng.text)),
          const SizedBox(height: 6),
          _basisRow(ng, 'transport'),
          const SizedBox(height: 10),
          _amountField(ng, 'advanceOnQuote', 'Advance Paid'),
          const SizedBox(height: 14),
          // Arun, 3 Sept 2026: "add price separately packing achrag,
          // loading , unloading". The prices existed from that day; what
          // was missing was any sign they did. Every line defaults to
          // "Incl. in Freight", which hides its price box, so the feature
          // was invisible unless you already knew to go looking for it -
          // and the only label saying otherwise was 11.5px grey text.
          Text('Packing & Labour',
              style: NgFonts.geist(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ng.text)),
          const SizedBox(height: 2),
          Text(
            'Each line is bundled into the freight price unless you switch '
            'it to "Bill separately", which opens its own price field.',
            style: NgFonts.geist(
                fontSize: 11.5, color: ng.mute, height: 1.35),
          ),
          const SizedBox(height: 10),
          for (final f in billable) _billableRow(ng, f),
          if (_separatelyBilledCount > 0) ...[
            const SizedBox(height: 2),
            Text(
              '$_separatelyBilledCount of ${billable.length} billed '
              'separately${_separatelyBilledUnpriced > 0 ? ' · '
                  '$_separatelyBilledUnpriced still to price' : ''}',
              style: NgFonts.geist(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _separatelyBilledUnpriced > 0
                      ? ng.amber
                      : ng.mute),
            ),
          ],
          const SizedBox(height: 14),
          Text('Other Charges',
              style: NgFonts.geist(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: ng.mute)),
          const SizedBox(height: 8),
          for (final f in other.where((f) =>
              ['storage', 'carTransport', 'misc', 'stCharge', 'otherCharges']
                  .contains(f.key)))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _amountField(ng, f.key, f.label),
            ),
          const SizedBox(height: 6),
          Text('Add-on Services',
              style: NgFonts.geist(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: ng.mute)),
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
              child: _amountField(ng, f.key, f.label),
            ),
          const SizedBox(height: 6),
          _amountField(ng, 'discount', 'Discount'),
        ],
      ),
    );
  }

  /// What the vendor has typed against a charge line, or 0.
  double _chargeAmount(String key) =>
      double.tryParse(_amountCtrl[key]?.text.trim() ?? '') ?? 0;

  /// Never invents a figure — an unpriced line says so in words rather
  /// than showing a plausible zero, which reads as a decision. Same rule
  /// as the commission work: a blank is visibly unfinished, a number is
  /// not.
  String _chargeAmountLabel(String key) {
    final v = _chargeAmount(key);
    return v > 0 ? '\u20B9${v.toStringAsFixed(0)}' : 'Not priced yet';
  }

  /// The five packing/labour lines the vendor has moved off freight.
  int get _separatelyBilledCount => _billingMode.entries
      .where((e) => e.value == 'additional')
      .length;

  /// Of those, the ones still carrying no price. Surfaced because
  /// switching a line and then not pricing it is the easy mistake: it
  /// looks handled, and bills nothing.
  int get _separatelyBilledUnpriced => _billingMode.entries
      .where((e) => e.value == 'additional' && _chargeAmount(e.key) <= 0)
      .length;

  Widget _billableRow(NgPalette ng, ChargeField f) {
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(f.label,
                        style: NgFonts.geist(
                            fontSize: 14, color: ng.text)),
                    // The figure, on the row, once there is one. Without
                    // it a priced line looks exactly like an unpriced one
                    // until you scroll into its expanded fields.
                    if (!included)
                      Text(
                        _chargeAmountLabel(f.key),
                        style: NgFonts.geist(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: _chargeAmount(f.key) > 0
                              ? ng.acc
                              : ng.amber,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                // "Bill separately" names the action, and the action is
                // what opens the price box.
                child: NgSegmented(
                  labels: const ['In freight', 'Separately'],
                  selected: included ? 0 : 1,
                  onSelect: (i) => setState(() =>
                      _billingMode[f.key] = i == 0 ? 'included' : 'additional'),
                ),
              ),
            ],
          ),
          // Basis + amount only matter once this line is actually charged
          // separately — a line bundled into freight has nothing to price
          // on its own (Part 8 Rev B item 4).
          if (!included) ...[
            const SizedBox(height: 6),
            _basisRow(ng, f.key),
          ],
        ],
      ),
    );
  }

  /// Basis dropdown + whatever value fields that basis needs (Part 8 Rev
  /// B item 4). Shared between the 5 billable rows above and the
  /// transport row below — transport has no included/additional toggle
  /// (it's never bundled into itself) but still gets a basis.
  Widget _basisRow(NgPalette ng, String key) {
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
        Expanded(flex: 3, child: _basisValueFields(ng, key, basis)),
      ],
    );
  }

  Widget _basisValueFields(NgPalette ng, String key, String basis) {
    switch (basis) {
      case 'per_cft':
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text('$_totalCft CFT',
                  style: NgFonts.geist(
                      fontSize: 12.5, color: ng.mute)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _rateCtrl[key],
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: '₹/CFT', isDense: true),
                onChanged: (_) => setState(() {}),
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
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _rateCtrl[key],
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Rate', isDense: true),
                onChanged: (_) => setState(() {}),
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
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _pctCtrl[key],
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '%', isDense: true),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        );
      case 'lumpsum':
      case 'at_actuals':
      default:
        return _amountField(ng, key, '₹');
    }
  }

  Widget _gstCard(NgPalette ng) => _card(
        ng,
        'GST (SAC $kGstSac)',
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const NgFieldLabel('Rate'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in kGstRateOptions)
                NgChip(
                  label: '$r%',
                  selected: _gstPct == r.toDouble(),
                  onTap: () => setState(() => _gstPct = r.toDouble()),
                ),
            ]),
            const SizedBox(height: 14),
            const NgFieldLabel('Type'),
            NgSegmented(
              labels: const ['Auto', 'CGST+SGST', 'IGST'],
              selected: const ['auto', 'intra', 'inter'].indexOf(_gstType) < 0
                  ? 0
                  : const ['auto', 'intra', 'inter'].indexOf(_gstType),
              onSelect: (i) =>
                  setState(() => _gstType = const ['auto', 'intra', 'inter'][i]),
            ),
            const SizedBox(height: 12),
            // A "Show GST in PDF" switch stood here and was REMOVED on
            // 10 Sept 2026, not wired up. It had no consumer: it wrote
            // `charges['_gstShowInPdf']`, and `quote_pdf.dart` never read
            // that key and carries no GST conditional at all. A vendor
            // turned it off and the PDF still showed GST — a control that
            // silently does nothing, the same trust damage as the invented
            // demo data and the dead "Add Expense" button.
            //
            // Deleted rather than implemented deliberately. What a
            // GST-suppressed document should BE — bill of supply, exempt
            // supply, reverse charge — is a CA question, still open
            // alongside the GSTIN and place-of-supply items. Wiring the
            // switch to hide the GST rows would produce a document headed
            // "BILL (TAX INVOICE)" with the tax silently omitted, which is
            // worse than the no-op it replaced. Restore this only with the
            // answer in hand.
            NgPill(
              _isInterstate
                  ? 'Interstate · IGST ₹${_gstAmount.toStringAsFixed(0)}'
                  : 'Intrastate · CGST ₹${(_gstAmount / 2).toStringAsFixed(0)} '
                      '+ SGST ₹${(_gstAmount / 2).toStringAsFixed(0)}',
              status: NgStatus.accent,
            ),
          ],
        ),
      );

  Widget _summaryCard(NgPalette ng) {
    final rows = <(String, double)>[
      ('Subtotal', _subtotal),
      ('GST (${_gstPct.toStringAsFixed(0)}%)', _gstAmount),
    ];
    return NgCard(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in rows)
            NgKeyValue(r.$1, functions.inrFull(r.$2.toDouble()), mono: true),
          Divider(height: 18, color: ng.w06),
          NgKeyValue('Total', functions.inrFull(_total.toDouble()),
              mono: true, strong: true),
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
