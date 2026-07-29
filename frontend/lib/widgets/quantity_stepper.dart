import 'package:flutter/material.dart';

/// Density variants for [QuantityStepper].
enum QuantityStepperSize {
  /// Default pill used when space allows (detailed inventory when scaled).
  standard,

  /// Compact list rows and match offer dialog.
  compact,

  /// Grid cells (tightest).
  dense,
}

/// Pill-style quantity control with clear ± affordance (#538).
///
/// Layout matches the product reference:
/// light gray rounded track · red decrement · white qty box · green increment.
///
/// Intrinsic width is fixed per [size]; callers on tight layouts should wrap
/// with [FittedBox] (`BoxFit.scaleDown`) so three-up columns do not overflow.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.quantity,
    this.onDecrement,
    this.onIncrement,
    this.size = QuantityStepperSize.standard,
    this.decrementKey,
    this.incrementKey,
    this.enabled = true,
    this.decrementSemanticLabel,
    this.incrementSemanticLabel,
  });

  final int quantity;

  /// When null, the decrement control is disabled (e.g. at min qty).
  final VoidCallback? onDecrement;

  /// When null, the increment control is disabled (e.g. at max qty).
  final VoidCallback? onIncrement;

  final QuantityStepperSize size;

  /// Optional keys for widget tests (e.g. `stepper_inc_HAVE`).
  final Key? decrementKey;
  final Key? incrementKey;

  /// Master enable; when false both sides are inert (deleted items).
  final bool enabled;

  /// Accessibility label for the decrement control (defaults to English).
  final String? decrementSemanticLabel;

  /// Accessibility label for the increment control (defaults to English).
  final String? incrementSemanticLabel;

  static const Color _trackColor = Color(0xFFF0F1F3);
  static const Color _decrementColor = Color(0xFFE25555);
  static const Color _incrementColor = Color(0xFF2EAF6A);
  static const Color _qtyBoxBorder = Color(0xFFE4E6EA);

  @override
  Widget build(BuildContext context) {
    final dims = _QuantityStepperDims.forSize(size);
    final canDec = enabled && onDecrement != null;
    final canInc = enabled && onIncrement != null;

    return Container(
      height: dims.height,
      decoration: BoxDecoration(
        color: _trackColor,
        borderRadius: BorderRadius.circular(dims.trackRadius),
      ),
      padding: EdgeInsets.symmetric(horizontal: dims.trackPadH),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(
            key: decrementKey,
            icon: Icons.remove,
            color: _decrementColor,
            size: dims,
            enabled: canDec,
            onTap: canDec ? onDecrement : null,
            semanticLabel: decrementSemanticLabel ?? 'Decrease quantity',
          ),
          _QuantityBox(quantity: quantity, size: dims),
          _StepButton(
            key: incrementKey,
            icon: Icons.add,
            color: _incrementColor,
            size: dims,
            enabled: canInc,
            onTap: canInc ? onIncrement : null,
            semanticLabel: incrementSemanticLabel ?? 'Increase quantity',
          ),
        ],
      ),
    );
  }
}

class _QuantityStepperDims {
  const _QuantityStepperDims({
    required this.height,
    required this.trackRadius,
    required this.trackPadH,
    required this.buttonExtent,
    required this.iconSize,
    required this.qtyMinWidth,
    required this.qtyHeight,
    required this.qtyRadius,
    required this.qtyFontSize,
    required this.gap,
  });

  final double height;
  final double trackRadius;
  final double trackPadH;
  final double buttonExtent;
  final double iconSize;
  final double qtyMinWidth;
  final double qtyHeight;
  final double qtyRadius;
  final double qtyFontSize;
  final double gap;

  static _QuantityStepperDims forSize(QuantityStepperSize size) {
    switch (size) {
      case QuantityStepperSize.standard:
        // Sized to stay readable when FittedBox-scaled into three-up columns.
        return const _QuantityStepperDims(
          height: 34,
          trackRadius: 17,
          trackPadH: 3,
          buttonExtent: 30,
          iconSize: 18,
          qtyMinWidth: 36,
          qtyHeight: 26,
          qtyRadius: 8,
          qtyFontSize: 14,
          gap: 2,
        );
      case QuantityStepperSize.compact:
        return const _QuantityStepperDims(
          height: 26,
          trackRadius: 13,
          trackPadH: 2,
          buttonExtent: 24,
          iconSize: 14,
          qtyMinWidth: 24,
          qtyHeight: 20,
          qtyRadius: 6,
          qtyFontSize: 12,
          gap: 1,
        );
      case QuantityStepperSize.dense:
        return const _QuantityStepperDims(
          height: 22,
          trackRadius: 11,
          trackPadH: 1,
          buttonExtent: 20,
          iconSize: 12,
          qtyMinWidth: 20,
          qtyHeight: 16,
          qtyRadius: 5,
          qtyFontSize: 10,
          gap: 0,
        );
    }
  }
}

class _QuantityBox extends StatelessWidget {
  const _QuantityBox({required this.quantity, required this.size});

  final int quantity;
  final _QuantityStepperDims size;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minWidth: size.qtyMinWidth),
      height: size.qtyHeight,
      margin: EdgeInsets.symmetric(horizontal: size.gap),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size.qtyRadius),
        border: Border.all(color: QuantityStepper._qtyBoxBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        '$quantity',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: size.qtyFontSize,
          fontWeight: FontWeight.w700,
          height: 1.1,
          color: const Color(0xFF212529),
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    super.key,
    required this.icon,
    required this.color,
    required this.size,
    required this.enabled,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final Color color;
  final _QuantityStepperDims size;
  final bool enabled;
  final VoidCallback? onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final iconColor = enabled ? color : color.withValues(alpha: 0.28);
    return SizedBox(
      width: size.buttonExtent,
      height: size.buttonExtent,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(size.buttonExtent / 2),
          child: Semantics(
            button: true,
            enabled: enabled,
            label: semanticLabel,
            child: Center(
              child: Icon(icon, size: size.iconSize, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}
