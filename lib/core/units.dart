import 'constants.dart';

/// 把数量+单位归一化成可合并的基准（质量为克、容积为毫升）。
({double? qty, String? unit}) normalizeQty(double? qty, String? unit) {
  if (qty == null) return (qty: null, unit: unit);
  final u = unit?.trim();
  switch (u) {
    case '千克':
      return (qty: qty * 1000, unit: '克');
    case '升':
      return (qty: qty * 1000, unit: '毫升');
    default:
      return (qty: qty, unit: (u == null || u.isEmpty) ? null : u);
  }
}

/// 数量显示：整数不带小数点，小数最多两位并去掉尾零。
String formatQty(double? qty) {
  if (qty == null) return '';
  if ((qty - qty.roundToDouble()).abs() < 0.001) return qty.round().toString();
  var s = qty.toStringAsFixed(2);
  s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'[.]$'), '');
  return s;
}

/// 一条食材的展示文本，如「五花肉 500克」「盐 适量」。
String ingredientLabel(String name, double? qty, String? unit) {
  final u = unit?.trim() ?? '';
  if (kVagueUnits.contains(u)) return name + ' ' + u;
  if (qty == null) return u.isEmpty ? name : name + ' ' + u;
  return u.isEmpty
      ? name + ' ' + formatQty(qty)
      : name + ' ' + formatQty(qty) + u;
}

/// 采购单聚合：同一基准单位的数值相加，模糊量单独归并成一条。
class MergeBucket {
  MergeBucket(this.name, this.unit);
  final String name;
  final String? unit;
  double? qty;
}

List<MergeBucket> mergeIngredients(
    Iterable<({String name, double? qty, String? unit})> rows) {
  final Map<String, MergeBucket> acc = {};
  final List<MergeBucket> order = [];
  for (final r in rows) {
    final norm = normalizeQty(r.qty, r.unit);
    final name = r.name.trim();
    if (name.isEmpty) continue;
    final unit = norm.unit;
    final key = name + '|' + (unit ?? '');
    final bucket = acc[key];
    if (bucket == null) {
      final b = MergeBucket(name, unit)..qty = norm.qty;
      acc[key] = b;
      order.add(b);
    } else if (norm.qty != null) {
      bucket.qty = (bucket.qty ?? 0) + norm.qty!;
    }
  }
  return order;
}
