import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '/app_session.dart';
import '/backend/audit_log_service.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/config/app_config.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';

/// Reviews (Session 4, Part B2) — was a ComingSoonPage stub.
///
/// `reviews` (migration 001) has no generated Dart class — same
/// established pattern as `lr_register`/`quote_outcomes` before their own
/// dedicated classes existed this session; a raw `SupaFlow.client.from(...)`
/// is used directly rather than adding one more thin file for a single
/// screen's worth of reads/writes.
///
/// "Auto-trigger N hours after delivered/closed" (the brief's own wording)
/// has no background-job infrastructure to run on in this app — no cron,
/// no Edge Function scheduler exists yet. Implemented as the honest
/// client-side equivalent: a "Due for review request" section surfaces
/// every delivered/closed order past the threshold with no request sent
/// yet, one tap away from sending — not a silent background send. A real
/// scheduled trigger would need a Supabase cron job or Edge Function,
/// flagged rather than faked.
class ReviewsPageWidget extends StatefulWidget {
  const ReviewsPageWidget({super.key});

  static String routeName = 'ReviewsPage';
  static String routePath = '/reviews';

  @override
  State<ReviewsPageWidget> createState() => _ReviewsPageWidgetState();
}

class _ReviewsPageWidgetState extends State<ReviewsPageWidget>
    with RefreshOnPopMixin<ReviewsPageWidget> {
  static const _autoTriggerHours = 24;

  bool _loading = true;
  List<Map<String, dynamic>> _reviews = [];
  List<OrdersRow> _dueOrders = [];
  int? _ratingFilter;
  String? _branchFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void onPageRefresh() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final orgId = OrgScope.currentOrgId;
      final reviewRows = await SupaFlow.client
          .from('reviews')
          .select()
          .eq('org_id', orgId as Object)
          .order('created_at', ascending: false);
      _reviews = List<Map<String, dynamic>>.from(reviewRows as List);

      // Candidates for the "due" list: delivered/closed orders with no
      // review row at all yet (requested or collected), past the
      // threshold. Requested-but-not-yet-rated orders already have a row
      // (rating null, requested_at set) so they naturally drop out here.
      final requestedOrderIds = _reviews
          .map((r) => r['order_id'] as String?)
          .whereType<String>()
          .toSet();
      final cutoff = DateTime.now().subtract(const Duration(hours: _autoTriggerHours));
      final candidates = await OrdersTable().queryRows(
        queryFn: (q) => OrgScope.read(q)
            .inFilter('status', ['delivered', 'closed'])
            .order('delivered_at', ascending: false),
      );
      _dueOrders = candidates.where((o) {
        if (o.id == null || requestedOrderIds.contains(o.id)) return false;
        final at = o.deliveredAt ?? o.closedAt;
        return at != null && at.isBefore(cutoff);
      }).take(20).toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load reviews: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String> _reviewMessage(String? customerName) async {
    String? googleUrl;
    try {
      final orgId = OrgScope.currentOrgId;
      final rows = await SupaFlow.client
          .from('organizations')
          .select('google_review_url')
          .eq('id', orgId as Object)
          .maybeSingle();
      googleUrl = rows?['google_review_url'] as String?;
    } catch (_) {}
    final org = AppSession.instance.currentOrgName ?? 'Nagarva';
    final greeting = 'Hi${(customerName ?? '').isEmpty ? '' : ' $customerName'}, '
        'thank you for choosing $org! We\'d really appreciate a quick review '
        'of your experience.';
    return (googleUrl ?? '').isEmpty
        ? greeting
        : '$greeting\n$googleUrl';
  }

  Future<void> _requestReview(OrdersRow order) async {
    try {
      final message = await _reviewMessage(order.customer);
      final uri = Uri.parse(buildWhatsAppLink(phone: order.phone, message: message));
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      final orgId = OrgScope.currentOrgId;
      await SupaFlow.client.from('reviews').insert({
        'org_id': orgId,
        'order_id': order.id,
        'customer_id': order.customerId,
        'channel': 'whatsapp',
        'requested_at': DateTime.now().toIso8601String(),
        'branch': order.branch,
      });
      await AuditLogService.log(
        entityType: 'reviews',
        entityId: order.id ?? '',
        action: 'review_requested',
        newValue: {'order_id': order.id, 'channel': 'whatsapp'},
      );
      if (!mounted) return;
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(opened
              ? 'Review request sent.'
              : 'Recorded — could not open WhatsApp automatically.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not request review: $e')));
    }
  }

  List<Map<String, dynamic>> get _filteredReviews => _reviews.where((r) {
        if (_ratingFilter != null && r['rating'] != _ratingFilter) return false;
        if (_branchFilter != null && r['branch'] != _branchFilter) return false;
        return true;
      }).toList();

  double get _averageRating {
    final rated = _reviews.where((r) => r['rating'] != null).toList();
    if (rated.isEmpty) return 0;
    return rated.fold<num>(0, (s, r) => s + (r['rating'] as num)) / rated.length;
  }

  List<String> get _branches => _reviews
      .map((r) => r['branch'] as String?)
      .whereType<String>()
      .where((b) => b.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final rated = _reviews.where((r) => r['rating'] != null).length;

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        automaticallyImplyLeading: true,
        title: Text('Reviews',
            style: theme.titleLarge.override(
                font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                fontSize: 22,
                fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      _statCard(theme, 'Collected', '$rated'),
                      const SizedBox(width: 12),
                      _statCard(theme, 'Avg Rating',
                          rated == 0 ? '—' : _averageRating.toStringAsFixed(1)),
                      const SizedBox(width: 12),
                      _statCard(theme, 'Due', '${_dueOrders.length}', danger: _dueOrders.isNotEmpty),
                    ],
                  ),
                  if (_dueOrders.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Due for review request',
                        style: GoogleFonts.interTight(
                            fontSize: 14, fontWeight: FontWeight.w700, color: theme.primaryText)),
                    const SizedBox(height: 8),
                    ..._dueOrders.map((o) => _dueOrderRow(theme, o)),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text('Collected Reviews',
                          style: GoogleFonts.interTight(
                              fontSize: 14, fontWeight: FontWeight.w700, color: theme.primaryText)),
                      const Spacer(),
                      DropdownButton<int?>(
                        value: _ratingFilter,
                        hint: const Text('Rating'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All ratings')),
                          for (var i = 5; i >= 1; i--)
                            DropdownMenuItem(value: i, child: Text('$i ★')),
                        ],
                        onChanged: (v) => setState(() => _ratingFilter = v),
                      ),
                      if (_branches.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        DropdownButton<String?>(
                          value: _branchFilter,
                          hint: const Text('Branch'),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('All branches')),
                            for (final b in _branches)
                              DropdownMenuItem(value: b, child: Text(b)),
                          ],
                          onChanged: (v) => setState(() => _branchFilter = v),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_filteredReviews.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text('No reviews yet.',
                          style: GoogleFonts.inter(color: theme.secondaryText)),
                    )
                  else
                    ..._filteredReviews.map((r) => _reviewRow(theme, r)),
                ],
              ),
            ),
    );
  }

  Widget _statCard(FlutterFlowTheme theme, String label, String value, {bool danger = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.inter(fontSize: 11, color: theme.secondaryText)),
            Text(value,
                style: GoogleFonts.interTight(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: danger ? theme.error : theme.primaryText)),
          ],
        ),
      ),
    );
  }

  Widget _dueOrderRow(FlutterFlowTheme theme, OrdersRow o) {
    final at = o.deliveredAt ?? o.closedAt;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o.customer,
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(
                    'Order ${o.id} · ${at == null ? '—' : DateFormat('d MMM').format(at)}',
                    style: GoogleFonts.inter(fontSize: 11.5, color: theme.secondaryText)),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () => _requestReview(o),
            child: const Text('Request'),
          ),
        ],
      ),
    );
  }

  Widget _reviewRow(FlutterFlowTheme theme, Map<String, dynamic> r) {
    final rating = r['rating'] as int?;
    final comment = r['comment'] as String?;
    final orderId = r['order_id'] as String?;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (rating != null)
                Row(
                  children: List.generate(
                      5,
                      (i) => Icon(i < rating ? Icons.star : Icons.star_border,
                          size: 16, color: Colors.amber)),
                )
              else
                Text('Awaiting response',
                    style: GoogleFonts.inter(fontSize: 12, color: theme.secondaryText)),
              const Spacer(),
              if ((r['branch'] as String?)?.isNotEmpty ?? false)
                Text(r['branch'] as String,
                    style: GoogleFonts.inter(fontSize: 11, color: theme.secondaryText)),
            ],
          ),
          if ((comment ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(comment!, style: GoogleFonts.inter(fontSize: 12.5)),
          ],
          if (orderId != null) ...[
            const SizedBox(height: 4),
            Text('Order $orderId',
                style: GoogleFonts.inter(fontSize: 11, color: theme.secondaryText)),
          ],
        ],
      ),
    );
  }
}
