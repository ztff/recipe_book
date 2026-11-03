import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/core/ocr.dart';
import 'package:recipe_book/core/screenshot_parser.dart';

OcrLine line(String text, double top, {double left = 40, double right = 700}) =>
    OcrLine(text: text, top: top, bottom: top + 34, left: left, right: right);

void main() {

  test('状态栏时钟和电量不会被当成菜名', () {
    final layout = OcrLayout(
      width: 540,
      height: 2600,
      lines: [
        line('5:07', 20),
        line('87%', 20, left: 470),
        line('酸菜炖大骨头', 180),
        line('冬天不吃炖酸菜，那谁能扛了想念啊', 260),
        line('用料', 420),
        line('酸菜 500克', 500),
        line('肘子骨头 2斤', 580),
        line('步骤 1', 760),
        line('骨头冷水下锅焯水，捞出洗净。', 900),
      ],
    );
    final r = parseScreenRecipe(layout);

    expect(r.name, '酸菜炖大骨头');
    expect(r.name, isNot(contains(':')));
    expect(r.description ?? '', isNot(contains('5:07')));
    expect(r.ingredients.length, greaterThanOrEqualTo(2));
  });
  test('小红书式截图：菜名、用料、步骤、小贴士', () {
    final layout = OcrLayout(
      width: 848,
      height: 4944,
      lines: [
        line('脆嫩好吃的清炒红薯叶，拿肉都不换！', 40),
        line('巴综合评分', 200),
        line('蕉下摇粒绒打底衫，轻盈', 260),
        line('焦下京东自营旗舰店', 300),
        line('今天给大家分享一道很简单的家常菜——清炒红薯叶，', 420),
        line('口感脆嫩、健康低脂！小时候在农村还拿着红薯叶', 500),
        line('用料', 620),
        line('红薯叶', 700),
        line('1把', 700, left: 600),
        line('肥猪肉', 780),
        line('50克', 780, left: 600),
        line('蒜头', 860),
        line('2~3片', 860, left: 600),
        line('步骤 1', 1000),
        line('红薯叶择好，多清洗几次，可以的话用淘米水浸泡20分钟~', 1600),
        line('步骤 2', 2000),
        line('一道健康又美味的红薯叶就做好！', 2600),
        line('小贴士', 3000),
        line('1.红薯叶不一定要用淘米水来浸泡', 3060),
      ],
    );
    final r = parseScreenRecipe(layout);

    expect(r.name, '清炒红薯叶');
    expect(r.ingredients.length, 3);
    expect(r.ingredients[0].name, '红薯叶');
    expect(r.ingredients[0].qty, 1);
    expect(r.ingredients[0].unit, '把');
    expect(r.ingredients[1].qty, 50);
    expect(r.ingredients[1].unit, '克');
    expect(r.ingredients[2].qty, 2);
    expect(r.ingredients[2].unit, '片');
    expect(r.steps.length, 2);
    expect(r.steps[0].text, contains('淘米水'));
    expect(r.tips, contains('淘米水'));
    expect(r.droppedLines, greaterThan(0));
  });

  test('说明里混进广告乱码时被丢掉', () {
    final layout = OcrLayout(
      width: 848,
      height: 3000,
      lines: [
        line('脆嫩好吃的清炒红薯叶', 40),
        line('不换!', 120),
        line('R2独合证公', 160),
        line('今天给大家分享一道很简单的家常菜，口感脆嫩健康低脂', 240),
        line('用料', 400),
        line('红薯叶', 460),
      ],
    );
    final r = parseScreenRecipe(layout);
    expect(r.description, contains('家常菜'));
    expect(r.description, isNot(contains('不换')));
    expect(r.description, isNot(contains('R2')));
  });

  test('步骤之间检测出配图区域', () {
    final layout = OcrLayout(
      width: 848,
      height: 4000,
      lines: [
        line('清炒红薯叶', 40),
        line('步骤 1', 1000),
        line('择好洗净', 2600),
        line('步骤 2', 3000),
        line('出锅装盘', 3800),
      ],
    );
    final r = parseScreenRecipe(layout);
    expect(r.steps.length, 2);
    expect(r.steps[0].imageRect, isNotNull);
    expect(r.steps[0].imageRect!.top, greaterThan(1000));
    expect(r.steps[0].imageRect!.bottom, lessThanOrEqualTo(2600));
  });

  test('没有结构的图不硬凑', () {
    final layout = OcrLayout(
      width: 848,
      height: 800,
      lines: [line('随便一句话', 40)],
    );
    final r = parseScreenRecipe(layout);
    expect(r.ingredients, isEmpty);
    expect(r.steps, isEmpty);
  });
}
