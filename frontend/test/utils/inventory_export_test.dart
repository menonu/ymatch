import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/generated/models.pb.dart';
import 'package:frontend/utils/inventory_export.dart';

/// Build an [InventoryItem] with the proto defaults filled in.
InventoryItem _item({
  required int merchId,
  required String status,
  required int quantity,
  required String merchName,
  required String groupName,
}) {
  return InventoryItem(
    id: merchId,
    userId: 1,
    merchId: merchId,
    status: status,
    quantity: quantity,
    merchName: merchName,
    groupName: groupName,
  );
}

const _labels = ExportLabels(have: '所持', want: '求', trade: '譲');

/// The canonical fixture from ADR 0007's `basic` example.
List<InventoryItem> _canonical() => [
  _item(
    merchId: 1,
    status: 'HAVE',
    quantity: 2,
    merchName: 'a',
    groupName: 'G',
  ),
  _item(
    merchId: 2,
    status: 'HAVE',
    quantity: 3,
    merchName: 'b',
    groupName: 'G',
  ),
  _item(
    merchId: 3,
    status: 'HAVE',
    quantity: 1,
    merchName: 'c',
    groupName: 'G',
  ),
  _item(
    merchId: 4,
    status: 'WANT',
    quantity: 1,
    merchName: 'd',
    groupName: 'G',
  ),
  _item(
    merchId: 5,
    status: 'WANT',
    quantity: 2,
    merchName: 'e',
    groupName: 'G',
  ),
  _item(
    merchId: 6,
    status: 'TRADE',
    quantity: 1,
    merchName: 'a',
    groupName: 'G',
  ),
  _item(
    merchId: 7,
    status: 'TRADE',
    quantity: 2,
    merchName: 'b',
    groupName: 'G',
  ),
];

void main() {
  group('exportInventoryText — basic format', () {
    test('canonical ADR 0007 example', () {
      final out = exportInventoryText(
        items: _canonical(),
        groupName: 'G',
        selected: {ExportStatus.have, ExportStatus.want, ExportStatus.trade},
        format: ExportFormat.basic,
        labels: _labels,
      );
      expect(out, '所持: a*2, b*3, c\n求: d, e*2\n譲: a, b*2');
    });

    test('qty == 1 omits the *qty suffix; qty > 1 keeps it', () {
      final out = exportInventoryText(
        items: [
          _item(
            merchId: 1,
            status: 'HAVE',
            quantity: 1,
            merchName: 'solo',
            groupName: 'G',
          ),
          _item(
            merchId: 2,
            status: 'HAVE',
            quantity: 4,
            merchName: 'multi',
            groupName: 'G',
          ),
        ],
        groupName: 'G',
        selected: {ExportStatus.have},
        format: ExportFormat.basic,
        labels: _labels,
      );
      // Alphabetical sort puts 'multi' before 'solo'.
      expect(out, '所持: multi*4, solo');
    });

    test('rows with quantity <= 0 are excluded', () {
      final out = exportInventoryText(
        items: [
          _item(
            merchId: 1,
            status: 'HAVE',
            quantity: 0,
            merchName: 'zero',
            groupName: 'G',
          ),
          _item(
            merchId: 2,
            status: 'HAVE',
            quantity: -1,
            merchName: 'neg',
            groupName: 'G',
          ),
          _item(
            merchId: 3,
            status: 'HAVE',
            quantity: 2,
            merchName: 'ok',
            groupName: 'G',
          ),
        ],
        groupName: 'G',
        selected: {ExportStatus.have},
        format: ExportFormat.basic,
        labels: _labels,
      );
      expect(out, '所持: ok*2');
    });

    test('checkbox filtering — only 所持 selected emits only the HAVE line', () {
      final out = exportInventoryText(
        items: _canonical(),
        groupName: 'G',
        selected: {ExportStatus.have},
        format: ExportFormat.basic,
        labels: _labels,
      );
      expect(out, '所持: a*2, b*3, c');
    });

    test(
      'checkbox filtering — 求 + 譲 selected, status order is fixed 所持→求→譲',
      () {
        final out = exportInventoryText(
          items: _canonical(),
          groupName: 'G',
          selected: {ExportStatus.want, ExportStatus.trade},
          format: ExportFormat.basic,
          labels: _labels,
        );
        expect(out, '求: d, e*2\n譲: a, b*2');
      },
    );

    test('empty selection yields an empty string', () {
      final out = exportInventoryText(
        items: _canonical(),
        groupName: 'G',
        selected: const {},
        format: ExportFormat.basic,
        labels: _labels,
      );
      expect(out, '');
    });

    test('items in other groups are excluded', () {
      final out = exportInventoryText(
        items: [
          ..._canonical(),
          _item(
            merchId: 99,
            status: 'HAVE',
            quantity: 5,
            merchName: 'zzz',
            groupName: 'Other',
          ),
        ],
        groupName: 'G',
        selected: {ExportStatus.have, ExportStatus.want, ExportStatus.trade},
        format: ExportFormat.basic,
        labels: _labels,
      );
      expect(out, '所持: a*2, b*3, c\n求: d, e*2\n譲: a, b*2');
    });

    test('items with an empty merchName are excluded', () {
      final out = exportInventoryText(
        items: [
          _item(
            merchId: 1,
            status: 'HAVE',
            quantity: 2,
            merchName: 'a',
            groupName: 'G',
          ),
          _item(
            merchId: 2,
            status: 'HAVE',
            quantity: 1,
            merchName: '',
            groupName: 'G',
          ),
        ],
        groupName: 'G',
        selected: {ExportStatus.have},
        format: ExportFormat.basic,
        labels: _labels,
      );
      expect(out, '所持: a*2');
    });

    test('items within a status are sorted alphabetically by name', () {
      // Supplied out of order; output must be alpha.
      final out = exportInventoryText(
        items: [
          _item(
            merchId: 1,
            status: 'HAVE',
            quantity: 1,
            merchName: 'cherry',
            groupName: 'G',
          ),
          _item(
            merchId: 2,
            status: 'HAVE',
            quantity: 1,
            merchName: 'apple',
            groupName: 'G',
          ),
          _item(
            merchId: 3,
            status: 'HAVE',
            quantity: 1,
            merchName: 'banana',
            groupName: 'G',
          ),
        ],
        groupName: 'G',
        selected: {ExportStatus.have},
        format: ExportFormat.basic,
        labels: _labels,
      );
      expect(out, '所持: apple, banana, cherry');
    });

    test('duplicate names in the same status are both listed', () {
      final out = exportInventoryText(
        items: [
          _item(
            merchId: 1,
            status: 'HAVE',
            quantity: 1,
            merchName: 'dup',
            groupName: 'G',
          ),
          _item(
            merchId: 2,
            status: 'HAVE',
            quantity: 2,
            merchName: 'dup',
            groupName: 'G',
          ),
        ],
        groupName: 'G',
        selected: {ExportStatus.have},
        format: ExportFormat.basic,
        labels: _labels,
      );
      expect(out, '所持: dup, dup*2');
    });

    test('no matching items for a selected status omits that status line', () {
      final out = exportInventoryText(
        items: [
          _item(
            merchId: 1,
            status: 'HAVE',
            quantity: 1,
            merchName: 'a',
            groupName: 'G',
          ),
        ],
        groupName: 'G',
        selected: {ExportStatus.have, ExportStatus.want, ExportStatus.trade},
        format: ExportFormat.basic,
        labels: _labels,
      );
      expect(out, '所持: a');
    });
  });

  group('exportInventoryText — csv format', () {
    test('header + one row per item, qty 1 emitted as literal 1', () {
      final out = exportInventoryText(
        items: [
          _item(
            merchId: 1,
            status: 'HAVE',
            quantity: 1,
            merchName: 'a',
            groupName: 'G',
          ),
          _item(
            merchId: 2,
            status: 'WANT',
            quantity: 2,
            merchName: 'b',
            groupName: 'G',
          ),
        ],
        groupName: 'G',
        selected: {ExportStatus.have, ExportStatus.want},
        format: ExportFormat.csv,
        labels: _labels,
      );
      expect(out, 'status,item,quantity\n所持,a,1\n求,b,2');
    });

    test('fields containing a comma are quoted', () {
      final out = exportInventoryText(
        items: [
          _item(
            merchId: 1,
            status: 'HAVE',
            quantity: 1,
            merchName: 'a,b',
            groupName: 'G',
          ),
        ],
        groupName: 'G',
        selected: {ExportStatus.have},
        format: ExportFormat.csv,
        labels: _labels,
      );
      expect(out, 'status,item,quantity\n所持,"a,b",1');
    });

    test('fields containing a quote are quoted and the quote is doubled', () {
      final out = exportInventoryText(
        items: [
          _item(
            merchId: 1,
            status: 'HAVE',
            quantity: 1,
            merchName: 'a"b',
            groupName: 'G',
          ),
        ],
        groupName: 'G',
        selected: {ExportStatus.have},
        format: ExportFormat.csv,
        labels: _labels,
      );
      expect(out, 'status,item,quantity\n所持,"a""b",1');
    });

    test('empty selection yields header only', () {
      final out = exportInventoryText(
        items: _canonical(),
        groupName: 'G',
        selected: const {},
        format: ExportFormat.csv,
        labels: _labels,
      );
      expect(out, 'status,item,quantity');
    });

    test('checkbox filtering keeps only selected status rows', () {
      final out = exportInventoryText(
        items: _canonical(),
        groupName: 'G',
        selected: {ExportStatus.trade},
        format: ExportFormat.csv,
        labels: _labels,
      );
      expect(out, 'status,item,quantity\n譲,a,1\n譲,b,2');
    });
  });

  group('exportInventoryText — markdown format', () {
    test('header + separator + one row per item', () {
      final out = exportInventoryText(
        items: [
          _item(
            merchId: 1,
            status: 'HAVE',
            quantity: 2,
            merchName: 'a',
            groupName: 'G',
          ),
          _item(
            merchId: 2,
            status: 'WANT',
            quantity: 1,
            merchName: 'b',
            groupName: 'G',
          ),
        ],
        groupName: 'G',
        selected: {ExportStatus.have, ExportStatus.want},
        format: ExportFormat.markdown,
        labels: _labels,
      );
      expect(
        out,
        '| status | item | qty |\n|--------|------|-----|\n| 所持 | a | 2 |\n| 求 | b | 1 |',
      );
    });

    test('empty selection yields header + separator only', () {
      final out = exportInventoryText(
        items: _canonical(),
        groupName: 'G',
        selected: const {},
        format: ExportFormat.markdown,
        labels: _labels,
      );
      expect(out, '| status | item | qty |\n|--------|------|-----|');
    });
  });

  group('exportInventoryText — status token mapping', () {
    test('unknown status strings are ignored (not HAVE/WANT/TRADE)', () {
      final out = exportInventoryText(
        items: [
          _item(
            merchId: 1,
            status: 'HAVE',
            quantity: 1,
            merchName: 'a',
            groupName: 'G',
          ),
          _item(
            merchId: 2,
            status: 'BOGUS',
            quantity: 9,
            merchName: 'x',
            groupName: 'G',
          ),
        ],
        groupName: 'G',
        selected: {ExportStatus.have, ExportStatus.want, ExportStatus.trade},
        format: ExportFormat.basic,
        labels: _labels,
      );
      expect(out, '所持: a');
    });
  });
}
