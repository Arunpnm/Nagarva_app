import 'package:flutter_test/flutter_test.dart';
import 'package:arun_p_k_r_s/permissions.dart';

/// Tests for the 25 Aug 2026 financial-tier split.
///
/// These exist for one specific reason: the split's safety rests on a
/// claim about `effective()`'s merge rule — that a module present in a
/// role preset but ABSENT from a saved matrix inherits the preset. If
/// that were wrong, every staff member with an explicitly saved
/// permissions matrix would silently lose the new tiers the moment the
/// modules were added, and the failure would be invisible: no error, no
/// analyzer warning, just cards quietly missing for one person.
///
/// That is exactly the shape of the bug this whole split is unpicking
/// (a manager losing Revenue/Labour/Expenses/Outstanding), so asserting
/// it rather than reasoning about it is the point.
///
/// `_rajeshSaved` below is the REAL matrix from the live `staff` row,
/// copied verbatim on 25 Aug 2026 — a materialised snapshot of
/// fullAccess() taken before the new modules existed. It is the actual
/// row the split has to survive, not a constructed example.
void main() {
  // Verbatim from live Postgres: the one staff row carrying an explicit
  // saved matrix. Note it has NO financials* keys — it predates them.
  const rajeshSaved = <String, dynamic>{
    'fleet': {'edit': true, 'view': true, 'create': true, 'delete': true},
    'leads': {'edit': true, 'view': true, 'create': true, 'delete': true},
    'orders': {'edit': true, 'view': true, 'create': true, 'delete': true},
    'reports': {'edit': true, 'view': true, 'create': true, 'delete': true},
    'accounts': {'edit': true, 'view': true, 'create': true, 'delete': true},
    'expenses': {'edit': true, 'view': true, 'create': true, 'delete': true},
    'payments': {'edit': true, 'view': true, 'create': true, 'delete': true},
    'dashboard': {'edit': true, 'view': true, 'create': true, 'delete': true},
    'pl_report': {'edit': true, 'view': true, 'create': true, 'delete': true},
    'operations': {'edit': true, 'view': true, 'create': true, 'delete': true},
    // 'quotations' is present on the live row but is NOT in kPermModules
    // (the real key is 'survey_quote'). decode() drops it. Kept here so
    // the fixture stays faithful to production drift.
    'quotations': {'edit': true, 'view': true, 'create': true, 'delete': true},
  };

  group('the two new modules exist and are money-marked', () {
    test('financials and financials_margin are registered', () {
      final keys = kPermModules.map((m) => m.key).toSet();
      expect(keys, contains('financials'));
      expect(keys, contains('financials_margin'));
    });

    test('both are moneyModule, so no non-admin preset picks them up', () {
      for (final k in ['financials', 'financials_margin']) {
        final m = kPermModules.firstWhere((m) => m.key == k);
        expect(m.moneyModule, isTrue, reason: '$k must be money-marked');
      }
    });

    test('both have an empty pageName and never widen the sidebar', () {
      // They gate cards inside HomePage, not destinations of their own.
      // If either ever gained a real pageName, a grant would silently
      // become a nav grant too.
      for (final k in ['financials', 'financials_margin']) {
        final m = kPermModules.firstWhere((m) => m.key == k);
        expect(m.pageName, isEmpty, reason: '$k must not be a page');
      }

      final pages = StaffPermissions.allowedPageNames({
        'financials': {'view': true},
        'financials_margin': {'view': true},
      });
      expect(pages, isEmpty,
          reason: 'financial tiers must contribute no page names');
      expect(pages, isNot(contains('')),
          reason: 'empty page name must never reach the allow-list');
    });
  });

  group('existing staff rows survive the split without a data migration', () {
    test('manager with a pre-split saved matrix still gets both tiers', () {
      // This is the assertion the "no migration needed" decision rests
      // on. effective() unions base.keys with saved.keys, so a module
      // the saved matrix has never heard of falls back to the preset —
      // and the manager preset is fullAccess(), which iterates
      // kPermModules and therefore now includes both new tiers.
      final eff = StaffPermissions.effective(
        rawPermissions: rajeshSaved,
        role: 'manager',
      );

      expect(StaffPermissions.can(eff, 'financials', 'view'), isTrue,
          reason: 'manager must not lose revenue when the split lands');
      expect(StaffPermissions.can(eff, 'financials_margin', 'view'), isTrue,
          reason: 'manager must not lose margin when the split lands');
    });

    test('their explicitly saved permissions are still honoured', () {
      // Guard against "fixed it by making everything full access".
      final eff = StaffPermissions.effective(
        rawPermissions: rajeshSaved,
        role: 'manager',
      );
      expect(StaffPermissions.can(eff, 'orders', 'delete'), isTrue);
      expect(StaffPermissions.can(eff, 'dashboard', 'view'), isTrue);
    });

    test('a staff row with {} permissions is pure preset', () {
      final eff = StaffPermissions.effective(
        rawPermissions: <String, dynamic>{},
        role: 'supervisor',
      );
      expect(StaffPermissions.can(eff, 'orders', 'view'), isTrue);
      expect(StaffPermissions.can(eff, 'financials', 'view'), isFalse);
    });
  });

  group('the tiers are actually separate — the split is not cosmetic', () {
    test('supervisor gets neither tier', () {
      final eff =
          StaffPermissions.effective(rawPermissions: null, role: 'supervisor');
      expect(StaffPermissions.can(eff, 'financials', 'view'), isFalse);
      expect(StaffPermissions.can(eff, 'financials_margin', 'view'), isFalse);
    });

    test('driver, helper and packer get neither tier', () {
      for (final role in ['driver', 'helper', 'packer']) {
        final eff =
            StaffPermissions.effective(rawPermissions: null, role: role);
        expect(StaffPermissions.can(eff, 'financials', 'view'), isFalse,
            reason: '$role must not see revenue');
        expect(StaffPermissions.can(eff, 'financials_margin', 'view'), isFalse,
            reason: '$role must not see margin');
      }
    });

    test('reports.view alone does NOT grant revenue or margin', () {
      // The whole point of the split. Before it, one `reports` grant
      // carried operational counts, revenue AND profit together.
      final onlyReports = <String, dynamic>{
        'reports': {'view': true},
      };
      final eff = StaffPermissions.effective(
        rawPermissions: onlyReports,
        role: 'driver', // a preset with none of the three
      );
      expect(StaffPermissions.can(eff, 'reports', 'view'), isTrue);
      expect(StaffPermissions.can(eff, 'financials', 'view'), isFalse,
          reason: 'reports must no longer imply revenue');
      expect(StaffPermissions.can(eff, 'financials_margin', 'view'), isFalse,
          reason: 'reports must no longer imply margin');
    });

    test('revenue can be granted without margin', () {
      // The branch-manager case that motivated the split: trusted with
      // turnover, not with cost and profit.
      final eff = StaffPermissions.effective(
        rawPermissions: <String, dynamic>{
          'financials': {'view': true},
        },
        role: 'supervisor',
      );
      expect(StaffPermissions.can(eff, 'financials', 'view'), isTrue);
      expect(StaffPermissions.can(eff, 'financials_margin', 'view'), isFalse);
    });
  });

  group('owner is unaffected', () {
    test('owner gets both tiers regardless of saved matrix', () {
      final eff = StaffPermissions.effective(
        rawPermissions: <String, dynamic>{'orders': {}},
        role: 'owner',
      );
      expect(StaffPermissions.can(eff, 'financials', 'view'), isTrue);
      expect(StaffPermissions.can(eff, 'financials_margin', 'view'), isTrue);
    });
  });
}
