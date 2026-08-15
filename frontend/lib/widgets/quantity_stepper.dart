import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Flat bordered quantity control for detailed inventory steppers (#538).
///
/// Visual:
/// - White track + card border, 1px inset, radius 4
/// - ± chips size 36 / icon 20 / radius 3 (expand: chip fills its flex slot)
/// - Center: optional status label above bare quantity (no qty box)
///
/// Hit targets (independent of chip paint):
/// - Left half → decrement (includes area under 所持/数字)
/// - Right half → increment
///
/// Set [expand] to `true` in constrained [Expanded] parents (detailed view).
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.quantity,
    this.onDecrement,
    this.onIncrement,
    this.expand = false,
    this.decrementKey,
    this.incrementKey,
    this.enabled = true,
    this.label,
    this.labelColor,
    this.quantityText,
    this.decrementSemanticLabel,
    this.incrementSemanticLabel,
  });

  final int quantity;

  /// When null, the decrement control is disabled (e.g. at min qty).
  final VoidCallback? onDecrement;

  /// When null, the increment control is disabled (e.g. at max qty).
  final VoidCallback? onIncrement;

  /// When true, fill the parent width (side chips fill flex slots).
  final bool expand;

  /// Optional keys for widget tests (e.g. `stepper_inc_HAVE`).
  final Key? decrementKey;
  final Key? incrementKey;

  /// Master enable; when false both sides are inert (deleted items).
  final bool enabled;

  /// Optional status label shown above the number (e.g. 所持 / 求 / 譲).
  final String? label;

  /// Color for [label]; defaults to [AppTheme.textSecondaryColor].
  final Color? labelColor;

  /// Optional center text (e.g. `2(1)`). Defaults to [quantity] as a string.
  final String? quantityText;

  /// Accessibility label for the decrement control.
  final String? decrementSemanticLabel;

  /// Accessibility label for the increment control.
  final String? incrementSemanticLabel;

  static const Color _decrementColor = Color(0xFFE25555);
  static const Color _incrementColor = Color(0xFF2EAF6A);

  // Layout metrics (detailed view / pre-#538 type scale).
  static const double _height = 44;
  static const double _trackRadius = 4;
  static const double _trackPad = 1;
  static const double _buttonExtent = 36;
  static const double _iconSize = 20;
  static const double _buttonRadius = 3;
  static const double _qtyMinWidth = 48;
  static const double _qtyFontSize = 15;
  static const double _labelFontSize = 9;
  static const double _gap = 2;

  @override
  Widget build(BuildContext context) {
    final hasLabel = label != null && label!.isNotEmpty;
    final canDec = enabled && onDecrement != null;
    final canInc = enabled && onIncrement != null;

    final decVisual = _StepChip(
      icon: Icons.remove,
      color: _decrementColor,
      expand: expand,
      enabled: canDec,
    );
    final qty = _QuantityCenter(
      quantity: quantity,
      expand: expand,
      label: hasLabel ? label : null,
      labelColor: labelColor ?? AppTheme.textSecondaryColor,
      quantityText: quantityText,
    );
    final incVisual = _StepChip(
      icon: Icons.add,
      color: _incrementColor,
      expand: expand,
      enabled: canInc,
    );

    final visualRow = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: expand
          ? [
              Expanded(flex: 2, child: decVisual),
              Flexible(flex: 3, child: qty),
              Expanded(flex: 2, child: incVisual),
            ]
          : [decVisual, qty, incVisual],
    );

    return Container(
      height: _height,
      width: expand ? double.infinity : null,
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(_trackRadius),
        border: Border.all(color: const Color(0xFFDEE2E6)),
      ),
      padding: const EdgeInsets.all(_trackPad),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: _HalfHitTarget(
                    key: decrementKey,
                    enabled: canDec,
                    onTap: canDec ? onDecrement : null,
                    semanticLabel:
                        decrementSemanticLabel ?? 'Decrease quantity',
                  ),
                ),
                Expanded(
                  child: _HalfHitTarget(
                    key: incrementKey,
                    enabled: canInc,
                    onTap: canInc ? onIncrement : null,
                    semanticLabel:
                        incrementSemanticLabel ?? 'Increase quantity',
                  ),
                ),
              ],
            ),
          ),
          IgnorePointer(child: visualRow),
        ],
      ),
    );
  }
}

/// Transparent left/right half hit target.
class _HalfHitTarget extends StatelessWidget {
  const _HalfHitTarget({
    super.key,
    required this.enabled,
    required this.onTap,
    required this.semanticLabel,
  });

  final bool enabled;
  final VoidCallback? onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, child: const SizedBox.expand()),
      ),
    );
  }
}

/// Painted ± chip only (not hit-tested — half layer handles taps).
class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.icon,
    required this.color,
    required this.expand,
    required this.enabled,
  });

  final IconData icon;
  final Color color;
  final bool expand;
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

    final chip = Container(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(QuantityStepper._buttonRadius),
        border: Border.all(color: border),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: QuantityStepper._iconSize, color: iconColor),
    );

    if (expand) {
      final chipH = QuantityStepper._height - QuantityStepper._trackPad * 2;
      return SizedBox(height: chipH, width: double.infinity, child: chip);
    }
    return SizedBox(
      width: QuantityStepper._buttonExtent,
      height: QuantityStepper._buttonExtent,
      child: chip,
    );
  }
}

/// Bare center: optional label above quantity — no border / box.
class _QuantityCenter extends StatelessWidget {
  const _QuantityCenter({
    required this.quantity,
    required this.expand,
    this.label,
    this.labelColor,
    this.quantityText,
  });

  final int quantity;
  final bool expand;
  final String? label;
  final Color? labelColor;
  final String? quantityText;

  @override
  Widget build(BuildContext context) {
    final hasLabel = label != null && label!.isNotEmpty;
    final qtyLabel = quantityText ?? '$quantity';
    final qtyStyle = const TextStyle(
      fontSize: QuantityStepper._qtyFontSize,
      fontWeight: FontWeight.bold,
      height: 1.1,
      color: AppTheme.textPrimaryColor,
    );
    // Scale down `2(-1)` / `12(8)` rather than overflowing the 44px track.
    final qtyText = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(qtyLabel, textAlign: TextAlign.center, style: qtyStyle),
    );
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
                  fontSize: QuantityStepper._labelFontSize,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                  color: labelColor,
                ),
              ),
              const SizedBox(height: 1),
              qtyText,
            ],
          )
        : qtyText;

    return Container(
      width: expand ? double.infinity : null,
      constraints: expand
          ? const BoxConstraints()
          : const BoxConstraints(minWidth: QuantityStepper._qtyMinWidth),
      margin: const EdgeInsets.symmetric(horizontal: QuantityStepper._gap),
      alignment: Alignment.center,
      child: content,
    );
  }
}
