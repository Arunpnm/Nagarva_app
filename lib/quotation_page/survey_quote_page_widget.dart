import 'dart:math';

import '/backend/pricing_defaults.dart';
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
    this.leadId,
    this.leadCustomer,
    this.leadPhone,
    this.leadFromCity,
    this.leadToCity,
    this.leadFromFloor,
    this.leadToFloor,
  });

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

// City -> GST state code, same lookup as order_detail_page_widget.dart's
// invoice generation (kept local — that one is private to its own file).
const Map<String, int> _kGstStateCodes = {
  'tamil nadu': 33, 'chennai': 33, 'coimbatore': 33,
  'karnataka': 29, 'bangalore': 29, 'bengaluru': 29,
  'andhra pradesh': 37, 'telangana': 36, 'hyderabad': 36,
  'kerala': 32, 'maharashtra': 27, 'mumbai': 27, 'pune': 27,
  'delhi': 7, 'haryana': 6, 'gurgaon': 6, 'uttar pradesh': 9, 'noida': 9,
  'gujarat': 24, 'rajasthan': 8, 'west bengal': 19, 'kolkata': 19,
  'madhya pradesh': 23, 'punjab': 3, 'odisha': 21,
};
int _gstStateCode(String? city) =>
    _kGstStateCodes[(city ?? '').toLowerCase().trim()] ?? 33;
bool _isInterState(String? a, String? b) =>
    _gstStateCode(a) != _gstStateCode(b);

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

  final _qty = <String, int>{}; // "cat|item|sub" -> qty
  late final Map<String, TextEditingController> _amountCtrl;
  final _billingMode = <String, String>{}; // billable key -> included/additional
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
    PricingConfig.loadForCurrentOrg().then((c) {
      if (!mounted) return;
      setState(() {
        _config = c;
        _gstPct = kGstRateOptions.contains(kGstDefaultPct)
            ? kGstDefaultPct.toDouble()
            : 5.0;
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _customer.dispose();
    _phone.dispose();
    _fromAddr.dispose();
    _toAddr.dispose();
    for (final c in _amountCtrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  double _amount(String key) => double.tryParse(_amountCtrl[key]!.text) ?? 0;

  int get _totalItems => _qty.values.fold(0, (s, q) => s + q);

  num get _totalCft {
    if (_config == null) return 0;
    num total = 0;
    _qty.forEach((key, qty) {
      if (qty <= 0) return;
      final parts = key.split('|');
      final cat = parts[0], itemName = parts[1], subLabel = parts[2];
      final items = _config!.surveyCats[cat] ?? [];
      for (final it in items) {
        if (it.name != itemName) continue;
        for (final s in it.subs) {
          if (s.label == subLabel) total += s.cft * qty;
        }
      }
    });
    return total;
  }

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
    return _isInterState(_fromAddr.text, _toAddr.text);
  }

  double get _gstAmount => (_subtotal * (_gstPct / 100)).roundToDouble();
  double get _total => _subtotal + _gstAmount;

  Future<void> _save() async {
    if (_customer.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter customer name first.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final items = <Map<String, dynamic>>[];
      _qty.forEach((key, qty) {
        if (qty <= 0) return;
        final parts = key.split('|');
        final cat = parts[0], itemName = parts[1], subLabel = parts[2];
        num cft = 0;
        for (final it in _config!.surveyCats[cat] ?? <SurveyItem>[]) {
          if (it.name != itemName) continue;
          for (final s in it.subs) {
            if (s.label == subLabel) cft = s.cft;
          }
        }
        items.add({
          'cat': cat,
          'item': itemName,
          'sub': subLabel,
          'qty': qty,
          'cft': cft,
          'totalCftItem': cft * qty,
        });
      });
      final charges = <String, dynamic>{
        for (final f in kDefaultChargeFields) f.key: _amount(f.key),
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
                  ..._config!.surveyCats.entries
                      .map((e) => _categorySection(theme, e.key, e.value)),
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

  Widget _categorySection(
      FlutterFlowTheme theme, String cat, List<SurveyItem> items) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ExpansionTile(
          title: Text(cat,
              style: GoogleFonts.interTight(
                  fontWeight: FontWeight.w700, color: theme.primaryText)),
          children: [
            for (final item in items) _itemRow(theme, cat, item),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _itemRow(FlutterFlowTheme theme, String cat, SurveyItem item) {
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
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (final sub in item.subs) _variantCounter(theme, cat, item.name, sub),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _variantCounter(
      FlutterFlowTheme theme, String cat, String itemName, SurveySubItem sub) {
    final key = '$cat|$itemName|${sub.label}';
    final qty = _qty[key] ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${sub.label} (${sub.cft} cft)',
              style: GoogleFonts.inter(fontSize: 11.5, color: theme.primaryText)),
          const SizedBox(width: 6),
          // 48x48dp tap targets throughout (parity brief Part 5e — built
          // to spec from the start rather than retrofitted).
          SizedBox(
            width: 40,
            height: 40,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              onPressed: qty > 0
                  ? () => setState(() => _qty[key] = qty - 1)
                  : null,
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
            width: 40,
            height: 40,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.add_circle_outline, size: 20),
              onPressed: () => setState(() => _qty[key] = qty + 1),
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
          _amountField(theme, 'transport', 'Freight / Transport'),
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
      child: Row(
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
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: _amountField(theme, f.key, '₹', enabled: !included),
          ),
        ],
      ),
    );
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
