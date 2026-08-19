import '/backend/supabase/supabase.dart';

/// Extracts a clean, user-facing message from a thrown Supabase Edge
/// Function error.
///
/// `supabase.functions.invoke()` throws `FunctionException` on any
/// non-2xx response — confirmed directly against functions_client
/// 2.4.2's source (17 Aug 2026), not assumed: every `if (data is! Map
/// || data['ok'] != true) throw ...` check written against `res.data`
/// across this app's Edge Function call sites is dead code for error
/// responses, because `res.data` is never reached on a non-2xx status —
/// the call throws before that line runs. `FunctionException.toString()`
/// is debug-format ("FunctionException(status: 403, details: {error:
/// ...}, reasonPhrase: Forbidden)"), never meant for a user to see, but
/// every Edge Function in this app returns `{error: "..."}` as its JSON
/// body on failure — already decoded into `.details` by the time it's
/// thrown. This unwraps that, falling back to [fallback] for anything
/// else (a network failure, a non-JSON body, ...).
String extractFunctionErrorMessage(Object error, {required String fallback}) {
  if (error is FunctionException) {
    final details = error.details;
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
  }
  return fallback;
}

/// Item 32: same idea, one layer down — for errors raised by a Postgres
/// trigger rather than an Edge Function.
///
/// The plan-enforcement triggers
/// (`20260818_item32_plan_enforcement.sql`) raise real sentences meant
/// for the vendor: "Staff limit reached (3/3 on your current plan).
/// Upgrade to add more staff." Those arrive as a `PostgrestException`
/// with `code == 'P0001'` (plpgsql RAISE's default SQLSTATE) and the
/// sentence in `.message`. Everything else — a null-violation, an RLS
/// denial, a network blip — has a message that would only confuse
/// someone, so those fall back.
///
/// Deliberately narrow: only P0001 is treated as user-facing, because
/// only code this project wrote raises it. Widening this to show any
/// Postgres message would leak column names and constraint identifiers
/// into the UI.
String extractDbErrorMessage(Object error, {required String fallback}) {
  if (error is PostgrestException && error.code == 'P0001') {
    final msg = error.message.trim();
    if (msg.isNotEmpty) return msg;
  }
  return fallback;
}
