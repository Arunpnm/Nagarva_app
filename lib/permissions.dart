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

  /// Role defaults. Used to pre-fill the matrix when a role is picked,
  /// and as the fallback for staff rows that have no permissions yet.
  ///
  /// Money modules (Payments/Expenses/Salary/P&L) are OFF for every role
  /// except admin — grant them per person if you want a specific
  /// supervisor to see money.
  static Map<String, Map<String, bool>> presetFor(String role) {
    final r = role.toLowerCase();

    Map<String, Map<String, bool>> build(Map<String, List<String>> spec) {
      final out = <String, Map<String, bool>>{};
      spec.forEach((k, actions) {
        out[k] = {for (final a in actions) a: true};
      });
      return out;
    }

    switch (r) {
      case 'admin':
        // Full access to everything, including money modules.
        return {
          for (final m in kPermModules)
            m.key: {for (final a in kPermActions) a: true}
        };
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

  /// Effective permissions for a logged-in staff member: their saved
  /// matrix, or the role preset when nothing has been configured yet.
  static Map<String, Map<String, bool>> effective({
    required dynamic rawPermissions,
    required String? role,
  }) {
    final saved = decode(rawPermissions);
    if (!isEmpty(saved)) return saved;
    return presetFor(role ?? '');
  }

  // ------------------------------------------------------------------
  // Active staff session state (set at PIN login / session restore,
  // cleared on Lock/Logout). main.dart's sidebar reads this; null means
  // "no staff permissions loaded" and the sidebar falls back to the
  // conservative hardcoded allow-list.
  static Set<String>? activeStaffPages;

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
        return;
      }
      final r = rows.first;
      final eff = effective(
        rawPermissions: r.data['permissions'],
        role: r.role,
      );
      activeStaffPages = allowedPageNames(eff);
    } catch (_) {
      activeStaffPages = null;
    }
  }

  static void clearActive() => activeStaffPages = null;

  /// Page names this permission set may open (drives the sidebar).
  static Set<String> allowedPageNames(Map<String, Map<String, bool>> perms) {
    final out = <String>{};
    for (final m in kPermModules) {
      if (canSeeModule(perms, m.key)) out.add(m.pageName);
    }
    return out;
  }
}
