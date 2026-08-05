import 'package:flutter/material.dart';

import '/backend/session_logout.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/main.dart' show MyApp;

/// AppBar overflow menu for supervisor screens — theme + logout.
///
/// Supervisor sessions have no drawer and the bottom nav has no account
/// item, so before this there was no reachable logout at all. Matches the
/// owner sidebar's own two controls (`_themeChip`/`_logout` in
/// `main.dart`) rather than reimplementing them: theme goes through the
/// same `MyApp.of(context).setThemeVariant`, logout through the same
/// shared `performLogout` the owner path now also calls.
///
/// Add to every supervisor-facing screen's `AppBar.actions`.
class SupervisorMenuButton extends StatelessWidget {
  const SupervisorMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final current = FlutterFlowTheme.effectiveVariant(context);
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: theme.primaryText),
      onSelected: (value) {
        if (value == 'logout') {
          performLogout(context);
        } else {
          MyApp.of(context).setThemeVariant(value);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          enabled: false,
          height: 28,
          child: Text('THEME',
              style: TextStyle(fontSize: 11, letterSpacing: 1)),
        ),
        for (final entry in const [
          ('light', 'Light'),
          ('dark', 'Dark'),
          ('midnight', 'Midnight'),
        ])
          CheckedPopupMenuItem<String>(
            value: entry.$1,
            checked: current == entry.$1,
            child: Text(entry.$2),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout, size: 18),
              SizedBox(width: 10),
              Text('Logout'),
            ],
          ),
        ),
      ],
    );
  }
}
