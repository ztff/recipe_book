import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/core/ocr.dart';
import 'package:recipe_book/core/screenshot_parser.dart';

OcrLine l(String text, double top, {double left = 40, double right = 700}) =>
    OcrLine(text: text, top: top, bottom: top + 40, left: left, right: right);

ScreenRecipe run(List<OcrLine> lines, {int height = 3000}) =>
    parseScreenRecipe(OcrLayout(width: 1080, height: height, lines: lines));

ScreenIngredient byName(ScreenRecipe r, String name) =>
    r.ingredients.firstWhere((e) => e.name == name);

void main() {
  group('名称和数量被拆成两行时能拼回去', () {
    test('中文数量单独成行：一壶', () {
      final r = run([
        l('红烧排骨', 40),
        l('用料', 200),
        l('开水', 300),
        l('一壶', 380),
      ]);
      expect(r.ingredients.length, 1);
      expect(byName(r, '开水').qty, 1);
      expect(byName(r, '开水').unit, '壶');
    });

    test('中文数量带大小：一大把', () {
      final r = run([
        l('红烧排骨', 40),
        l('用料', 200),
        l('冰糖', 300),
        l('一大把', 380),
      ]);
      expect(byName(r, '冰糖').qty, 1);
      expect(byName(r, '冰糖').unit, '大把');
    });

    test('单位没认出来只剩数字，也要挂回去', () {
      final r = run([
        l('红烧排骨', 40),
        l('用料', 200),
        l('料酒', 300),
        l('4', 380),
        l('生抽', 460),
        l('2', 540),
      ]);
      expect(r.ingredients.length, 2);
      expect(byName(r, '料酒').qty, 4);
      expect(byName(r, '生抽').qty, 2);
      // 单位丢了就按常识补
      expect(byName(r, '料酒').unit, '汤匙');
      expect(byName(r, '生抽').unit, '汤匙');
    });

    test('只剩一个单位字也能挂回去', () {
      final r = run([
        l('红烧排骨', 40),
        l('用料', 200),
        l('开水', 300),
        l('壶', 380),
      ]);
      expect(r.ingredients.length, 1);
      expect(byName(r, '开水').unit, '壶');
    });

    test('已经完整的行不会被后面的数字抢走', () {
      final r = run([
        l('红烧排骨', 40),
        l('用料', 200),
        l('料酒', 300),
        l('4勺', 340),
        l('生抽', 420),
        l('2', 500),
      ]);
      expect(byName(r, '料酒').qty, 4);
      expect(byName(r, '料酒').unit, '勺');
      expect(byName(r, '生抽').qty, 2);
    });
  });

  group('步骤按句子换行', () {
    test('折行接上，句号处才换行', () {
      final r = run([
        l('红烧排骨', 40),
        l('用料', 200),
        l('排骨', 260),
        l('步骤 1', 600),
        l('排骨切段，泡冷水2个小时以上，多次换血水，至肉发', 700),
        l('白就差不多了。', 760),
        l('大厨反复强调，排骨不腥的关键就在于去血水', 820),
        l('，水里也可以加少许花雕酒。', 880),
      ]);
      final t = r.steps.first.text;
      expect(t, contains('至肉发白就差不多了。'));
      expect(t, contains('去血水，水里也可以加少许花雕酒。'));
      // 两句之间才断行
      expect(t.split('\n').length, 2);
    });

    test('没写完的行不硬断', () {
      final r = run([
        l('红烧排骨', 40),
        l('用料', 200),
        l('排骨', 260),
        l('步骤 1', 600),
        l('锅里放底油，把冰糖放进去大火炒化，冰糖有一点', 700),
        l('颜色', 760),
        l('的时候，就放入葱姜八角翻炒片刻。', 820),
      ]);
      final t = r.steps.first.text;
      expect(t, contains('冰糖有一点颜色的时候'));
      expect(t.split('\n').length, 1);
    });
  });

  group('状态栏过滤只看最顶上', () {
    test('顶部的时间电量被丢掉', () {
      final r = run([
        l('5:07', 10),
        l('87%', 60),
        l('红烧排骨', 200),
        l('用料', 400),
        l('排骨', 460),
      ]);
      expect(r.name, '红烧排骨');
    });

    test('用料区里的纯数字不当状态栏', () {
      final r = run([
        l('红烧排骨', 200),
        l('用料', 400),
        l('排骨', 460),
        l('800', 520),
      ]);
      expect(r.ingredients.length, 1);
      expect(byName(r, '排骨').qty, 800);
    });
  });
}
