import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/utils/inventory_quantity_format.dart';

void main() {
  test('omits parentheses when projected is null or equal (#427)', () {
    expect(formatInventoryQuantity(2, null), '2');
    expect(formatInventoryQuantity(2, 2), '2');
    expect(formatInventoryQuantity(0, 0), '0');
  });

  test('shows current(projected) when they differ (#427)', () {
    expect(formatInventoryQuantity(2, 1), '2(1)');
    expect(formatInventoryQuantity(1, 0), '1(0)');
    expect(formatInventoryQuantity(1, -1), '1(-1)');
    expect(formatInventoryQuantity(0, 1), '0(1)');
  });
}
