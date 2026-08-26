import '/app_session.dart';
import '/backend/supabase/supabase.dart';

/// Nagarva staff permissions model.
///
/// Stored per staff member in `staff.permissions` (jsonb) as:
///   { "orders": {"view": true, "create": true, "edit": false, "delete": false},
///     "payments": {"view": true, ...}, ... }
///
/// Module keys map 1:1 to the sidebar page names in main.dart, so the
/// sidebar can be driven by permissions instead of the hardcoded
/// {HomePage, OrdersPage, OperationsPage} allow-list.
///
/// Convention: an empty/missing permissions map means "fall back to the
/// role preset" — so existing staff rows (permissions = {}) keep working
/// exactly as before until the owner edits them.
class PermModule {
  const PermModule(this.key, this.label, this.pageName, {this.moneyModule = false});

  /// Stable key used in the jsonb payload. Never rename without a migration.
  final String key;

  /// Human label shown in the permission table.
  final String label;

  /// Route/page name in main.dart's nav list.
  final String pageName;

  /// Money-sensitive modules. These stay owner-only unless explicitly
  /// granted, and are never included in a non-admin role preset.
  final bool moneyModule;
}

const kPermActions = <String>['view', 'create', 'edit', 'delete'];

/// Short column headers for the permission table.
const kPermActionLabels = <String, String>{
  'view': 'View',
  'create': 'Add',
  'edit': 'Edit',
  'delete': 'Del',
};

const kPermModules = <PermModule>[
  PermModule('dashboard', 'Dashboard', 'HomePage'),
  PermModule('orders', 'Orders', 'OrdersPage'),
  PermModule('leads', 'Leads / CRM', 'LeadsPage'),
  PermModule('operations', 'Operations', 'OperationsPage'),
  PermModule('payments', 'Payments', 'PaymentsPage', moneyModule: true),
  PermModule('expenses', 'Expenses', 'ExpensePage', moneyModule: true),
  PermModule('accounts', 'Accounts', 'AccountsPage', moneyModule: true),
  PermModule('salary', 'Salary', 'SalaryPage', moneyModule: true),
  PermModule('staff', 'Staff', 'UsersPage'),
  PermModule('fleet', 'Fleet', 'FleetPage'),
  PermModule('pl_report', 'P & L', 'PLReportPage', moneyModule: true),
  PermModule('settings', 'Settings', 'SettingsPage'),
  // Added per the permission-model decision (1 Aug 2026), decision 2:
  // "fleet" and "accounts" were already asked for but already existed
  // above (flagged back rather than duplicated) - these three are the
  // genuinely new ones. Keys are cheap now, expensive to retrofit once
  // real staff.permissions rows exist with a fixed module set.
  PermModule('materials', 'Materials', 'MaterialsPage'),
  PermModule('reports', 'Reports', 'ReportsPage'),
  // Session 4, Part B2/B3: Reviews and WA Inbox were ComingSoon stubs with
  // no permission module at all — owner/manager get them automatically
  // via fullAccess() (iterates kPermModules), every other role simply
  // doesn't see them unless granted per person, same as any other module
  // absent from that role's presetFor() list.
  PermModule('reviews', 'Reviews', 'ReviewsPage'),
  PermModule('inbox', 'WA Inbox', 'WaInboxPage'),
  // Session 4, Part B4.
  PermModule('survey_quote', 'Survey & Quote', 'SurveyQuoteHubPage'),
  // Session 4, Part B1.
  PermModule('surveys', 'Customer Surveys', 'CustomerSurveysPage'),
  // Session 4, Part C-2.
  PermModule('rate_cards', 'Rate Cards', 'RateCardsPage'),
  // Session 4, Part C-3.
  PermModule('lr_register', 'LR Register', 'LrRegisterPage'),
  // Session 4, Part C-4.
  PermModule('ops_log', 'Ops Log', 'OperationsStandalonePage'),
  // Session 4, Part C-6.
  PermModule('vendors', 'Vendors', 'VendorsPage'),
  // Session 4, Part C-7.
  PermModule('customers', 'Customers', 'CustomersPage'),
  // Session 4, Part C-8.
  PermModule('insurance_claims', 'Insurance & Claims', 'InsuranceClaimsPage'),
  // Session 4, Part C-9.
  PermModule('trips', 'Trips', 'TripsPage'),
  // Session 4, Part C-12.
  PermModule('tasks', 'Tasks & Activities', 'TasksPage'),

  // ---------------------------------------------------------------
  // Dashboard financial tiers (25 Aug 2026).
  //
  // Split out of `reports`, which was a single coarse gate covering
  // operational counts, revenue AND margin at once. That made a
  // branch manager who needs Active Moves indistinguishable from one
  // trusted with net profit. Decided BEFORE the dashboard redesign
  // deliberately: tiles are built against the final matrix rather
  // than retrofitted onto it.
  //
  // The three tiers, and what each gates:
  //   reports.view            operational counts (leads, orders,
  //                           reminders, active moves)
  //   financials.view         revenue, outstanding, monthly target
  //   financials_margin.view  profit, expenses, cost
  //
  // NOTE ON NAMING: the decision was written as `financials.margin`.
  // That would be a fifth ACTION, and kPermActions is a global list
  // driving the columns of the permission table in
  // staff_form_sheet.dart — adding one there would put a "Margin"
  // checkbox on all 27 modules, meaningless on 25 of them. Modelled
  // as a second MODULE instead, so the semantics are exactly as
  // decided while the table stays a clean 4-column grid.
  //
  // PAGE NAME IS DELIBERATELY EMPTY: neither is a navigable page,
  // they gate cards on a page the `dashboard` module already covers.
  // allowedPageNames() skips empty names so these can never widen
  // the sidebar. See its own comment.
  //
  // Both are moneyModule, so they carry the ₹ marker and stay out of
  // every non-owner/manager preset unless granted per person.
  PermModule('financials', 'Financials — Revenue', '', moneyModule: true),
  PermModule('financials_margin', 'Financials — Margin & Cost', '',
      moneyModule: true),
];

/// Helpers for reading/writing the jsonb payload.
class StaffPermissions {
  /// Safely coerce whatever came back from Supabase into a nested map.
  /// Accepts null, {}, or a well-formed map; anything else yields {}.
  static Map<String, Map<String, bool>> decode(dynamic raw) {
    final out = <String, Map<String, bool>>{};
    if (raw is! Map) return out;
    for (final m in kPermModules) {
      final v = raw[m.key];
      if (v is! Map) continue;
      final actions = <String, bool>{};
      for (final a in kPermActions) {
        if (v[a] == true) actions[a] = true;
      }
      if (actions.isNotEmpty) out[m.key] = actions;
    }
    return out;
  }

  /// Build the jsonb payload. Only `true` flags are stored, so the column
  /// stays small and "missing" always reads as false.
  static Map<String, dynamic> encode(Map<String, Map<String, bool>> perms) {
    final out = <String, dynamic>{};
    perms.forEach((moduleKey, actions) {
      final on = <String, dynamic>{};
      actions.forEach((a, v) {
        if (v == true) on[a] = true;
      });
      if (on.isNotEmpty) out[moduleKey] = on;
    });
    return out;
  }

  static bool isEmpty(Map<String, Map<String, bool>> perms) =>
      encode(perms).isEmpty;

  /// Does this permission set allow [action] on [moduleKey]?
  static bool can(
    Map<String, Map<String, bool>> perms,
    String moduleKey,
    String action,
  ) =>
      perms[moduleKey]?[action] == true;

  /// Any access at all to a module (used for sidebar visibility).
  static bool canSeeModule(
          Map<String, Map<String, bool>> perms, String moduleKey) =>
      (perms[moduleKey] ?? const {}).values.any((v) => v == true);

  /// Canonical role vocabulary (permission-model decision, 1 Aug 2026,
  /// "supersedes Users Kickoff §1"). `org_members.role` (owner/staff/
  /// manager) and `staff.role` (manager/supervisor/driver/helper/packer/
  /// admin) used three overlapping vocabularies before this — this is the
  /// one list everything should normalise to. `admin` is kept as a read
  /// alias for `owner` (see [_normalizeRole]) rather than migrated in the
  /// DB, per the decision's own instruction not to run that migration
  /// blind.
  static const kCanonicalRoles = [
    'owner', 'manager', 'supervisor', 'driver', 'packer', 'helper',
  ];

  /// `admin` -> `owner` alias on read only; every other value passes
  /// through lowercased. Never write `'admin'` as a new role — new staff
  /// rows should use `'owner'`/`'manager'` directly.
  static String _normalizeRole(String? role) {
    final r = (role ?? '').toLowerCase();
    return r == 'admin' ? 'owner' : r;
  }

  /// Public alias check for callers outside this file (e.g.
  /// staff_form_sheet.dart's "owner role can't have permissions edited"
  /// rule, Users Kickoff Step 3.2) that need to know whether a raw
  /// `staff.role` value resolves to owner-equivalent access, without
  /// duplicating the 'admin' alias logic locally.
  static bool isOwnerRole(String? role) => _normalizeRole(role) == 'owner';

  /// Role defaults. Used to pre-fill the matrix when a role is picked,
  /// and as the fallback for staff rows that have no permissions yet.
  ///
  /// Money modules (Payments/Expenses/Salary/P&L) are OFF for every role
  /// except owner/manager — grant them per person if you want a specific
  /// supervisor to see money.
  static Map<String, Map<String, bool>> presetFor(String role) {
    final r = _normalizeRole(role);

    Map<String, Map<String, bool>> build(Map<String, List<String>> spec) {
      final out = <String, Map<String, bool>>{};
      spec.forEach((k, actions) {
        out[k] = {for (final a in actions) a: true};
      });
      return out;
    }

    Map<String, Map<String, bool>> fullAccess() => {
          for (final m in kPermModules)
            m.key: {for (final a in kPermActions) a: true}
        };

    switch (r) {
      case 'owner':
        // Full access to everything, including money modules. Also
        // short-circuited before this is ever called for a real vendor
        // session — see AppSession.currentStaffId == null callers and
        // [canActive] — but presetFor('owner') resolves correctly on its
        // own too, for direct callers and tests.
        return fullAccess();
      case 'manager':
        // Real preset, previously missing entirely (defect 2) — a
        // manager fell through to the conservative `default` case below,
        // i.e. dashboard/orders/operations view-only, which is not what
        // any prior brief describes a manager as. Modelled as full
        // access, matching every manager row in the Part 8 kickoff's own
        // now-superseded role-default table (manager = 1 for all 14
        // keys there) — not an owner-level *bypass* (still goes through
        // the matrix, still overridable per person), just the same
        // breadth of grant.
        return fullAccess();
      case 'supervisor':
        return build({
          'dashboard': ['view'],
          'orders': ['view', 'create', 'edit'],
          'leads': ['view', 'create', 'edit'],
          'operations': ['view', 'create', 'edit'],
          'staff': ['view'],
          'fleet': ['view'],
        });
      case 'driver':
        return build({
          'dashboard': ['view'],
          'orders': ['view'],
          'operations': ['view', 'edit'],
          'fleet': ['view'],
        });
      case 'helper':
      case 'packer':
        return build({
          'dashboard': ['view'],
          'orders': ['view'],
          'operations': ['view'],
        });
      default:
        return build({
          'dashboard': ['view'],
          'orders': ['view'],
          'operations': ['view'],
        });
    }
  }

  /// Effective permissions for a logged-in staff member: role preset as
  /// the foundation, with any saved per-action overrides layered on top.
  ///
  /// FIXED (defect 1, permission-model decision 1 Aug 2026): this used to
  /// be all-or-nothing — any saved permissions at all discarded the role
  /// preset entirely, so granting a supervisor one extra permission
  /// silently dropped every other permission their role had (a module
  /// absent from the saved matrix stopped inheriting its default instead
  /// of falling back to it). Now merges per **action**: saving
  /// `{"orders": {"delete": true}}` overrides only `orders.delete` —
  /// `orders.view`/`create`/`edit` still come from the role preset.
  ///
  /// `owner` short-circuits to full access unconditionally, before the
  /// saved matrix is even consulted — matches Users Kickoff §3.2's rule
  /// that an owner's permissions can never be edited down.
  static Map<String, Map<String, bool>> effective({
    required dynamic rawPermissions,
    required String? role,
  }) {
    final canonicalRole = _normalizeRole(role);
    if (canonicalRole == 'owner') return presetFor('owner');

    final base = presetFor(canonicalRole);
    final saved = decode(rawPermissions);
    if (isEmpty(saved)) return base;

    final merged = <String, Map<String, bool>>{};
    for (final moduleKey in {...base.keys, ...saved.keys}) {
      merged[moduleKey] = {
        ...?base[moduleKey],
        ...?saved[moduleKey],
      };
    }
    return merged;
  }

  // ------------------------------------------------------------------
  // Active staff session state (set at PIN login / session restore,
  // cleared on Lock/Logout). main.dart's sidebar reads this; null means
  // "no staff permissions loaded" and the sidebar falls back to the
  // conservative hardcoded allow-list.
  static Set<String>? activeStaffPages;

  /// Full effective-permissions map for the active staff session, cached
  /// alongside [activeStaffPages] so [canActive] doesn't recompute
  /// `effective()` (a decode + merge) on every widget build. Added for
  /// defect 3 (permission-model decision, 1 Aug 2026) — enforcement was
  /// nav-only before this; individual buttons/cards need a cheap check.
  static Map<String, Map<String, bool>>? activePerms;

  /// Load the logged-in staff member's effective permissions and cache
  /// the allowed page names for the sidebar. Runs under the STAFF
  /// session; works because staff can read their own org's staff table
  /// via RLS (org_members row created by the staff-login function).
  static Future<void> loadForStaff(String staffId) async {
    try {
      final rows = await StaffTable().queryRows(
        queryFn: (q) => q.eq('id', staffId),
      );
      if (rows.isEmpty) {
        activeStaffPages = null;
        activePerms = null;
        AppSession.instance.currentStaffBranch = null;
        return;
      }
      final r = rows.first;
      final eff = effective(
        rawPermissions: r.data['permissions'],
        role: r.role,
      );
      activeStaffPages = allowedPageNames(eff);
      activePerms = eff;
      // Same query already fetched the row — no extra round trip to get
      // the branch a PIN session belongs to (NewOrderPage's branch
      // dropdown is the first consumer).
      AppSession.instance.currentStaffBranch = r.branch;
    } catch (_) {
      activeStaffPages = null;
      activePerms = null;
      AppSession.instance.currentStaffBranch = null;
    }
  }

  static void clearActive() {
    activeStaffPages = null;
    activePerms = null;
  }

  /// The one call a UI gate should use (defect 3 enforcement sweep,
  /// permission-model decision 1 Aug 2026): true for a vendor/owner
  /// session (no staff PIN identity — [AppSession.currentStaffId] null,
  /// the existing pattern main.dart's nav filtering already relies on)
  /// or a staff session whose cached [activePerms] grants [action] on
  /// [moduleKey]. Encapsulates both branches so a call site can't forget
  /// the owner-bypass half and accidentally hide something from the
  /// owner's own session.
  static bool canActive(String moduleKey, String action) {
    if (AppSession.instance.currentStaffId == null) return true;
    return can(activePerms ?? const {}, moduleKey, action);
  }

  /// Page names this permission set may open (drives the sidebar).
  ///
  /// Modules with an empty [PermModule.pageName] are skipped: they gate
  /// content INSIDE a page rather than a destination of their own (the
  /// two `financials*` tiers). Without this guard an empty string would
  /// be added to the allow-list — harmless today because no nav item is
  /// named '', but it would silently become a real grant the moment
  /// anything looked up a page by empty name.
  static Set<String> allowedPageNames(Map<String, Map<String, bool>> perms) {
    final out = <String>{};
    for (final m in kPermModules) {
      if (m.pageName.isEmpty) continue;
      if (canSeeModule(perms, m.key)) out.add(m.pageName);
    }
    return out;
  }
}
