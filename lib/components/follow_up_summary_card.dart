import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/reminders_service.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';

/// Dashboard "Today's Follow-ups / Overdue" card (live-test fix brief #2,
/// item 10.5 — "reminders nobody sees are useless").
///
/// Renders nothing at all when both counts are zero, so a quiet day costs
/// no vertical space on the dashboard.
class FollowUpSummaryCard extends StatefulWidget {
  const FollowUpSummaryCard({super.key});

  @override
  State<FollowUpSummaryCard> createState() => FollowUpSummaryCardState();
}

class FollowUpSummaryCardState extends State<FollowUpSummaryCard> {
  int _today = 0;
  int _overdue = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final c = await RemindersService.counts();
    if (!mounted) return;
    setState(() {
      _today = c.today;
      _overdue = c.overdue;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || (_today == 0 && _overdue == 0)) {
      return const SizedBox.shrink();
    }
    final theme = FlutterFlowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // Leads list is where follow-ups get actioned.
        onTap: () => context.pushNamed(LeadsPageWidget.routeName),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.secondaryBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _overdue > 0
                  ? theme.error.withValues(alpha: 0.45)
                  : theme.alternate,
            ),
          ),
          child: Row(
            children: [
              Icon(
                _overdue > 0 ? Icons.notification_important : Icons.today,
                color: _overdue > 0 ? theme.error : theme.primary,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Follow-ups',
                      style: GoogleFonts.interTight(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: theme.primaryText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (_overdue > 0) '$_overdue overdue',
                        if (_today > 0) '$_today due today',
                      ].join(' · '),
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _overdue > 0 ? theme.error : theme.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.secondaryText),
            ],
          ),
        ),
      ),
    );
  }
}
