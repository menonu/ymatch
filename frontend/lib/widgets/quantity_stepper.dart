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

/// Flat white quantity control with clear ± affordance (#538).
///
/// Layout matches the app's minimalist Material surface language
/// (cards use elevation 0 + subtle border — no floating shadow):
/// - White track + thin border ([AppTheme] card style)
/// - Light red / green rounded chips for − / +
/// - Center: optional status label above bare quantity (no qty box)
///
/// Set [expand] to `true` in constrained [Expanded] parents (detailed view)
/// so the control fills column width at full type size.
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

  /// Optional status label shown above the number (e.g. 所持 / 求 / 譲).
  final String? label;

  /// Color for [label]; defaults to muted gray when null.
  final Color? labelColor;

  /// Accessibility label for the decrement control (defaults to English).
  final String? decrementSemanticLabel;

  /// Accessibility label for the increment control (defaults to English).
  final String? incrementSemanticLabel;

  // Same surface language as AppTheme.cardTheme (white + #DEE2E6 border).
  static const Color _trackColor = Colors.white;
  static const Color _trackBorder = Color(0xFFDEE2E6);
  static const Color _decrementColor = Color(0xFFE25555);
  static const Color _incrementColor = Color(0xFF2EAF6A);
  static const Color _defaultLabelColor = Color(0xFF6C757D);
  static const Color _qtyColor = Color(0xFF212529);

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
    final qty = _QuantityCenter(
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
        border: Border.all(color: const Color(0xFFE8EAED)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 1,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(
        horizontal: dims.trackPadH,
        vertical: dims.trackPadV,
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: expand
            ? [
                Expanded(flex: 2, child: dec),
                Flexible(flex: 3, child: qty),
                Expanded(flex: 2, child: inc),
              ]
            : [dec, qty, inc],
      ),
    );
  }
}

class _QuantityStepperDims {
  const _QuantityStepperDims({
    required this.height,
    required this.trackRadius,
    required this.trackPadH,
    required this.trackPadV,
    required this.buttonExtent,
    required this.iconSize,
    required this.buttonRadius,
    required this.qtyMinWidth,
    required this.qtyFontSize,
    required this.labelFontSize,
    required this.gap,
  });

  final double height;
  final double trackRadius;
  final double trackPadH;
  final double trackPadV;
  final double buttonExtent;
  final double iconSize;
  final double buttonRadius;
  final double qtyMinWidth;
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
        return const _QuantityStepperDims(
          height: 44,
          trackRadius: 10,
          trackPadH: 4,
          trackPadV: 4,
          buttonExtent: 36,
          iconSize: 20,
          buttonRadius: 8,
          qtyMinWidth: 48,
          qtyFontSize: 15,
          labelFontSize: 9,
          gap: 4,
        );
      case QuantityStepperSize.compact:
        return _QuantityStepperDims(
          height: hasLabel ? 36 : 28,
          trackRadius: 8,
          trackPadH: 3,
          trackPadV: 3,
          buttonExtent: hasLabel ? 28 : 22,
          iconSize: 16,
          buttonRadius: 6,
          qtyMinWidth: hasLabel ? 34 : 26,
          qtyFontSize: 12,
          labelFontSize: 9,
          gap: 3,
        );
      case QuantityStepperSize.dense:
        return _QuantityStepperDims(
          height: hasLabel ? 36 : 28,
          trackRadius: 8,
          trackPadH: 2,
          trackPadV: 2,
          buttonExtent: hasLabel ? 28 : 22,
          iconSize: 16,
          buttonRadius: 6,
          qtyMinWidth: hasLabel ? 32 : 24,
          qtyFontSize: 12,
          labelFontSize: 8,
          gap: 2,
        );
    }
  }
}

/// Bare center: optional label above quantity — no border / box.
class _QuantityCenter extends StatelessWidget {
  const _QuantityCenter({
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
                  color: QuantityStepper._qtyColor,
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
              color: QuantityStepper._qtyColor,
            ),
          );

    return Container(
      width: expand ? double.infinity : null,
      constraints: expand
          ? const BoxConstraints()
          : BoxConstraints(minWidth: size.qtyMinWidth),
      margin: EdgeInsets.symmetric(horizontal: size.gap),
      alignment: Alignment.center,
      child: content,
    );
  }
}

/// ± chip with a light tinted fill of [color] (red / green).
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
    final fill = enabled
        ? color.withValues(alpha: 0.12)
        : color.withValues(alpha: 0.05);
    final border = enabled
        ? color.withValues(alpha: 0.28)
        : color.withValues(alpha: 0.12);

    final chip = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size.buttonRadius),
        child: Ink(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(size.buttonRadius),
            border: Border.all(color: border),
          ),
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

    if (expand) {
      // Fill the Expanded slot; chip height fits inside track padding.
      final chipH = size.height - size.trackPadV * 2;
      return SizedBox(height: chipH, width: double.infinity, child: chip);
    }
    return SizedBox(
      width: size.buttonExtent,
      height: size.buttonExtent,
      child: chip,
    );
  }
}
