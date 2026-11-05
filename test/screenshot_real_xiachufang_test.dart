import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/core/ocr.dart';
import 'package:recipe_book/core/screenshot_parser.dart';

/// 一张真实的下厨房长截图（1080x13454）跑 PP-OCRv4 的结果。
/// 这张图踩过好几个坑，留作回归用：
///  - 「用料」标题行右边挂着「丢进菜篮子」按钮，被界面词过滤后整行消失，
///    导致用料区起点丢失、14 条用料全没
///  - 正文和用料之间夹了一张朴朴超市的广告卡片，说明被顶成商品名
///  - 截图时页面在滚动，炒糖色那一步有文字重影，读出来是乱码
OcrLayout loadFixture() {
  final raw = File('test/fixtures/xiachufang_hongshao_paigu.json')
      .readAsStringSync();
  final j = jsonDecode(raw) as Map<String, dynamic>;
  return OcrLayout(
    width: (j['width'] as num).toInt(),
    height: (j['height'] as num).toInt(),
    lines: (j['lines'] as List)
        .map((e) => OcrLine(
              text: e['text'] as String,
              top: (e['top'] as num).toDouble(),
              bottom: (e['bottom'] as num).toDouble(),
              left: (e['left'] as num).toDouble(),
              right: (e['right'] as num).toDouble(),
            ))
        .toList(),
  );
}

void main() {
  final r = parseScreenRecipe(loadFixture());

  test('菜名去掉后缀', () {
    expect(r.name, '红烧排骨玉米');
  });

  test('「用料」标题挂着界面按钮时，用料照样能解析', () {
    expect(r.ingredients.length, 11);
    final names = r.ingredients.map((e) => e.name).toList();
    expect(names, contains('排骨'));
    expect(names, contains('玉米'));
    expect(names, contains('耗油'));
  });

  test('中文数量拆成数值和单位', () {
    final bingtang = r.ingredients.firstWhere((e) => e.name == '冰糖');
    expect(bingtang.qty, 1);
    expect(bingtang.unit, '小把');

    final kaishui = r.ingredients.firstWhere((e) => e.name == '开水');
    expect(kaishui.qty, 1);
    expect(kaishui.unit, '壶');
  });

  test('用料不再一股脑全是主料', () {
    String g(String n) =>
        r.ingredients.firstWhere((e) => e.name == n).group;

    expect(g('排骨'), '主料');
    expect(g('玉米'), '主料');
    expect(g('八角'), '辅料');
    expect(g('姜片'), '辅料');
    expect(g('大葱'), '辅料');
    expect(g('生抽'), '调料');
    expect(g('老抽'), '调料');
    expect(g('耗油'), '调料');
    expect(g('冰糖'), '调料');
  });

  test('说明跳过夹在中间的广告卡片', () {
    expect(r.description, isNotNull);
    expect(r.description, contains('看到某点的排骨打折'));
    expect(r.description, contains('酱香味很足'));
    expect(r.description, isNot(contains('超市')));
    expect(r.description, isNot(contains('上装')));
    expect(r.description, isNot(contains('内衣')));
  });

  test('步骤里的文字重影被丢掉', () {
    expect(r.steps.length, 7);
    expect(r.steps[3].text, contains('锅里放底油'));
    expect(r.steps[3].text, isNot(contains('抑水糖')));
    expect(r.steps[3].text, isNot(contains('占额色')));
  });

  test('步骤里的折行接上，不按屏幕宽度断', () {
    // 「至肉发」和「白就差不多了。」在 OCR 里是两行，显示时要连起来
    expect(r.steps[0].text, contains('至肉发白就差不多了。'));
    expect(r.steps[3].text, contains('冰糖有一点颜色的时候'));
  });

  test('小贴士识别出来', () {
    expect(r.tips, contains('糖色'));
    expect(r.summary, contains('11 条用料'));
  });
}
