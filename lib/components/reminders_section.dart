import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '/backend/reminders_service.dart';
import '/backend/supabase/supabase.dart';
import '/config/app_config.dart';
import '/flutter_flow/flutter_flow_theme.dart';

/// REMINDERS section for Lead Details and the quote screen (live-test fix
/// brief #2, item 10).
///
/// Self-contained and polymorphic — drop it on any screen with an
/// entityType/entityId. Owns its own loading and refresh so the host page
/// doesn't have to thread state through.
class RemindersSection extends StatefulWidget {
  const RemindersSection({
    super.key,
    required this.entityType,
    required this.entityId,
    this.customerName,
    this.customerPhone,
    this.title = 'Reminders',
  });

  final String entityType;
  final String entityId;
  final String? customerName;
  final String? customerPhone;
  final String title;

  @override
  State<RemindersSection> createState() => RemindersSectionState();
}

class RemindersSectionState extends State<RemindersSection> {
  List<RemindersRow> _open = [];
  List<FollowUpLogsRow> _logs = [];
  bool _loading = true;
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    reload();
  }

  /// Public so the host page's onPageRefresh can drive it too.
  Future<void> reload() async {
    try {
      final results = await Future.wait([
        RemindersService.openFor(
            entityType: widget.entityType, entityId: widget.entityId),
        RemindersService.logsFor(
            entityType: widget.entityType, entityId: widget.entityId),
      ]);
      if (!mounted) return;
      setState(() {
        _open = results[0] as List<RemindersRow>;
        _logs = results[1] as List<FollowUpLogsRow>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                widget.title.toUpperCase(),
                style: GoogleFonts.interTight(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  letterSpacing: 0.4,
                  color: theme.primaryText,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _addReminder,
                icon: const Icon(Icons.add, size: 17),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                label: const Text('Add'),
              ),
            ],
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_open.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No open follow-ups. Add one so this never goes quiet.',
                style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                    color: theme.secondaryText),
              ),
            )
          else
            for (final r in _open) _reminderRow(theme, r),
          if (_logs.isNotEmpty) ...[
            const Divider(height: 20),
            InkWell(
              onTap: () => setState(() => _showHistory = !_showHistory),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      _showHistory ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: theme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _showHistory
                          ? 'Hide follow-ups'
                          : 'Show all ${_logs.length} follow-up'
                              '${_logs.length == 1 ? '' : 's'}',
                      style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: theme.primary),
                    ),
                  ],
                ),
              ),
            ),
            if (_showHistory)
              for (final l in _logs) _logRow(theme, l),
          ],
        ],
      ),
    );
  }

  Widget _reminderRow(FlutterFlowTheme theme, RemindersRow r) {
    final state = dueStateOf(r.dueDate);
    final color = dueColor(state,
        overdue: theme.error, today: theme.warning, normal: theme.secondaryText);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: theme.primaryBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: state == DueState.overdue
              ? theme.error.withValues(alpha: 0.5)
              : theme.alternate,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            r.title ?? 'Follow up',
            style: GoogleFonts.inter(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: theme.primaryText),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(
                state == DueState.overdue
                    ? Icons.error_outline
                    : Icons.schedule,
                size: 13,
                color: color,
              ),
              const SizedBox(width: 4),
              Text(
                _dueLabel(r.dueDate, state),
                style: GoogleFonts.inter(
                    fontSize: 11.5, fontWeight: FontWeight.w600, color: color),
              ),
            ],
          ),
          if ((r.description ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              r.description!.trim(),
              style: GoogleFonts.inter(
                  fontSize: 12, height: 1.35, color: theme.secondaryText),
            ),
          ],
          const SizedBox(height: 2),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _logCall(r),
                icon: const Icon(Icons.phone_in_talk, size: 16),
                style: TextButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                label: const Text('Log Call',
                    style: TextStyle(fontSize: 12.5)),
              ),
              TextButton.icon(
                onPressed: () async {
                  await RemindersService.setStatus(r.id!, kReminderDone);
                  await reload();
                },
                icon: const Icon(Icons.check_circle_outline, size: 16),
                style: TextButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    foregroundColor: theme.tertiary),
                label:
                    const Text('Done', style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _logRow(FlutterFlowTheme theme, FollowUpLogsRow l) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_channelIcon(l.channel), size: 15, color: theme.secondaryText),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${followUpChannelLabel(l.channel ?? 'call')}'
                  ' · ${followUpOutcomeLabel(l.outcome)}',
                  style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: theme.primaryText),
                ),
                if ((l.notes ?? '').trim().isNotEmpty)
                  Text(
                    l.notes!.trim(),
                    style: GoogleFonts.inter(
                        fontSize: 12, height: 1.3, color: theme.secondaryText),
                  ),
                if (l.loggedAt != null)
                  Text(
                    DateFormat('d MMM yyyy, h:mm a')
                        .format(l.loggedAt!.toLocal()),
                    style: GoogleFonts.inter(
                        fontSize: 11, color: theme.secondaryText),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _channelIcon(String? c) {
    switch (c) {
      case 'whatsapp':
        return Icons.chat;
      case 'sms':
        return Icons.sms;
      case 'email':
        return Icons.mail_outline;
      case 'visit':
        return Icons.place_outlined;
      case 'other':
        return Icons.more_horiz;
      default:
        return Icons.phone;
    }
  }

  static String _dueLabel(DateTime? due, DueState state) {
    if (due == null) return 'No due date';
    final d = due.toLocal();
    final t = DateFormat('h:mm a').format(d);
    switch (state) {
      case DueState.overdue:
        return 'Overdue — was due ${DateFormat('d MMM').format(d)}, $t';
      case DueState.today:
        return 'Due today, $t';
      default:
        return 'Due ${DateFormat('d MMM yyyy').format(d)}, $t';
    }
  }

  // ---- Actions -----------------------------------------------------------

  Future<void> _addReminder() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddReminderSheet(
        entityType: widget.entityType,
        entityId: widget.entityId,
        customerName: widget.customerName,
      ),
    );
    if (created == true) await reload();
  }

  Future<void> _logCall(RemindersRow r) async {
    final logged = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LogCallSheet(
        entityType: widget.entityType,
        entityId: widget.entityId,
        reminder: r,
        customerName: widget.customerName,
        customerPhone: widget.customerPhone,
      ),
    );
    if (logged == true) await reload();
  }
}

// ===========================================================================
// Add reminder
// ===========================================================================

class _AddReminderSheet extends StatefulWidget {
  const _AddReminderSheet({
    required this.entityType,
    required this.entityId,
    this.customerName,
  });

  final String entityType;
  final String entityId;
  final String? customerName;

  @override
  State<_AddReminderSheet> createState() => _AddReminderSheetState();
}

class _AddReminderSheetState extends State<_AddReminderSheet> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  DateTime _due = DateTime.now().add(const Duration(days: 1));
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title.text = widget.customerName == null
        ? 'Follow up'
        : 'Follow up: ${widget.customerName}';
    // Default to 10am tomorrow — a reminder due at the current time of day
    // tomorrow is rarely what anyone means.
    _due = DateTime(_due.year, _due.month, _due.day, 10, 0);
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'Add reminder',
      children: [
        TextField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        const SizedBox(height: 12),
        _DuePickerRow(
          due: _due,
          onChanged: (d) => setState(() => _due = d),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Note (optional)',
            hintText: 'e.g. Followup by 3pm, wants a revised price',
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: _saving
                ? null
                : () async {
                    if (_title.text.trim().isEmpty) return;
                    setState(() => _saving = true);
                    try {
                      await RemindersService.add(
                        entityType: widget.entityType,
                        entityId: widget.entityId,
                        title: _title.text.trim(),
                        dueAt: _due,
                        note: _note.text.trim().isEmpty
                            ? null
                            : _note.text.trim(),
                      );
                      if (context.mounted) Navigator.of(context).pop(true);
                    } catch (e) {
                      if (context.mounted) {
                        setState(() => _saving = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Could not save: $e')),
                        );
                      }
                    }
                  },
            child: Text(_saving ? 'Saving…' : 'Add reminder'),
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Log call — the auto-chain lives here
// ===========================================================================

class _LogCallSheet extends StatefulWidget {
  const _LogCallSheet({
    required this.entityType,
    required this.entityId,
    required this.reminder,
    this.customerName,
    this.customerPhone,
  });

  final String entityType;
  final String entityId;
  final RemindersRow reminder;
  final String? customerName;
  final String? customerPhone;

  @override
  State<_LogCallSheet> createState() => _LogCallSheetState();
}

class _LogCallSheetState extends State<_LogCallSheet> {
  String _channel = 'call';
  String? _outcome = 'connected';
  final _notes = TextEditingController();
  bool _setNext = true;
  DateTime _next = DateTime.now().add(const Duration(days: 2));
  bool _markDone = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _next = DateTime(_next.year, _next.month, _next.day, 10, 0);
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return _SheetShell(
      title: 'Log follow-up',
      children: [
        // Item 10.6: WhatsApp quick action that also records the attempt,
        // so reaching out and logging it aren't two separate chores.
        if ((widget.customerPhone ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final uri = Uri.parse(buildWhatsAppLink(
                    phone: widget.customerPhone,
                    message:
                        'Hello${widget.customerName == null ? '' : ' ${widget.customerName}'}, '
                        'following up on your move enquiry.',
                  ));
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                  // Pre-select the channel so returning from WhatsApp and
                  // hitting Save records it as a whatsapp contact.
                  if (mounted) setState(() => _channel = 'whatsapp');
                },
                icon: const Icon(Icons.chat, size: 18),
                label: const Text('Message on WhatsApp'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF25D366),
                  side: const BorderSide(color: Color(0xFF25D366)),
                ),
              ),
            ),
          ),
        DropdownButtonFormField<String>(
          // `value:` is deprecated after 3.33; DropdownButtonFormField's
          // didUpdateWidget re-seeds from initialValue, so the selection
          // still tracks setState.
          initialValue: _channel,
          decoration: const InputDecoration(labelText: 'Channel'),
          items: [
            for (final c in kFollowUpChannels)
              DropdownMenuItem(value: c, child: Text(followUpChannelLabel(c))),
          ],
          onChanged: (v) => setState(() => _channel = v ?? 'call'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _outcome,
          decoration: const InputDecoration(labelText: 'Outcome'),
          items: [
            for (final o in kFollowUpOutcomes)
              DropdownMenuItem(value: o, child: Text(followUpOutcomeLabel(o))),
          ],
          onChanged: (v) => setState(() => _outcome = v),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Notes (optional)'),
        ),
        const SizedBox(height: 6),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _markDone,
          onChanged: (v) => setState(() => _markDone = v ?? true),
          title: const Text('Mark this reminder done',
              style: TextStyle(fontSize: 13.5)),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _setNext,
          onChanged: (v) => setState(() => _setNext = v ?? false),
          title: const Text('Set next follow-up',
              style: TextStyle(fontSize: 13.5)),
          subtitle: Text(
            'Creates the next reminder automatically, so the lead never '
            'goes quiet.',
            style: GoogleFonts.inter(
                fontSize: 11.5, color: theme.secondaryText),
          ),
        ),
        if (_setNext)
          _DuePickerRow(
            due: _next,
            onChanged: (d) => setState(() => _next = d),
          ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save follow-up'),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await RemindersService.logFollowUp(
        entityType: widget.entityType,
        entityId: widget.entityId,
        channel: _channel,
        outcome: _outcome,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        nextActionAt: _setNext ? _next : null,
        reminderId: widget.reminder.id,
        completeReminderId: _markDone ? widget.reminder.id : null,
        nextTitle: widget.customerName == null
            ? 'Follow up'
            : 'Follow up: ${widget.customerName}',
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not log follow-up: $e')),
        );
      }
    }
  }
}

// ===========================================================================
// Shared bits
// ===========================================================================

class _DuePickerRow extends StatelessWidget {
  const _DuePickerRow({required this.due, required this.onChanged});

  final DateTime due;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: due,
                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
              );
              if (d != null) {
                onChanged(DateTime(d.year, d.month, d.day, due.hour, due.minute));
              }
            },
            icon: const Icon(Icons.event, size: 17),
            label: Text(DateFormat('d MMM yyyy').format(due)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              foregroundColor: theme.primaryText,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final t = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(due),
              );
              if (t != null) {
                onChanged(DateTime(
                    due.year, due.month, due.day, t.hour, t.minute));
              }
            },
            icon: const Icon(Icons.schedule, size: 17),
            label: Text(DateFormat('h:mm a').format(due)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              foregroundColor: theme.primaryText,
            ),
          ),
        ),
      ],
    );
  }
}

class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Padding(
      // Keeps the sheet above the keyboard when a field is focused.
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: theme.secondaryBackground,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: theme.alternate,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  title,
                  style: GoogleFonts.interTight(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: theme.primaryText),
                ),
                const SizedBox(height: 14),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
