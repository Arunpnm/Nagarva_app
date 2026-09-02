import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/pricing_defaults.dart';
import '/backend/storage_billing.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';

/// Warehouse storage, as a revenue line ON THE ORDER.
///
/// Storage is not a separate order (brief §37): the same goods flow
/// move-in → stored → move-out, so the inbound job, the storage period
/// and the outbound delivery stay on one record.
///
/// Two states:
///  * **no stay** — offer "Move into warehouse"
///  * **in storage** — show the ACCRUING charge (§41: storage accrues, it
///    is not a single bill raised at booking) and offer release
///  * **closed** — show the settled charge
///
/// The rate is SNAPSHOTTED onto the record at booking and never re-read
/// from a rate card (§44), so a later price revision cannot re-bill goods
/// already in store. That is why the booking sheet lets the vendor edit
/// the pre-filled rate: what they agree with this customer today is what
/// this stay bills, forever.
class OrderStorageSection extends StatefulWidget {
  const OrderStorageSection({
    super.key,
    required this.orderId,
    this.orderCft,
    this.onChanged,
  });

  final String orderId;

  /// Goods volume from the order/quote, used to pre-fill the stay.
  final double? orderCft;

  final VoidCallback? onChanged;

  @override
  State<OrderStorageSection> createState() => OrderStorageSectionState();
}

class OrderStorageSectionState extends State<OrderStorageSection> {
  StorageJobsRow? _job;
  WarehousesRow? _warehouse;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final jobs = await StorageJobsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('order_id', widget.orderId),
        limit: 1,
      );
      WarehousesRow? wh;
      if (jobs.isNotEmpty && (jobs.first.warehouseId ?? '').isNotEmpty) {
        final whs = await WarehousesTable().queryRows(
          queryFn: (q) => OrgScope.read(q).eq('id', jobs.first.warehouseId!),
          limit: 1,
        );
        if (whs.isNotEmpty) wh = whs.first;
      }
      if (!mounted) return;
      setState(() {
        _job = jobs.isEmpty ? null : jobs.first;
        _warehouse = wh;
        _loading = false;
      });
    } catch (_) {
      // A storage card that fails to load must not blank the order screen.
      if (mounted) setState(() => _loading = false);
    }
  }

  StorageCharge? get _charge {
    final j = _job;
    if (j == null || j.inDate == null) return null;
    return computeStorageCharge(
      inDate: j.inDate!,
      outDate: j.outDate,
      mode: storageBillingModeFromWire(j.billingMode),
      rate: j.rate,
      minBillingDays: j.minBillingDays,
      handlingIn: j.handlingInCharge,
      handlingOut: j.handlingOutCharge,
      // A custom arrangement stores the agreed amount in `rate`.
      customAmount: j.rate,
    );
  }

  Future<void> _book() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
      builder: (_) => _StorageBookingSheet(
        orderId: widget.orderId,
        orderCft: widget.orderCft,
      ),
    );
    if (saved == true) {
      await reload();
      widget.onChanged?.call();
    }
  }

  Future<void> _release() async {
    final j = _job;
    if (j == null || j.id == null) return;
    // A stay that already has an out-date is settled. The button is hidden
    // in that state, but the guard is what actually protects the charge -
    // a double tap, a stale card or a second device must not be able to
    // re-close it and move the figure.
    if (j.outDate != null || j.status == 'closed') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('These goods have already been released.')));
      }
      return;
    }
    final c = _charge;
    final theme = FlutterFlowTheme.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Release goods from storage?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This closes the stay today and fixes the storage charge. '
              'The goods can then be delivered out.',
              style: theme.bodyMedium.override(font: GoogleFonts.inter()),
            ),
            if (c != null) ...[
              const SizedBox(height: 10),
              Text(
                'Final storage charge: ₹${c.total.toStringAsFixed(0)}'
                '  (${c.billedUnits} ${c.unitLabel})',
                style: theme.bodyMedium.override(
                    font: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              ),
              if (c.minimumApplied)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Includes the ${j.minBillingDays}-day minimum — the goods '
                    'were in store ${c.days} ${c.days == 1 ? 'day' : 'days'}.',
                    style: theme.bodySmall.override(
                        font: GoogleFonts.inter(), color: theme.secondaryText),
                  ),
                ),
              if (storageBillingModeFromWire(j.billingMode) ==
                  StorageBillingMode.perMonth)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Monthly plan — the full month is charged even on early '
                    'collection. This was disclosed at booking.',
                    style: theme.bodySmall.override(
                        font: GoogleFonts.inter(), color: theme.secondaryText),
                  ),
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Release')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final today = DateTime.now();
      await StorageJobsTable().update(
        data: {
          'out_date':
              DateTime(today.year, today.month, today.day).toIso8601String(),
          'status': 'closed',
        },
        matchingRows: (q) => OrgScope.write(q).eq('id', j.id!),
      );
      // Re-read rather than patching the cached row: the settled charge is
      // computed from what the DB now holds, not from what we think we
      // just wrote (CLAUDE.md's refresh-the-row rule).
      await reload();
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not release: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    if (_loading) return const SizedBox.shrink();

    final j = _job;
    final c = _charge;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.warehouse_outlined, size: 18, color: theme.primary),
              const SizedBox(width: 7),
              Text('Warehouse Storage',
                  style: theme.bodyLarge.override(
                      font: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      color: theme.primary)),
              const Spacer(),
              if (j != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: j.outDate == null
                        ? theme.primary.withValues(alpha: .12)
                        : theme.alternate,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    j.outDate == null ? 'In storage' : 'Released',
                    style: theme.bodySmall.override(
                        font: GoogleFonts.inter(fontWeight: FontWeight.w600),
                        color: j.outDate == null
                            ? theme.primary
                            : theme.secondaryText),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            if (j == null) ...[
              Text(
                'Goods are going straight to the customer. If they are being '
                'held instead, move them into a godown — rent accrues from '
                'the day they go in.',
                style: theme.bodySmall.override(
                    font: GoogleFonts.inter(), color: theme.secondaryText),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _book,
                icon: const Icon(Icons.move_to_inbox_outlined, size: 18),
                label: const Text('Move into warehouse'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44)),
              ),
            ] else ...[
              _row(theme, 'Godown', _warehouse?.name ?? '—'),
              if ((_warehouse?.city ?? '').isNotEmpty)
                _row(theme, 'City', _warehouse!.city!),
              _row(theme, 'Goods in', _fmtDate(j.inDate)),
              if (j.outDate != null) _row(theme, 'Goods out', _fmtDate(j.outDate)),
              if (j.outDate == null && j.expectedOutDate != null)
                _row(theme, 'Expected out', _fmtDate(j.expectedOutDate)),
              _row(theme, 'Plan',
                  storageBillingModeLabel(storageBillingModeFromWire(j.billingMode))),
              _row(
                  theme,
                  'Agreed rate',
                  storageBillingModeFromWire(j.billingMode) ==
                          StorageBillingMode.custom
                      ? '₹${j.rate.toStringAsFixed(0)} for the stay'
                      : '₹${j.rate.toStringAsFixed(0)} / '
                          '${storageBillingModeFromWire(j.billingMode) == StorageBillingMode.perDay ? 'day' : 'month'}'),
              if (j.totalCft > 0)
                _row(theme, 'Volume', '${j.totalCft.toStringAsFixed(0)} CFT'),
              if (j.packageCount > 0)
                _row(theme, 'Packages', '${j.packageCount}'),
              if (j.securityDeposit > 0)
                _row(theme, 'Deposit held',
                    '₹${j.securityDeposit.toStringAsFixed(0)}'),
              const Divider(height: 22),
              if (c != null) ...[
                _row(theme, j.outDate == null ? 'Accrued so far' : 'Storage rent',
                    '₹${c.rent.toStringAsFixed(0)}',
                    detail: '${c.billedUnits} ${c.unitLabel}'
                        '${c.days != c.billedUnits ? ' · in store ${c.days} ${c.days == 1 ? 'day' : 'days'}' : ''}'),
                if (c.handlingIn > 0)
                  _row(theme, 'Handling in',
                      '₹${c.handlingIn.toStringAsFixed(0)}'),
                if (c.handlingOut > 0)
                  _row(theme, 'Handling out',
                      '₹${c.handlingOut.toStringAsFixed(0)}'),
                const SizedBox(height: 6),
                Row(children: [
                  Text('Storage income',
                      style: theme.bodyLarge.override(
                          font:
                              GoogleFonts.inter(fontWeight: FontWeight.w700))),
                  const Spacer(),
                  Text('₹${c.total.toStringAsFixed(0)}',
                      style: theme.bodyLarge.override(
                          font: GoogleFonts.inter(fontWeight: FontWeight.w700),
                          color: theme.primary)),
                ]),
                if (c.minimumApplied)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Minimum ${j.minBillingDays} days applied.',
                      style: theme.bodySmall.override(
                          font: GoogleFonts.inter(),
                          color: theme.secondaryText),
                    ),
                  ),
              ],
              if (j.outDate == null) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _release,
                  icon: const Icon(Icons.outbox_outlined, size: 18),
                  label: Text(_busy ? 'Releasing…' : 'Release & deliver'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(44)),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(FlutterFlowTheme theme, String label, String value,
          {String? detail}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: theme.bodyMedium.override(
                          font: GoogleFonts.inter(),
                          color: theme.secondaryText)),
                  if (detail != null)
                    Text(detail,
                        style: theme.bodySmall.override(
                            font: GoogleFonts.inter(),
                            color: theme.secondaryText)),
                ],
              ),
            ),
            Text(value,
                textAlign: TextAlign.right,
                style: theme.bodyMedium
                    .override(font: GoogleFonts.inter(fontWeight: FontWeight.w600))),
          ],
        ),
      );

  static String _fmtDate(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
}

/// Booking sheet — "move into warehouse".
class _StorageBookingSheet extends StatefulWidget {
  const _StorageBookingSheet({required this.orderId, this.orderCft});
  final String orderId;
  final double? orderCft;

  @override
  State<_StorageBookingSheet> createState() => _StorageBookingSheetState();
}

class _StorageBookingSheetState extends State<_StorageBookingSheet> {
  List<WarehousesRow> _warehouses = [];

  /// This org's own storage rates. Empty until the vendor sets them —
  /// there is no shipped table to fall back on.
  List<StorageSizeRate> _rates = const [];

  String? _warehouseId;
  String? _size;
  StorageBillingMode _mode = StorageBillingMode.perMonth;

  final _rate = TextEditingController();
  final _minDays =
      TextEditingController(text: '$kStorageDefaultMinDays');
  final _cft = TextEditingController();
  final _packages = TextEditingController();
  final _deposit = TextEditingController();
  final _handlingIn = TextEditingController();
  final _handlingOut = TextEditingController();
  final _notes = TextEditingController();
  DateTime _inDate = DateTime.now();
  DateTime? _expectedOut;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if ((widget.orderCft ?? 0) > 0) {
      _cft.text = widget.orderCft!.toStringAsFixed(0);
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await WarehousesTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('active', true).order('name'),
      );
      final cfg = await PricingConfig.loadForCurrentOrg();
      if (!mounted) return;
      setState(() {
        _warehouses = rows;
        _rates = cfg.storageRates;
        _warehouseId = rows.isEmpty ? null : rows.first.id;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      _rate,
      _minDays,
      _cft,
      _packages,
      _deposit,
      _handlingIn,
      _handlingOut,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Pre-fills the rate from the size template for the chosen plan.
  ///
  /// A SUGGESTION ONLY — the field stays editable and whatever is saved is
  /// what bills. The template is the vendor's default structure, not a
  /// price the product asserts (§44), and the two plans are independent
  /// numbers, so switching plan re-reads the matching column rather than
  /// converting one into the other.
  void _prefillRate() {
    final size = _size;
    if (size == null) return;
    final row = _rates.where((r) => r.size == size);
    if (row.isEmpty) return;
    final r = row.first;
    switch (_mode) {
      case StorageBillingMode.perDay:
        _rate.text = r.perDay.toStringAsFixed(0);
        _minDays.text = '${r.minDays}';
        break;
      case StorageBillingMode.perMonth:
        _rate.text = r.perMonth.toStringAsFixed(0);
        break;
      case StorageBillingMode.custom:
        break;
    }
    setState(() {});
  }

  Future<void> _save() async {
    if (_warehouseId == null) {
      setState(() => _error = 'Pick a godown.');
      return;
    }
    final rate = double.tryParse(_rate.text.trim()) ?? 0;
    if (rate <= 0) {
      setState(() => _error = 'Enter the agreed rate.');
      return;
    }
    // Goods cannot leave before they arrive. Caught here rather than left
    // to the charge calculation, which clamps negatives to zero days and
    // would quietly bill the minimum instead of flagging the typo.
    if (_expectedOut != null &&
        DateTime(_expectedOut!.year, _expectedOut!.month, _expectedOut!.day)
            .isBefore(
                DateTime(_inDate.year, _inDate.month, _inDate.day))) {
      setState(() =>
          _error = 'Expected out date is before the goods-in date.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await StorageJobsTable().insert({
        ...OrgScope.stamp(),
        'order_id': widget.orderId,
        'warehouse_id': _warehouseId,
        'in_date':
            DateTime(_inDate.year, _inDate.month, _inDate.day).toIso8601String(),
        if (_expectedOut != null)
          'expected_out_date': DateTime(_expectedOut!.year, _expectedOut!.month,
                  _expectedOut!.day)
              .toIso8601String(),
        'total_cft': double.tryParse(_cft.text.trim()) ?? 0,
        'package_count': int.tryParse(_packages.text.trim()) ?? 0,
        'billing_mode': storageBillingModeToWire(_mode),
        // Snapshotted: a later rate-card change must not re-bill this stay.
        'rate': rate,
        'min_billing_days': int.tryParse(_minDays.text.trim()) ?? 0,
        'security_deposit': double.tryParse(_deposit.text.trim()) ?? 0,
        'handling_in_charge': double.tryParse(_handlingIn.text.trim()) ?? 0,
        'handling_out_charge': double.tryParse(_handlingOut.text.trim()) ?? 0,
        'status': 'in_storage',
        'notes': [
          if (_size != null) 'Size: $_size',
          if (_notes.text.trim().isNotEmpty) _notes.text.trim(),
        ].join(' · '),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Move into warehouse',
                style: theme.headlineSmall.override(
                    font: GoogleFonts.interTight(fontWeight: FontWeight.w600))),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_warehouses.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No active godown yet. Add one under Warehouses first — a '
                  'stay has to be somewhere.',
                  style: theme.bodyMedium.override(font: GoogleFonts.inter()),
                ),
              )
            else ...[
              DropdownButtonFormField<String>(
                initialValue: _warehouseId,
                decoration: const InputDecoration(
                    labelText: 'Godown', isDense: true),
                items: _warehouses
                    .map((w) => DropdownMenuItem(
                          value: w.id,
                          child: Text(
                              [w.name, if ((w.city ?? '').isNotEmpty) w.city!]
                                  .join(' · ')),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _warehouseId = v),
              ),
              const SizedBox(height: 10),
              if (_rates.isEmpty)
                // No shipped rate table to fall back on, deliberately. The
                // vendor still books the stay — they just type the rate
                // they agreed, which is the only number that was ever
                // legitimate here.
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'No storage rates set yet. Set them under Warehouses → '
                    'Storage rates to pick a size and pre-fill, or just '
                    'enter the agreed rate below.',
                    style: theme.bodySmall.override(
                        font: GoogleFonts.inter(), color: theme.secondaryText),
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _size,
                  decoration: const InputDecoration(
                      labelText: 'Storage size', isDense: true),
                  items: _rates
                      .map((r) => DropdownMenuItem(
                          value: r.size,
                          child: Text(
                              '${r.size}  ·  ₹${r.perDay.toStringAsFixed(0)}/day  ·  ₹${r.perMonth.toStringAsFixed(0)}/mo')))
                      .toList(),
                  onChanged: (v) {
                    _size = v;
                    _prefillRate();
                  },
                ),
              const SizedBox(height: 10),
              // Plan is chosen at booking and locked for the stay (§39).
              SegmentedButton<StorageBillingMode>(
                segments: const [
                  ButtonSegment(
                      value: StorageBillingMode.perDay, label: Text('Daily')),
                  ButtonSegment(
                      value: StorageBillingMode.perMonth,
                      label: Text('Monthly')),
                  ButtonSegment(
                      value: StorageBillingMode.custom, label: Text('Custom')),
                ],
                selected: {_mode},
                onSelectionChanged: (s) {
                  _mode = s.first;
                  _prefillRate();
                },
              ),
              const SizedBox(height: 6),
              Text(
                _mode == StorageBillingMode.perMonth
                    ? 'Whole months. Early collection still pays the full '
                        'month — tell the customer at booking.'
                    : _mode == StorageBillingMode.perDay
                        ? 'Per day, with a minimum. A shorter stay still '
                            'bills the minimum.'
                        : 'Bills exactly the agreed amount for the stay.',
                style: theme.bodySmall.override(
                    font: GoogleFonts.inter(), color: theme.secondaryText),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: _field(
                      _rate,
                      _mode == StorageBillingMode.custom
                          ? 'Agreed amount (₹)'
                          : _mode == StorageBillingMode.perDay
                              ? 'Rate per day (₹)'
                              : 'Rate per month (₹)',
                      keyboard: TextInputType.number),
                ),
                if (_mode == StorageBillingMode.perDay) ...[
                  const SizedBox(width: 10),
                  Expanded(
                      child: _field(_minDays, 'Minimum days',
                          keyboard: TextInputType.number)),
                ],
              ]),
              Row(children: [
                Expanded(
                    child: _field(_cft, 'Volume (CFT)',
                        keyboard: TextInputType.number)),
                const SizedBox(width: 10),
                Expanded(
                    child: _field(_packages, 'Packages',
                        keyboard: TextInputType.number)),
              ]),
              Row(children: [
                Expanded(
                    child: _field(_handlingIn, 'Handling in (₹)',
                        keyboard: TextInputType.number)),
                const SizedBox(width: 10),
                Expanded(
                    child: _field(_handlingOut, 'Handling out (₹)',
                        keyboard: TextInputType.number)),
              ]),
              _field(_deposit, 'Security deposit (₹)',
                  keyboard: TextInputType.number),
              _dateRow(theme, 'Goods in', _inDate, (d) {
                setState(() => _inDate = d);
              }),
              _dateRow(theme, 'Expected out (optional)', _expectedOut, (d) {
                setState(() => _expectedOut = d);
              }),
              _field(_notes, 'Notes', maxLines: 2),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(_error!,
                    style: theme.bodySmall.override(
                        font: GoogleFonts.inter(), color: theme.error)),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving…' : 'Move in'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dateRow(FlutterFlowTheme theme, String label, DateTime? value,
          ValueChanged<DateTime> onPick) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(
            child: Text(
              value == null
                  ? label
                  : '$label: ${OrderStorageSectionState._fmtDate(value)}',
              style: theme.bodyMedium.override(font: GoogleFonts.inter()),
            ),
          ),
          TextButton(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: value ?? DateTime.now(),
                firstDate: DateTime(DateTime.now().year - 1),
                lastDate: DateTime(DateTime.now().year + 3),
              );
              if (picked != null) onPick(picked);
            },
            child: const Text('Pick'),
          ),
        ]),
      );

  Widget _field(TextEditingController c, String label,
          {int maxLines = 1, TextInputType? keyboard}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          maxLines: maxLines,
          keyboardType: keyboard,
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      );
}
