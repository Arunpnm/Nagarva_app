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
  PermModule('quotations', 'Quotations', 'QuotationPage'),
  PermModule('materials', 'Materials', 'MaterialsPage'),
  PermModule('reports', 'Reports', 'ReportsPage'),
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
        return;
      }
      final r = rows.first;
      final eff = effective(
        rawPermissions: r.data['permissions'],
        role: r.role,
      );
      activeStaffPages = allowedPageNames(eff);
      activePerms = eff;
    } catch (_) {
      activeStaffPages = null;
      activePerms = null;
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
  static Set<String> allowedPageNames(Map<String, Map<String, bool>> perms) {
    final out = <String>{};
    for (final m in kPermModules) {
      if (canSeeModule(perms, m.key)) out.add(m.pageName);
    }
    return out;
  }
}
