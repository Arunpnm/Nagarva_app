import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kNotificationsEnabledKey = '__notifications_enabled__';

/// Per-device notification preference (parity brief Part 2a — this
/// control previously did nothing at all). Gates only the disruptive
/// in-app SnackBar popup on new Realtime notifications; the bell's badge
/// and list still show every notification regardless, so turning this off
/// mutes interruptions without hiding anything.
class NotificationPrefs {
  static SharedPreferences? _prefs;

  static Future<void> initialize() async =>
      _prefs = await SharedPreferences.getInstance();

  static bool get popupsEnabled => _prefs?.getBool(_kNotificationsEnabledKey) ?? true;

  static Future<void> setPopupsEnabled(bool value) async =>
      _prefs?.setBool(_kNotificationsEnabledKey, value);
}

/// Sidebar notification bell (v1 in-app notifications).
///
/// Rows come from DB triggers (see 20260717_notifications_and_settings.sql):
/// new lead → vendor/owner, order assigned → that supervisor. This widget
/// shows an unread badge, listens on Supabase Realtime for new inserts in
/// the current org, pops a SnackBar when one arrives, and opens a popup
/// list with mark-all-read.
///
/// Addressing rule (client-side, matches the migration header):
///   - staff PIN session (AppSession.currentStaffId set) → only rows where
///     recipient_staff_id == that staff id
///   - vendor/owner session → only rows where recipient_staff_id is null
///
/// True push (FCM) is Week 3 — same table will feed it.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key, this.iconSize = 22, this.iconColor});

  final double iconSize;

  /// Overrides the icon's colour. Null keeps the original sidebar look
  /// (`theme.secondaryText`) — pass `IconTheme.of(context).color` when
  /// placing this in an AppBar's actions so it matches whatever colour
  /// the AppBar's other icons resolve to in every theme variant, instead
  /// of hardcoding a colour that would only be right in one theme.
  final Color? iconColor;

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  List<NotificationsRow> _items = [];
  RealtimeChannel? _channel;

  bool get _isStaffSession => AppSession.instance.currentStaffId != null;

  bool _forMe(Map<String, dynamic> row) {
    final recipient = row['recipient_staff_id'] as String?;
    return _isStaffSession
        ? recipient == AppSession.instance.currentStaffId
        : recipient == null;
  }

  int get _unread => _items.where((n) => !n.read).length;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    // Corrections session, B2 (7 Aug 2026): this used to fetch the last 30
    // notifications for the WHOLE org and only filter to "is this mine"
    // client-side afterward — every colleague's row was already on the
    // wire by the time _forMe ran. Staff PIN sessions each have their own
    // Supabase auth user (see staff-login Edge Function), so that was a
    // real exposure, not just noise: any staff session could read
    // colleagues' notification rows directly off the network response.
    // Filtering server-side closes that, and the matching RLS policy
    // (notifications_select, see the corrections-session migration) makes
    // it enforced rather than just app-well-behaved — a request that
    // skips this app code entirely still can't pull rows it shouldn't.
    // _forMe stays as a second, redundant guard below rather than being
    // removed — cheap, and it's what already renders the Realtime
    // channel's live inserts, which RLS now also scopes the same way.
    final rows = await NotificationsTable().queryRows(
      queryFn: (q) {
        final scoped = OrgScope.read(q);
        final filtered = _isStaffSession
            ? scoped.eq(
                'recipient_staff_id', AppSession.instance.currentStaffId!)
            : scoped.isFilter('recipient_staff_id', null);
        return filtered.order('created_at').limit(30);
      },
    );
    if (!mounted) return;
    setState(() {
      _items = rows.where((r) => _forMe(r.data)).toList();
    });
  }

  void _subscribe() {
    final orgId = AppSession.instance.currentOrgId;
    if (orgId == null) return;
    _channel = SupaFlow.client
        .channel('notifications_$orgId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'org_id',
            value: orgId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (!_forMe(row) || !mounted) return;
            setState(() => _items.insert(0, NotificationsRow(row)));
            if (!NotificationPrefs.popupsEnabled) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${row['title'] ?? 'New notification'}'
                  '${(row['body'] ?? '').toString().isNotEmpty ? ' — ${row['body']}' : ''}',
                ),
                duration: const Duration(milliseconds: 4000),
              ),
            );
          },
        )
        .subscribe();
  }

  /// Marks everything currently listed as read.
  ///
  /// Rewritten 3 Sept 2026. The old version cleared the badge in local
  /// state FIRST and then fired the update without awaiting it and
  /// without a catch. Two consequences, both silent: a failed write left
  /// the badge cleared on screen while the row was still unread in
  /// Postgres, so the count came back on the next load with no error
  /// anywhere; and any thrown error became an unhandled async
  /// exception, because the one caller did not await either.
  ///
  /// Now the write goes first and the rows are RE-READ afterwards rather
  /// than hand-patched - CLAUDE.md's standing rule, learned three times:
  /// patching by hand is a bet that you can list every field the write
  /// touched, and that bet loses quietly.
  Future<void> _markAllRead() async {
    final unreadIds = _items.where((n) => !n.read).map((n) => n.id).toList();
    if (unreadIds.isEmpty) return;
    try {
      await NotificationsTable().update(
        data: {'read': true},
        matchingRows: (q) => OrgScope.write(q).inFilter('id', unreadIds),
      );
    } catch (e) {
      // The badge deliberately STAYS. It is telling the truth: these are
      // still unread in the database.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not mark notifications as read: $e')));
      }
      return;
    }
    await _load();
  }

  /// Opens the panel, and marks everything read once it CLOSES.
  ///
  /// Arun, 3 Sept 2026: *"check notification how it works even after
  /// reading its still showing"*. He was right, and the database showed
  /// exactly why: three of his org's owner notifications are already
  /// `read = true`, so the write works - but nothing marked anything
  /// read except a small "Mark all read" text link in the corner of the
  /// panel. Open the bell, read the notification, close it, and the
  /// badge was still there, because in the app's model he had never
  /// said he had read them.
  ///
  /// Marking on CLOSE rather than on open is the deliberate half: the
  /// rows keep their unread weight while he is looking at them, which is
  /// what tells him which ones are new, and the badge clears when he is
  /// done. Marking on open would fade them out from under him.
  Future<void> _openList() async {
    final theme = FlutterFlowTheme.of(context);
    await showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: theme.secondaryBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Notifications',
                      style: GoogleFonts.interTight(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: theme.primaryText,
                      ),
                    ),
                    // Was a "Mark all read" link - the ONLY thing in the
                    // app that ever cleared the badge, and easy to miss.
                    // Closing the panel does it now, so this states that
                    // rather than offering a second way to do the same
                    // thing one tap earlier.
                    if (_unread > 0)
                      Text(
                        'Marked read on close',
                        style: GoogleFonts.inter(
                            fontSize: 11, color: theme.secondaryText),
                      ),
                  ],
                ),
                Flexible(
                  child: _items.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No notifications yet.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                                color: theme.secondaryText, fontSize: 13),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: theme.secondaryText.withOpacity(0.15)),
                          itemBuilder: (_, i) {
                            final n = _items[i];
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                switch (n.type) {
                                  'order_assigned' => Icons.assignment_ind,
                                  'otp_completed' => Icons.task_alt,
                                  _ => Icons.person_add_alt_1,
                                },
                                color: n.read
                                    ? theme.secondaryText
                                    : theme.primary,
                                size: 20,
                              ),
                              title: Text(
                                n.title,
                                style: GoogleFonts.inter(
                                  fontSize: 13.5,
                                  fontWeight: n.read
                                      ? FontWeight.w500
                                      : FontWeight.w700,
                                  color: theme.primaryText,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  if ((n.body ?? '').isNotEmpty) n.body!,
                                  if (n.createdAt != null)
                                    dateTimeFormat('relative', n.createdAt),
                                ].join(' · '),
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  color: theme.secondaryText,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await _markAllRead();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: _openList,
      child: SizedBox(
        // Fixed 48x48 minimum touch target regardless of icon size —
        // Part 8 addendum item 1 (previously just enough Padding to
        // roughly frame the icon, ~34x34, below Material's minimum).
        width: 48,
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Icon(Icons.notifications_none,
                color: widget.iconColor ?? theme.secondaryText,
                size: widget.iconSize),
            if (_unread > 0)
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: theme.error,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  constraints:
                      const BoxConstraints(minWidth: 15, minHeight: 14),
                  child: Text(
                    // Cap at 99+ (Part 8 addendum item 1) — was 9+.
                    _unread > 99 ? '99+' : '$_unread',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
