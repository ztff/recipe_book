import 'constants.dart';
import 'units.dart';

/// 按份量缩放后的用料数量。
///
/// 规则：
/// - 有数字的按 target / base 等比换算
/// - 「适量」「少许」这类模糊量原样不动，加个数字反而误导
/// - 没有数量的（只有单位或什么都没有）也原样不动
/// - [base] 或 [target] 非法时返回原值，绝不返回错误倍数
double? scaleQty(double? qty, int base, int target) {
  if (qty == null) return null;
  if (base <= 0 || target <= 0) return qty;
  if (base == target) return qty;
  return qty * target / base;
}

/// 只要数量那一段的展示文本，如「500 克」「适量」。
///
/// 用料列表里名字单独占一列，右边只放数量，所以只提供拆开的版本。
/// 拼成整行的 [ingredientLabel] 在 units.dart 里，不带缩放。
String scaledQtyText(double? qty, String? unit, int base, int target) {
  final u = unit?.trim() ?? '';
  if (kVagueUnits.contains(u)) return u;
  final q = scaleQty(qty, base, target);
  if (q == null) return u;
  return u.isEmpty ? formatQty(q) : formatQty(q) + ' ' + u;
}

/// 份量的合法范围。0 人份或负数没有意义。
const int kMinServings = 1;
const int kMaxServings = 20;
