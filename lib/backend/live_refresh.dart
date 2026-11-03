import 'dart:async';
import 'dart:math';

import '/backend/supabase/supabase.dart';

/// One record to watch: rows of [table] whose [column] equals [value].
class LiveWatch {
  const LiveWatch(this.table, this.column, this.value);
  final String table;
  final String column;
  final String value;
}

/// Screens move on by themselves (pending UX list item 2, 15 Sept 2026):
/// "customer fills the survey link -> the screen should move to View /
/// Edit quote instead of staying on the same page."
///
/// ONE mechanism for every screen: say which records it shows, and it
/// reloads when any of them changes — the customer submits the survey,
/// signs the quote, the office confirms the order. The screen's own load
/// then re-derives its stage and buttons (LeadActions / JourneyData), so
/// nothing here knows about stages.
///
/// Needs the tables in the `supabase_realtime` publication
/// (supabase/20261103_realtime_journey_tables.sql). Row Level Security
/// still applies: a session only hears about its own company's rows.
/// If realtime is unavailable nothing breaks — pull-to-refresh remains.
class LiveRefresh {
  LiveRefresh._(this._channel, this._timer);

  final RealtimeChannel _channel;
  final _Debounce _timer;

  /// Starts watching. Several changes close together (a quote insert plus
  /// its lead's status update) cause ONE reload, 700 ms after the last.
  static LiveRefresh? watch(
    List<LiveWatch> watches,
    void Function() onChange,
  ) {
    final live = watches.where((w) => w.value.isNotEmpty).toList();
    if (live.isEmpty) return null;
    final debounce = _Debounce(const Duration(milliseconds: 700), onChange);
    var channel = SupaFlow.client
        .channel('live_${Random().nextInt(1 << 31)}');
    for (final w in live) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: w.table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: w.column,
          value: w.value,
        ),
        callback: (_) => debounce.hit(),
      );
    }
    channel.subscribe();
    return LiveRefresh._(channel, debounce);
  }

  /// Call from the screen's dispose().
  void dispose() {
    _timer.cancel();
    SupaFlow.client.removeChannel(_channel);
  }
}

class _Debounce {
  _Debounce(this.wait, this.action);
  final Duration wait;
  final void Function() action;
  Timer? _t;

  void hit() {
    _t?.cancel();
    _t = Timer(wait, action);
  }

  void cancel() => _t?.cancel();
}
