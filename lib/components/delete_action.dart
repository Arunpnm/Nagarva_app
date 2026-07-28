import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/soft_delete.dart';
import '/flutter_flow/flutter_flow_theme.dart';

/// Shared destructive-delete flow (live-test fix brief #2, item 11.4).
///
/// One implementation so every screen behaves identically: destructive
/// styling, a confirmation that says what will actually happen, a
/// mandatory reason where the brief requires one, blocked cases that
/// explain *why* and offer the alternative, and an undo snackbar.
class DeleteAction {
  /// Full delete flow. Returns true if the row was soft-deleted.
  ///
  /// [check] runs the guard first. [onAlternative] is invoked with the
  /// alternative key ('mark_lost' | 'cancel_order' | 'supersede' |
  /// 'deactivate') when the user takes the offered route instead.
  static Future<bool> run(
    BuildContext context, {
    required String table,
    required String id,
    required String entityLabel,
    required Future<DeleteCheck> Function() check,
    bool reasonRequired = false,
    void Function(String alternative)? onAlternative,
    VoidCallback? onDeleted,
  }) async {
    final guard = await check();
    if (!context.mounted) return false;

    if (!guard.allowed) {
      await _showBlocked(context, guard, entityLabel, onAlternative);
      return false;
    }

    final reason = await _confirm(
      context,
      entityLabel: entityLabel,
      reasonRequired: reasonRequired,
    );
    if (reason == null) return false; // cancelled

    try {
      await SoftDeleteService.softDelete(
        table: table,
        id: id,
        reason: reason.isEmpty ? null : reason,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: $e')),
        );
      }
      return false;
    }

    if (context.mounted) {
      // Undo (item 11.4) — the cheapest possible fix for the most common
      // support request. 10s, per the brief.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$entityLabel deleted'),
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              try {
                await SoftDeleteService.restore(table: table, id: id);
              } catch (_) {
                // The row is still recoverable from the recycle bin, so a
                // failed undo is not a dead end.
              }
            },
          ),
        ),
      );
    }
    onDeleted?.call();
    return true;
  }

  static Future<void> _showBlocked(
    BuildContext context,
    DeleteCheck guard,
    String entityLabel,
    void Function(String)? onAlternative,
  ) async {
    final alt = guard.alternative;
    final theme = FlutterFlowTheme.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text("Can't delete this $entityLabel"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(guard.reason ?? 'This record cannot be deleted.'),
            if (alt != null) ...[
              const SizedBox(height: 12),
              Text(
                _altExplanation(alt),
                style: GoogleFonts.inter(
                    fontSize: 12.5, height: 1.4, color: theme.secondaryText),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          if (alt != null && onAlternative != null)
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                onAlternative(alt);
              },
              child: Text(_altLabel(alt)),
            ),
        ],
      ),
    );
  }

  static String _altLabel(String alt) {
    switch (alt) {
      case 'mark_lost':
        return 'Mark as Lost';
      case 'cancel_order':
        return 'Cancel Order';
      case 'supersede':
        return 'New version';
      case 'deactivate':
        return 'Deactivate';
      default:
        return 'Continue';
    }
  }

  static String _altExplanation(String alt) {
    switch (alt) {
      case 'mark_lost':
        return 'Marking it Lost keeps the history and removes it from your '
            'active pipeline.';
      case 'cancel_order':
        return 'Cancelling keeps the order and its financial record, but '
            'takes it out of your active jobs.';
      case 'supersede':
        return 'Create a new version of the quote instead — the signed one '
            'stays as the record of what was agreed.';
      case 'deactivate':
        return 'Deactivating keeps salary, attendance and job history '
            'intact, and stops them logging in.';
      default:
        return '';
    }
  }

  /// Returns the reason string on confirm (possibly empty when not
  /// required), or null if cancelled.
  static Future<String?> _confirm(
    BuildContext context, {
    required String entityLabel,
    required bool reasonRequired,
  }) async {
    final reasonCtrl = TextEditingController();
    final theme = FlutterFlowTheme.of(context);
    var canSubmit = !reasonRequired;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Delete this $entityLabel?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This $entityLabel will be removed from your list. It can be '
                'restored by the owner from Settings → Deleted Items.',
                style: GoogleFonts.inter(fontSize: 13.5, height: 1.4),
              ),
              if (reasonRequired) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: reasonCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Reason (required)',
                    hintText: 'e.g. duplicate entry, created in error',
                  ),
                  onChanged: (v) => setDialogState(
                      () => canSubmit = v.trim().isNotEmpty),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: canSubmit
                  ? () => Navigator.of(dialogContext).pop(true)
                  : null,
              style: TextButton.styleFrom(foregroundColor: theme.error),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );

    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    return ok == true ? reason : null;
  }

  /// Destructive-styled button for the bottom of a detail screen. Kept
  /// visually distinct and deliberately never placed beside a primary
  /// action (item 11.4).
  static Widget button({
    required VoidCallback? onPressed,
    required String label,
    required BuildContext context,
    bool busy = false,
  }) {
    final theme = FlutterFlowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton.icon(
          onPressed: busy ? null : onPressed,
          icon: Icon(Icons.delete_outline, size: 19, color: theme.error),
          label: Text(
            busy ? 'Deleting…' : label,
            style: GoogleFonts.interTight(
                fontWeight: FontWeight.w600, color: theme.error),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: theme.error.withValues(alpha: 0.6)),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    );
  }
}
