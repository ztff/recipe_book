import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/core/ocr.dart';
import 'package:recipe_book/core/screenshot_parser.dart';

OcrLine l(String text, double top, {double left = 40, double right = 700}) =>
    OcrLine(text: text, top: top, bottom: top + 40, left: left, right: right);

ScreenRecipe run(List<OcrLine> lines) =>
    parseScreenRecipe(OcrLayout(width: 1080, height: 3000, lines: lines));

ScreenIngredient byName(ScreenRecipe r, String name) =>
    r.ingredients.firstWhere((e) => e.name == name);

void main() {
  group('数量和单位被拆到两行', () {
    test('4 和 勺 各自成行', () {
      final r = run([
        l('红烧排骨', 40), l('用料', 200),
        l('料酒', 300), l('4', 380), l('勺', 460),
      ]);
      expect(r.ingredients.length, 1);
      expect(byName(r, '料酒').qty, 4);
      expect(byName(r, '料酒').unit, '勺');
    });

    test('一 和 壶 各自成行', () {
      final r = run([
        l('红烧排骨', 40), l('用料', 200),
        l('开水', 300), l('一', 380), l('壶', 460),
      ]);
      expect(r.ingredients.length, 1);
      expect(byName(r, '开水').qty, 1);
      expect(byName(r, '开水').unit, '壶');
    });

    test('单位先来、数量后到也能补上', () {
      final r = run([
        l('红烧排骨', 40), l('用料', 200),
        l('开水', 300), l('壶', 380), l('一', 460),
      ]);
      expect(byName(r, '开水').qty, 1);
      expect(byName(r, '开水').unit, '壶');
    });

    test('半 也能认成 0.5', () {
      final r = run([
        l('红烧排骨', 40), l('用料', 200),
        l('老抽', 300), l('半', 380), l('勺', 460),
      ]);
      expect(byName(r, '老抽').qty, 0.5);
      expect(byName(r, '老抽').unit, '勺');
    });

    test('单位不会盖掉本来有的单位', () {
      final r = run([
        l('红烧排骨', 40), l('用料', 200),
        l('排骨', 300), l('800克', 380),
        l('料酒', 460), l('4', 540), l('勺', 620),
      ]);
      expect(byName(r, '排骨').qty, 800);
      expect(byName(r, '排骨').unit, '克');
      expect(byName(r, '料酒').qty, 4);
      expect(byName(r, '料酒').unit, '勺');
    });

    test('完整写在一行的不受影响', () {
      final r = run([
        l('红烧排骨', 40), l('用料', 200),
        l('料酒', 300), l('4勺', 340),
        l('开水', 420), l('一壶', 460),
      ]);
      expect(byName(r, '料酒').qty, 4);
      expect(byName(r, '料酒').unit, '勺');
      expect(byName(r, '开水').qty, 1);
      expect(byName(r, '开水').unit, '壶');
    });
  });
}
