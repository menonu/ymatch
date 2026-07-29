import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/quantity_stepper.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );
  }

  testWidgets('renders quantity and fires ± callbacks (#538)', (tester) async {
    var qty = 3;
    await tester.pumpWidget(
      wrap(
        StatefulBuilder(
          builder: (context, setState) {
            return QuantityStepper(
              quantity: qty,
              incrementKey: const Key('inc'),
              decrementKey: const Key('dec'),
              onIncrement: () => setState(() => qty++),
              onDecrement: () => setState(() => qty--),
            );
          },
        ),
      ),
    );

    expect(find.text('3'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byIcon(Icons.remove), findsOneWidget);

    await tester.tap(find.byKey(const Key('inc')));
    await tester.pump();
    expect(find.text('4'), findsOneWidget);

    await tester.tap(find.byKey(const Key('dec')));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('null callbacks disable the matching side (#538)', (
    tester,
  ) async {
    var called = false;
    await tester.pumpWidget(
      wrap(
        QuantityStepper(
          quantity: 0,
          incrementKey: const Key('inc'),
          decrementKey: const Key('dec'),
          onIncrement: () => called = true,
          onDecrement: null,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('dec')));
    await tester.pump();
    expect(called, isFalse);

    await tester.tap(find.byKey(const Key('inc')));
    await tester.pump();
    expect(called, isTrue);
  });

  testWidgets('enabled:false disables both sides (#538)', (tester) async {
    var called = false;
    await tester.pumpWidget(
      wrap(
        QuantityStepper(
          quantity: 2,
          enabled: false,
          incrementKey: const Key('inc'),
          decrementKey: const Key('dec'),
          onIncrement: () => called = true,
          onDecrement: () => called = true,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('inc')));
    await tester.tap(find.byKey(const Key('dec')));
    await tester.pump();
    expect(called, isFalse);
  });

  testWidgets('label renders above the bare quantity (#538)', (tester) async {
    await tester.pumpWidget(
      wrap(
        const QuantityStepper(
          quantity: 5,
          label: '所持',
          labelColor: Colors.indigo,
        ),
      ),
    );
    expect(find.text('所持'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    final labelTop = tester.getTopLeft(find.text('所持')).dy;
    final qtyTop = tester.getTopLeft(find.text('5')).dy;
    expect(labelTop, lessThan(qtyTop));
  });

  testWidgets(
    'three expanded steppers fill narrow columns without overflow (#538)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: Row(
                children: List.generate(3, (i) {
                  return Expanded(
                    child: QuantityStepper(
                      quantity: i + 1,
                      expand: true,
                      label: 'L$i',
                      onDecrement: () {},
                      onIncrement: () {},
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(QuantityStepper), findsNWidgets(3));
      expect(tester.widget<Text>(find.text('1')).style?.fontSize, 15);
    },
  );

  testWidgets('standard sizes match detailed-view metrics (#538)', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const QuantityStepper(quantity: 2, label: '所持')),
    );
    expect(tester.widget<Text>(find.text('所持')).style?.fontSize, 9);
    expect(tester.widget<Text>(find.text('2')).style?.fontSize, 15);
    expect(tester.getSize(find.byType(QuantityStepper)).height, 44);
  });

  testWidgets('half-area hit works under the label (#538)', (tester) async {
    var inc = 0;
    var dec = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              child: QuantityStepper(
                quantity: 1,
                expand: true,
                label: '所持',
                incrementKey: const Key('inc'),
                decrementKey: const Key('dec'),
                onIncrement: () => inc++,
                onDecrement: () => dec++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final stepper = tester.getRect(find.byType(QuantityStepper));
    final decBox = tester.getRect(find.byKey(const Key('dec')));
    expect(decBox.width, closeTo(stepper.width / 2, 2));

    await tester.tapAt(Offset(stepper.center.dx - 8, stepper.center.dy));
    await tester.pump();
    expect(dec, 1);

    await tester.tapAt(Offset(stepper.center.dx + 8, stepper.center.dy));
    await tester.pump();
    expect(inc, 1);
  });
}
