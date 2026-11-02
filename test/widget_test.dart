import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/core/units.dart';

void main() {
  group('采购清单合并', () {
    test('同名同单位相加，克与千克归一', () {
      final merged = mergeIngredients([
        (name: '五花肉', qty: 500.0, unit: '克'),
        (name: '五花肉', qty: 0.5, unit: '千克'),
        (name: '盐', qty: null, unit: '适量'),
        (name: '盐', qty: null, unit: '适量'),
      ]);
      expect(merged.length, 2);
      final pork = merged.firstWhere((m) => m.name == '五花肉');
      expect(pork.qty, 1000.0);
      expect(pork.unit, '克');
    });

    test('不同单位分别成条', () {
      final merged = mergeIngredients([
        (name: '鸡蛋', qty: 3.0, unit: '个'),
        (name: '鸡蛋', qty: 100.0, unit: '克'),
      ]);
      expect(merged.length, 2);
    });
  });

  group('数量格式化', () {
    test('整数不带小数点', () => expect(formatQty(200.0), '200'));
    test('小数去尾零', () => expect(formatQty(1.50), '1.5'));
    test('空值返回空串', () => expect(formatQty(null), ''));
  });
}
