import '/components/ng_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '/backend/audit_log_service.dart';
import '/backend/staff_pay_types.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';
import '/components/load_error_state.dart';
import '/flutter_flow/ng_tokens.dart';
import '/permissions.dart';

/// Day-close crew sheet — the per-job staff record from the staff-pay
/// brief §4, filled at end of day by the supervisor.
///
/// One row per person: present/absent, the wage the vendor types, exactly
/// one driver tag, and an additive A/C amount. It replaces the nightly
/// handwritten wage grid, so the governing constraint is speed: "the app
/// must be faster than paper. Every field that requires typing is a field
/// that risks sending the vendor back to the diary."
///
/// Four decisions worth not undoing:
///
/// 1. **Wages are never auto-calculated** (brief §3). This screen does not
///    suggest, derive or pre-fill an amount from `staff.salary` or from
///    anything else — a new row's wage field opens EMPTY. The diary shows
///    rates moving with job type and role, but not reliably enough to
///    automate, and "an auto-suggested rate the vendor has to correct on
///    every job is slower than typing the right number once". The one
///    thing this screen remembers is the last A/C amount typed on THIS
///    sheet (see [_lastAcAmount]) — that is memory of what the human just
///    said, not a judgement about what a wage should be.
///
/// 2. **Present == an `order_staff` row exists.** There is no separate
///    presence column, and there should not be one: two sources of truth
///    for "was this man on this job" is exactly how the labour figure and
///    the crew list drift apart. Toggling someone off deletes their row.
///
/// 3. **The driver tag belongs to the assignment, not the person** (§4).
///    A crew may hold three licensed drivers; what matters is who drove
///    THIS job. Postgres enforces at most one via the partial unique index
///    `order_staff_one_driver_per_order`; the "at least one" half of the
///    rule is enforced here at save, because a partial unique index cannot
///    express it.
///
/// 4. **Gated on `orders`, not on the `salary` money module.** The brief
///    assigns day close to the supervisor, and `presetFor('supervisor')`
///    grants orders view/create/edit but no money modules at all. Gating
///    wage entry behind `salary` would lock out the exact person the
///    screen exists for. Per CLAUDE.md the gate still goes through
///    [StaffPermissions.canActive] rather than a session-shape test, so a
///    vendor who customises the supervisor role is obeyed.
class CrewSheetPageWidget extends StatefulWidget {
  const CrewSheetPageWidget({super.key, this.orderId});

  final String? orderId;

  static String routeName = 'CrewSheetPage';
  static String routePath = '/crew-sheet';

  @override
  State<CrewSheetPageWidget> createState() => _CrewSheetPageWidgetState();
}

/// One person's line on the sheet. Holds both the persisted row (null
/// until they have ever been marked present) and the live edit state.
class _CrewLine {
  _CrewLine({required this.staff, this.existing})
      : present = existing != null,
        isDriver = existing?.isDriver ?? false,
        acDone = (existing?.acAmount ?? 0) > 0,
        wage = TextEditingController(
          text: (existing?.salaryAmount ?? 0) == 0
              ? ''
              : existing!.salaryAmount!.toStringAsFixed(0),
        ),
        ac = TextEditingController(
          text: (existing?.acAmount ?? 0) == 0
              ? ''
              : existing!.acAmount.toStringAsFixed(0),
        );

  final StaffRow staff;
  final OrderStaffRow? existing;

  bool present;
  bool isDriver;
  bool acDone;
  final TextEditingController wage;
  final TextEditingController ac;

  String get staffId => staff.id!;
  double get wageAmount => double.tryParse(wage.text.trim()) ?? 0;
  double get acAmount => acDone ? (double.tryParse(ac.text.trim()) ?? 0) : 0;
  double get total => wageAmount + acAmount;

  void dispose() {
    wage.dispose();
    ac.dispose();
  }
}

class _CrewSheetPageWidgetState extends State<CrewSheetPageWidget> {
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  OrdersRow? _order;
  List<_CrewLine> _lines = [];

  /// `order_staff` rows for people who are NOT crew-sheet eligible —
  /// monthly-fixed staff, almost always attached before pay types existed
  /// or by the supervisor's job_team sync. Validation rule §11 says they
  /// cannot be ADDED to a crew sheet; it says nothing about ones already
  /// there, and silently hiding them would leave labour cost in the job's
  /// profit that no screen can account for. So they are shown, read-only,
  /// with a way to detach them — visible and fixable, not invisible.
  List<OrderStaffRow> _ineligible = [];
  final Map<String, StaffRow> _staffById = {};

  /// Staff to open as present on the next load — set when a temporary hand
  /// is created mid-sheet, so the man who just turned up is ticked without
  /// the vendor having to find him again in the list.
  final Set<String> _pendingPresent = {};

  /// The last A/C amount typed on this sheet, reused as the default when a
  /// second person's A/C tick goes on. The diary's `500 x 2` on 27/8 is two
  /// men at the same rate; typing it twice is exactly the friction this
  /// screen exists to remove. Memory of a human's own number — not a
  /// derived or suggested wage (see the class doc, decision 1).
  String _lastAcAmount = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  bool get _canEdit => StaffPermissions.canActive('orders', 'edit') && !_locked;

  /// Mirrors OrderCrewSection's own lock: once the owner closes the order,
  /// its P&L inputs stop accepting changes. Deliberately NOT locked at
  /// supervisor completion — day close is when this sheet gets filled, so
  /// locking it at OTP success would lock it before its only use.
  bool get _locked => (_order?.status ?? '').toLowerCase() == 'closed';

  List<_CrewLine> get _present => _lines.where((l) => l.present).toList();
  double get _wageTotal => _present.fold(0.0, (s, l) => s + l.wageAmount);
  double get _acTotal => _present.fold(0.0, (s, l) => s + l.acAmount);

  _CrewLine? get _driver {
    for (final l in _present) {
      if (l.isDriver) return l;
    }
    return null;
  }

  Future<void> _load() async {
    final orderId = widget.orderId;
    if (orderId == null || orderId.isEmpty) {
      setState(() {
        _loading = false;
        _loadError = 'No order was passed to the crew sheet.';
      });
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        OrdersTable().queryRows(
          queryFn: (q) => OrgScope.read(q).eq('id', orderId),
        ),
        StaffTable().queryRows(
          queryFn: (q) => OrgScope.read(q).eq('active', true).order('name'),
        ),
        OrderStaffTable().queryRows(
          queryFn: (q) => OrgScope.read(q).eq('order_id', orderId),
        ),
      ]);
      final orders = (results[0] as List).cast<OrdersRow>();
      final staff = (results[1] as List).cast<StaffRow>();
      final crew = (results[2] as List).cast<OrderStaffRow>();

      _staffById
        ..clear()
        ..addEntries(
            staff.where((s) => s.id != null).map((s) => MapEntry(s.id!, s)));

      final crewByStaffId = <String, OrderStaffRow>{
        for (final c in crew)
          if (c.staffId != null) c.staffId!: c,
      };

      // Eligible universe: active dynamic + temporary staff. Monthly-fixed
      // staff are absent by construction (§11), not merely unticked.
      final eligible = staff.where(StaffPayType.isOnCrewSheet).toList();
      final eligibleIds = eligible.map((s) => s.id).toSet();

      for (final l in _lines) {
        l.dispose();
      }
      _lines = [
        for (final s in eligible)
          _CrewLine(staff: s, existing: crewByStaffId[s.id]),
      ];
      for (final l in _lines) {
        if (_pendingPresent.contains(l.staffId)) l.present = true;
      }
      _pendingPresent.clear();

      _ineligible = crew
          .where((c) => c.staffId != null && !eligibleIds.contains(c.staffId))
          .toList();

      _order = orders.isNotEmpty ? orders.first : null;
      _loadError = _order == null ? 'That order could not be found.' : null;
      _lastAcAmount = '';
    } catch (e) {
      _loadError = 'Could not load the crew sheet. $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _setPresent(_CrewLine line, bool present) {
    setState(() {
      line.present = present;
      // Absent means absent: a person who is not on the job cannot be its
      // driver, and cannot have done its A/C work. Leaving either flag set
      // on an unticked row is how a sheet ends up trying to save two
      // drivers.
      if (!present) {
        line.isDriver = false;
        line.acDone = false;
      }
    });
  }

  void _setDriver(_CrewLine line) {
    setState(() {
      final wasDriver = line.isDriver;
      for (final l in _lines) {
        l.isDriver = false;
      }
      // Tapping the current driver again clears the tag rather than being a
      // no-op — otherwise a mis-tap can only be corrected by tagging
      // somebody else, which is worse than an empty tag the save blocks.
      line.isDriver = !wasDriver;
    });
  }

  void _setAcDone(_CrewLine line, bool done) {
    setState(() {
      line.acDone = done;
      if (done && line.ac.text.trim().isEmpty && _lastAcAmount.isNotEmpty) {
        line.ac.text = _lastAcAmount;
      }
    });
  }

  // --------------------------------------------------------------------
  // Temporary hand — created from inside the sheet, two fields.
  // --------------------------------------------------------------------

  /// Brief §2: "A helper who turns up on the morning of a job is the most
  /// time-critical moment in the whole flow; if the vendor has to leave the
  /// job to add him, the app gets abandoned." Name and phone only — role
  /// and branch are inferred, and everything else on the staff record can
  /// wait until he becomes a regular.
  Future<void> _addTemporaryHand() async {
    final ng = NgPalette.of(context);
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ng.s1,
        title: const Text('Add temporary hand'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                  hintText: '+91 XXXXX XXXXX',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Paid for this job and settled the same day. If he keeps '
                'coming back, change his pay type to Dynamic on the Staff '
                'page — same person, history kept.',
                style: NgFonts.geist(
                    fontSize: 11.5, color: ng.mute),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.of(dialogContext).pop(true);
                }
              },
              child: const Text('Add')),
        ],
      ),
    );

    final name = nameCtrl.text.trim();
    final phone = phoneCtrl.text.trim();
    nameCtrl.dispose();
    phoneCtrl.dispose();
    if (confirmed != true || name.isEmpty || !mounted) return;

    // Brief §2: "Never force the vendor to create a second person for the
    // same man." This cannot detect a returning hand reliably, but a name
    // collision is worth one question before creating a duplicate person —
    // a duplicate splits his pay history in two, silently.
    StaffRow? clash;
    for (final s in _staffById.values) {
      if (s.name.trim().toLowerCase() == name.toLowerCase()) {
        clash = s;
        break;
      }
    }
    if (clash != null) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor:
              NgPalette.of(dialogContext).s1,
          title: const Text('Someone with this name already exists'),
          content: Text(
            '$name (${StaffPayType.label(StaffPayType.of(clash!))}) is already '
            'on the staff list. If this is the same man, cancel and tick him '
            'on the sheet instead — adding him again splits his pay history '
            'in two.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Add anyway')),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _saving = true);
    try {
      final created = await StaffTable().insert({
        ...OrgScope.stamp(),
        'name': name,
        'phone': phone.isEmpty ? null : phone,
        // The staff role vocabulary (permissions.dart / staff_form_sheet)
        // is about ACCESS; pay_type is about how he earns. A casual hand is
        // a helper with no PIN — he never logs in.
        'role': 'helper',
        'pay_type': StaffPayType.temporary,
        'active': true,
        // Inherit the job's branch so he lands in the right branch's
        // reporting. Null is safe: staff_branch_fk is a composite FK, so a
        // null branch is simply not checked.
        if ((_order?.branch ?? '').isNotEmpty) 'branch': _order!.branch,
      });
      if (created.id != null) _pendingPresent.add(created.id!);
      await _load();
      if (mounted) _toast('$name added and marked present.');
    } catch (e) {
      if (mounted) _toast('Could not add $name: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // --------------------------------------------------------------------
  // Save
  // --------------------------------------------------------------------

  Future<void> _save() async {
    final orderId = widget.orderId!;
    final present = _present;

    if (present.isEmpty) {
      _toast('Mark at least one person present before saving.');
      return;
    }
    final drivers = present.where((l) => l.isDriver).toList();
    if (drivers.isEmpty) {
      // Brief §4: "a job cannot be saved with zero drivers tagged, or with
      // more than one". More-than-one is unreachable through this UI
      // (_setDriver clears the others) and is additionally refused by
      // Postgres, so zero is the half that has to live here.
      _toast('Tap one name as the driver for this job.');
      return;
    }
    if (drivers.length > 1) {
      _toast('Only one person can be tagged as driver.');
      return;
    }

    // Blanks are questioned once, never blocked — the vendor decides what a
    // man earns, including nothing (§3: "the app's job is arithmetic and
    // memory, not judgement"). But a silently-zero wage on a present crew
    // member is far more often a missed field than a decision.
    final noWage = present.where((l) => l.wageAmount <= 0).toList();
    final noAc = present.where((l) => l.acDone && l.acAmount <= 0).toList();
    if (noWage.isNotEmpty || noAc.isNotEmpty) {
      final msgs = <String>[
        if (noWage.isNotEmpty)
          'No amount entered for: ${noWage.map((l) => l.staff.name).join(', ')}.',
        if (noAc.isNotEmpty)
          'A/C ticked with no amount for: ${noAc.map((l) => l.staff.name).join(', ')}.',
      ];
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor:
              NgPalette.of(dialogContext).s1,
          title: const Text('Save with blanks?'),
          content: Text('${msgs.join('\n\n')}\n\nThey will be recorded as ₹0.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Go back')),
            FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Save anyway')),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _saving = true);
    try {
      final orgId = OrgScope.currentOrgId;

      // 1. Clear every existing driver tag on this order FIRST. The partial
      //    unique index `order_staff_one_driver_per_order` is checked as
      //    each row is written, so upserting a new driver while the old one
      //    is still flagged is a live constraint violation, not a
      //    last-write-wins.
      await OrderStaffTable().update(
        data: {'is_driver': false},
        matchingRows: (q) =>
            OrgScope.write(q).eq('order_id', orderId).eq('is_driver', true),
      );

      // 2. Drop anyone toggled off. Scoped to the crew-sheet-eligible staff
      //    on screen, so a row this sheet never showed (the monthly-fixed
      //    leftovers in [_ineligible]) is never collateral.
      final removedIds = _lines
          .where((l) => !l.present && l.existing != null)
          .map((l) => l.staffId)
          .toList();
      if (removedIds.isNotEmpty) {
        await OrderStaffTable().delete(
          matchingRows: (q) => OrgScope.write(q)
              .eq('order_id', orderId)
              .inFilter('staff_id', removedIds),
        );
      }

      // 3. One statement for every present row. Upsert on the real
      //    (order_id, staff_id) unique constraint rather than the old
      //    "insert, catch the conflict, update" dance — per CLAUDE.md's
      //    convention for any table that actually has one.
      final payload = [
        for (final l in present)
          {
            ...OrgScope.stamp(orgId: orgId),
            'order_id': orderId,
            'staff_id': l.staffId,
            'salary_amount': l.wageAmount,
            // `order_staff.ac_amount` is
            // `GENERATED ALWAYS AS ((ac_units)::numeric * ac_rate) STORED`,
            // so naming it in any write raises 428C9 before anything lands.
            // It was named here, which is why every save this sheet has ever
            // attempted failed at the database — see CLAUDE.md, "the Crew
            // Sheet has NEVER been able to save". `ac_units`/`ac_rate` are
            // the only writable inputs.
            //
            // The sheet asks for a flat per-man A/C amount, so units = 1 and
            // rate = the typed figure: the generated column then equals what
            // the vendor typed, exactly. Not ticked -> 0 units, not 1 unit at
            // a zero rate. If A/C turns out to be genuinely per-unit (brief
            // §12.1) that changes what the FORM asks for; this does not stand
            // in the way of it.
            'ac_units': l.acDone ? 1 : 0,
            'ac_rate': l.acAmount,
            'is_driver': l.isDriver,
            'team_type': 'labour',
          }
      ];
      await SupaFlow.client
          .from('order_staff')
          .upsert(payload, onConflict: 'order_id,staff_id');

      final savedWages = _wageTotal;
      final savedAc = _acTotal;
      await AuditLogService.log(
        entityType: 'order',
        entityId: orderId,
        action: 'crew_sheet_saved',
        newValue: {
          'headcount': present.length,
          'driver_staff_id': drivers.first.staffId,
          'wage_total': savedWages,
          'ac_total': savedAc,
          'removed_staff_ids': removedIds,
        },
        changedFields: const ['order_staff'],
      );

      // Never hand-patch local state after a write (CLAUDE.md): re-read the
      // rows, so anything a default or a trigger set comes back too.
      await _load();
      if (mounted) {
        final money = NumberFormat.decimalPattern('en_IN');
        _toast('Crew sheet saved — ${present.length} on the job, '
            '₹${money.format(savedWages + savedAc)} total.');
      }
    } catch (e) {
      if (mounted) _toast('Could not save the crew sheet: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _detachIneligible(OrderStaffRow row) async {
    final name = _staffById[row.staffId]?.name ?? 'This person';
    setState(() => _saving = true);
    try {
      await OrderStaffTable().delete(
        matchingRows: (q) => OrgScope.write(q).eq('id', row.id!),
      );
      await _load();
      if (mounted) _toast('$name removed from this job.');
    } catch (e) {
      if (mounted) _toast('Could not remove $name: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // --------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ng = NgPalette.of(context);
    return Scaffold(
      backgroundColor: ng.bg,
      appBar: NgSimpleBar(title: 'Crew sheet', actions: [
        NgHeaderButtonBox(
          icon: Icons.refresh_rounded,
          tooltip: 'Reload',
          onTap: _saving ? null : _load,
        ),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: LoadErrorState(message: _loadError!, onRetry: _load))
              : _body(ng),
      bottomNavigationBar:
          _loading || _loadError != null ? null : _footer(ng),
    );
  }

  Widget _body(NgPalette ng) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _jobHeader(ng),
          if (!StaffPermissions.canActive('orders', 'edit'))
            _notice(ng,
                icon: Icons.lock_outline_rounded,
                text: 'You can view this crew sheet but not change it.'),
          if (_locked)
            _notice(ng,
                icon: Icons.lock_rounded,
                text: 'This order is closed. The crew sheet is locked so the '
                    "job's profit figure cannot move after the fact."),
          const SizedBox(height: 18),
          NgGroupTitle(
            'Crew · ${_present.length} present',
            actionLabel: 'Temp hand',
            onAction: _canEdit && !_saving ? _addTemporaryHand : null,
          ),
          if (_lines.isEmpty)
            _notice(ng,
                icon: Icons.groups_outlined,
                text:
                    'No crew to show. Only Dynamic and Temporary staff appear '
                    'here — monthly-fixed staff earn their salary, not a job '
                    'wage. Add a temporary hand above, or set a pay type on '
                    'the Staff page.')
          else
            NgRowsCard(rows: [for (final l in _lines) _crewRow(ng, l)]),
          if (_ineligible.isNotEmpty) _ineligibleCard(ng),
        ],
      ),
    );
  }

  Widget _jobHeader(NgPalette ng) {
    final o = _order!;
    final route =
        [o.fromCity, o.toCity].where((c) => (c ?? '').isNotEmpty).join(' → ');
    return NgCard(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(o.id ?? '',
                  style: NgFonts.mono(fontSize: 12, color: ng.faint)),
            ),
            Icon(Icons.event_outlined, size: 16, color: ng.mute),
            const SizedBox(width: 5),
            Text(DateFormat('d MMM yyyy').format(o.moveDate),
                style: NgFonts.geist(
                    fontSize: 12.5, fontWeight: FontWeight.w500, color: ng.soft)),
          ]),
          const SizedBox(height: 10),
          Text(o.customer,
              style: NgFonts.geist(
                  fontSize: 17, fontWeight: FontWeight.w600, color: ng.text)),
          if (route.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(route, style: NgFonts.geist(fontSize: 13, color: ng.mute)),
          ],
        ],
      ),
    );
  }

  Widget _notice(NgPalette ng,
      {required IconData icon, required String text}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ng.amberBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: ng.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: NgFonts.geist(fontSize: 13, height: 1.4, color: ng.text)),
          ),
        ],
      ),
    );
  }

  Widget _smallMoneyField(NgPalette ng, TextEditingController ctrl,
          {required String hint, required ValueChanged<String> onChanged}) =>
      SizedBox(
        width: 120,
        child: TextField(
          controller: ctrl,
          enabled: _canEdit && !_saving,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: onChanged,
          style: NgFonts.mono(fontSize: 14, color: ng.text),
          cursorColor: ng.acc,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: NgFonts.geist(fontSize: 13, color: ng.faint),
            prefixText: '₹ ',
            prefixStyle: NgFonts.mono(fontSize: 14, color: ng.mute),
            filled: true,
            fillColor: ng.inset,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: ng.w08)),
            disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: ng.w06)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: ng.acc, width: 1.5)),
          ),
        ),
      );

  Widget _crewRow(NgPalette ng, _CrewLine l) {
    final isTemp = StaffPayType.of(l.staff) == StaffPayType.temporary;
    final money = NumberFormat.decimalPattern('en_IN');
    final canTap = _canEdit && !_saving;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: canTap ? () => _setPresent(l, !l.present) : null,
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: l.present ? ng.accBtn : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                        width: 1.5, color: l.present ? ng.accBtn : ng.w15),
                  ),
                  child: l.present
                      ? const Icon(Icons.check_rounded,
                          size: 16, color: NgPalette.onAcc)
                      : null,
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    l.staff.name,
                    overflow: TextOverflow.ellipsis,
                    style: NgFonts.geist(
                      fontSize: 14.5,
                      fontWeight: l.present ? FontWeight.w600 : FontWeight.w400,
                      color: l.present ? ng.text : ng.mute,
                    ),
                  ),
                ),
                if (isTemp) ...[
                  const SizedBox(width: 6),
                  const NgPill('Temp', status: NgStatus.blue),
                ],
                const Spacer(),
                if (l.present)
                  Text('₹${money.format(l.total)}',
                      style: NgFonts.mono(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: ng.text)),
              ],
            ),
          ),
          if (l.present) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _smallMoneyField(ng, l.wage,
                      hint: 'Wage', onChanged: (_) => setState(() {})),
                  _tagButton(ng,
                      label: 'Driver',
                      icon: Icons.local_shipping_outlined,
                      selected: l.isDriver,
                      onTap: canTap ? () => _setDriver(l) : null),
                  _tagButton(ng,
                      label: 'A/C',
                      icon: Icons.ac_unit_rounded,
                      selected: l.acDone,
                      onTap: canTap ? () => _setAcDone(l, !l.acDone) : null),
                ],
              ),
            ),
            if (l.acDone)
              Padding(
                padding: const EdgeInsets.only(left: 36, top: 8),
                child: Row(
                  children: [
                    _smallMoneyField(ng, l.ac,
                        hint: 'A/C work',
                        onChanged: (v) => setState(() {
                              if (v.trim().isNotEmpty) {
                                _lastAcAmount = v.trim();
                              }
                            })),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Added on top of the wage, and reported as its own line.',
                        style: NgFonts.geist(fontSize: 12, color: ng.mute),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _tagButton(
    NgPalette ng, {
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final fg = selected ? ng.acc : ng.soft;
    return Material(
      color: selected ? ng.status(NgStatus.accent).bg : ng.s2,
      shape: StadiumBorder(
          side: BorderSide(color: selected ? ng.acc : Colors.transparent)),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 5),
              Text(label,
                  style: NgFonts.geist(
                      fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ineligibleCard(NgPalette ng) {
    final money = NumberFormat.decimalPattern('en_IN');
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const NgGroupTitle('Not paid per job'),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(
              'These people are attached to this job but are on a monthly '
              'salary, so they do not earn a job wage. Their amounts still '
              "count as labour cost in this job's profit — remove them if they "
              'were added by mistake.',
              style: NgFonts.geist(fontSize: 12.5, height: 1.4, color: ng.mute),
            ),
          ),
          NgRowsCard(rows: [
            for (final r in _ineligible)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                child: Row(
                  children: [
                    NgAvatar(_staffById[r.staffId]?.name ?? 'Staff', size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_staffById[r.staffId]?.name ?? 'Staff',
                          style: NgFonts.geist(fontSize: 14, color: ng.text)),
                    ),
                    Text(
                        '₹${money.format((r.salaryAmount ?? 0) + r.acAmount)}',
                        style: NgFonts.mono(fontSize: 13.5, color: ng.text)),
                    const SizedBox(width: 6),
                    NgLinkButton('Remove',
                        onTap: _canEdit && !_saving && r.id != null
                            ? () => _detachIneligible(r)
                            : null),
                  ],
                ),
              ),
          ]),
        ],
      ),
    );
  }

  Widget _footer(NgPalette ng) {
    final money = NumberFormat.decimalPattern('en_IN');
    final driver = _driver;
    return NgBottomActionBar(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Wages today',
                    style: NgFonts.geist(fontSize: 12.5, color: ng.mute)),
                Text('₹${money.format(_wageTotal + _acTotal)}',
                    style: NgFonts.mono(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        color: ng.text)),
                Text(
                  // A/C reports as its own line, never absorbed into the
                  // wage figure (brief §5).
                  [
                    if (_acTotal > 0) 'A/C ₹${money.format(_acTotal)}',
                    '${_present.length} present',
                    driver == null
                        ? 'no driver tagged'
                        : 'driver ${driver.staff.name}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NgFonts.geist(
                    fontSize: 12,
                    color: driver == null && _present.isNotEmpty
                        ? ng.red
                        : ng.mute,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: NgPrimaryButton(
              icon: Icons.check_rounded,
              label: _saving ? 'Saving…' : 'Save',
              onPressed: _canEdit && !_saving ? _save : null,
            ),
          ),
        ],
      ),
    );
  }
}
