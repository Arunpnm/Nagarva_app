import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import 'plan_edit_sheet.dart';

/// Step 1 (super-admin console): subscription_plans management. Was
/// SQL-only before this — new plans/price changes needed a manual insert.
class PlansTab extends StatefulWidget {
  const PlansTab({super.key});

  @override
  State<PlansTab> createState() => _PlansTabState();
}

class _PlansTabState extends State<PlansTab> {
  bool _loading = true;
  List<SubscriptionPlansRow> _plans = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final plans = await SubscriptionPlansTable().queryRows(
        queryFn: (q) => q.order('price_inr'),
      );
      if (mounted) setState(() => _plans = plans);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load plans: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([SubscriptionPlansRow? plan]) async {
    final otherPlans =
        _plans.where((p) => p.id != plan?.id).toList();
    final saved = await PlanEditSheet.show(context,
        existing: plan, otherPlans: otherPlans);
    if (saved) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _plans.length + 1,
        itemBuilder: (context, i) {
          if (i == _plans.length) {
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: OutlinedButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('New Plan'),
              ),
            );
          }
          final p = _plans[i];
          final limits = (p.limits is Map) ? p.limits as Map : const {};
          final features =
              (p.features is Map) ? p.features as Map : const {};
          final activeFeatures = features.entries
              .where((e) => e.value == true)
              .map((e) => e.key)
              .join(', ');
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
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
                      child: Text(
                        p.name ?? p.code ?? p.id ?? '(unnamed)',
                        style: GoogleFonts.interTight(
                            color: theme.primaryText,
                            fontSize: 15,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (p.isDefaultTrial ?? false)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('default trial',
                            style: GoogleFonts.inter(
                                color: theme.primary, fontSize: 11)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '₹${p.priceInr?.toStringAsFixed(0) ?? '—'} / ${p.billingPeriod ?? '—'}'
                  '${p.code != null ? ' · ${p.code}' : ''}',
                  style: GoogleFonts.inter(
                      color: theme.secondaryText, fontSize: 12.5),
                ),
                const SizedBox(height: 6),
                Text(
                  // Item 32 key fix — was reading `max_orders`, which no
                  // plan has ever carried (the real key is
                  // max_orders_per_month).
                  'Limits: max_users=${limits['max_users'] ?? '—'}, '
                  'max_orders_per_month=${limits['max_orders_per_month'] ?? '—'}, '
                  'max_whatsapp_per_month=${limits['max_whatsapp_per_month'] ?? '—'}',
                  style: GoogleFonts.inter(
                      color: theme.primaryText, fontSize: 12),
                ),
                if (activeFeatures.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Features: $activeFeatures',
                        style: GoogleFonts.inter(
                            color: theme.primaryText, fontSize: 12)),
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _edit(p),
                    child: const Text('Edit'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
