/// A one-shot message the email-confirmation deep-link handler
/// (main.dart) stashes right before routing to `/login` on failure — an
/// `error`/`error_description` fragment from the confirmation link, or a
/// `setSession()` that threw. LoginPageWidget reads and clears it in its
/// own `initState` to populate its error banner.
///
/// Exists because GoRouter builds a fresh `LoginPageWidget`/
/// `LoginPageModel` on navigation with no route-param plumbing wired up
/// to carry a message through `context.go('/login')` — this is the
/// simplest bridge, same static-cache shape as `StaffPermissions`/
/// `DeviceOrgBinding` elsewhere in this app. A message is shown once:
/// [takeAndClear] both reads and clears, so it never reappears on a
/// later rebuild, hot reload, or unrelated navigation back to `/login`.
class PendingAuthMessage {
  PendingAuthMessage._();

  static String? _message;

  static void set(String message) => _message = message;

  static String? takeAndClear() {
    final m = _message;
    _message = null;
    return m;
  }
}
