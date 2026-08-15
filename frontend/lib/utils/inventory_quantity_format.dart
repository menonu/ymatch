/// Format a Detailed-view inventory quantity (#427).
///
/// Outer number is the DB quantity. Parentheses are the post in-progress-trade
/// projected quantity. Omit parentheses when [projected] is null or equal.
String formatInventoryQuantity(int quantity, int? projected) {
  if (projected == null || projected == quantity) {
    return '$quantity';
  }
  return '$quantity($projected)';
}
