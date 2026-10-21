import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/staff_pay_types.dart';
import '/components/load_error_state.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import '/l10n/gen/app_localizations.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'staff_form_sheet.dart';
import 'users_page_model.dart';
export 'users_page_model.dart';

/// Staff Management (Week 2 of the v1 launch plan).
///
/// History: was an empty FlutterFlow shell with hardcoded cards, then a
/// read-only list. Now full CRUD-lite: add/edit via StaffFormSheet
/// (bottom sheet), role filter chips matching the real APC roles
/// (supervisor / driver / helper / packer / admin), active/inactive
/// sections, and plan-limit gating on add (subscription_plans.limits
/// key `max_users`, -1 = unlimited).
///
/// Org-scoped via OrgScope (reads, writes, and insert stamping) — see
/// LEAK_AUDIT.md conventions. Deleting staff is deliberately not offered:
/// staff rows are referenced by orders/attendance/salary history, so the
/// supported flow is marking them Inactive (also blocks their PIN login).
class UsersPageWidget extends StatefulWidget {
  const UsersPageWidget({super.key});

  static String routeName = 'UsersPage';
  static String routePath = '/users';

  @override
  State<UsersPageWidget> createState() => _UsersPageWidgetState();
}

class _UsersPageWidgetState extends State<UsersPageWidget>
    with RefreshOnPopMixin<UsersPageWidget> {
  late UsersPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => UsersPageModel());

    SchedulerBinding.instance.addPostFrameCallback((_) => _reload());

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  // Refresh-after-write fix (parity brief Part 1): re-run when
  // StaffFormSheet (add/edit) is popped back to this list.
  @override
  void onPageRefresh() => _reload();

  Future<void> _reload() async {
    // Hang follow-up (7 Aug 2026): was unguarded — a failure here used to
    // leave the page on "Loading…" forever with no way to tell whether it
    // was still working or stuck. See table.dart's new query timeout for
    // the other half of this fix.
    try {
      _model.staffOut = await StaffTable().queryRows(
        queryFn: (q) => OrgScope.read(q).order('name'),
      );
      _model.staffList = (_model.staffOut ?? []).toList().cast<StaffRow>();
      _loadError = null;
    } catch (e) {
      _loadError = 'Could not load staff: $e';
    }
    safeSetState(() {});
  }

  late final _searchCtrl = TextEditingController(text: _model.searchQuery);

  @override
  void dispose() {
    _model.dispose();
    _searchCtrl.dispose();

    super.dispose();
  }

  List<StaffRow> get _filteredStaff {
    var out = _model.staffList;
    if (_model.roleFilter != null) {
      out = out
          .where((s) => (s.role ?? '').toLowerCase() == _model.roleFilter)
          .toList();
    }
    final q = _model.searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out
          .where((s) =>
              s.name.toLowerCase().contains(q) ||
              (s.phone ?? '').toLowerCase().contains(q))
          .toList();
    }
    return out;
  }

  Future<void> _addStaff() async {
    // Plan gate: limits.max_users from the org's subscription plan.
    // Counts every staff row (active + inactive) — an inactive row still
    // occupies a seat until the org upgrades.
    final count = _model.staffList.length;
    if (AppSession.instance.isOverLimit('max_users', count)) {
      final max = AppSession.instance.getLimit('max_users');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Staff limit reached ($count/$max on the '
            '${AppSession.instance.planName ?? 'current'} plan). '
            'Upgrade to add more staff.',
          ),
          duration: const Duration(milliseconds: 4000),
        ),
      );
      return;
    }
    final saved = await StaffFormSheet.show(context);
    if (saved) _reload();
  }

  // RLS remediation Tier A (supabase/20260808_tierA_staff_credentials_rls.sql,
  // not yet run — this gate ships in the APK first, same ordering rule as
  // Phase 0's set_staff_pin() rollout): UPDATE/DELETE on `staff` becomes
  // owner-only at the database, via is_org_owner(org_id), which checks
  // org_members.role = 'owner' — a genuine vendor/Auth session, never a
  // staff PIN session, not even one whose own staff.role is 'manager' or
  // 'admin'. AppSession.instance.currentStaffId == null is the exact
  // client-side mirror of that same check (same gate SettingsPage already
  // uses for its owner-only PIN card and Recycle Bin). Add Staff is
  // untouched — Tier A leaves INSERT at org-scope, so a manager creating a
  // new staff member still works both before and after that migration runs.
  bool get _isOwnerSession => AppSession.instance.currentStaffId == null;

  Future<void> _editStaff(StaffRow s) async {
    if (!_isOwnerSession) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only the owner can edit staff details.'),
        ),
      );
      return;
    }
    final saved = await StaffFormSheet.show(context, existing: s);
    if (saved) _reload();
  }

  /// Pay-type filter (the handoff's first chip row). Null = all.
  String? _payFilter;

  String _payLabel(String payType) {
    final l = AppLocalizations.of(context);
    return switch (payType) {
      StaffPayType.monthlyFixed => l.ngStaffMonthly,
      StaffPayType.temporary => l.ngStaffTemporary,
      _ => l.ngStaffDaily,
    };
  }

  String _roleLabel(String? role) {
    final r = (role ?? '').trim();
    return r.isEmpty ? '' : r[0].toUpperCase() + r.substring(1);
  }

  Widget _staffRow(BuildContext context, StaffRow s) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final active = s.active ?? true;
    final pay = StaffPayType.of(s);
    final phone = (s.phone ?? '').trim();
    final line1 = [
      _payLabel(pay),
      if (pay == StaffPayType.monthlyFixed && (s.salary ?? 0) > 0)
        functions.inrFull(s.salary),
      if (s.createdAt != null)
        l.ngStaffJoined(DateFormat("d MMM ''yy").format(s.createdAt!)),
    ].join(' · ');
    return InkWell(
      onTap: () => _editStaff(s),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            NgAvatar(s.name,
                status: active ? NgStatus.blue : NgStatus.neutral, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: s.name,
                          style: NgFonts.geist(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: active ? c.text : c.mute)),
                      if (_roleLabel(s.role).isNotEmpty)
                        TextSpan(
                            text: ' · ${_roleLabel(s.role)}',
                            style:
                                NgFonts.geist(fontSize: 12.5, color: c.mute)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(line1,
                      maxLines: 2,
                      style: NgFonts.geist(
                          fontSize: 12.5, height: 1.35, color: c.mute)),
                  if (phone.isNotEmpty)
                    Text(phone,
                        style: NgFonts.mono(fontSize: 12, color: c.mute)),
                ],
              ),
            ),
            if (phone.isNotEmpty)
              SizedBox(
                width: 38,
                height: 38,
                child: Material(
                  color: c.s2,
                  borderRadius: BorderRadius.circular(11),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(11),
                    onTap: () => launchURL('tel:$phone'),
                    child: Icon(Icons.call_outlined, size: 18, color: c.green),
                  ),
                ),
              ),
            const SizedBox(width: 4),
            // Edit is owner-only at the database (Tier A RLS), so a staff
            // session sees a lock instead of a way in.
            Icon(
                _isOwnerSession
                    ? Icons.chevron_right_rounded
                    : Icons.lock_outline_rounded,
                size: 20,
                color: c.faint),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final all = _model.staffList;
    int payCount(String p) =>
        all.where((s) => StaffPayType.of(s) == p).length;
    final filtered = _filteredStaff
        .where((s) => _payFilter == null || StaffPayType.of(s) == _payFilter)
        .toList();
    final active = filtered.where((s) => s.active ?? true).toList();
    final inactive = filtered.where((s) => !(s.active ?? true)).toList();
    const roles = ['supervisor', 'driver', 'helper', 'packer', 'admin'];
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: c.bg,
      appBar: NgTopBar(onRefresh: _reload),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            NgModuleHeader(
              l.ngStaffTitle,
              subtitle: l.ngStaffSummary(
                  all.length,
                  payCount(StaffPayType.monthlyFixed),
                  all.length - payCount(StaffPayType.monthlyFixed)),
              actions: [
                NgPrimaryButton(
                  compact: true,
                  height: 40,
                  icon: Icons.person_add_alt_1_outlined,
                  label: l.ngStaffAdd,
                  onPressed: _addStaff,
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_loadError != null)
              LoadErrorState(message: _loadError!, onRetry: _reload)
            else ...[
              NgSearchField(
                controller: _searchCtrl,
                hint: l.ngNameOrPhone,
                onChanged: (v) => safeSetState(() => _model.searchQuery = v),
              ),
              const SizedBox(height: 14),
              NgChipRow(
                edge: 0,
                chips: [
                  NgChip(
                    label: l.ngTabAll,
                    count: all.length,
                    selected: _payFilter == null,
                    onTap: () => safeSetState(() => _payFilter = null),
                  ),
                  for (final p in StaffPayType.all)
                    NgChip(
                      label: _payLabel(p),
                      count: payCount(p),
                      selected: _payFilter == p,
                      onTap: () => safeSetState(() => _payFilter = p),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final r in [null, ...roles])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () =>
                              safeSetState(() => _model.roleFilter = r),
                          child: Container(
                            height: 32,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _model.roleFilter == r
                                  ? c.sel
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                                r == null ? l.ngStaffAllRoles : _roleLabel(r),
                                style: NgFonts.geist(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: _model.roleFilter == r
                                        ? c.text
                                        : c.mute)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (active.isEmpty && inactive.isEmpty)
                NgCard(
                  child: Text(l.ngStaffNone,
                      textAlign: TextAlign.center,
                      style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
                )
              else ...[
                if (active.isNotEmpty)
                  NgCardList(children: [
                    for (final s in active) _staffRow(context, s),
                  ]),
                if (inactive.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  NgSectionHeader(l.ngStaffInactive,
                      trailing: '${inactive.length}'),
                  const SizedBox(height: 10),
                  NgCardList(children: [
                    for (final s in inactive) _staffRow(context, s),
                  ]),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }
}
