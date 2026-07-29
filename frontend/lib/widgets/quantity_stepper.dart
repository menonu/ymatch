import 'package:flutter/material.dart';

/// Density variants for [QuantityStepper].
enum QuantityStepperSize {
  /// Detailed inventory cards and offer dialog.
  standard,

  /// Compact list rows.
  compact,

  /// Grid cells (tightest).
  dense,
}

/// Pill-style quantity control with clear ± affordance (#538).
///
/// Layout matches the product reference:
/// light gray rounded track · red decrement · white qty box · green increment.
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
            semanticLabel: 'Decrease quantity',
          ),
          _QuantityBox(quantity: quantity, size: dims),
          _StepButton(
            key: incrementKey,
            icon: Icons.add,
            color: _incrementColor,
            size: dims,
            enabled: canInc,
            onTap: canInc ? onIncrement : null,
            semanticLabel: 'Increase quantity',
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
        return const _QuantityStepperDims(
          height: 36,
          trackRadius: 18,
          trackPadH: 4,
          buttonExtent: 32,
          iconSize: 18,
          qtyMinWidth: 40,
          qtyHeight: 28,
          qtyRadius: 8,
          qtyFontSize: 15,
          gap: 2,
        );
      case QuantityStepperSize.compact:
        return const _QuantityStepperDims(
          height: 28,
          trackRadius: 14,
          trackPadH: 2,
          buttonExtent: 26,
          iconSize: 14,
          qtyMinWidth: 28,
          qtyHeight: 22,
          qtyRadius: 6,
          qtyFontSize: 12,
          gap: 1,
        );
      case QuantityStepperSize.dense:
        return const _QuantityStepperDims(
          height: 24,
          trackRadius: 12,
          trackPadH: 1,
          buttonExtent: 22,
          iconSize: 12,
          qtyMinWidth: 22,
          qtyHeight: 18,
          qtyRadius: 5,
          qtyFontSize: 11,
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
