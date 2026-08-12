# Fix brief — Quick Entry sheet + bottom nav

**For:** Claude Code
**Scope:** Two UI defects observed on device. No schema changes. No new modules.

> **Verify before editing.** File and symbol names below come from earlier session reports
> (`QuickEntryDialog`, `mobile_bottom_nav.dart`, `nav.dart`, `main.dart`'s `_tabs`), not from
> reading the current tree. Confirm each against actual code before applying. If a name
> differs, follow the real code — do not rename to match this brief.

---

## Bug 1 — Quick Entry

Three separate defects presenting as one broken screen. Fix all three; they are independent.

### 1a. Tap does nothing — dead `BuildContext` after pop

**Cause (primary hypothesis).** Tiles call `Navigator.pop(context)` and then
`GoRouter.of(context).pushNamed(routeName)` on the *same* context. Once the dialog route is
popped, that element is deactivated and the subsequent navigation silently no-ops. Orders'
and Leads' FABs work because they call `context.pushNamed` on a live page context — this is
exactly the "one level removed" difference identified in the earlier read.

**Confirm first.** Add a temporary `debugPrint` immediately before the `pushNamed` call and
tap a tile. If the line prints but no navigation occurs, the hypothesis holds. If it does not
print, the failure is upstream in the tile's `onTap` and this fix is the wrong one — report
back rather than proceeding.

**Fix.** The sheet must not navigate. It returns a route name; the caller navigates.

```dart
// Caller — the Dashboard FAB's onPressed
Future<void> _openQuickEntry(BuildContext context) async {
  final routeName = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const QuickEntrySheet(),
  );
  if (routeName == null) return;
  if (!context.mounted) return;
  context.pushNamed(routeName);
}
```

```dart
// Tile — inside the sheet
onTap: () => Navigator.of(context).pop(tile.routeName),
```

`context.mounted` is the guard that makes this safe across the await. Keep it.

### 1b. Full-screen box instead of a bottom sheet

Replace the `Dialog`/`showDialog` presentation with `showModalBottomSheet` as above, and
give the sheet body:

```dart
class QuickEntrySheet extends StatelessWidget {
  const QuickEntrySheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tiles = quickEntryTilesFor(context); // permission-filtered — see 1c

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Quick Entry', style: theme.textTheme.titleLarge),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                  constraints: const BoxConstraints.tightFor(
                    width: 48, height: 48,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: [for (final t in tiles) QuickEntryTile(tile: t)],
            ),
          ],
        ),
      ),
    );
  }
}
```

Key points: `mainAxisSize: MainAxisSize.min` plus `shrinkWrap` is what makes the sheet wrap
its content instead of filling the screen. `isScrollControlled: true` allows it to exceed
half-height if a tenant ever has more tiles. `backgroundColor: Colors.transparent` on the
sheet lets the rounded corners show against the scrim.

Each tile should be a bordered card, not bare icon-and-text — the reference has a visible
1px border, ~12px radius, and internal padding. Wrap the whole card in the `InkWell`/
`GestureDetector` so the entire card area is the tap target, not just the icon.

### 1c. Two tiles missing

Reference shows four: New Inquiry (3 steps), Confirm Booking (4 steps), Record Payment
(2 steps), Quick Expense (2 steps). Device shows only the first two, on an owner session.

Do not guess at the permission keys. Print the resolved permission set for the current
session, then print the gate condition evaluated for each of the four tiles, and report
which key is failing and why. Likely one of: the key for Record Payment / Quick Expense is
absent from `permissions.dart`; or it exists but is not in the owner grant list; or the tile
list itself was truncated during a refactor and no permission is involved at all.

**Open question for Arun — do not resolve unilaterally.** If the two tiles were
intentionally dropped from Nagarva's scope, only 1a and 1b are bugs. Ask before adding them
back.

---

## Bug 2 — Bottom nav

### 2a. Dead space when the bar hides

**Cause.** The bar is animated out visually, but the body still reserves its height — either
because it is overlaid with `extendBody` and a fixed bottom padding, or because the hide
animation only affects opacity/offset and not layout size.

**Preferred fix — collapse the layout, don't overlay.** Wrap the bar in a `SizeTransition`
driven by the same controller that currently hides it. When the size factor reaches zero the
bar occupies no layout height at all, `Scaffold` gives the reclaimed space to the body
automatically, and no padding compensation is needed anywhere:

```dart
Scaffold(
  // extendBody stays false — the bar participates in layout
  bottomNavigationBar: SizeTransition(
    sizeFactor: _navController,   // 1.0 = shown, 0.0 = hidden
    axisAlignment: -1,
    child: const MobileBottomNav(),
  ),
  body: ...,
)
```

If any scroll view currently carries `EdgeInsets.only(bottom: kNavHeight)` or a trailing
`SizedBox` sized to the nav, remove it — with `SizeTransition` it becomes double-counting
and reintroduces the gap. Search for that padding before committing.

Only fall back to `extendBody: true` with animated padding if the nav genuinely must float
over content for a design reason. If so, the padding must be driven by the same
`AnimationController` inside an `AnimatedBuilder` so it animates in lockstep — a static
padding value is what produces the dead space.

### 2b. Six items, last one clipped

`Calendar` is cut off at the right edge. `BottomNavigationBar` will not fit six labelled
destinations at typical phone widths regardless of styling. Options, in order of preference:

1. Reduce to five destinations and move the sixth behind an overflow entry or the drawer.
2. Migrate to Material 3 `NavigationBar`, which handles overflow more gracefully — but
   verify it against the dark theme before adopting.
3. Custom `Row` of `Expanded` children with icon-only rendering below a width threshold.

Pick one, state which and why in the commit message.

### 2c. `Surveys` and `Survey` both present

Two destinations one character apart, one carrying a badge. Almost certainly list-view vs.
new-survey. Rename to something unambiguous (`Surveys` / `New Survey`) so it doesn't read as
a duplicate. Cosmetic, but it is the kind of thing a tenant will file a support ticket about.

---

## Gate before commit

1. `flutter analyze` clean — necessary, not sufficient.
2. Build an APK and tap the Quick Entry FAB. Every visible tile must navigate.
3. Scroll a long list until the nav hides. No dead band at the bottom, and content reaches
   the screen edge.
4. Confirm all six (or five) nav destinations are reachable and none is clipped, on both
   owner and manager sessions.

Report 1c's finding before implementing it. Everything else can ship in one commit per bug.
