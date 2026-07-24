// Unit tests for Event Detail inventory filter + display-mode helpers (#472 / #494).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/event_detail/merch_filters.dart';

void main() {
  group('matchesMerchFilter (#472)', () {
    test('all always matches', () {
      expect(
        matchesMerchFilter(MerchFilter.all, have: 0, want: 0, trade: 0),
        isTrue,
      );
    });

    test('have requires HAVE > 0', () {
      expect(
        matchesMerchFilter(MerchFilter.have, have: 1, want: 0, trade: 0),
        isTrue,
      );
      expect(
        matchesMerchFilter(MerchFilter.have, have: 0, want: 5, trade: 5),
        isFalse,
      );
    });

    test('want requires WANT > 0', () {
      expect(
        matchesMerchFilter(MerchFilter.want, have: 0, want: 1, trade: 0),
        isTrue,
      );
      expect(
        matchesMerchFilter(MerchFilter.want, have: 5, want: 0, trade: 5),
        isFalse,
      );
    });

    test('trade requires TRADE > 0', () {
      expect(
        matchesMerchFilter(MerchFilter.trade, have: 0, want: 0, trade: 1),
        isTrue,
      );
      expect(
        matchesMerchFilter(MerchFilter.trade, have: 5, want: 5, trade: 0),
        isFalse,
      );
    });

    test('missing is HAVE == 0 && WANT == 0 (TRADE ignored)', () {
      expect(
        matchesMerchFilter(MerchFilter.missing, have: 0, want: 0, trade: 0),
        isTrue,
      );
      // Existing semantics: trade-only stock still counts as "missing" owned.
      expect(
        matchesMerchFilter(MerchFilter.missing, have: 0, want: 0, trade: 3),
        isTrue,
      );
      expect(
        matchesMerchFilter(MerchFilter.missing, have: 1, want: 0, trade: 0),
        isFalse,
      );
      expect(
        matchesMerchFilter(MerchFilter.missing, have: 0, want: 1, trade: 0),
        isFalse,
      );
    });
  });

  group('inventoryDisplayFlags (#472)', () {
    test('have shows only Own stepper', () {
      final f = inventoryDisplayFlags(InventoryDisplayMode.have);
      expect(f.showHave, isTrue);
      expect(f.showWant, isFalse);
      expect(f.showTrade, isFalse);
    });

    test('wantTrade shows Wish + For Trade', () {
      final f = inventoryDisplayFlags(InventoryDisplayMode.wantTrade);
      expect(f.showHave, isFalse);
      expect(f.showWant, isTrue);
      expect(f.showTrade, isTrue);
    });

    test('trade shows only For Trade stepper', () {
      final f = inventoryDisplayFlags(InventoryDisplayMode.trade);
      expect(f.showHave, isFalse);
      expect(f.showWant, isFalse);
      expect(f.showTrade, isTrue);
    });

    test('all shows every stepper', () {
      final f = inventoryDisplayFlags(InventoryDisplayMode.all);
      expect(f.showHave, isTrue);
      expect(f.showWant, isTrue);
      expect(f.showTrade, isTrue);
    });
  });

  group('naturalCompare / resolveInitialGroupTabIndex (#494)', () {
    test('naturalCompare orders numeric runs by value', () {
      expect(naturalCompare('item2', 'item10'), lessThan(0));
      expect(naturalCompare('item10', 'item2'), greaterThan(0));
      expect(naturalCompare('alpha', 'beta'), lessThan(0));
    });

    test('resolveInitialGroupTabIndex maps name or falls back', () {
      expect(resolveInitialGroupTabIndex(['A', 'B'], 'B'), 1);
      expect(resolveInitialGroupTabIndex(['A', 'B'], 'missing'), 0);
      expect(resolveInitialGroupTabIndex(['A', 'B'], null), 0);
      expect(resolveInitialGroupTabIndex([], 'B'), 0);
    });
  });

  group('GroupInventoryTotals (#508)', () {
    test('sums HAVE/WANT/TRADE across multiple merch ids', () {
      final lookup = <int, Map<String, int>>{
        1: {'HAVE': 2, 'WANT': 1, 'TRADE': 0},
        2: {'HAVE': 1, 'WANT': 0, 'TRADE': 3},
        3: {'HAVE': 1, 'WANT': 4, 'TRADE': 1},
      };
      final t = GroupInventoryTotals.fromMerchIds([1, 2, 3], lookup);
      expect(t.totalHave, 4);
      expect(t.totalWant, 5);
      expect(t.totalTrade, 4);
    });

    test('zeros when all empty or ids missing from lookup', () {
      expect(
        GroupInventoryTotals.fromMerchIds([1, 2], {}),
        isA<GroupInventoryTotals>()
            .having((t) => t.totalHave, 'have', 0)
            .having((t) => t.totalWant, 'want', 0)
            .having((t) => t.totalTrade, 'trade', 0),
      );
      final partial = GroupInventoryTotals.fromMerchIds(
        [1, 99],
        {
          1: {'HAVE': 0, 'WANT': 0, 'TRADE': 0},
        },
      );
      expect(partial.totalHave, 0);
      expect(partial.totalWant, 0);
      expect(partial.totalTrade, 0);
    });

    test('missing status keys count as zero', () {
      final t = GroupInventoryTotals.fromMerchIds(
        [1],
        {
          1: {'HAVE': 5},
        },
      );
      expect(t.totalHave, 5);
      expect(t.totalWant, 0);
      expect(t.totalTrade, 0);
    });

    test('empty id list yields zeros', () {
      final t = GroupInventoryTotals.fromMerchIds(const [], {
        1: {'HAVE': 9},
      });
      expect(t.totalHave, 0);
      expect(t.totalWant, 0);
      expect(t.totalTrade, 0);
    });
  });

  group('per-event view/filter providers (#494)', () {
    test('family keys isolate state across eventIds', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(viewModeProvider(1).notifier).state = ViewMode.grid;
      container.read(merchFilterProvider(1).notifier).state = MerchFilter.have;
      container.read(inventoryDisplayModeProvider(1).notifier).state =
          InventoryDisplayMode.trade;

      expect(container.read(viewModeProvider(2)), ViewMode.detailed);
      expect(container.read(merchFilterProvider(2)), MerchFilter.all);
      expect(
        container.read(inventoryDisplayModeProvider(2)),
        InventoryDisplayMode.all,
      );

      expect(container.read(viewModeProvider(1)), ViewMode.grid);
      expect(container.read(merchFilterProvider(1)), MerchFilter.have);
      expect(
        container.read(inventoryDisplayModeProvider(1)),
        InventoryDisplayMode.trade,
      );
    });
  });
}
