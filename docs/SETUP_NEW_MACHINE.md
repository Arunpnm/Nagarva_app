# Setting up on another machine

Written 27 Aug 2026, after moving between two machines twice in one
week. Read this instead of re-deriving it.

## Short version

```bash
git clone https://github.com/Arunpnm/Nagarva_app.git
cd Nagarva_app
flutter pub get          # NOT optional — see below
flutter analyze lib/     # expect 177 issues, 0 errors
flutter build apk --release
```

**There are no secrets to copy across.** Nothing gitignored is required
to build. Verified 27 Aug 2026: `.env`, `sentry.properties` and
`android/key.properties` **do not exist on the dev machine either** — the
build does not read them.

---

## 1. `flutter pub get` is mandatory before the first compile

`lib/l10n/gen/` is **gitignored** (five generated `AppLocalizations`
files, NG-055). `flutter pub get` regenerates them from
`lib/l10n/*.arb` via the `generate: true` flag in `pubspec.yaml`.

**A fresh clone will not compile until it has been run** — you will get
a wall of "AppLocalizations isn't defined" errors that look like broken
code and are not.

## 2. Flutter version — 3.35.5, pinned, do not upgrade

The dev machine runs **3.35.5**. `CLAUDE.md`'s environment rules give
the current pinned SDK path and working-copy path — both have moved at
least once (this file previously said `C:\src\flutter`, which was
wrong; check `CLAUDE.md` rather than trusting a path cached here).

**Newer Flutter marks `IconData` as `final`, which breaks the pinned
`font_awesome_flutter 10.x` and `page_transition 2.x`.** This is the
first rule in `CLAUDE.md` and it is not advisory — the build fails.

```bash
flutter --version    # must say 3.35.5
```

**Watch for a second Flutter install** if the machine has more than
one SDK on disk — only PATH order keeps the right one in front. If in
doubt, **check `flutter --version` in the same shell you build from**
— not in a different terminal, since PATH can differ between them.

Never run `flutter upgrade` in this repo. Avoid `flutter pub upgrade` —
`pubspec.yaml` pins exact versions FlutterFlow-style, on purpose.

## 3. Toolchain

| | version on the dev machine |
|---|---|
| Flutter | 3.35.5 (Dart 3.9.2) |
| JDK | 17 (Temurin/Oracle both fine; 21 untested) |
| Android SDK | standard; CMake 3.22.1 is auto-installed on first build |
| `adb` | in `platform-tools`; **add it to PATH yourself**, it is not there by default |

**First release build takes ~55 minutes** (Gradle distribution +
dependency download). Later builds are minutes. That is normal, not a
hang.

## 4. Backend needs nothing

Supabase URL and **anon key are committed** in
`lib/backend/supabase/supabase.dart` (tracked, deliberately — an anon
key is public by design and RLS is the actual boundary). Project
`hqqcapifefsaqvotqvlt`. No setup step.

## 5. Optional `--dart-define`s

All have safe defaults; omit them and the app builds and runs.

| define | default | effect if omitted |
|---|---|---|
| `NAGARVA_SENTRY_DSN` | empty | **crash reporting silently OFF** — deliberate, so a forgotten flag is silence, not a crash |
| `NAGARVA_SENTRY_ENV` | `dev` | use `tester` for shared builds |
| `NAGARVA_PUBLIC_BASE_URL` | `https://link.nagarva.in` | customer share links |
| `NAGARVA_APP_VERSION` | tracks `pubspec.yaml` `version:` (currently `1.0.0+1`) | shown in Settings → Help & About |

The Sentry DSN is in the Sentry dashboard, not in this repo. Crash
reporting being off is fine for local work — but a build handed to a
tester should carry the DSN, or you learn nothing from their crashes.

## 6. Release signing — currently DEBUG keys

`android/app/build.gradle` still has:

```gradle
release {
    signingConfig signingConfigs.debug
}
```

So `flutter build apk --release` produces a **debug-signed** APK. Fine
to sideload for testing; **blocks Play Store**. There is no
`android/key.properties` to copy because one has never been created.
When a real keystore exists, it and `key.properties` stay gitignored and
must be moved between machines by hand — that will be the first genuine
secret this project has.

## 7. Emulator — Impeller renders BLACK

Flutter 3.35 defaults to Impeller on Android, and on the emulator's GL
translator the app surface composites to **pure black** while the native
splash renders fine. No Dart error appears, because there is none.

```bash
adb shell am start -n in.nagarva.app/.MainActivity --ez enable-impeller false
```

Cost an hour once. Full detail, including the two false trails
(`screencap` black is not proof of anything; do **not** "fix" it with
`-gpu swiftshader_indirect`), is in `CLAUDE.md`'s 25 Aug 2026 entry.

## 8. Know the baseline before you blame yourself

```
flutter analyze lib/
```

The pre-existing baseline is **0 errors, a couple hundred warnings/infos**
(mostly `deprecated_member_use` from Flutter framework churn, plus a
handful of `unused_import`/`avoid_unnecessary_containers`/
`use_build_context_synchronously` infos). The exact count drifts as the
Flutter SDK's own deprecations change — don't hardcode a number here,
compare against `git stash` / a clean checkout if you need to know
whether YOUR change introduced something. **Any `error •` line is always
yours to fix.**

`flutter analyze` exits **non-zero whenever it reports anything**, so a
non-zero exit does not mean failure — check for `error •` lines, not the
exit code.

## 9. Line endings

The repo has **no `.gitattributes`**, and `windows/flutter/generated_*`
show as modified on a fresh checkout with CRLF-only differences. Leave
them uncommitted. Inspect with:

```bash
git diff --ignore-cr-at-eol
```

Avoid editing tracked files with scripts that rewrite whole files —
Python's text-mode write silently converts the file to CRLF and turns a
50-line change into a 1400-line diff. If a diffstat is far larger than
your edit, stop and check before committing.

---

## Where the project state actually lives

- **`CLAUDE.md`** (project root) — the single source of truth: brief,
  architecture, conventions, known issues, roadmap, and a dated
  changelog of why things are the way they are. Read this first.
  (The separate module-status tracker this section used to point at
  was folded into `CLAUDE.md` and removed — everything it tracked is
  now recorded there, kept current.)
- **`supabase/*.sql`** — migrations. **Handed over, never auto-run.**
  Check `CLAUDE.md`'s "Known bugs" / roadmap sections for which are
  still unrun.
