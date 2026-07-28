import 'package:flutter/material.dart';

/// Single source of truth for the app's top-level navigation destinations.
///
/// Previously duplicated in two places that drifted apart: main.dart's
/// NavBarPage (bottom nav / sidebar, permission-filtered) had all 12, but
/// HomePage's own hamburger drawer hand-duplicated only 8 of them
/// (Accounts, Staff, Fleet, and P&L were simply missing — not filtered
/// out by permission, just never added when those pages were built).
/// Found live-testing the mobile drawer after the Part 5 nav rebuild.
const kAllNavItems = [
  (name: 'HomePage', icon: Icons.dashboard, label: 'Dashboard'),
  (name: 'OrdersPage', icon: Icons.assignment, label: 'Orders'),
  (name: 'LeadsPage', icon: Icons.people, label: 'Leads / CRM'),
  (name: 'OperationsPage', icon: Icons.local_shipping, label: 'Operations'),
  (name: 'PaymentsPage', icon: Icons.payments, label: 'Payments'),
  (name: 'ExpensePage', icon: Icons.receipt_long, label: 'Expenses'),
  (
    name: 'AccountsPage',
    icon: Icons.account_balance_wallet,
    label: 'Accounts'
  ),
  (name: 'SalaryPage', icon: Icons.badge, label: 'Salary'),
  (name: 'UsersPage', icon: Icons.groups, label: 'Staff'),
  (name: 'FleetPage', icon: Icons.directions_car, label: 'Fleet'),
  (name: 'PLReportPage', icon: Icons.assessment, label: 'P & L'),
  (name: 'SettingsPage', icon: Icons.settings, label: 'Settings'),
];
