import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/core/ingredient_rules.dart';
import 'package:recipe_book/core/ocr.dart';
import 'package:recipe_book/core/screenshot_parser.dart';

/// 第二份真机留档（同一道菜重识）。这份暴露了两件事：
/// 1. 「料酒」没识别到用量，却因为规则库被补了「汤匙」，看着像有量
/// 2. 「4片」是姜片的量，不能因为靠得近就挂到料酒头上
void main() {
  late ScreenRecipe r;

  setUpAll(() {
    final f = File('test/fixtures/ocr_20261106_221818.json');
    final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final raw = (j['lines'] as List).cast<Map<String, dynamic>>();
    r = parseScreenRecipe(
      OcrLayout(
        lines: [
          for (final e in raw)
            OcrLine(
              text: e['text'] as String,
              left: (e['left'] as num).toDouble(),
              top: (e['top'] as num).toDouble(),
              right: (e['right'] as num).toDouble(),
              bottom: (e['bottom'] as num).toDouble(),
              score: (e['score'] as num?)?.toDouble(),
              tile: (e['tile'] as num?)?.toInt() ?? -1,
            ),
        ],
        width: 1080,
        height: 13454,
      ),
      rules: IngredientRuleSet.builtin,
    );
  });

  ScreenIngredient at(String name) =>
      r.ingredients.firstWhere((e) => e.name == name);

  test('料酒没识别到用量就不该补单位', () {
    final l = at('料酒');
    expect(l.qty, isNull);
    expect(l.unit, isNull, reason: '没数量却显示「汤匙」会让人以为有量');
  });

  test('姜片拿的是它自己的 4 片', () {
    final g = at('姜片');
    expect(g.qty, 4);
    expect(g.unit, '片');
  });

  test('其他用量都对', () {
    expect(at('排骨').qty, 800);
    expect(at('排骨').unit, '克');
    expect(at('玉米').qty, 1);
    expect(at('玉米').unit, '根');
    expect(at('八角').qty, 1);
    expect(at('八角').unit, '个');
    expect(at('生抽').qty, 2);
    expect(at('生抽').unit, '勺');
    expect(at('老抽').qty, 1);
    expect(at('老抽').unit, '勺');
    expect(at('开水').qty, 1);
    expect(at('开水').unit, '壶');
    expect(at('开水').group, '主料');
  });

  test('有数量的液体调料仍然补汤匙', () {
    // 反向确认：修的是「没数量也补」，不是把补单位整个关掉
    final s = r.ingredients.firstWhere((e) => e.name == '生抽');
    expect(s.unit, isNotNull);
  });

  test('小贴士提取到了，不是空的', () {
    expect(r.tips, isNotNull);
    expect(r.tips!.contains('糖色'), isTrue);
  });

  test('步骤数量和首句都对', () {
    expect(r.steps.length, 7);
    expect(r.steps.first.text.contains('排骨切段'), isTrue);
    expect(r.steps.last.text.contains('收汁儿'), isTrue);
  });
}
