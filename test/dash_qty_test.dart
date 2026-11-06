import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/core/ingredient_rules.dart';
import 'package:recipe_book/core/ocr.dart';
import 'package:recipe_book/core/screenshot_parser.dart';

/// 真机记录：1080x13454 的下厨房长截图，用量列认出了「—壶」（破折号）。
/// 这组用例直接拿那次识别结果当输入。
void main() {
  group('横线折回「一」', () {
    test('各种横线都算一', () {
      expect(normalizeCnDash('—壶'), '一壶');
      expect(normalizeCnDash('–壶'), '一壶');
      expect(normalizeCnDash('－壶'), '一壶');
      expect(normalizeCnDash('−壶'), '一壶');
    });

    test('ASCII 连字符不动', () {
      expect(normalizeCnDash('1-2个'), '1-2个');
      expect(normalizeCnDash('朴朴超市-30分钟'), '朴朴超市-30分钟');
    });

    test('正常文本不动', () {
      expect(normalizeCnDash('红烧排骨'), '红烧排骨');
    });

    test('名字尾巴上是横线也当 1', () {
      final r = splitTrailingQuantity('开水—', '壶', null);
      expect(r.name, '开水');
      expect(r.qty, 1);
    });
  });

  group('真机数据回放', () {
    late ScreenRecipe r;

    setUpAll(() {
      final f = File('test/fixtures/ocr_20261106_221241.json');
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

    test('配料表里开水是 1 壶', () {
      final water = r.ingredients.where((e) => e.name.contains('开水')).toList();
      expect(water.isNotEmpty, isTrue, reason: '要有开水这条');
      expect(water.first.name, '开水');
      expect(water.first.qty, 1);
      expect(water.first.unit, '壶');
      expect(water.first.group, '主料');
    });

    test('用量列没有横线残留', () {
      expect(r.ingredients.where((e) => e.name.contains('—')).isEmpty, isTrue);
    });

    test('分片接缝的碎块不进正文', () {
      // tile 5 在 y≈7983 上有「冰糖有-」「点颜色，」两个碎块，
      // tile 6 的完整行覆盖了同一位置，碎块要被吃掉。
      for (final s in r.steps) {
        expect(s.text.contains('冰糖有-'), isFalse,
            reason: '步骤里混进了分片碎块：' + s.text);
        expect(s.text.contains('点颜色，'), isFalse,
            reason: '步骤里混进了分片碎块：' + s.text);
      }
    });

    test('步骤按句末断开，不按屏幕宽度断', () {
      final s4 = r.steps[3].text;
      expect(s4.contains('锅里放底油'), isTrue);
      expect(s4.contains('碎碎念'), isTrue);
    });

    test('菜名和用料数量都认得出来', () {
      expect(r.name, '红烧排骨玉米');
      expect(r.ingredients.length, greaterThan(8));
    });
  });
}
