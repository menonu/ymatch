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
    'three standard steppers in narrow columns do not overflow (#538)',
    (tester) async {
      // Simulate detailed-view three-up columns on a ~360dp phone content width.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: Row(
                children: List.generate(3, (i) {
                  return Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('L$i'),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: QuantityStepper(
                            quantity: i + 1,
                            size: QuantityStepperSize.standard,
                            onDecrement: () {},
                            onIncrement: () {},
                          ),
                        ),
                      ],
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
    },
  );
}
