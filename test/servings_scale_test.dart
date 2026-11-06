import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/core/servings_scale.dart';

void main() {
  test('翻倍时数量翻倍', () {
    expect(scaleQty(500, 2, 4), 1000);
    expect(scaleQty(2, 2, 4), 4);
  });

  test('减半时数量减半', () {
    expect(scaleQty(500, 4, 2), 250);
    expect(scaleQty(3, 3, 1), 1);
  });

  test('份量不变时原样返回', () {
    expect(scaleQty(500, 2, 2), 500);
  });

  test('没有数量的不动', () {
    expect(scaleQty(null, 2, 4), isNull);
  });

  test('份量非法时返回原值', () {
    expect(scaleQty(500, 0, 4), 500);
    expect(scaleQty(500, 2, 0), 500);
    expect(scaleQty(500, -1, 4), 500);
  });

  test('适量少许原样不动', () {
    expect(scaledQtyText(null, '适量', 2, 4), '适量');
    expect(scaledQtyText(5, '少许', 2, 4), '少许');
  });

  test('有数量的按比例并格式化', () {
    expect(scaledQtyText(500, '克', 2, 4), '1000 克');
    expect(scaledQtyText(2, '勺', 4, 2), '1 勺');
  });

  test('小数份量算出干净的数字', () {
    // 3 克按 2→3 人份是 4.5 克
    expect(scaledQtyText(3, '克', 2, 3), '4.5 克');
    // 1 个鸡蛋按 3→2 是 0.67，舍到两位
    expect(scaledQtyText(1, '个', 3, 2), '0.67 个');
  });

  test('没有单位只有数量', () {
    expect(scaledQtyText(2, null, 2, 4), '4');
  });

  test('没有数量只有单位', () {
    expect(scaledQtyText(null, '把', 2, 4), '把');
  });

  test('数量和单位都没有', () {
    expect(scaledQtyText(null, null, 2, 4), '');
  });

  test('单位带空格时不会多出空格', () {
    expect(scaledQtyText(500, ' 克 ', 2, 4), '1000 克');
  });
}
