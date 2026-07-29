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

  testWidgets('dense/compact sizes still mount (#538)', (tester) async {
    await tester.pumpWidget(
      wrap(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            QuantityStepper(quantity: 1, size: QuantityStepperSize.dense),
            QuantityStepper(quantity: 2, size: QuantityStepperSize.compact),
            QuantityStepper(quantity: 3, size: QuantityStepperSize.standard),
          ],
        ),
      ),
    );
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets(
    'three expanded standard steppers fill narrow columns without overflow (#538)',
    (tester) async {
      // Detailed-view three-up columns: expand fills width at full type size.
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
                      size: QuantityStepperSize.standard,
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
      // Type scale must not be shrunk: qty uses 15 (standard dims).
      final qtyStyle = tester.widget<Text>(find.text('1')).style;
      expect(qtyStyle?.fontSize, 15);
    },
  );

  testWidgets('standard labeled stepper keeps pre-#538 type scale (#538)', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const QuantityStepper(
          quantity: 2,
          label: '所持',
          size: QuantityStepperSize.standard,
        ),
      ),
    );
    expect(tester.widget<Text>(find.text('所持')).style?.fontSize, 9);
    expect(tester.widget<Text>(find.text('2')).style?.fontSize, 15);
    // Track height matches the old detailed Container (44).
    final stepper = tester.getSize(find.byType(QuantityStepper));
    expect(stepper.height, 44);
  });
}
