import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/entity_picker_dialog.dart';
import '/flutter_flow/flutter_flow_theme.dart';
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

  Widget _priorityChip(FlutterFlowTheme theme, String priority) {
    final color = {
          'low': Colors.grey,
          'medium': Colors.blue,
          'high': Colors.orange,
          'urgent': Colors.red,
        }[priority] ??
        Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
      child: Text(priority, style: GoogleFonts.inter(fontSize: 10.5, color: color, fontWeight: FontWeight.w700)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        automaticallyImplyLeading: true,
        title: Text('Tasks & Activities',
            style: theme.titleLarge.override(
                font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                fontSize: 19,
                fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Tasks'), Tab(text: 'Activities')],
        ),
        actions: [
          if (_tabs.index == 0)
            IconButton(
              tooltip: _myTasksOnly ? 'Show All' : 'My Tasks Only',
              icon: Icon(_myTasksOnly ? Icons.person : Icons.people_outline),
              onPressed: () => setState(() => _myTasksOnly = !_myTasksOnly),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _tabs.index == 0 ? _newTask() : _newActivity(),
        icon: const Icon(Icons.add),
        label: Text(_tabs.index == 0 ? 'New Task' : 'Log Activity'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                    children: [
                      if (_filteredTasks.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text('No tasks found.',
                              style: GoogleFonts.inter(color: theme.secondaryText)),
                        )
                      else
                        for (final t in _filteredTasks) _taskRow(theme, t),
                    ],
                  ),
                ),
                RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                    children: [
                      if (_activities.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text('No activities logged yet.',
                              style: GoogleFonts.inter(color: theme.secondaryText)),
                        )
                      else
                        for (final a in _activities) _activityRow(theme, a),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _taskRow(FlutterFlowTheme theme, TasksRow t) {
    final done = t.status == 'completed' || t.status == 'cancelled';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: theme.secondaryBackground, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.title,
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        decoration: done ? TextDecoration.lineThrough : null)),
                Text(
                  [
                    _staffName(t.assignedTo),
                    if (t.dueAt != null) DateFormat('d MMM, h:mm a').format(t.dueAt!.toLocal()),
                    if ((t.entityId ?? '').isNotEmpty) '${t.entityType} ${t.entityId}',
                  ].join(' · '),
                  style: GoogleFonts.inter(fontSize: 11.5, color: theme.secondaryText),
                ),
              ],
            ),
          ),
          _priorityChip(theme, t.priority),
          if (!done) ...[
            IconButton(
                icon: const Icon(Icons.check_circle_outline, size: 20),
                onPressed: () => _completeTask(t)),
            IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => _cancelTask(t)),
          ],
        ],
      ),
    );
  }

  Widget _activityRow(FlutterFlowTheme theme, ActivitiesRow a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: theme.secondaryBackground, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${a.activityType ?? '—'}${(a.subject ?? '').isNotEmpty ? ' — ${a.subject}' : ''}',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12.5),
          ),
          if ((a.body ?? '').isNotEmpty)
            Text(a.body!, style: GoogleFonts.inter(fontSize: 11.5, color: theme.secondaryText)),
          Text(
            [
              if (a.occurredAt != null)
                DateFormat('d MMM yyyy, h:mm a').format(a.occurredAt!.toLocal()),
              if ((a.entityId ?? '').isNotEmpty) '${a.entityType} ${a.entityId}',
            ].join(' · '),
            style: GoogleFonts.inter(fontSize: 10.5, color: theme.secondaryText),
          ),
        ],
      ),
    );
  }
}
