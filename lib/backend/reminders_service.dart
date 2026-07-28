import 'package:flutter/material.dart';

import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';

/// Follow-ups, reminders and the call log (live-test fix brief #2, item 10).
///
/// Entity types are polymorphic across leads, quotes and orders — see
/// `reminders.entity_id`, which is TEXT because `orders.id` is NGV-XXXX.
///
/// NOTE on the `reminders` table: it pre-dated this feature with
/// `lead_id`/`order_id` FK columns and a `done` boolean. The 28 Jul
/// migration added `entity_type`/`entity_id`/`status` and keeps `status`
/// and `done` in sync with a trigger, so CalendarPage (which reads `done`
/// through `reminders_view`) keeps working untouched. Writes here set the
/// legacy FK column too where it applies, so the view's joins still
/// resolve a customer name.

const String kEntityLead = 'lead';
const String kEntityQuote = 'quote';
const String kEntityOrder = 'order';

const String kReminderOpen = 'open';
const String kReminderDone = 'done';
const String kReminderCancelled = 'cancelled';

const List<String> kFollowUpChannels = [
  'call',
  'whatsapp',
  'sms',
  'email',
  'visit',
  'other',
];

const List<String> kFollowUpOutcomes = [
  'connected',
  'no_answer',
  'busy',
  'callback_requested',
  'not_interested',
  'converted',
];

String followUpChannelLabel(String c) {
  switch (c) {
    case 'whatsapp':
      return 'WhatsApp';
    case 'sms':
      return 'SMS';
    case 'email':
      return 'Email';
    case 'visit':
      return 'Site visit';
    case 'other':
      return 'Other';
    default:
      return 'Call';
  }
}

String followUpOutcomeLabel(String? o) {
  switch (o) {
    case 'connected':
      return 'Connected';
    case 'no_answer':
      return 'No answer';
    case 'busy':
      return 'Busy';
    case 'callback_requested':
      return 'Callback requested';
    case 'not_interested':
      return 'Not interested';
    case 'converted':
      return 'Converted';
    default:
      return '—';
  }
}

/// Default lead time for the two auto-created follow-ups (item 10.4).
/// Overridable per org via the `followup_quote_days` / `followup_survey_days`
/// settings keys.
const int kDefaultQuoteFollowUpDays = 2;
const int kDefaultSurveyFollowUpDays = 1;

enum DueState { overdue, today, upcoming, none }

DueState dueStateOf(DateTime? due) {
  if (due == null) return DueState.none;
  final now = DateTime.now();
  final d = due.toLocal();
  if (d.isBefore(now)) return DueState.overdue;
  final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
  return d.isAfter(endOfToday) ? DueState.upcoming : DueState.today;
}

Color dueColor(DueState s, {required Color overdue, required Color today,
    required Color normal}) {
  switch (s) {
    case DueState.overdue:
      return overdue;
    case DueState.today:
      return today;
    default:
      return normal;
  }
}

class RemindersService {
  /// Open reminders for one entity, soonest first.
  static Future<List<RemindersRow>> openFor({
    required String entityType,
    required String entityId,
  }) async {
    final rows = await RemindersTable().queryRows(
      queryFn: (q) => OrgScope
          .read(q)
          .eq('entity_type', entityType)
          .eq('entity_id', entityId)
          .eq('status', kReminderOpen)
          .order('due_date', ascending: true),
    );
    return rows;
  }

  /// Every reminder for an entity including completed ones, newest first —
  /// backs the collapsible history.
  static Future<List<RemindersRow>> allFor({
    required String entityType,
    required String entityId,
  }) async {
    return RemindersTable().queryRows(
      queryFn: (q) => OrgScope
          .read(q)
          .eq('entity_type', entityType)
          .eq('entity_id', entityId)
          .order('due_date', ascending: false),
    );
  }

  static Future<List<FollowUpLogsRow>> logsFor({
    required String entityType,
    required String entityId,
  }) async {
    return FollowUpLogsTable().queryRows(
      queryFn: (q) => OrgScope
          .read(q)
          .eq('entity_type', entityType)
          .eq('entity_id', entityId)
          .order('logged_at', ascending: false),
    );
  }

  static Future<RemindersRow> add({
    required String entityType,
    required String entityId,
    required String title,
    required DateTime dueAt,
    String? note,
    String? assignedTo,
  }) async {
    return RemindersTable().insert({
      ...OrgScope.stamp(),
      'entity_type': entityType,
      'entity_id': entityId,
      // Also populate the legacy FK column so reminders_view can still
      // join through to a customer name for CalendarPage.
      if (entityType == kEntityLead) 'lead_id': entityId,
      if (entityType == kEntityOrder) 'order_id': entityId,
      'title': title,
      'description': note,
      'due_date': dueAt.toIso8601String(),
      'status': kReminderOpen,
      'reminder_type': entityType,
      'assigned_to': assignedTo,
      'created_by': SupaFlow.client.auth.currentUser?.id,
    });
  }

  static Future<void> setStatus(String reminderId, String status) async {
    // completed_at is stamped by the DB trigger, so it can't drift from
    // status regardless of which client wrote the change.
    await RemindersTable().update(
      data: {'status': status},
      matchingRows: (q) => OrgScope.write(q).eq('id', reminderId),
    );
  }

  /// Records a contact attempt and, when [nextActionAt] is given,
  /// **auto-creates the next reminder in the same action**.
  ///
  /// This is the loop the brief calls the point of the feature: a lead
  /// should never be left without a next step. Returns the new reminder if
  /// one was chained.
  ///
  /// [completeReminderId] is marked done first, so "log the call and close
  /// this one" is a single user action rather than two.
  static Future<RemindersRow?> logFollowUp({
    required String entityType,
    required String entityId,
    required String channel,
    String? outcome,
    String? notes,
    DateTime? nextActionAt,
    String? reminderId,
    String? completeReminderId,
    String? nextTitle,
  }) async {
    await FollowUpLogsTable().insert({
      ...OrgScope.stamp(),
      'entity_type': entityType,
      'entity_id': entityId,
      'reminder_id': reminderId,
      'channel': channel,
      'outcome': outcome,
      'notes': notes,
      'next_action_at': nextActionAt?.toIso8601String(),
      'logged_by': SupaFlow.client.auth.currentUser?.id,
    });

    if (completeReminderId != null) {
      await setStatus(completeReminderId, kReminderDone);
    }

    if (nextActionAt == null) return null;
    return add(
      entityType: entityType,
      entityId: entityId,
      title: nextTitle ?? 'Follow up',
      dueAt: nextActionAt,
      note: notes,
    );
  }

  /// Creates the standard follow-up after a quote or survey is sent
  /// (item 10.4), unless an open reminder of the same kind already exists.
  ///
  /// Idempotent on purpose: re-sending a quote link shouldn't stack up
  /// duplicate "Quote follow-up" reminders on the same lead.
  static Future<void> autoCreate({
    required String entityType,
    required String entityId,
    required String title,
    required int days,
  }) async {
    try {
      final existing = await openFor(
        entityType: entityType,
        entityId: entityId,
      );
      if (existing.any((r) => (r.title ?? '') == title)) return;
      await add(
        entityType: entityType,
        entityId: entityId,
        title: title,
        // 10am local, so an auto-reminder lands in working hours rather
        // than at whatever time the quote happened to be sent.
        dueAt: _atTenAm(DateTime.now().add(Duration(days: days))),
      );
    } catch (_) {
      // Auto-creating a reminder must never fail the action that
      // triggered it (sending a quote or survey link).
    }
  }

  static DateTime _atTenAm(DateTime d) =>
      DateTime(d.year, d.month, d.day, 10, 0);

  /// Org-wide counts for the dashboard (item 10.5).
  static Future<({int today, int overdue})> counts() async {
    try {
      final rows = await RemindersTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('status', kReminderOpen),
      );
      var today = 0, overdue = 0;
      for (final r in rows) {
        switch (dueStateOf(r.dueDate)) {
          case DueState.overdue:
            overdue++;
            break;
          case DueState.today:
            today++;
            break;
          default:
            break;
        }
      }
      return (today: today, overdue: overdue);
    } catch (_) {
      return (today: 0, overdue: 0);
    }
  }

  /// Entity ids in this org that have at least one overdue reminder —
  /// drives the "needs follow-up" badge on the leads list (item 10.5).
  static Future<Set<String>> overdueEntityIds(String entityType) async {
    try {
      final rows = await RemindersTable().queryRows(
        queryFn: (q) => OrgScope
            .read(q)
            .eq('entity_type', entityType)
            .eq('status', kReminderOpen),
      );
      return {
        for (final r in rows)
          if (dueStateOf(r.dueDate) == DueState.overdue && r.entityId != null)
            r.entityId!,
      };
    } catch (_) {
      return {};
    }
  }

  static String get _actorName =>
      AppSession.instance.currentStaffName ?? 'Owner';

  /// Convenience for display: "you" vs a staff name.
  static String actorLabel(String? id) =>
      id == SupaFlow.client.auth.currentUser?.id ? _actorName : 'Staff';
}
