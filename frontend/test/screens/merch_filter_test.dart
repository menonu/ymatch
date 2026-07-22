// Unit tests for Event Detail inventory filter + display-mode helpers (#472 / #494).

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
}
