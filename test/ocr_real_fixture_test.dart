import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/core/ocr.dart';
import 'package:recipe_book/core/screenshot_parser.dart';

/// 真机跑出来的 38 行（540x2600 的「酸菜炖大骨头」截图，PP-OCRv4 原始输出）。
OcrLine l(String text, double top, double left) =>
    OcrLine(text: text, top: top, bottom: top + 28, left: left, right: left + 200);

final _real = <OcrLine>[
  l('酸菜炖大骨头', 19, 205),
  l('酸菜炖大骨头', 546, 169),
  l('8.2综合评分·1人最近7天做过', 610, 148),
  l('徕芬高速吹风机，有效减', 671, 280),
  l('少静电，抚平毛躁，让头...', 696, 279),
  l('loifan', 699, 92),
  l('静电退散柔顺过冬', 717, 41),
  l('年末大酸优惠来袭', 735, 61),
  l('点山能城大额优惠立发', 764, 66),
  l('徕芬京东自营旗舰店', 783, 306),
  l('关注', 874, 441),
  l('张小样的厨房', 878, 125),
  l('冬天不吃炖酸菜、那谁能扛了想念啊、', 967, 28),
  l('用料', 1064, 24),
  l('去进采蓝子', 1070, 395),
  l('酸菜', 1156, 24),
  l('500克', 1157, 340),
  l('肘子骨头', 1228, 24),
  l('2斤', 1227, 338),
  l('五花肉', 1299, 25),
  l('任意多少', 1299, 340),
  l('葱', 1362, 25),
  l('一段', 1361, 340),
  l('姜', 1433, 24),
  l('2片', 1433, 338),
  l('蒜', 1504, 24),
  l('2瓣', 1506, 339),
  l('八角', 1577, 24),
  l('1个', 1579, 341),
  l('干辣椒', 1648, 24),
  l('1个（孩子吃我没', 1649, 341),
  l('放)', 1678, 338),
  l('料酒', 1750, 23),
  l('一勺(喝汤勺)', 1747, 340),
  l('生抽', 1821, 24),
  l('一勺(喝汤勺)', 1819, 340),
  l('黄豆酱', 1894, 25),
  l('一大勺(喝汤勺)', 1893, 342),
  l('蚝油', 1965, 24),
  l('一勺(喝汤勺)', 1963, 341),
  l('老抽', 2036, 24),
  l('半勺(喝汤勺)', 2037, 340),
  l('暴三十', 2106, 23),
  l('适量', 2108, 338),
  l('按口味调料', 2180, 341),
  l('步骤1', 2244, 23),
];

void main() {
  test('真机输出：菜名、说明、用料全部到位', () {
    final r = parseScreenRecipe(
      OcrLayout(width: 540, height: 2600, lines: _real),
    );
    // ignore: avoid_print
    print('NAME=' + (r.name ?? 'null'));
    // ignore: avoid_print
    print('DESC=' + (r.description ?? 'null'));
    for (final i in r.ingredients) {
      // ignore: avoid_print
      print('ING=' + i.display);
    }
    expect(r.name, '酸菜炖大骨头');
    expect(r.description, contains('冬天不吃炖酸菜'));
    expect(r.ingredients.length, greaterThanOrEqualTo(14));
    expect(r.ingredients.map((e) => e.name).join(','), contains('姜'));
    expect(r.ingredients.map((e) => e.name).join(','), contains('料酒'));
    expect(r.ingredients.map((e) => e.name).join(','), contains('生抽'));
  });
}
