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

/// Flat bordered quantity control with clear ± affordance (#538).
///
/// **Visual** (does not define hit size):
/// - White track + thin border, small inset from the frame
/// - Compact red / green ± chips on the sides
/// - Bare center: optional status label above quantity
///
/// **Hit targets** (larger than the chips):
/// - Left **half** of the control → decrement (extends under 所持/数字)
/// - Right **half** → increment
/// This is the old half-area pattern: taps near the number still count.
///
/// Set [expand] to `true` so the control fills an [Expanded] parent width.
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

  /// When true, fill the parent width.
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

    final body = Stack(
      alignment: Alignment.center,
      children: [
        // --- Hit layer: full left / right halves (under the number) ---
        Positioned.fill(
          child: Row(
            children: [
              Expanded(
                child: _HalfHitTarget(
                  key: decrementKey,
                  enabled: canDec,
                  onTap: canDec ? onDecrement : null,
                  semanticLabel: decrementSemanticLabel ?? 'Decrease quantity',
                  align: Alignment.centerLeft,
                ),
              ),
              Expanded(
                child: _HalfHitTarget(
                  key: incrementKey,
                  enabled: canInc,
                  onTap: canInc ? onIncrement : null,
                  semanticLabel: incrementSemanticLabel ?? 'Increase quantity',
                  align: Alignment.centerRight,
                ),
              ),
            ],
          ),
        ),
        // --- Visual layer: chips + center (taps pass through to halves) ---
        // Chips sit inset from the frame; scaleDown only when the column is
        // narrower than preferred chip width (3-up on small phones).
        IgnorePointer(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: dims.trackPadH,
              vertical: dims.trackPadV,
            ),
            child: expand
                ? Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: _VisualChip(
                              icon: Icons.remove,
                              color: _decrementColor,
                              size: dims,
                              enabled: canDec,
                            ),
                          ),
                        ),
                      ),
                      _QuantityCenter(
                        quantity: quantity,
                        size: dims,
                        expand: false,
                        label: hasLabel ? label : null,
                        labelColor: labelColor ?? _defaultLabelColor,
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: _VisualChip(
                              icon: Icons.add,
                              color: _incrementColor,
                              size: dims,
                              enabled: canInc,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _VisualChip(
                        icon: Icons.remove,
                        color: _decrementColor,
                        size: dims,
                        enabled: canDec,
                      ),
                      _QuantityCenter(
                        quantity: quantity,
                        size: dims,
                        expand: false,
                        label: hasLabel ? label : null,
                        labelColor: labelColor ?? _defaultLabelColor,
                      ),
                      _VisualChip(
                        icon: Icons.add,
                        color: _incrementColor,
                        size: dims,
                        enabled: canInc,
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );

    return Container(
      height: dims.height,
      width: expand ? double.infinity : null,
      decoration: BoxDecoration(
        color: _trackColor,
        borderRadius: BorderRadius.circular(dims.trackRadius),
        border: Border.all(color: _trackBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: body,
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
        // Pre hit-target-tweak sizes: height 44, chip 36, slight frame inset.
        return const _QuantityStepperDims(
          height: 44,
          trackRadius: 4,
          trackPadH: 3,
          trackPadV: 3,
          buttonExtent: 36,
          iconSize: 20,
          buttonRadius: 3,
          qtyMinWidth: 48,
          qtyFontSize: 15,
          labelFontSize: 9,
          gap: 4,
        );
      case QuantityStepperSize.compact:
        return _QuantityStepperDims(
          height: hasLabel ? 36 : 28,
          trackRadius: 4,
          trackPadH: 2,
          trackPadV: 2,
          buttonExtent: hasLabel ? 28 : 22,
          iconSize: 16,
          buttonRadius: 3,
          qtyMinWidth: hasLabel ? 34 : 26,
          qtyFontSize: 12,
          labelFontSize: 9,
          gap: 3,
        );
      case QuantityStepperSize.dense:
        return _QuantityStepperDims(
          height: hasLabel ? 36 : 28,
          trackRadius: 4,
          trackPadH: 2,
          trackPadV: 2,
          buttonExtent: hasLabel ? 28 : 22,
          iconSize: 16,
          buttonRadius: 3,
          qtyMinWidth: hasLabel ? 32 : 24,
          qtyFontSize: 12,
          labelFontSize: 8,
          gap: 2,
        );
    }
  }
}

/// Full half of the control — transparent hit target (left or right).
class _HalfHitTarget extends StatelessWidget {
  const _HalfHitTarget({
    super.key,
    required this.enabled,
    required this.onTap,
    required this.semanticLabel,
    required this.align,
  });

  final bool enabled;
  final VoidCallback? onTap;
  final String semanticLabel;
  final Alignment align;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          // Ripple fills the half; visual chips are drawn above this layer.
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// Painted ± chip only (not hit-tested — parent half handles taps).
class _VisualChip extends StatelessWidget {
  const _VisualChip({
    required this.icon,
    required this.color,
    required this.size,
    required this.enabled,
  });

  final IconData icon;
  final Color color;
  final _QuantityStepperDims size;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final iconColor = enabled ? color : color.withValues(alpha: 0.28);
    final fill = enabled
        ? color.withValues(alpha: 0.12)
        : color.withValues(alpha: 0.05);
    final border = enabled
        ? color.withValues(alpha: 0.28)
        : color.withValues(alpha: 0.12);

    return Container(
      width: size.buttonExtent,
      height: size.buttonExtent,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(size.buttonRadius),
        border: Border.all(color: border),
      ),
      child: Icon(icon, size: size.iconSize, color: iconColor),
    );
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

    final child = Padding(
      padding: EdgeInsets.symmetric(horizontal: size.gap),
      child: content,
    );

    if (expand) {
      return Expanded(child: Center(child: child));
    }
    return Container(
      constraints: BoxConstraints(minWidth: size.qtyMinWidth),
      alignment: Alignment.center,
      child: child,
    );
  }
}
