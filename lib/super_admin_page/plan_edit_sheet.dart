import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';

/// Create/edit sheet for a subscription_plans row. The limits/features
/// keys edited here are exactly the ones the app actually reads — grepped
/// before writing this, not invented:
///   limits:   max_users (enforced, see AppSession.isOverLimit in
///             users_page_widget.dart), max_orders, max_leads (both
///             display-only on PlanPage today, not yet enforced anywhere)
///   features: whatsapp, reports, invoice, fleet, salary (all display-only
///             on PlanPage today via AppSession.hasFeature - nothing else
///             gates on them yet)
/// -1 in a limit field means unlimited (PlanPageWidget._limitRow's
/// existing convention).
class PlanEditSheet extends StatefulWidget {
  const PlanEditSheet({super.key, this.existing, required this.otherPlans});

  /// Null = create mode.
  final SubscriptionPlansRow? existing;

  /// Every other existing plan, used only to check the is_default_trial
  /// guard (can't unset the last remaining default).
  final List<SubscriptionPlansRow> otherPlans;

  /// Returns true if a plan was saved (caller should reload the list).
  static Future<bool> show(
    BuildContext context, {
    SubscriptionPlansRow? existing,
    required List<SubscriptionPlansRow> otherPlans,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          PlanEditSheet(existing: existing, otherPlans: otherPlans),
    );
    return saved == true;
  }

  @override
  State<PlanEditSheet> createState() => _PlanEditSheetState();
}

class _PlanEditSheetState extends State<PlanEditSheet> {
  static const _limitKeys = ['max_users', 'max_orders', 'max_leads'];

  // Toggles shown for these specific keys. Corrected 27 Jul 2026 after
  // live-testing this editor against nagarva-demo's real plans: the
  // original list here (whatsapp/reports/invoice/fleet/salary) was taken
  // from plan_page_widget.dart's _featureLabel map, which turned out to
  // be a purely cosmetic label lookup, not the real key set — the live
  // data actually uses `gst_invoice` (not `invoice`) and `multi_branch`
  // (not present in that map at all); `fleet`/`salary` don't appear on
  // any real plan. Caught before ever saving anything, by reading the
  // live Plans tab before opening the editor.
  static const _featureKeys = <String, String>{
    'whatsapp': 'WhatsApp Alerts',
    'reports': 'P&L Reports',
    'gst_invoice': 'GST Invoice',
    'multi_branch': 'Multi-Branch',
  };

  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _price;
  late String _billingPeriod;
  late bool _isDefaultTrial;
  late final Map<String, TextEditingController> _limitCtrls;
  late final Map<String, bool> _featureValues;

  // Full original limits/features jsonb, kept so save() can merge its
  // edits on top instead of replacing the whole object — protects any
  // key this editor doesn't know about (there was already one real
  // example, multi_branch, before the correction above) from being
  // silently dropped on save.
  late final Map<String, dynamic> _originalLimits;
  late final Map<String, dynamic> _originalFeatures;

  bool _saving = false;
  String? _error;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _code = TextEditingController(text: p?.code ?? '');
    _name = TextEditingController(text: p?.name ?? '');
    _price = TextEditingController(
        text: p?.priceInr != null ? p!.priceInr!.toStringAsFixed(0) : '');
    _billingPeriod = p?.billingPeriod ?? 'monthly';
    _isDefaultTrial = p?.isDefaultTrial ?? false;

    _originalLimits =
        (p?.limits is Map) ? Map<String, dynamic>.from(p!.limits as Map) : {};
    _limitCtrls = {
      for (final k in _limitKeys)
        k: TextEditingController(
            text: _originalLimits[k] != null
                ? _originalLimits[k].toString()
                : ''),
    };

    _originalFeatures = (p?.features is Map)
        ? Map<String, dynamic>.from(p!.features as Map)
        : {};
    _featureValues = {
      for (final k in _featureKeys.keys) k: _originalFeatures[k] == true,
    };
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _price.dispose();
    for (final c in _limitCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    // Guard: refuse to unset is_default_trial if this is the only plan
    // that has it — otherwise a new signup resolves no plan at all
    // (signup_page_widget.dart looks up is_default_trial = true with no
    // fallback).
    if (isEdit &&
        (widget.existing!.isDefaultTrial ?? false) &&
        !_isDefaultTrial &&
        !widget.otherPlans.any((p) => p.isDefaultTrial ?? false)) {
      setState(() => _error =
          'At least one plan must be the default trial plan — set another plan as default first.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Merge onto the original jsonb rather than replacing it outright —
      // this editor only shows a fixed set of known keys, and the plan
      // row can (and, live, already does for multi_branch) have other
      // keys this UI has never heard of. Merging means those survive a
      // save unchanged instead of quietly vanishing.
      final limits = <String, dynamic>{..._originalLimits};
      for (final k in _limitKeys) {
        if (_limitCtrls[k]!.text.trim().isNotEmpty) {
          limits[k] = int.tryParse(_limitCtrls[k]!.text.trim()) ?? -1;
        }
      }
      final features = <String, dynamic>{
        ..._originalFeatures,
        for (final k in _featureKeys.keys) k: _featureValues[k],
      };
      final data = {
        'code': _code.text.trim().isEmpty ? null : _code.text.trim(),
        'name': _name.text.trim(),
        'price_inr': double.tryParse(_price.text.trim()),
        'billing_period': _billingPeriod,
        'is_default_trial': _isDefaultTrial,
        'limits': limits,
        'features': features,
      };

      // If this plan is becoming the default trial plan, atomically clear
      // the flag on whichever plan currently has it — subscription_plans
      // has no DB constraint enforcing "at most one default", so this app
      // pass has to keep that invariant itself, same as the is-default
      // guard above.
      if (_isDefaultTrial) {
        for (final p in widget.otherPlans) {
          if ((p.isDefaultTrial ?? false) && p.id != widget.existing?.id) {
            await SubscriptionPlansTable().update(
              data: {'is_default_trial': false},
              matchingRows: (q) => q.eq('id', p.id!),
            );
          }
        }
      }

      if (isEdit) {
        await SubscriptionPlansTable().update(
          data: data,
          matchingRows: (q) => q.eq('id', widget.existing!.id!),
        );
      } else {
        // subscription_plans.id has no confirmed DB default — generate
        // client-side rather than assume one exists. quotations.id/token
        // both turned out to lack defaults despite looking like every
        // other uuid PK in this schema, so this table gets the same
        // defensive treatment instead of finding out live a third time.
        await SubscriptionPlansTable().insert({
          'id': const Uuid().v4(),
          ...data,
          'active': true,
        });
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.primaryBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.secondaryText.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isEdit ? 'Edit Plan' : 'New Plan',
                      style: GoogleFonts.interTight(
                        color: theme.primaryText,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _code,
                    decoration: const InputDecoration(
                        labelText: 'Code (short slug, e.g. "pro")'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _price,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Price (₹)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _billingPeriod,
                          decoration:
                              const InputDecoration(labelText: 'Billing'),
                          items: const [
                            DropdownMenuItem(
                                value: 'monthly', child: Text('Monthly')),
                            DropdownMenuItem(
                                value: 'yearly', child: Text('Yearly')),
                          ],
                          onChanged: (v) =>
                              setState(() => _billingPeriod = v ?? 'monthly'),
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Default trial plan'),
                    subtitle: const Text(
                        'New signups get this plan automatically'),
                    value: _isDefaultTrial,
                    onChanged: (v) => setState(() => _isDefaultTrial = v),
                  ),
                  const SizedBox(height: 12),
                  Text('Limits',
                      style: GoogleFonts.interTight(
                          color: theme.primaryText,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  Text('-1 = unlimited',
                      style: GoogleFonts.inter(
                          color: theme.secondaryText, fontSize: 11.5)),
                  const SizedBox(height: 8),
                  for (final k in _limitKeys)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: _limitCtrls[k],
                        keyboardType:
                            const TextInputType.numberWithOptions(signed: true),
                        decoration: InputDecoration(labelText: k),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text('Features',
                      style: GoogleFonts.interTight(
                          color: theme.primaryText,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  for (final entry in _featureKeys.entries)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(entry.value),
                      value: _featureValues[entry.key] ?? false,
                      onChanged: (v) =>
                          setState(() => _featureValues[entry.key] = v),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!,
                        style: GoogleFonts.inter(
                            color: theme.error, fontSize: 13)),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(isEdit ? 'Save Changes' : 'Create Plan',
                              style: const TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
