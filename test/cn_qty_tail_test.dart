import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/core/ingredient_rules.dart';
import 'package:recipe_book/core/ocr.dart';
import 'package:recipe_book/core/screenshot_parser.dart';

OcrLine l(String text, double top, {double left = 40, double right = 700}) =>
    OcrLine(text: text, top: top, bottom: top + 40, left: left, right: right);

ScreenRecipe run(List<OcrLine> lines) =>
    parseScreenRecipe(OcrLayout(width: 1080, height: 3000, lines: lines));

ScreenIngredient byName(ScreenRecipe r, String name) =>
    r.ingredients.firstWhere((e) => e.name == name);

void main() {
  group('名字尾巴上的中文数字要还原', () {
    test('拆函数本身', () {
      final a = splitTrailingQuantity('开水一', '壶', null);
      expect(a.name, '开水');
      expect(a.qty, 1);

      final b = splitTrailingQuantity('老抽半', '勺', null);
      expect(b.name, '老抽');
      expect(b.qty, 0.5);
    });

    test('没单位不拆', () {
      final r = splitTrailingQuantity('一', null, null);
      expect(r.name, '一');
      expect(r.qty, isNull);
    });

    test('已经有数量不拆', () {
      final r = splitTrailingQuantity('开水一', '壶', 3);
      expect(r.name, '开水一');
      expect(r.qty, 3);
    });

    test('正常名字不动', () {
      expect(splitTrailingQuantity('三文鱼', '克', null).name, '三文鱼');
      expect(splitTrailingQuantity('五花肉', '克', null).name, '五花肉');
      expect(splitTrailingQuantity('十三香', '克', null).name, '十三香');
    });

    test('单个字的名字不拆', () {
      final r = splitTrailingQuantity('盐', '茶匙', null);
      expect(r.name, '盐');
    });
  });

  group('整条链路', () {
    test('「开水一」和「壶」分两行', () {
      final r = run([
        l('红烧排骨', 40),
        l('用料', 200),
        l('开水一', 300),
        l('壶', 380),
      ]);
      expect(r.ingredients.length, 1);
      final i = byName(r, '开水');
      expect(i.qty, 1);
      expect(i.unit, '壶');
    });

    test('「开水」和「一壶」分两行', () {
      final r = run([
        l('红烧排骨', 40),
        l('用料', 200),
        l('开水', 300),
        l('一壶', 380),
      ]);
      expect(byName(r, '开水').qty, 1);
      expect(byName(r, '开水').unit, '壶');
    });

    test('「老抽半」和「勺」分两行', () {
      final r = run([
        l('红烧排骨', 40),
        l('用料', 200),
        l('老抽半', 300),
        l('勺', 380),
      ]);
      expect(byName(r, '老抽').qty, 0.5);
      expect(byName(r, '老抽').unit, '勺');
    });
  });
}
