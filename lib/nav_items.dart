import 'package:flutter/material.dart';

import '/app_session.dart';
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
typedef NavItem = ({String name, IconData icon, String label});

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
  (name: 'HomePage', icon: Icons.dashboard, label: 'Dashboard'),
  (name: 'LeadsPage', icon: Icons.people, label: 'Leads / CRM'),
  (name: 'CustomerSurveysPage', icon: Icons.fact_check, label: 'Surveys'),
  (name: 'WaInboxPage', icon: Icons.inbox, label: 'Inbox'),
  (name: 'SurveyQuoteHubPage', icon: Icons.add_task, label: 'Survey'),
  (name: 'CalendarPage', icon: Icons.calendar_month, label: 'Calendar'),
  (name: 'OrdersPage', icon: Icons.assignment, label: 'Orders'),
  (name: 'OperationsPage', icon: Icons.local_shipping, label: 'Operations'),
  (name: 'ReviewsPage', icon: Icons.star_outline, label: 'Reviews'),
  (name: 'PaymentsPage', icon: Icons.payments, label: 'Payments'),
  (name: 'ExpensePage', icon: Icons.receipt_long, label: 'Expenses'),
  (name: 'UsersPage', icon: Icons.groups, label: 'Staff'), // label overridden dynamically
  (name: 'FleetPage', icon: Icons.directions_car, label: 'Fleet'),
  (name: 'MaterialsPage', icon: Icons.inventory_2, label: 'Materials'),
  // Session 4, Part C-2 — new module, not a former ComingSoon stub.
  (name: 'RateCardsPage', icon: Icons.price_change, label: 'Rate Cards'),
  (name: 'AccountsPage', icon: Icons.account_balance_wallet, label: 'Accounts'),
  (name: 'PLReportPage', icon: Icons.assessment, label: 'P & L'),
  (name: 'ReportsPage', icon: Icons.bar_chart, label: 'Reports'),
  (name: 'SalaryPage', icon: Icons.badge, label: 'Salary'),
  (name: 'SettingsPage', icon: Icons.settings, label: 'Settings'),
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
  (name: 'SupervisorJobsListPage', icon: Icons.work_outline, label: 'My Jobs'),
  (name: 'SupervisorTeamPage', icon: Icons.groups_outlined, label: 'My Team'),
  (name: 'SupervisorEarningsPage', icon: Icons.currency_rupee, label: 'My Earnings'),
  (name: 'SupervisorAttendancePage', icon: Icons.event_available, label: 'My Attendance'),
];

/// Field staff nav (Users Kickoff Step 2.3): driver / helper / packer.
/// Neither screen exists yet.
const kFieldStaffNavItems = <NavItem>[
  (name: 'MyAttComingSoon', icon: Icons.event_available, label: 'My Attendance'),
  (name: 'MySalComingSoon', icon: Icons.currency_rupee, label: 'My Earnings'),
];

/// Canonical "is this session owner-or-manager" check for nav purposes —
/// a vendor session (no staff identity) or a staff session whose role is
/// `owner`/`manager`. Mirrors the permission-model decision's answer to
/// the "manager nav gate" question: checks `staff.role`, never
/// `org_members.role`.
bool get isOwnerOrManagerSession {
  if (AppSession.instance.currentStaffId == null) return true;
  final role = AppSession.instance.currentStaffRole;
  return role == 'owner' || role == 'manager';
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
  return [
    for (final item in kOwnerManagerNavItems)
      if (item.name == 'UsersPage')
        (
          name: item.name,
          icon: item.icon,
          label: canEditSalary ? 'Salary & Staff' : 'Team Attendance',
        )
      else
        item,
  ];
}
