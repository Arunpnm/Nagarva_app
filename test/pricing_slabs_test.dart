import 'package:flutter_test/flutter_test.dart';
import 'package:arun_p_k_r_s/backend/pricing_defaults.dart';

/// Item 12B/12A unit tests.
///
/// These cover the parts of the slab work that are pure logic and carry
/// real money risk: the validation that stops a vendor saving a broken
/// table, the two-list round-trip that keeps `cft_ranges` and `packages`
/// in sync, and — the actual bug this item was raised for — the removal of
/// `packageInfoForCft`'s silent `packages.first` fallback.
///
/// Deliberately not covered here: the editor widget itself and anything
/// touching Supabase. Those need a session and a live DB; see the session
/// notes for what was and wasn't verified on device.
void main() {
  CftSlab slab(num from, num? to, String pkg,
          {String vehicle = '14 Ft', int crew = 4}) =>
      CftSlab(
        cftFrom: from,
        cftTo: to,
        packageName: pkg,
        vehicle: vehicle,
        crew: crew,
        vehicleCft: to ?? from,
      );

  group('validateSlabs', () {
    test('accepts a contiguous table ending open-ended', () {
      final errors = validateSlabs([
        slab(0, 100, 'Micro'),
        slab(101, 250, 'Mini'),
        slab(251, null, 'Standard'),
      ]);
      expect(errors, isEmpty);
    });

    test('rejects an overlap', () {
      final errors = validateSlabs([
        slab(0, 150, 'Micro'),
        slab(101, 250, 'Mini'),
        slab(251, null, 'Standard'),
      ]);
      expect(errors.map((e) => e.message).join(' '), contains('overlaps'));
    });

    test('rejects a gap — the "silently no suggestion" case', () {
      final errors = validateSlabs([
        slab(0, 100, 'Micro'),
        slab(150, 250, 'Mini'),
        slab(251, null, 'Standard'),
      ]);
      final msg = errors.map((e) => e.message).join(' ');
      expect(msg, contains('Gap'));
      // The message must name the range that would fall through, so the
      // vendor can fix it without arithmetic.
      expect(msg, contains('101'));
      expect(msg, contains('149'));
    });

    test('requires an open-ended top row', () {
      final errors = validateSlabs([
        slab(0, 100, 'Micro'),
        slab(101, 250, 'Mini'),
      ]);
      expect(errors.map((e) => e.message).join(' '), contains('open-ended'));
    });

    test('rejects more than one open-ended row', () {
      final errors = validateSlabs([
        slab(0, null, 'Micro'),
        slab(101, null, 'Mini'),
      ]);
      expect(errors.map((e) => e.message).join(' '),
          contains('Only the last slab'));
    });

    test('rejects duplicate package names (the join key)', () {
      final errors = validateSlabs([
        slab(0, 100, 'Standard'),
        slab(101, null, 'Standard'),
      ]);
      expect(errors.map((e) => e.message).join(' '),
          contains('share the package name'));
    });

    test('rejects a first row that does not start at 0', () {
      final errors = validateSlabs([slab(50, null, 'Micro')]);
      expect(errors.map((e) => e.message).join(' '), contains('Start it at 0'));
    });

    test('rejects blank vehicle and zero crew', () {
      final errors = validateSlabs([
        CftSlab(
            cftFrom: 0,
            cftTo: null,
            packageName: 'Standard',
            vehicle: '',
            crew: 0,
            vehicleCft: 0),
      ]);
      final msg = errors.map((e) => e.message).join(' ');
      expect(msg, contains('no vehicle'));
      expect(msg, contains('crew count'));
    });

    test('rejects an empty table', () {
      expect(validateSlabs([]), isNotEmpty);
    });
  });

  group('slabsToConfig round-trip', () {
    test('writes both lists and survives a trip back through slabs', () {
      final original = [
        slab(0, 100, 'Micro', vehicle: '7 Ft', crew: 2),
        slab(101, 250, 'Mini', vehicle: '10 Ft', crew: 3),
        slab(251, null, 'Standard', vehicle: '14 Ft', crew: 4),
      ];
      final config = PricingConfig.slabsToConfig(original);

      // Both lists written, same length, same order.
      expect((config['cft_ranges'] as List).length, 3);
      expect((config['packages'] as List).length, 3);
      expect((config['cft_ranges'] as List).last['max'], isNull);

      // Round-trip: parse them back the way loadForCurrentOrg would and
      // confirm the derived From chain rebuilds exactly.
      final ranges = [
        for (final r in config['cft_ranges'] as List)
          CftRange(r['max'] as num?, r['pkg'] as String),
      ];
      final packages = [
        for (final p in config['packages'] as List)
          PackageInfo(p['type'] as String, p['crew'] as int,
              p['vehicle'] as String, p['vehicleCft'] as num),
      ];

      for (var i = 0; i < original.length; i++) {
        final s = suggestPackage(
            original[i].cftFrom == 0 ? 50 : original[i].cftFrom, ranges, packages);
        expect(s.ok, isTrue, reason: 'row $i should resolve');
      }
    });

    test('throws rather than writing an invalid config', () {
      expect(
        () => PricingConfig.slabsToConfig([slab(0, 100, 'Micro')]),
        throwsStateError,
      );
    });
  });

  group('suggestPackage — the packages.first fallback fix', () {
    final ranges = [
      const CftRange(100, 'Micro'),
      const CftRange(450, '2 BHK Small'),
      const CftRange(null, 'Big'),
    ];
    final packages = [
      const PackageInfo('Micro', 2, '7 Ft', 161),
      const PackageInfo('2 BHK Small', 4, '14 Ft', 546),
      const PackageInfo('Big', 8, '19 Ft', 931),
    ];

    test('resolves a normal total', () {
      final s = suggestPackage(400, ranges, packages);
      expect(s.ok, isTrue);
      expect(s.info!.type, '2 BHK Small');
      expect(s.info!.crew, 4);
      expect(s.info!.vehicle, '14 Ft');
    });

    test('reports a renamed package instead of guessing packages.first', () {
      // The exact regression: the range still says "2 BHK Small" but the
      // packages list was renamed. The OLD code returned packages.first —
      // a 7 Ft tempo and 2 crew for a 400 CFT move, with no error.
      final renamed = [
        const PackageInfo('Micro', 2, '7 Ft', 161),
        const PackageInfo('2BHK Small', 4, '14 Ft', 546), // note: no space
        const PackageInfo('Big', 8, '19 Ft', 931),
      ];
      final s = suggestPackage(400, ranges, renamed);

      expect(s.ok, isFalse);
      expect(s.isConfigError, isTrue);
      expect(s.unresolvedPackageName, '2 BHK Small');
      // Crucially: it must NOT have silently produced the first package.
      expect(s.info, isNull);
    });

    test('zero/empty is "nothing yet", not a config error', () {
      final s = suggestPackage(0, ranges, packages);
      expect(s.empty, isTrue);
      expect(s.isConfigError, isFalse);
    });

    test('a top-end gap is a config error, not a wrong answer', () {
      // No open-ended row: 9999 matches nothing. Validation prevents
      // saving this, but a hand-edited config can still contain it.
      final capped = [const CftRange(100, 'Micro')];
      final s = suggestPackage(9999, capped, packages);
      expect(s.isConfigError, isTrue);
      expect(s.info, isNull);
    });
  });

  group('activeSurveyCats (Item 12A)', () {
    test('hides deactivated items and now-empty categories, keeps the rest',
        () {
      final cfg = PricingConfig.forTest(surveyCats: {
        'Bedrooms': [
          const SurveyItem('Bed', [SurveySubItem('Single', 30)]),
          const SurveyItem('Old Item', [SurveySubItem('X', 5)], active: false),
        ],
        'Retired': [
          const SurveyItem('Gone', [SurveySubItem('X', 5)], active: false),
        ],
      });

      final active = cfg.activeSurveyCats;
      expect(active.keys, ['Bedrooms']);
      expect(active['Bedrooms']!.length, 1);
      expect(active['Bedrooms']!.single.name, 'Bed');

      // The unfiltered map is untouched — a hidden item must still
      // resolve for a quote that already references it.
      expect(cfg.surveyCats['Retired'], isNotNull);
    });
  });
}
