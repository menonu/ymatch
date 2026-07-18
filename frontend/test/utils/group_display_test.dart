import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/models.dart';
import 'package:frontend/utils/group_display.dart';

MerchandiseGroup _group(String name, {String? displayName}) {
  final g = MerchandiseGroup()
    ..id = 1
    ..eventId = 1
    ..groupName = name;
  if (displayName != null) g.displayName = displayName;
  return g;
}

void main() {
  group('groupDisplayName (#425 / #466)', () {
    test('uses display_name when set', () {
      final byName = {'Pins': _group('Pins', displayName: 'Enamel Pins!')};
      expect(groupDisplayName('Pins', byName), 'Enamel Pins!');
    });

    test('falls back to key when display_name unset, empty, or missing', () {
      expect(groupDisplayName('Stickers', {}), 'Stickers');
      expect(
        groupDisplayName('Bad', {'Bad': _group('Bad', displayName: '')}),
        'Bad',
      );
      expect(groupDisplayNameFor('Key', null), 'Key');
    });
  });

  group('groupLabel (#466)', () {
    test('prefers non-empty display name', () {
      expect(groupLabel('Pins', 'Enamel Pins!'), 'Enamel Pins!');
    });

    test('falls back when null or empty', () {
      expect(groupLabel('Pins', null), 'Pins');
      expect(groupLabel('Pins', ''), 'Pins');
    });
  });
}
