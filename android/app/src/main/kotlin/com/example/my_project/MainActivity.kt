package `in`.nagarva.app

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity, not FlutterActivity (12 Nov 2026): the
// fingerprint / face prompt (local_auth) needs a FragmentActivity and
// fails without one.
class MainActivity: FlutterFragmentActivity() {
}
