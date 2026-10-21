import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '/backend/audit_log_service.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/config/app_config.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/backend/vendor_identity.dart';

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
    final org = VendorIdentity.forSentence;
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
    final c = NgPalette.of(context);
    final rated = _reviews.where((r) => r['rating'] != null).length;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: NgTopBar(onRefresh: _load),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  const NgModuleHeader('Reviews'),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _statCard('Collected', '$rated', c.text),
                      const SizedBox(width: 8),
                      _statCard(
                          'Avg rating',
                          rated == 0 ? '—' : _averageRating.toStringAsFixed(1),
                          c.amber),
                      const SizedBox(width: 8),
                      _statCard('Due', '${_dueOrders.length}',
                          _dueOrders.isNotEmpty ? c.red : c.text),
                    ],
                  ),
                  if (_dueOrders.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Ask for a review',
                              style: NgFonts.geist(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: c.text)),
                          Text(
                              'Delivered more than 24 hours ago, not asked yet',
                              style:
                                  NgFonts.geist(fontSize: 12.5, color: c.mute)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    NgCardList(children: [
                      for (final o in _dueOrders) _dueOrderRow(o),
                    ]),
                  ],
                  const SizedBox(height: 16),
                  NgChipRow(edge: 0, chips: [
                    NgChip(
                        label: 'All',
                        selected: _ratingFilter == null,
                        onTap: () => setState(() => _ratingFilter = null)),
                    for (var i = 5; i >= 1; i--)
                      NgChip(
                          label: '$i ★',
                          selected: _ratingFilter == i,
                          onTap: () => setState(() => _ratingFilter = i)),
                  ]),
                  if (_branches.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    NgChipRow(edge: 0, chips: [
                      NgChip(
                          label: 'All branches',
                          selected: _branchFilter == null,
                          onTap: () => setState(() => _branchFilter = null)),
                      for (final b in _branches)
                        NgChip(
                            label: b,
                            selected: _branchFilter == b,
                            onTap: () => setState(() => _branchFilter = b)),
                    ]),
                  ],
                  const SizedBox(height: 14),
                  if (_filteredReviews.isEmpty)
                    NgCard(
                      child: Text('No reviews yet.',
                          textAlign: TextAlign.center,
                          style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
                    )
                  else
                    NgCardList(children: [
                      for (final r in _filteredReviews) _reviewRow(r),
                    ]),
                ],
              ),
            ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    final c = NgPalette.of(context);
    return Expanded(
      child: NgCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
            const SizedBox(height: 4),
            Text(value,
                style: NgFonts.mono(
                    fontSize: 20, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _dueOrderRow(OrdersRow o) {
    final c = NgPalette.of(context);
    final at = o.deliveredAt ?? o.closedAt;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o.customer,
                    style: NgFonts.geist(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: c.text)),
                Text(
                    '${o.id} · delivered ${at == null ? '—' : DateFormat('d MMM').format(at)}',
                    style: NgFonts.mono(fontSize: 12, color: c.mute)),
              ],
            ),
          ),
          NgPrimaryButton(
            compact: true,
            height: 38,
            icon: Icons.rate_review_outlined,
            label: 'Request',
            onPressed: () => _requestReview(o),
          ),
        ],
      ),
    );
  }

  Widget _reviewRow(Map<String, dynamic> r) {
    final c = NgPalette.of(context);
    final rating = r['rating'] as int?;
    final comment = r['comment'] as String?;
    final orderId = r['order_id'] as String?;
    final name = (r['customer_name'] ?? r['customer'] ?? '') as String;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name.isEmpty ? (orderId ?? '—') : name,
                    style: NgFonts.geist(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: c.text)),
              ),
              if (rating != null)
                Row(
                  children: List.generate(
                      5,
                      (i) => Icon(
                          i < rating
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 18,
                          color: c.amber)),
                )
              else
                Text('Awaiting response',
                    style: NgFonts.geist(fontSize: 12, color: c.mute)),
            ],
          ),
          if ((comment ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(comment!,
                style: NgFonts.geist(fontSize: 13.5, height: 1.4, color: c.soft)),
          ],
          const SizedBox(height: 4),
          Text(
            [
              if (orderId != null) orderId,
              if ((r['branch'] as String?)?.isNotEmpty ?? false)
                r['branch'] as String,
            ].join(' · '),
            style: NgFonts.mono(fontSize: 12, color: c.mute),
          ),
        ],
      ),
    );
  }
}
