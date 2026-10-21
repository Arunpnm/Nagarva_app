import 'package:flutter/material.dart';

import '/app_session.dart';
import '/backend/soft_delete.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/delete_action.dart';
import '/components/entity_picker_dialog.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';

/// Tasks & Activities (Session 4, Part C-12; entity picker generalized in
/// the corrections session, 7 Aug 2026). Live schema confirmed directly
/// against the DB: tasks + activities, both polymorphic via
/// entity_type/entity_id.
///
/// All four entity types (order/lead/customer/vendor) now get a real
/// picker via [EntityPickerDialog] — previously only 'order' did, so
/// picking a lead/customer/vendor selected the type but left entity_id
/// blank, producing rows that could never be joined or filtered.
class TasksPageWidget extends StatefulWidget {
  const TasksPageWidget({super.key});

  static String routeName = 'TasksPage';
  static String routePath = '/tasks';

  @override
  State<TasksPageWidget> createState() => _TasksPageWidgetState();
}

class _TasksPageWidgetState extends State<TasksPageWidget>
    with SingleTickerProviderStateMixin, RefreshOnPopMixin<TasksPageWidget> {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  bool _loading = true;
  List<TasksRow> _tasks = [];
  List<ActivitiesRow> _activities = [];
  List<StaffRow> _staff = [];
  bool _myTasksOnly = false;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  void onPageRefresh() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _tasks = await TasksTable().queryRows(
        queryFn: (q) => OrgScope.read(q).order('due_at', ascending: true),
      );
      _activities = await ActivitiesTable().queryRows(
        queryFn: (q) => OrgScope.read(q).order('occurred_at', ascending: false).limit(100),
      );
      _staff = await StaffTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('active', true).order('name'),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<TasksRow> get _filteredTasks {
    if (!_myTasksOnly) return _tasks;
    final myId = AppSession.instance.currentStaffId;
    if (myId == null) return _tasks;
    return _tasks.where((t) => t.assignedTo == myId).toList();
  }

  String _staffName(String? id) {
    if (id == null) return '—';
    for (final s in _staff) {
      if (s.id == id) return s.name;
    }
    return '—';
  }

  // ---- Tasks -----------------------------------------------------------

  Future<void> _newTask() async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String taskType = 'follow_up';
    String entityType = 'general';
    EntityPickedResult? linkedEntity;
    String priority = 'medium';
    String? assignedTo;
    DateTime? dueAt;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('New Task'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(labelText: 'Title'),
                      autofocus: true),
                  TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(labelText: 'Description'),
                      maxLines: 2),
                  DropdownButtonFormField<String>(
                    initialValue: taskType,
                    decoration: const InputDecoration(labelText: 'Task Type'),
                    items: const [
                      DropdownMenuItem(value: 'call', child: Text('Call')),
                      DropdownMenuItem(value: 'follow_up', child: Text('Follow Up')),
                      DropdownMenuItem(value: 'site_visit', child: Text('Site Visit')),
                      DropdownMenuItem(value: 'document', child: Text('Document')),
                      DropdownMenuItem(value: 'general', child: Text('General')),
                    ],
                    onChanged: (v) => setDialogState(() => taskType = v ?? 'follow_up'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: entityType,
                    decoration: const InputDecoration(labelText: 'Linked To'),
                    items: const [
                      DropdownMenuItem(value: 'general', child: Text('Nothing (general)')),
                      DropdownMenuItem(value: 'order', child: Text('Order')),
                      DropdownMenuItem(value: 'lead', child: Text('Lead')),
                      DropdownMenuItem(value: 'customer', child: Text('Customer')),
                      DropdownMenuItem(value: 'vendor', child: Text('Vendor')),
                    ],
                    // Clears any previously-picked entity when the type
                    // changes — otherwise switching from Lead to Vendor
                    // after already picking a lead would silently keep
                    // that lead's id and write it under entity_type
                    // 'vendor'.
                    onChanged: (v) => setDialogState(() {
                      entityType = v ?? 'general';
                      linkedEntity = null;
                    }),
                  ),
                  if (entityType != 'general')
                    OutlinedButton.icon(
                      icon: const Icon(Icons.search, size: 16),
                      label: Text(linkedEntity?.label ??
                          'Pick ${kEntityPickerConfigs[entityType]?.label ?? ''}'),
                      onPressed: () async {
                        final picked =
                            await EntityPickerDialog.show(dialogCtx, entityType);
                        if (picked != null) {
                          setDialogState(() => linkedEntity = picked);
                        }
                      },
                    ),
                  DropdownButtonFormField<String>(
                    initialValue: assignedTo,
                    decoration: const InputDecoration(labelText: 'Assign To'),
                    items: [
                      for (final s in _staff)
                        DropdownMenuItem(value: s.id, child: Text(s.name)),
                    ],
                    onChanged: (v) => setDialogState(() => assignedTo = v),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: priority,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    items: const [
                      DropdownMenuItem(value: 'low', child: Text('Low')),
                      DropdownMenuItem(value: 'medium', child: Text('Medium')),
                      DropdownMenuItem(value: 'high', child: Text('High')),
                      DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                    ],
                    onChanged: (v) => setDialogState(() => priority = v ?? 'medium'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Due'),
                    subtitle: Text(dueAt == null
                        ? '—'
                        : DateFormat('d MMM yyyy, h:mm a').format(dueAt!)),
                    trailing: const Icon(Icons.calendar_today, size: 18),
                    onTap: () async {
                      final date = await showDatePicker(
                          context: dialogCtx,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100));
                      if (date == null) return;
                      final time = await showTimePicker(
                          context: dialogCtx, initialTime: TimeOfDay.now());
                      setDialogState(() => dueAt = DateTime(
                          date.year, date.month, date.day, time?.hour ?? 9, time?.minute ?? 0));
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: titleCtrl.text.trim().isEmpty
                    ? null
                    : () => Navigator.of(dialogCtx).pop(true),
                child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok != true || titleCtrl.text.trim().isEmpty) return;
    try {
      await TasksTable().insert({
        ...OrgScope.stamp(),
        'title': titleCtrl.text.trim(),
        if (descCtrl.text.trim().isNotEmpty) 'description': descCtrl.text.trim(),
        'task_type': taskType,
        'entity_type': entityType,
        'entity_id': entityType == 'general' ? null : linkedEntity?.id,
        'assigned_to': assignedTo,
        'assigned_by': SupaFlow.client.auth.currentUser?.id,
        'priority': priority,
        'status': 'pending',
        'due_at': dueAt?.toUtc().toIso8601String(),
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not create task: $e')));
      }
    }
  }

  Future<void> _completeTask(TasksRow t) async {
    if (t.id == null) return;
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Complete Task'),
        content: TextField(
          controller: noteCtrl,
          decoration: const InputDecoration(labelText: 'Completion Note (optional)'),
          maxLines: 2,
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('Mark Complete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await TasksTable().update(
        data: {
          'status': 'completed',
          'completed_at': DateTime.now().toUtc().toIso8601String(),
          'completed_by': SupaFlow.client.auth.currentUser?.id,
          if (noteCtrl.text.trim().isNotEmpty) 'completion_note': noteCtrl.text.trim(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        matchingRows: (q) => OrgScope.write(q).eq('id', t.id!),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not complete task: $e')));
      }
    }
  }

  Future<void> _cancelTask(TasksRow t) async {
    if (t.id == null) return;
    try {
      await TasksTable().update(
        data: {'status': 'cancelled', 'updated_at': DateTime.now().toUtc().toIso8601String()},
        matchingRows: (q) => OrgScope.write(q).eq('id', t.id!),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not cancel task: $e')));
      }
    }
  }

  // Item 11 sweep (17 Aug 2026): tasks had a live column but no delete UI.
  Future<void> _deleteTask(TasksRow t) async {
    if (t.id == null) return;
    final deleted = await DeleteAction.run(
      context,
      table: 'tasks',
      id: t.id!,
      entityLabel: 'task',
      check: () async => DeleteCheck.allow,
      onDeleted: _load,
    );
    if (deleted) await _load();
  }

  // ---- Activities --------------------------------------------------------

  Future<void> _newActivity() async {
    String activityType = 'call';
    String entityType = 'general';
    EntityPickedResult? linkedEntity;
    String direction = 'outbound';
    final subjectCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final durationCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('Log Activity'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: activityType,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(value: 'call', child: Text('Call')),
                      DropdownMenuItem(value: 'meeting', child: Text('Meeting')),
                      DropdownMenuItem(value: 'note', child: Text('Note')),
                      DropdownMenuItem(value: 'site_visit', child: Text('Site Visit')),
                    ],
                    onChanged: (v) => setDialogState(() => activityType = v ?? 'call'),
                  ),
                  if (activityType == 'call')
                    DropdownButtonFormField<String>(
                      initialValue: direction,
                      decoration: const InputDecoration(labelText: 'Direction'),
                      items: const [
                        DropdownMenuItem(value: 'outbound', child: Text('Outbound')),
                        DropdownMenuItem(value: 'inbound', child: Text('Inbound')),
                      ],
                      onChanged: (v) => setDialogState(() => direction = v ?? 'outbound'),
                    ),
                  DropdownButtonFormField<String>(
                    initialValue: entityType,
                    decoration: const InputDecoration(labelText: 'Linked To'),
                    items: const [
                      DropdownMenuItem(value: 'general', child: Text('Nothing (general)')),
                      DropdownMenuItem(value: 'order', child: Text('Order')),
                      DropdownMenuItem(value: 'lead', child: Text('Lead')),
                      DropdownMenuItem(value: 'customer', child: Text('Customer')),
                      DropdownMenuItem(value: 'vendor', child: Text('Vendor')),
                    ],
                    onChanged: (v) => setDialogState(() {
                      entityType = v ?? 'general';
                      linkedEntity = null;
                    }),
                  ),
                  if (entityType != 'general')
                    OutlinedButton.icon(
                      icon: const Icon(Icons.search, size: 16),
                      label: Text(linkedEntity?.label ??
                          'Pick ${kEntityPickerConfigs[entityType]?.label ?? ''}'),
                      onPressed: () async {
                        final picked =
                            await EntityPickerDialog.show(dialogCtx, entityType);
                        if (picked != null) {
                          setDialogState(() => linkedEntity = picked);
                        }
                      },
                    ),
                  TextField(
                      controller: subjectCtrl,
                      decoration: const InputDecoration(labelText: 'Subject')),
                  TextField(
                      controller: bodyCtrl,
                      decoration: const InputDecoration(labelText: 'Notes'),
                      maxLines: 3),
                  if (activityType == 'call')
                    TextField(
                        controller: durationCtrl,
                        decoration: const InputDecoration(labelText: 'Duration (seconds)'),
                        keyboardType: TextInputType.number),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ActivitiesTable().insert({
        ...OrgScope.stamp(),
        'activity_type': activityType,
        'entity_type': entityType,
        'entity_id': entityType == 'general' ? null : linkedEntity?.id,
        if (subjectCtrl.text.trim().isNotEmpty) 'subject': subjectCtrl.text.trim(),
        if (bodyCtrl.text.trim().isNotEmpty) 'body': bodyCtrl.text.trim(),
        if (activityType == 'call') 'direction': direction,
        'duration_sec': int.tryParse(durationCtrl.text.trim()),
        'occurred_at': DateTime.now().toUtc().toIso8601String(),
        'performed_by': AppSession.instance.currentStaffId,
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not log activity: $e')));
      }
    }
  }

  NgStatus _priorityTone(String p) => switch (p) {
        'urgent' => NgStatus.red,
        'high' => NgStatus.accent,
        'medium' => NgStatus.blue,
        _ => NgStatus.neutral,
      };

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final onTasks = _tabs.index == 0;
    Widget tabButton(int i, String label) => Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _tabs.animateTo(i),
            child: Container(
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _tabs.index == i ? c.sel : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(label,
                  style: NgFonts.geist(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: _tabs.index == i ? c.text : c.mute)),
            ),
          ),
        );
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        children: [
          const NgModuleHeader('Tasks & activities'),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                      color: c.s1, borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    tabButton(0, 'Tasks'),
                    tabButton(1, 'Activities'),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              NgPrimaryButton(
                compact: true,
                height: 44,
                icon: Icons.add_rounded,
                label: onTasks ? 'New task' : 'Log activity',
                onPressed: () => onTasks ? _newTask() : _newActivity(),
              ),
            ],
          ),
          if (onTasks) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: NgSecondaryButton(
                height: 36,
                icon: _myTasksOnly
                    ? Icons.person_outline_rounded
                    : Icons.groups_outlined,
                label: _myTasksOnly ? 'Mine' : 'Everyone',
                onPressed: () => setState(() => _myTasksOnly = !_myTasksOnly),
              ),
            ),
          ],
          const SizedBox(height: 10),
        ],
      ),
    );
    Widget empty(String text) => NgCard(
          child: Text(text,
              textAlign: TextAlign.center,
              style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
        );
    return Scaffold(
      backgroundColor: c.bg,
      appBar: NgTopBar(onRefresh: _load),
      body: Column(
        children: [
          header,
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabs,
                    children: [
                      RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          children: [
                            if (_filteredTasks.isEmpty)
                              empty('No tasks found.')
                            else
                              NgCardList(children: [
                                for (final t in _filteredTasks) _taskRow(t),
                              ]),
                          ],
                        ),
                      ),
                      RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          children: [
                            if (_activities.isEmpty)
                              empty('No activities logged yet.')
                            else
                              NgCardList(children: [
                                for (final a in _activities) _activityRow(a),
                              ]),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _taskRow(TasksRow t) {
    final c = NgPalette.of(context);
    final done = t.status == 'completed' || t.status == 'cancelled';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.title,
                    style: NgFonts.geist(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: done ? c.mute : c.text,
                        decoration: done ? TextDecoration.lineThrough : null)),
                const SizedBox(height: 3),
                Text(
                  [
                    _staffName(t.assignedTo),
                    if (t.dueAt != null)
                      DateFormat('d MMM, h:mm a').format(t.dueAt!.toLocal()),
                    if ((t.entityId ?? '').isNotEmpty)
                      '${t.entityType} · ${t.entityId}',
                  ].where((x) => x.isNotEmpty).join(' · '),
                  style: NgFonts.geist(
                      fontSize: 12.5, height: 1.35, color: c.mute),
                ),
                const SizedBox(height: 6),
                NgPill(
                    t.priority.isEmpty
                        ? ''
                        : t.priority[0].toUpperCase() + t.priority.substring(1),
                    status: _priorityTone(t.priority)),
              ],
            ),
          ),
          if (!done) ...[
            IconButton(
                tooltip: 'Complete',
                icon: Icon(Icons.check_circle_outline_rounded,
                    size: 21, color: c.green),
                onPressed: () => _completeTask(t)),
            IconButton(
                tooltip: 'Cancel',
                icon: Icon(Icons.close_rounded, size: 20, color: c.mute),
                onPressed: () => _cancelTask(t)),
          ],
          IconButton(
            tooltip: 'Delete task',
            icon: Icon(Icons.delete_outline_rounded, size: 19, color: c.faint),
            onPressed: () => _deleteTask(t),
          ),
        ],
      ),
    );
  }

  Widget _activityRow(ActivitiesRow a) => NgListRow(
        icon: Icons.history_rounded,
        title:
            '${a.activityType ?? '—'}${(a.subject ?? '').isNotEmpty ? ' · ${a.subject}' : ''}',
        subtitle: [
          if ((a.body ?? '').isNotEmpty) a.body!,
          [
            if (a.occurredAt != null)
              DateFormat('d MMM yyyy, h:mm a').format(a.occurredAt!.toLocal()),
            if ((a.entityId ?? '').isNotEmpty) '${a.entityType} ${a.entityId}',
          ].join(' · '),
        ].join('\n'),
      );
}
