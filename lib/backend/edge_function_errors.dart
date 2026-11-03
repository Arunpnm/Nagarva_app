import 'dart:async';

import '/backend/supabase/supabase.dart';

const kGenericErrorMessage = 'Something went wrong. Please try again.';

/// ONE plain-language line for any error, for showing to a user
/// (Arun, 3 Nov 2026: "all errors should be a simple basic line, no
/// technical words"). Before this, ~180 places showed `$e` raw, e.g.
/// "PostgrestException(message: …, code: 23505, details: , hint: null)".
///
/// Sentences this project writes itself (trigger RAISEs, Edge Function
/// `{error: "…"}` bodies, `throw Exception('Wrong PIN. Try again.')`) are
/// passed through when they read like a sentence; anything that looks
/// technical (table/column names, codes, stack-ish text) is replaced by a
/// plain line for its kind of failure.
String friendlyError(Object? error) {
  if (error == null) return kGenericErrorMessage;

  if (error is PostgrestException) {
    final code = error.code ?? '';
    final msg = error.message.trim();
    if (code == 'P0001' && msg.isNotEmpty) return msg;
    if (msg.contains('row-level security') ||
        msg.contains('permission denied') ||
        code == '42501') {
      return "You don't have permission to do this.";
    }
    if (code == '23505') {
      return _looksHuman(msg)
          ? msg
          : 'This already exists. Please use a different value.';
    }
    if (code == '23503') {
      return "This is linked to other records, so it can't be changed or "
          'removed.';
    }
    if (code == '23502') return 'A required field is empty. Please fill it in.';
    if (code.startsWith('22') || code == '23514') {
      return 'Some values entered are not valid. Please check and try again.';
    }
    if (code == 'PGRST116') {
      return 'This record was not found. It may have been deleted.';
    }
    if (code == 'PGRST301' || code == 'PGRST303' || msg.contains('JWT')) {
      return 'Your login has expired. Please log in again.';
    }
    if (_looksHuman(msg)) return msg;
    return kGenericErrorMessage;
  }

  if (error is FunctionException) {
    final details = error.details;
    if (details is Map && details['error'] is String) {
      final m = (details['error'] as String).trim();
      if (_looksHuman(m)) return m;
    }
    if (error.status == 401 || error.status == 403) {
      return "You don't have permission to do this.";
    }
    return kGenericErrorMessage;
  }

  if (error is AuthException) {
    final m = error.message.toLowerCase();
    if (m.contains('invalid login')) return 'Wrong email or password.';
    if (m.contains('expired') || m.contains('invalid') && m.contains('otp')) {
      return 'The code is wrong or has expired. Please try again.';
    }
    if (m.contains('rate limit') || m.contains('too many')) {
      return 'Too many attempts. Please wait a minute and try again.';
    }
    if (_looksHuman(error.message)) return error.message;
    return 'Could not sign you in. Please try again.';
  }

  if (error is StorageException) {
    if (error.statusCode == '403' || error.statusCode == '401') {
      return "You don't have permission to do this.";
    }
    return 'Could not upload or open the file. Please try again.';
  }

  if (error is TimeoutException) {
    return 'This is taking too long. Check your internet and try again.';
  }

  final s = error.toString();
  const network = [
    'SocketException',
    'Failed host lookup',
    'ClientException',
    'Failed to fetch',
    'XMLHttpRequest',
    'Connection refused',
    'NetworkError',
    'Network is unreachable',
  ];
  if (network.any(s.contains)) {
    return 'No internet connection. Check your network and try again.';
  }
  if (error is String && _looksHuman(error)) return error;
  if (s.startsWith('Exception: ')) {
    final m = s.substring('Exception: '.length).trim();
    if (_looksHuman(m)) return m;
  }
  return kGenericErrorMessage;
}

/// True when [m] reads like a sentence meant for a person, not a
/// developer: short, no code-ish fragments.
bool _looksHuman(String m) {
  final t = m.trim();
  if (t.isEmpty || t.length > 220) return false;
  const technical = [
    'Exception', 'exception', '{', '}', '::', '_id', 'null', 'relation "',
    'column', 'violates', 'constraint', 'syntax', 'function ', 'PGRST',
    'org=', 'uuid', 'SQL', 'sql', 'stack', 'Instance of', '\$',
    'TypeError', 'NoSuchMethod', 'RangeError', 'FormatException',
  ];
  return !technical.any(t.contains);
}

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
  final f = friendlyError(error);
  return f == kGenericErrorMessage ? fallback : f;
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
  // Plain line for everything else (3 Nov 2026), [fallback] when there's
  // nothing more specific to say.
  final f = friendlyError(error);
  return f == kGenericErrorMessage ? fallback : f;
}
