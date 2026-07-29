import 'package:flutter/material.dart';

/// Density variants for [QuantityStepper].
enum QuantityStepperSize {
  /// Detailed inventory cards — matches pre-#538 type scale (label 9 / qty 15).
  standard,

  /// Compact list rows and match offer dialog.
  compact,

  /// Grid cells (tightest).
  dense,
}

/// Pill-style quantity control with clear ± affordance (#538).
///
/// Layout: light gray track · red decrement · white qty box · green increment.
/// When [label] is set, it is drawn **inside** the white box above the number.
///
/// Set [expand] to `true` in constrained [Expanded] parents (detailed view)
/// so the control fills column width at full type size — same as the old
/// half-area steppers — instead of shrinking via [FittedBox].
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.quantity,
    this.onDecrement,
    this.onIncrement,
    this.size = QuantityStepperSize.standard,
    this.expand = false,
    this.decrementKey,
    this.incrementKey,
    this.enabled = true,
    this.label,
    this.labelColor,
    this.decrementSemanticLabel,
    this.incrementSemanticLabel,
  });

  final int quantity;

  /// When null, the decrement control is disabled (e.g. at min qty).
  final VoidCallback? onDecrement;

  /// When null, the increment control is disabled (e.g. at max qty).
  final VoidCallback? onIncrement;

  final QuantityStepperSize size;

  /// When true, fill the parent width (side buttons grow; type size fixed).
  final bool expand;

  /// Optional keys for widget tests (e.g. `stepper_inc_HAVE`).
  final Key? decrementKey;
  final Key? incrementKey;

  /// Master enable; when false both sides are inert (deleted items).
  final bool enabled;

  /// Optional status label shown inside the qty box above the number
  /// (e.g. 所持 / 求 / 譲).
  final String? label;

  /// Color for [label]; defaults to muted gray when null.
  final Color? labelColor;

  /// Accessibility label for the decrement control (defaults to English).
  final String? decrementSemanticLabel;

  /// Accessibility label for the increment control (defaults to English).
  final String? incrementSemanticLabel;

  static const Color _trackColor = Color(0xFFF0F1F3);
  static const Color _decrementColor = Color(0xFFE25555);
  static const Color _incrementColor = Color(0xFF2EAF6A);
  static const Color _qtyBoxBorder = Color(0xFFE4E6EA);
  static const Color _defaultLabelColor = Color(0xFF6C757D);

  @override
  Widget build(BuildContext context) {
    final hasLabel = label != null && label!.isNotEmpty;
    final dims = _QuantityStepperDims.forSize(size, hasLabel: hasLabel);
    final canDec = enabled && onDecrement != null;
    final canInc = enabled && onIncrement != null;

    final dec = _StepButton(
      key: decrementKey,
      icon: Icons.remove,
      color: _decrementColor,
      size: dims,
      expand: expand,
      enabled: canDec,
      onTap: canDec ? onDecrement : null,
      semanticLabel: decrementSemanticLabel ?? 'Decrease quantity',
    );
    final qtyBox = _QuantityBox(
      quantity: quantity,
      size: dims,
      expand: expand,
      label: hasLabel ? label : null,
      labelColor: labelColor ?? _defaultLabelColor,
    );
    final inc = _StepButton(
      key: incrementKey,
      icon: Icons.add,
      color: _incrementColor,
      size: dims,
      expand: expand,
      enabled: canInc,
      onTap: canInc ? onIncrement : null,
      semanticLabel: incrementSemanticLabel ?? 'Increase quantity',
    );

    return Container(
      height: dims.height,
      width: expand ? double.infinity : null,
      decoration: BoxDecoration(
        color: _trackColor,
        borderRadius: BorderRadius.circular(dims.trackRadius),
      ),
      padding: EdgeInsets.symmetric(horizontal: dims.trackPadH),
      // Clip so dense three-up columns never paint outside the pill.
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: expand
            // Side buttons + qty share width flexibly (old steppers filled
            // the column; type size stays fixed, layout width adapts).
            ? [
                Expanded(flex: 2, child: dec),
                Flexible(flex: 3, child: qtyBox),
                Expanded(flex: 2, child: inc),
              ]
            : [dec, qtyBox, inc],
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
    required this.labelFontSize,
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
  final double labelFontSize;
  final double gap;

  static _QuantityStepperDims forSize(
    QuantityStepperSize size, {
    required bool hasLabel,
  }) {
    switch (size) {
      case QuantityStepperSize.standard:
        // Match pre-#538 detailed stepper: height 44, label 9, qty 15.
        return _QuantityStepperDims(
          height: 44,
          trackRadius: 8,
          trackPadH: 2,
          buttonExtent: 40,
          iconSize: 22,
          qtyMinWidth: hasLabel ? 52 : 40,
          qtyHeight: hasLabel ? 38 : 32,
          qtyRadius: 8,
          qtyFontSize: 15,
          labelFontSize: 9,
          gap: 2,
        );
      case QuantityStepperSize.compact:
        // Pre-#538 compact row was height 26 with 11–12pt type; keep that
        // when unlabeled, slightly taller when label stacks above qty.
        return _QuantityStepperDims(
          height: hasLabel ? 36 : 28,
          trackRadius: 8,
          trackPadH: 2,
          buttonExtent: hasLabel ? 32 : 28,
          iconSize: 16,
          qtyMinWidth: hasLabel ? 36 : 28,
          qtyHeight: hasLabel ? 30 : 22,
          qtyRadius: 6,
          qtyFontSize: 12,
          labelFontSize: 9,
          gap: 1,
        );
      case QuantityStepperSize.dense:
        return _QuantityStepperDims(
          height: hasLabel ? 36 : 28,
          trackRadius: 8,
          trackPadH: 1,
          buttonExtent: hasLabel ? 30 : 26,
          iconSize: 16,
          qtyMinWidth: hasLabel ? 34 : 26,
          qtyHeight: hasLabel ? 30 : 22,
          qtyRadius: 6,
          qtyFontSize: 12,
          labelFontSize: 8,
          gap: 1,
        );
    }
  }
}

class _QuantityBox extends StatelessWidget {
  const _QuantityBox({
    required this.quantity,
    required this.size,
    required this.expand,
    this.label,
    this.labelColor,
  });

  final int quantity;
  final _QuantityStepperDims size;
  final bool expand;
  final String? label;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final hasLabel = label != null && label!.isNotEmpty;
    final content = hasLabel
        ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label!,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: size.labelFontSize,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                  color: labelColor,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                '$quantity',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: size.qtyFontSize,
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                  color: const Color(0xFF212529),
                ),
              ),
            ],
          )
        : Text(
            '$quantity',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: size.qtyFontSize,
              fontWeight: FontWeight.bold,
              height: 1.1,
              color: const Color(0xFF212529),
            ),
          );

    return Container(
      // When expanded, fill the Flexible slot; otherwise use fixed min width.
      width: expand ? double.infinity : null,
      constraints: expand
          ? BoxConstraints(minHeight: size.qtyHeight)
          : BoxConstraints(minWidth: size.qtyMinWidth),
      height: size.qtyHeight,
      margin: EdgeInsets.symmetric(horizontal: size.gap),
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: hasLabel ? 2 : 0),
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
      child: content,
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    super.key,
    required this.icon,
    required this.color,
    required this.size,
    required this.expand,
    required this.enabled,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final Color color;
  final _QuantityStepperDims size;
  final bool expand;
  final bool enabled;
  final VoidCallback? onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final iconColor = enabled ? color : color.withValues(alpha: 0.28);
    final child = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size.trackRadius),
        child: Semantics(
          button: true,
          enabled: enabled,
          label: semanticLabel,
          child: Center(
            child: Icon(icon, size: size.iconSize, color: iconColor),
          ),
        ),
      ),
    );

    if (expand) {
      // Fill the Expanded parent for a large hit target (old half-area style).
      return SizedBox(
        height: size.height,
        width: double.infinity,
        child: child,
      );
    }
    return SizedBox(
      width: size.buttonExtent,
      height: size.buttonExtent,
      child: child,
    );
  }
}
