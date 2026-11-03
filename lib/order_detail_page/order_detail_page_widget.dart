import '/components/ng_widgets.dart';
import '/order_detail_page/order_overview_section.dart';



import '/app_session.dart';
import '/permissions.dart';
import '/backend/audit_log_service.dart';
import '/backend/signature_service.dart';
import '/backend/soft_delete.dart';
import '/components/delete_action.dart';
import '/components/detail_row.dart';
import '/backend/tracking_service.dart';
import '/components/share_link_sheet.dart';
import '/config/app_config.dart';
import 'invoice_generator.dart';
import 'order_crew_section.dart';
import 'order_documents_section.dart';
import 'order_storage_section.dart';
import 'order_addons_section.dart';
import 'order_materials_section.dart';
import 'order_pnl_section.dart';
import 'payment_history_section.dart';
import 'quotation_breakdown_section.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/l10n/gen/app_localizations.dart';
import '/components/keyboard_scroll_view.dart';
import '/backend/detail_navigation.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'arrival_code_card.dart';
import 'order_detail_page_model.dart';
import '/backend/vendor_identity.dart';
import '/backend/order_id_allocator.dart';
import '/backend/edge_function_errors.dart';
export 'order_detail_page_model.dart';

/// Read-only view of a single order.
class OrderDetailPageWidget extends StatefulWidget {
  const OrderDetailPageWidget({
    super.key,
    this.orderId,
    this.orderCustomer,
    this.orderPhone,
    this.orderFromCity,
    this.orderToCity,
    this.orderFromAddress,
    this.orderToAddress,
    this.orderFromFloor,
    this.orderToFloor,
    this.orderMoveDate,
    this.orderAmount,
    this.orderStatus,
    this.orderPaymentStatus,
    this.orderTrackingStatus,
    this.orderService,
    this.orderBranch,
    this.orderType,
    this.orderNotes,
  });

  final String? orderId;
  final String? orderCustomer;
  final String? orderPhone;
  final String? orderFromCity;
  final String? orderToCity;
  final String? orderFromAddress;
  final String? orderToAddress;
  final String? orderFromFloor;
  final String? orderToFloor;
  final String? orderMoveDate;
  final String? orderAmount;
  final String? orderStatus;
  final String? orderPaymentStatus;
  final String? orderTrackingStatus;
  final String? orderService;
  final String? orderBranch;
  final String? orderType;
  final String? orderNotes;

  static String routeName = 'OrderDetailPage';
  static String routePath = '/order-detail';

  @override
  State<OrderDetailPageWidget> createState() => _OrderDetailPageWidgetState();
}

class _OrderDetailPageWidgetState extends State<OrderDetailPageWidget>
    with RefreshOnPopMixin<OrderDetailPageWidget> {
  late OrderDetailPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  bool _generatingInvoice = false;

  // ---- Item 3: customer signature ---------------------------------------
  SignatureRequest? _signature;
  bool _sendingSignature = false;

  // ---- Item 6: tracking link --------------------------------------------
  bool _sharingTracking = false;

  // ---- Item 11: delete --------------------------------------------------
  bool _deleting = false;

  /// Owner-only, and blocked entirely once payments exist or a GST invoice
  /// has been issued — the guard is `can_delete_order()` server-side, so
  /// the UI is not the only thing enforcing it.
  Future<void> _deleteOrder() async {
    if (widget.orderId == null) return;
    setState(() => _deleting = true);
    try {
      final deleted = await DeleteAction.run(
        context,
        table: 'orders',
        id: widget.orderId!,
        entityLabel: 'order',
        // Mandatory reason for orders, per item 11.4.
        reasonRequired: true,
        check: () => SoftDeleteService.canDeleteOrder(widget.orderId!),
        onAlternative: (alt) {
          if (alt == 'cancel_order') _cancelOrder();
        },
      );
      if (deleted && mounted) context.pop();
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  /// The alternative offered when an order can't be deleted: keeps the row
  /// and its financial record, takes it out of active jobs, and lands on
  /// the customer-facing timeline like any other status change.
  Future<void> _cancelOrder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: const Text(
          'The order and its payment history are kept, but it moves out of '
          'your active jobs. This is the right choice for an order that was '
          'called off.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
                foregroundColor: NgPalette.of(context).red),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await TrackingService.setStatus(
        orderId: widget.orderId!,
        status: 'cancelled',
        note: 'Order cancelled',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order cancelled')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not cancel: ${friendlyError(e)}')),
        );
      }
    }
  }

  // ---- Order Details Session 1, item 3: duplicate ------------------------
  bool _duplicating = false;

  /// Same convention as new_order_page's/lead_detail_page's own
  /// `_nextOrderId` — orders.id is text with no default, must be supplied
  /// on insert or NOT-NULL fires (23502).

  /// Clones the shipment/pricing fields only — the same field set
  /// new_order_page's own create-payload uses. Transactional/workflow
  /// state (status, payment_status, tracking_status, paid_total)
  /// always resets to fresh-order defaults, never carried
  /// over, so a duplicate never inherits the source order's payment
  /// history or job progress.
  Future<void> _duplicateOrder() async {
    if (widget.orderId == null) return;
    final rows = await OrdersTable().queryRows(
      queryFn: (q) => OrgScope.read(q).eq('id', widget.orderId!),
    );
    if (rows.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Order not found.')));
      }
      return;
    }
    final o = rows.first;

    DateTime pickedDate = DateTime.now();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: NgPalette.of(context).s1,
          title: const Text('Duplicate Order'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Creates a new order for ${o.customer} with the same '
                'shipment details. Payment and job status start fresh.',
                style: NgFonts.geist(fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: dialogContext,
                    initialDate: pickedDate,
                    firstDate:
                        DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setDialogState(() => pickedDate = picked);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Move Date'),
                  child: Text(DateFormat('d MMM y').format(pickedDate)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Duplicate')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    setState(() => _duplicating = true);
    try {
      final orgId = OrgScope.currentOrgId!;
      final newOrderId = await OrderIdAllocator.next();
      final created = await OrdersTable().insert({
        'id': newOrderId,
        ...OrgScope.stamp(orgId: orgId),
        'customer': o.customer,
        'phone': o.phone,
        if (o.customerId != null) 'customer_id': o.customerId,
        'from_city': o.fromCity,
        'to_city': o.toCity,
        'from_address': o.fromAddress,
        'to_address': o.toAddress,
        'from_floor': o.fromFloor,
        'to_floor': o.toFloor,
        'move_date': supaSerialize<DateTime>(pickedDate),
        'amount': o.amount,
        'distance_km': o.distanceKm,
        'service': o.service,
        'branch': o.branch,
        'order_type': o.orderType,
        'order_source': o.orderSource,
        if (o.rateCardId != null) 'rate_card_id': o.rateCardId,
        if (o.contractId != null) 'contract_id': o.contractId,
        // Not in the brief's literal §3 clone list, but necessary for
        // consistency: commission lives in commission_expected /
        // commission_pct / lead_source_id (order_type is just a
        // Direct/Porter label here, not the brief's assumed
        // local/outstation split — see the P&L card's own doc comment).
        //
        // ALL THREE ARE COPIED TOGETHER, and they have to be. They are one
        // snapshot of the commercial terms agreed at order time, and any
        // two of them without the third is a contradiction: expected
        // without a rate silently flags the duplicate unpriced when the
        // original was not; a rate without expected leaves it costed but
        // unexplained; either without the source id loses the attribution
        // that says where the money went.
        //
        // Copied, never re-derived from the lead source's CURRENT terms: a
        // duplicate of an order priced at 14% is a 14% job even if that
        // source charges 18% today (brief §44). Copying a null rate is
        // equally deliberate — the original was never priced, so the
        // duplicate inherits the gap rather than inventing a rate.
        'commission_expected': o.commissionExpected ?? false,
        'commission_pct': o.commissionPct,
        'lead_source_id': o.leadSourceId,
        // Brief §3 "Set": notes -> "Copy of {source_id}", not the
        // original notes.
        'notes': 'Copy of ${o.id}',
        // Brief §3 "Reset": pending, not new_order_page's usual 'booked' —
        // a duplicate starts one stage earlier, before paid_total and
        // payment_status reset to their own zero/pending defaults
        // below. vehicle_no/driver/supervisor_id/invoice_no/
        // lr_id/job_otp/supervisor_status are satisfied by omission (a
        // fresh insert starts every unlisted column at its own default).
        'status': 'pending',
        'payment_status': 'pending',
        'tracking_status': 'Pending',
      });
      await AuditLogService.log(
        entityType: 'orders',
        entityId: created.id!,
        action: 'duplicated',
        newValue: {'source_order_id': o.id, 'move_date': created.moveDateOrNull?.toString()},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Duplicated as ${created.id}.')));
      openOrderJourney(context, created);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not duplicate: ${friendlyError(e)}')));
      }
    } finally {
      if (mounted) setState(() => _duplicating = false);
    }
  }

  /// Refresh-after-write: re-read the signature so the chip flips from
  /// "Awaiting" to "Signed" when returning to this page, without a
  /// restart. The customer signs on their own phone, so there is no
  /// in-app event to hook — reconciling on refresh is the only way.
  @override
  void onPageRefresh() {
    _loadSignature();
    // Item 2: re-pull the linked quote so an edited quote's lines,
    // charges and GST show without a restart.
    _breakdownKey.currentState?.reload();
    // Order Details Session 1, item 1: keep the P&L card current after a
    // payment update, an expense/vendor-bill write, etc. elsewhere.
    _pnlKey.currentState?.reload();
    _overviewKey.currentState?.reload();
    _activityKey.currentState?.reload();
  }

  final _breakdownKey = GlobalKey<QuotationBreakdownSectionState>();
  final _pnlKey = GlobalKey<OrderPnlSectionState>();

  /// The order row, loaded from the database.
  ///
  /// This page was built to render from NAVIGATION PARAMS - the caller
  /// passes customer, phone, amount and the rest when pushing the route.
  /// That works when you tap through from a list and fails completely
  /// otherwise: a browser refresh, a pasted link or any direct URL
  /// arrives with only `orderId`, and every one of those fields rendered
  /// as "-" while the DB-backed sections below loaded fine (found 2 Sep
  /// 2026 opening an order by URL).
  ///
  /// The params are kept as the fast path so tapping through still paints
  /// instantly with no wait, and this row fills in whatever they did not
  /// carry.
  OrdersRow? _rowFallback;

  Future<void> _loadRowFallback() async {
    final id = widget.orderId;
    if (id == null || id.isEmpty) return;
    try {
      final rows = await OrdersTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('id', id),
        limit: 1,
      );
      if (!mounted || rows.isEmpty) return;
      setState(() => _rowFallback = rows.first);
    } catch (_) {
      // Params-only rendering is still better than an error page.
    }
  }

  String? _fromRow(String column) {
    final v = _rowFallback?.data[column];
    if (v == null) return null;
    final s = '$v'.trim();
    return s.isEmpty ? null : s;
  }
  String? get _orderCustomer => widget.orderCustomer ?? _fromRow('customer');
  String? get _orderPhone => widget.orderPhone ?? _fromRow('phone');
  String? get _orderFromAddress => widget.orderFromAddress ?? _fromRow('from_address');
  String? get _orderToAddress => widget.orderToAddress ?? _fromRow('to_address');
  String? get _orderFromFloor => widget.orderFromFloor ?? _fromRow('from_floor');
  String? get _orderToFloor => widget.orderToFloor ?? _fromRow('to_floor');
  String? get _orderStatus => widget.orderStatus ?? _fromRow('status');
  String? get _orderService => widget.orderService ?? _fromRow('service');
  String? get _orderBranch => widget.orderBranch ?? _fromRow('branch');
  String? get _orderType => widget.orderType ?? _fromRow('order_type');
  String? get _orderNotes => widget.orderNotes ?? _fromRow('notes');

  final _storageKey = GlobalKey<OrderStorageSectionState>();
  final _addonsKey = GlobalKey<OrderAddonsSectionState>();
  final _materialsKey = GlobalKey<OrderMaterialsSectionState>();
  final _overviewKey = GlobalKey<OrderOverviewSectionState>();
  final _activityKey = GlobalKey<OrderActivitySectionState>();
  final _paymentHistoryKey = GlobalKey<PaymentHistorySectionState>();

  Future<void> _loadSignature() async {
    if (widget.orderId == null) return;
    try {
      final sig = await SignatureService.find(
        documentType: 'invoice',
        documentId: widget.orderId!,
      );
      if (mounted) setState(() => _signature = sig);
    } catch (_) {
      // Supplemental — a failure here must not blank the page.
    }
  }

  Future<void> _sendForSignature() async {
    final id = widget.orderId;
    if (id == null) return;
    setState(() => _sendingSignature = true);
    try {
      final sig = await InvoiceGenerator(context, orderId: id)
          .sendForSignature(customer: _orderCustomer, phone: _orderPhone);
      if (sig != null && mounted) setState(() => _signature = sig);
    } finally {
      if (mounted) setState(() => _sendingSignature = false);
    }
  }


  Future<void> _shareTrackingLink() async {
    if (widget.orderId == null) return;
    setState(() => _sharingTracking = true);
    try {
      final token = await TrackingService.tokenForOrder(widget.orderId!);
      if (token == null) {
        throw Exception(
            'The tracking link for this order is not ready yet. Please try '
            'again in a moment.');
      }
      if (!mounted) return;
      final org = VendorIdentity.forSentence;
      await ShareLinkSheet.show(
        context,
        title: 'Share tracking link',
        subtitle: 'The customer can follow their move status live. No login '
            'needed — the link itself is the access.',
        link: buildTokenLink('/track', token),
        phone: _orderPhone,
        message: 'Hello${_orderCustomer == null ? '' : ' ${_orderCustomer}'}, '
            'you can track your move with $org here:',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create tracking link: ${friendlyError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _sharingTracking = false);
    }
  }

  Widget _signatureStatusChip(BuildContext context) {
    final sig = _signature;
    if (sig == null) return const SizedBox.shrink();
    final ng = NgPalette.of(context);
    final signed = sig.isSigned;
    final color = signed ? ng.blue : ng.amber;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(signed ? Icons.verified : Icons.hourglass_empty,
              size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              signed
                  ? 'Signed by ${sig.customerName ?? 'customer'}'
                      '${sig.signedAt == null ? '' : ' on ${DateFormat('d MMM yyyy').format(sig.signedAt!.toLocal())}'}'
                  : 'Awaiting customer signature',
              style: NgFonts.geist(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: ng.text,
              ),
            ),
          ),
          // Arun, 8 Sept 2026: "if the customer sign is not available then
          // share that sign link capture and update in doc".
          //
          // The banner used to only REPORT the gap. Noticing "awaiting
          // customer signature" and being able to do something about it are
          // the same moment, and separating them meant hunting for the
          // Send for Signature button further down the page — so in
          // practice the link did not get sent. This is the same
          // affordance, offered where the absence is visible.
          if (!signed)
            TextButton(
              onPressed: _sendingSignature ? null : _sendForSignature,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 32),
              ),
              child: Text(
                sig.link.isEmpty ? 'Send link' : 'Share link',
                style: NgFonts.geist(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          // Once they have signed, the DOCUMENT still has to be rebuilt to
          // carry the signature — the stored copy on the customer's link
          // was generated before they signed. Regenerating is what updates
          // both, so say so rather than leaving the vendor to discover it.
          if (signed)
            IconButton(
              tooltip: 'Regenerate the invoice so it carries this signature',
              onPressed: _refreshSignature,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.refresh, size: 18, color: color),
            ),
        ],
      ),
    );
  }

  /// Re-reads the signature and tells the vendor what to do with it.
  ///
  /// A signature captured on the public link lands in Postgres, not in the
  /// PDF that was generated before it. Nothing is wrong — the document is
  /// rebuilt on demand and picks it up — but a vendor looking at a green
  /// "Signed by ..." badge reasonably assumes the copy the customer can
  /// download already shows it. It does not until the invoice is
  /// regenerated, which is also what refreshes the stored copy behind the
  /// tracking link.
  Future<void> _refreshSignature() async {
    try {
      final sig = await SignatureService.find(
        documentType: 'invoice',
        documentId: widget.orderId!,
      );
      if (!mounted) return;
      if (sig != null) setState(() => _signature = sig);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text((sig?.isSigned ?? false)
            ? 'Signature on file. Generate the invoice again so the copy '
                'the customer downloads carries it.'
            : 'Not signed yet.'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not check the signature: ${friendlyError(e)}')));
    }
  }

  /// Invoice generation lives in [InvoiceGenerator] so the order journey's
  /// Invoice stage runs exactly the same code.
  Future<void> _generateInvoice() async {
    final id = widget.orderId;
    if (id == null) return;
    await InvoiceGenerator(
      context,
      orderId: id,
      hideCustomer: _hideCustomer,
      signature: _signature,
      onBusy: (b) {
        if (mounted) setState(() => _generatingInvoice = b);
      },
    ).generate();
  }

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => OrderDetailPageModel());
    _loadSignature();
    // Fills in any field the caller did not pass, so a refresh or a
    // direct link renders a complete order instead of a page of dashes.
    _loadRowFallback();

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  /// Privacy: supervisors must not see customer identity once the order is
  /// completed (belt-and-braces on top of the OrdersPage masking, since this
  /// page is also reachable by deep link with arbitrary params).
  bool get _hideCustomer {
    if (!AppSession.instance.isSupervisorSession) return false;
    final st = (_orderStatus ?? '').toLowerCase();
    return st == 'delivered' || st == 'done' || st == 'completed' ||
        st == 'closed';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: NgPalette.of(context).bg,
        appBar: NgSimpleBar(
          title: widget.orderId ?? AppLocalizations.of(context).orderDetails,
          mono: true,
          actions: [
            if (kTrackLinkHosted && widget.orderId != null)
              NgHeaderButtonBox(
                icon: Icons.share_outlined,
                tooltip: 'Share tracking link',
                onTap: _sharingTracking ? null : _shareTrackingLink,
              ),
          ],
        ),
        body: SafeArea(
          top: true,
          child: Container(
            decoration: BoxDecoration(
              color: NgPalette.of(context).bg,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: KeyboardScrollView(
                // Pull-to-refresh: everything onPageRefresh reloads, plus
                // the order row and the sections it doesn't cover.
                onRefresh: () async {
                  onPageRefresh();
                  _storageKey.currentState?.reload();
                  _addonsKey.currentState?.reload();
                  _materialsKey.currentState?.reload();
                  _paymentHistoryKey.currentState?.reload();
                  await _loadRowFallback();
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Claude Design handoff "ORDER DETAIL": journey strip,
                    // who/where, Call/WhatsApp/Maps, Progress, Crew &
                    // vehicle and Payment. See OrderOverviewSection.
                    if (widget.orderId != null)
                      OrderOverviewSection(
                        key: _overviewKey,
                        orderId: widget.orderId!,
                        hideCustomer: _hideCustomer,
                        onChanged: () {
                          _loadRowFallback();
                          _pnlKey.currentState?.reload();
                          _paymentHistoryKey.currentState?.reload();
                          _activityKey.currentState?.reload();
                        },
                      ),
                    // Addresses, floors and the office fields the
                    // overview's one-line route leaves out.
                    DetailCard(
                      title: AppLocalizations.of(context).odMoveDetails,
                      children: [
                        DetailRow(
                          label: 'Phone',
                          value: _hideCustomer
                              ? '••••••••••'
                              : _orderPhone,
                        ),
                        DetailRow(
                          label: 'Address (From)',
                          value: _orderFromAddress,
                          hideWhenEmpty: true,
                        ),
                        DetailRow(
                          label: 'Floor (From)',
                          value: _orderFromFloor,
                          hideWhenEmpty: true,
                        ),
                        DetailRow(
                          label: 'Address (To)',
                          value: _orderToAddress,
                          hideWhenEmpty: true,
                        ),
                        DetailRow(
                          label: 'Floor (To)',
                          value: _orderToFloor,
                          hideWhenEmpty: true,
                        ),
                        DetailRow(label: 'Service', value: _orderService),
                        DetailRow(label: 'Branch', value: _orderBranch),
                        DetailRow(label: 'Type', value: _orderType),
                      ],
                    ),
                    // Arrival code (19 Aug 2026). Placed high on the page
                    // on purpose: the office reads this out when a crew
                    // phones from the doorstep, so it must not be
                    // something you scroll for. Owner/manager/admin only —
                    // the widget enforces that itself too, because
                    // showing it to the supervisor would make the gate
                    // decorative (see its doc comment).
                    if (widget.orderId != null)
                      ArrivalCodeCard(orderId: widget.orderId!),
                    // Item 4.3: this had the same "Notes / Notes" duplicate
                    // as Lead Details — a section header wrapping a row
                    // whose label was also "Notes".
                    DetailCard(
                      title: 'Notes',
                      children: [
                        DetailNote(text: _orderNotes),
                      ],
                    ),
                    // Item 11 sweep: payment-entry delete UI. Renders
                    // regardless of order/balance state (unlike
                    // QuickPaymentSection above) — always visible when
                    // canActive('orders','edit'), same gate.
                    if (widget.orderId != null &&
                        StaffPermissions.canActive('orders', 'edit'))
                      PaymentHistorySection(
                          key: _paymentHistoryKey,
                          orderId: widget.orderId!,
                          onChanged: () => _pnlKey.currentState?.reload()),
                    // Order Details Session 1, item 1: P&L card. Gated on
                    // canActive('reports','view') — absent, not disabled,
                    // for a session without reports access (matches the
                    // OrderCrewSection gate immediately below).
                    if (widget.orderId != null &&
                        StaffPermissions.canActive('reports', 'view'))
                      OrderPnlSection(
                          key: _pnlKey, orderId: widget.orderId!),
                    // Parity brief Part 3e: itemized quotation breakdown,
                    // if this order has one linked — was previously just a
                    // bare total with no itemisation.
                    if (widget.orderId != null)
                      QuotationBreakdownSection(
                          key: _breakdownKey, orderId: widget.orderId!),
                    // Warehouse storage as a revenue line ON the order
                    // (brief section 37) - move in, accrue rent, release
                    // out. Same reports gate as the P&L card it feeds.
                    if (widget.orderId != null &&
                        StaffPermissions.canActive('reports', 'view'))
                      OrderStorageSection(
                          key: _storageKey,
                          orderId: widget.orderId!,
                          onChanged: () => _pnlKey.currentState?.reload()),
                    // Add-on services: extra work agreed after the quote,
                    // often done on a different day. Sits directly under
                    // storage because both are revenue lines added to an
                    // order after it was booked, and both feed the same
                    // P&L card. Gated on orders.edit rather than reports
                    // or salary — recording that a job still owes an AC
                    // install is order admin, not a money module, and the
                    // supervisor who did the uninstall is the person who
                    // knows.
                    if (widget.orderId != null &&
                        StaffPermissions.canActive('orders', 'view'))
                      OrderAddonsSection(
                        key: _addonsKey,
                        orderId: widget.orderId!,
                        readOnly: !StaffPermissions.canActive('orders', 'edit'),
                        onChanged: () => _pnlKey.currentState?.reload(),
                      ),
                    // Materials used on THIS job, recorded from the order
                    // rather than from the Materials page. Sits beside
                    // add-ons because both change what the job costs and
                    // what it earns, and both feed the same P&L card.
                    if (widget.orderId != null &&
                        StaffPermissions.canActive('orders', 'view'))
                      OrderMaterialsSection(
                        key: _materialsKey,
                        orderId: widget.orderId!,
                        readOnly: !StaffPermissions.canActive('orders', 'edit'),
                        onChanged: () {
                          _pnlKey.currentState?.reload();
                          _addonsKey.currentState?.reload();
                        },
                      ),
                    // Assign supervisor + labour/salary (owner view) —
                    // was missing from the order flow entirely.
                    // Permission-model decision (1 Aug 2026), Step 4 sweep:
                    // absent, not disabled, for a staff session without
                    // salary.view — a supervisor must not see this section
                    // at all.
                    if (widget.orderId != null &&
                        StaffPermissions.canActive('salary', 'view'))
                      OrderCrewSection(
                          orderId: widget.orderId!,
                          onCrewChanged: () =>
                              _pnlKey.currentState?.reload()),
                    // Items 3 + 6: signature status and the two customer
                    // share actions.
                    _signatureStatusChip(context),
                    // Hidden while the customer signature page is down.
                    // Verified 3 Sept 2026 by fetching link.nagarva.in/sign:
                    // it returns "Link unavailable". Sending a signature
                    // request would put a dead link in front of the
                    // customer at the moment they are being asked to
                    // approve a document.
                    if (!kSignLinkHosted)
                      NgCard(
                        color: NgPalette.of(context).amberBg,
                        child: Text(
                          'Remote signature links are switched off — the '
                          'customer signing page is not live. Use '
                          'Capture Signature in Documents below to take '
                          'the signature in person.',
                          style: NgFonts.geist(
                              fontSize: 12.5,
                              height: 1.4,
                              color: NgPalette.of(context).text),
                        ),
                      )
                    else
                      NgSecondaryButton(
                        onPressed:
                            _sendingSignature ? null : _sendForSignature,
                        label: _sendingSignature
                            ? 'Preparing…'
                            : (_signature?.isSigned ?? false)
                                ? 'View signed copy'
                                : 'Send for Signature',
                        icon: Icons.draw_outlined,
                        iconColor: NgPalette.of(context).acc,
                        height: 46,
                      ),
                    // The tracking link is shared from the top bar's share
                    // button (kTrackLinkHosted); the flag still turns it
                    // off if the page ever goes down.
                    Row(children: [
                      Expanded(
                        child: NgSecondaryButton(
                          onPressed: () {
                            context.pushNamed(
                              SupervisorJobPageWidget.routeName,
                              queryParameters: {
                                'orderId': serializeParam(
                                    widget.orderId, ParamType.String),
                              }.withoutNulls,
                            );
                          },
                          label: 'Open Field Job',
                          icon: Icons.local_shipping_outlined,
                          iconColor: NgPalette.of(context).acc,
                          height: 46,
                        ),
                      ),
                      // Permission-model decision (1 Aug 2026), Step 4
                      // sweep: absent, not disabled, without orders.edit.
                      if (StaffPermissions.canActive('orders', 'edit')) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: NgSecondaryButton(
                            onPressed: () async {
                              context.pushNamed(
                                NewOrderPageWidget.routeName,
                                queryParameters: {
                                  'orderId': serializeParam(
                                      widget.orderId, ParamType.String),
                                }.withoutNulls,
                              );
                            },
                            label: AppLocalizations.of(context).editOrder,
                            icon: Icons.edit_outlined,
                            iconColor: NgPalette.of(context).acc,
                            height: 46,
                          ),
                        ),
                      ],
                    ]),
                    NgPrimaryButton(
                      onPressed: _generatingInvoice ? null : _generateInvoice,
                      // BUG-047: once issued, the same button re-opens
                      // the SAME invoice (no new number) — say so.
                      label: _generatingInvoice
                          ? 'Generating…'
                          : (_rowFallback?.invoiceNo ?? '').isNotEmpty
                              ? 'View invoice ${_rowFallback!.invoiceNo}'
                              : 'Generate Invoice',
                      icon: Icons.receipt_long_outlined,
                    ),
                    // Order Details Session 1, item 4: the 8-document grid
                    // + 4-button utility row (incl. "⧉ Copy" = Duplicate
                    // Order, per the brief's §3 placement) lives here.
                    if (widget.orderId != null)
                      OrderDocumentsSection(
                        orderId: widget.orderId!,
                        duplicating: _duplicating,
                        onDuplicate: _duplicateOrder,
                        onGenerateInvoice:
                            _generatingInvoice ? () {} : _generateInvoice,
                      ),
                    if (widget.orderId != null)
                      OrderActivitySection(
                          key: _activityKey, orderId: widget.orderId!),
                    // Item 11: owner-only, destructive, at the very bottom.
                    // Staff don't see it at all rather than seeing a
                    // button that always refuses.
                    if (widget.orderId != null && SoftDeleteService.isOwner)
                      DeleteAction.button(
                        context: context,
                        busy: _deleting,
                        label: 'Delete Order',
                        onPressed: _deleteOrder,
                      ),
                  ].divide(const SizedBox(height: 12.0)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
