/// Set by auth_deep_link.dart's recovery branch (type=recovery) right
/// after establishing the vendor session from a password-reset link,
/// before returning — so nav.dart's `_initialize` route (the one GoRouter
/// builds for a cold start, before any router.go() is possible) can send
/// the user to SetNewPasswordPageWidget instead of the ordinary Home/PIN/
/// Login landing. Warm resume doesn't need this — startListening() has a
/// live GoRouter and routes there directly — but cold start has no
/// router yet at the point the deep link is processed (see main()).
///
/// Cleared by SetNewPasswordPageWidget itself once it has taken over, so
/// a later app restart (after the password is already set) doesn't keep
/// landing here.
class PendingPasswordReset {
  PendingPasswordReset._();

  static bool active = false;
}
