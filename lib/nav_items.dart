import 'package:flutter/material.dart';

import '/app_session.dart';
import '/index.dart';
import '/permissions.dart';

/// Navigation model — Users Kickoff Step 2 (1 Aug 2026).
///
/// Previously a single 12-item list (`kAllNavItems`) filtered down to a
/// permission-driven subset for every staff session — a supervisor just
/// saw fewer of the owner's own tabs. Step 2 replaces that with three
/// **genuinely different** destination sets, not one list filtered three
/// ways: owner/manager get the full 19-entry operational nav; supervisor
/// gets 5 job-focused destinations of their own (plus a differently-
/// labelled "staff" entry) that don't exist in the owner's nav at all;
/// field staff (driver/helper/packer) get 2. The existing per-person
/// permission matrix (`StaffPermissions.effective`/`presetFor`) still
/// governs which of the 19 owner/manager destinations a *manager*
/// session can reach (and, independently, in-page action gates like
/// Edit/Delete via `canActive` — unaffected by this file) — it does not
/// apply to the supervisor/field-staff sets, which are fixed by role,
/// not per-person customizable.
///
/// Single source of truth for main.dart's bottom nav/sidebar AND
/// HomePage's drawer — both used to read `kAllNavItems` directly and
/// drifted apart once already (see the history note below); both now
/// call [navItemsForCurrentSession] instead of branching on session type
/// themselves, so they cannot drift apart again.
/// A navigation destination.
///
/// [group] was added 3 Sept 2026: the owner nav had grown to 34 flat
/// entries and Arun could not tell "which is for what". It is used ONLY
/// for rendering section headers in the drawer — `name` is untouched,
/// which matters because `main.dart`'s `_tabs` map keys off `name` and
/// IS the real router for nav destinations. A previous session changed
/// the nav list without changing `_tabs` and six screens silently
/// rendered a "coming soon" stub, so grouping deliberately changes
/// presentation only.
typedef NavItem = ({
  String name,
  IconData icon,
  String label,
  String group,
});

/// Drawer section order. Anything whose group is not listed falls to the
/// end under [kNavGroupOther] rather than vanishing - a new item added
/// without a group must still be reachable.
const kNavGroups = <String>[
  'Sales',
  'Operations',
  'Money',
  'People',
  'Assets',
  'Partners',
  'Setup',
];

const kNavGroupOther = 'Other';

/// The handful shown in the bottom bar on a phone. Everything else lives
/// in the drawer, grouped.
///
/// Before this the bottom bar rendered ALL owner items and scrolled
/// horizontally - 34 destinations in a strip five wide, which is how a
/// vendor ends up not knowing what exists. These five are the ones a
/// working day actually returns to.
const kPrimaryNavNames = <String>{
  'HomePage',
  'LeadsPage',
  'OrdersPage',
  'OperationsPage',
  'PaymentsPage',
};

/// The destinations the mobile bottom bar shows, for THIS session.
///
/// **Fixes a regression introduced 3 Sept 2026 by the grouping change.**
/// `main.dart` filtered its nav list through [kPrimaryNavNames] directly
/// and rendered nothing when the result was empty. Every name in that set
/// belongs to the owner/manager nav, so a SUPERVISOR or FIELD-STAFF
/// session matched none of them and lost its bottom bar entirely - and
/// those sessions have no drawer either, so they were left with no
/// navigation at all. The bar was only ever meant to be trimmed because
/// the OWNER set had grown to 27; the supervisor set is 4 and the
/// field-staff set is 2, which were never the problem.
///
/// Falls back to the full list rather than an empty bar in every case, so
/// a future set that happens to share no names with [kPrimaryNavNames]
/// degrades to "shows everything" instead of "shows nothing".
List<NavItem> primaryNavItems(List<NavItem> all) {
  if (!isOwnerOrManagerSession) return all;
  final primary = all.where((e) => kPrimaryNavNames.contains(e.name)).toList();
  return primary.isEmpty ? all : primary;
}

/// The 19 owner/manager destinations (Users Kickoff Step 2.1). Six of
/// these route to `ComingSoonPage` today — `surveys`, `inbox`, `survey`
/// and `reviews` are genuinely unbuilt. **`materials`, `reports` and
/// `calendar` are NOT unbuilt** despite the kickoff brief listing them
/// as placeholder candidates — `MaterialsPage`, `ReportsPage` and
/// `CalendarPage` all already exist and are wired to real pages here.
/// (Corrected against the actual routed pages in `nav.dart`, not copied
/// from the brief — see report.)
///
/// `'staff'`'s label is computed at read time, not stored here — see
/// [navItemsForCurrentSession].
///
/// History (pre-Step-2): this list previously had 12 entries and was
/// duplicated in two places that drifted apart — main.dart's NavBarPage
/// had all 12, but HomePage's own hamburger drawer hand-duplicated only
/// 8 (Accounts, Staff, Fleet, P&L were simply missing, not permission-
/// filtered). Both call sites now read this file instead of hand-rolling
/// their own copy — see [navItemsForCurrentSession].
const kOwnerManagerNavItems = <NavItem>[
  (name: 'HomePage', icon: Icons.dashboard, label: 'Dashboard',
    group: 'Sales',
  ),
  (name: 'LeadsPage', icon: Icons.people, label: 'Leads / CRM',
    group: 'Sales',
  ),
  // REMOVED FROM NAV 3 Sept 2026. `CustomerSurveysPage` reads
  // `customer_surveys`, and NOTHING HAS EVER WRITTEN A ROW TO THAT
  // TABLE. Verified against the live database: 0 rows, no writer
  // anywhere in `lib/`, and all four survey RPCs -- `submit_survey`,
  // `get_survey_by_token`, and the two `public_*` ones the live
  // link.nagarva.in site calls -- write to `surveys`, not to this
  // table.
  //
  // So it occupied a top-level slot with a screen that could only ever
  // be empty, one character away from 'Survey & Quote' (the real
  // staff-side builder, which reads `surveys`). Arun, 3 Sept 2026:
  // "there is two survey it is creating confusion".
  //
  // The page, its detail sheet and `survey_queue.dart` are LEFT IN
  // PLACE and the route stays registered -- the 29-column shape may
  // have been intended for something, and an unrouted page costs
  // nothing. Only the nav entry is gone. The real path is Leads ->
  // "Request Survey" -> customer fills -> Survey & Quote.
  (name: 'WaInboxPage', icon: Icons.inbox, label: 'Inbox',
    group: 'Sales',
  ),
  (name: 'SurveyQuoteHubPage', icon: Icons.add_task, label: 'Survey & Quote',
    group: 'Sales',
  ),
  (name: 'CalendarPage', icon: Icons.calendar_month, label: 'Calendar',
    group: 'Operations',
  ),
  (name: 'OrdersPage', icon: Icons.assignment, label: 'Orders',
    group: 'Operations',
  ),
  (name: 'OperationsPage', icon: Icons.local_shipping, label: 'Operations',
    group: 'Operations',
  ),
  (name: 'ReviewsPage', icon: Icons.star_outline, label: 'Reviews',
    group: 'Sales',
  ),
  (name: 'PaymentsPage', icon: Icons.payments, label: 'Payments',
    group: 'Money',
  ),
  (name: 'ExpensePage', icon: Icons.receipt_long, label: 'Expenses',
    group: 'Money',
  ),
  (
    name: 'UsersPage',
    icon: Icons.groups,
    label: 'Staff',
    group: 'People',
  ), // label overridden dynamically
  (name: 'FleetPage', icon: Icons.directions_car, label: 'Fleet',
    group: 'Assets',
  ),
  (name: 'MaterialsPage', icon: Icons.inventory_2, label: 'Materials',
    group: 'Assets',
  ),
  (name: 'WarehousesPage', icon: Icons.warehouse, label: 'Warehouses',
    group: 'Assets',
  ),
  // Session 4, Part C-2 — new module, not a former ComingSoon stub.
  (name: 'RateCardsPage', icon: Icons.price_change, label: 'Rate Cards',
    group: 'Money',
  ),
  (
    name: 'LrRegisterPage',
    icon: Icons.receipt_long_outlined,
    label: 'LR Register',
    group: 'Operations',
  ),
  (
    name: 'OperationsStandalonePage',
    icon: Icons.support_agent,
    label: 'Ops Log',
    group: 'Operations',
  ),
  (name: 'VendorsPage', icon: Icons.local_shipping_outlined, label: 'Vendors',
    group: 'Partners',
  ),
  (name: 'CustomersPage', icon: Icons.people_outline, label: 'Customers',
    group: 'Sales',
  ),
  (
    name: 'InsuranceClaimsPage',
    icon: Icons.shield_outlined,
    label: 'Insurance',
    group: 'Partners',
  ),
  (name: 'TripsPage', icon: Icons.alt_route, label: 'Trips',
    group: 'Operations',
  ),
  (name: 'TasksPage', icon: Icons.task_alt, label: 'Tasks',
    group: 'Operations',
  ),
  (name: 'AccountsPage', icon: Icons.account_balance_wallet, label: 'Accounts',
    group: 'Money',
  ),
  (name: 'PLReportPage', icon: Icons.assessment, label: 'P & L',
    group: 'Money',
  ),
  (name: 'ReportsPage', icon: Icons.bar_chart, label: 'Reports',
    group: 'Money',
  ),
  (name: 'SalaryPage', icon: Icons.badge, label: 'Salary',
    group: 'People',
  ),
  (name: 'SettingsPage', icon: Icons.settings, label: 'Settings',
    group: 'Setup',
  ),
];

/// Backward-compat alias — kept because the pre-Step-2 name is still the
/// obvious thing to grep for. Same list.
const kAllNavItems = kOwnerManagerNavItems;

/// Supervisor nav (Users Kickoff Step 2.2, trimmed on device-test
/// follow-up). 4 real screens, all built in Session 2 (Part B1 + Part C):
/// `sup-jobs` (`SupervisorJobsListPage`) is NOT the same thing as the
/// existing `SupervisorJobPage` (that's the field-side of a specific
/// job's OTP workflow, opened from an order; this is the "My Jobs" list
/// view across all of a supervisor's assigned jobs that opens it).
///
/// Two items dropped after real-device testing:
///   - 'Job Entry' (`SupervisorEntryPage`) — supervisors work assigned
///     jobs, they don't book new ones. The screen still exists
///     (`lib/supervisor_entry_page/`) and its route is still registered,
///     just no longer reachable from nav.
///   - 'Team Attendance' (`StaffTeamAttendance`) — was a ComingSoon stub
///     duplicating what `SupervisorTeamPage` ("My Team") already does in
///     full: branch staff, today's attendance state, mark-present. Rather
///     than build a second screen for the same job, dropped as redundant.
/// Trimming both also fixed the 6-item bottom nav's horizontal-scroll
/// cutoff (Team Attendance was getting clipped) — 4 items fit without
/// scrolling on any phone width this app supports.
const kSupervisorNavItems = <NavItem>[
  (name: 'SupervisorJobsListPage', icon: Icons.work_outline, label: 'My Jobs',
    group: 'Field',
  ),
  (name: 'SupervisorTeamPage', icon: Icons.groups_outlined, label: 'My Team',
    group: 'Field',
  ),
  (
    name: 'SupervisorEarningsPage',
    icon: Icons.currency_rupee,
    label: 'My Earnings',
    group: 'Field',
  ),
  (
    name: 'SupervisorAttendancePage',
    icon: Icons.event_available,
    label: 'My Attendance',
    group: 'Field',
  ),
];

/// Field staff nav (Users Kickoff Step 2.3): driver / helper / packer.
/// Neither screen exists yet.
const kFieldStaffNavItems = <NavItem>[
  (
    name: 'MyAttComingSoon',
    icon: Icons.event_available,
    label: 'My Attendance',
    group: 'Field',
  ),
  (name: 'MySalComingSoon', icon: Icons.currency_rupee, label: 'My Earnings',
    group: 'Field',
  ),
];

/// Canonical "is this session owner-or-manager" check for nav purposes —
/// a vendor session (no staff identity) or a staff session whose role is
/// owner-equivalent. Mirrors the permission-model decision's answer to
/// the "manager nav gate" question: checks `staff.role`, never
/// `org_members.role`.
///
/// **`admin` is included, and its absence was a live bug** (found 19 Aug
/// 2026, fixed same day). This checked only the literal strings 'owner'
/// and 'manager', but no `staff` row has ever had role 'owner' — the
/// role dropdown in `staff_form_sheet.dart` offers **admin**, manager,
/// supervisor, driver, helper, packer, and `permissions.dart` treats
/// `admin` as the owner-equivalent role. So an admin-role staff session
/// was denied owner-level navigation everywhere this getter is used:
/// the drawer, the bottom nav, the home redirect and the Operations
/// approval badge.
///
/// The SQL side already had this right — `is_org_manager()` matches
/// `role in ('owner','admin','manager')` — so the database and the app
/// disagreed about who an admin was. Keep these two definitions in step.
bool get isOwnerOrManagerSession {
  if (AppSession.instance.currentStaffId == null) return true;
  final role = AppSession.instance.currentStaffRole;
  return role == 'owner' || role == 'admin' || role == 'manager';
}

/// The role-appropriate home destination (Users Kickoff Step 2.2/2.3
/// "Home redirect"). Only meaningful for a fresh landing, not every
/// rebuild — callers apply this once, not on every navigation.
String homeNavNameForCurrentSession() {
  if (isOwnerOrManagerSession) return 'HomePage';
  if (AppSession.instance.currentStaffRole == 'supervisor') {
    // Same class of bug as the device-test _tabs miss: this was still the
    // pre-rename ComingSoon name after Session 2 renamed the route to
    // 'SupervisorJobsListPage'. Since nothing in _tabs recognises the old
    // name, a supervisor's first login after this function ran would have
    // landed on a blank body (tabs[_currentPageName] == null) until they
    // tapped a bottom-nav item themselves.
    return 'SupervisorJobsListPage';
  }
  return 'MySalComingSoon';
}

/// The full nav set for the current session type, **before** the
/// per-person permission filter a manager session still goes through
/// (see main.dart's `_navItems`, which applies `StaffPermissions.
/// activeStaffPages` on top of this for a manager — never for owner,
/// which bypasses filtering entirely, and never for supervisor/field
/// staff, whose sets are fixed by role). The "staff" entry's label is
/// computed here since it depends on a runtime permission check
/// (`salary.edit`), not something a const list can express.
List<NavItem> navItemsForCurrentSession() {
  if (!isOwnerOrManagerSession) {
    final role = AppSession.instance.currentStaffRole;
    return role == 'supervisor' ? kSupervisorNavItems : kFieldStaffNavItems;
  }
  final canEditSalary = StaffPermissions.canActive('salary', 'edit');
  final items = [
    for (final item in kOwnerManagerNavItems)
      if (item.name == 'UsersPage')
        (
          name: item.name,
          icon: item.icon,
          // 'Staff', not 'Salary & Staff'. Grouping the drawer put this
          // directly above SalaryPage's own 'Salary' tile, so the two
          // read as near-duplicates of each other — the confusion Arun
          // reported. This screen manages PEOPLE (add, edit, roles,
          // permissions, PIN); SalaryPage pays them. The label now says
          // which is which.
          label: canEditSalary ? 'Staff' : 'Team Attendance',
          // Carried from the const entry rather than restated, so this
          // rebuild cannot silently drop the item into a different
          // drawer section than the one it is declared in.
          group: item.group,
        )
      else
        item,
  ];
  // Platform Admin (16 Aug 2026): /super-admin had no in-app path on
  // Android — no nav link anywhere, and typing a URL isn't something a
  // phone can do. AppSession.isPlatformAdmin is resolved once at login
  // (see /backend/platform_admin_status.dart) and read synchronously
  // here, same contract as canEditSalary above. Appended rather than
  // spliced into kOwnerManagerNavItems itself, since that const list has
  // no way to express "only for the ~1 account that's a platform admin" —
  // every other entry there is visible to every owner/manager.
  if (AppSession.instance.isPlatformAdmin) {
    items.add((
      name: SuperAdminPageWidget.routeName,
      icon: Icons.admin_panel_settings,
      label: 'Platform Admin',
      group: 'Setup',
    ));
  }
  return items;
}
