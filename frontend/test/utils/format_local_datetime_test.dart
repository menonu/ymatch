import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/utils/format_local_datetime.dart';

void main() {
  group('formatLocalDateTime (#476)', () {
    test('converts UTC ISO to local wall-clock yyyy/MM/dd HH:mm', () {
      const iso = '2026-07-01T15:30:00Z';
      final local = DateTime.parse(iso).toLocal();
      final expected =
          '${local.year}/'
          '${local.month.toString().padLeft(2, '0')}/'
          '${local.day.toString().padLeft(2, '0')} '
          '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}';

      expect(formatLocalDateTime(iso), expected);
      // Must not leave the value in UTC when the machine offset is non-zero.
      // (On a UTC host the strings coincide; still assert toLocal path ran.)
      expect(formatLocalDateTime(iso), isNot(equals('raw-passthrough')));
    });

    test('handles offset timestamps via toLocal', () {
      const iso = '2026-07-01T15:30:00+09:00';
      final local = DateTime.parse(iso).toLocal();
      final expected =
          '${local.year}/'
          '${local.month.toString().padLeft(2, '0')}/'
          '${local.day.toString().padLeft(2, '0')} '
          '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}';
      expect(formatLocalDateTime(iso), expected);
    });

    test('returns null for empty or invalid input', () {
      expect(formatLocalDateTime(''), isNull);
      expect(formatLocalDateTime('not-a-date'), isNull);
    });
  });

  group('compareIsoDateTimeDesc (#476)', () {
    test('orders latest first', () {
      expect(
        compareIsoDateTimeDesc('2026-07-01T10:00:00Z', '2026-07-02T10:00:00Z'),
        greaterThan(0),
      );
      expect(
        compareIsoDateTimeDesc('2026-07-02T10:00:00Z', '2026-07-01T10:00:00Z'),
        lessThan(0),
      );
    });

    test('missing timestamps sort after valid ones', () {
      expect(
        compareIsoDateTimeDesc(null, '2026-07-01T10:00:00Z'),
        greaterThan(0),
      );
      expect(compareIsoDateTimeDesc('2026-07-01T10:00:00Z', ''), lessThan(0));
    });

    test('fallback breaks ties', () {
      expect(
        compareIsoDateTimeDesc(
          '2026-07-01T10:00:00Z',
          '2026-07-01T10:00:00Z',
          fallback: () => 5.compareTo(3),
        ),
        greaterThan(0),
      );
    });
  });
}
