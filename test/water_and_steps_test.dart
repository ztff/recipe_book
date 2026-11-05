import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/core/ingredient_rules.dart';
import 'package:recipe_book/data/db.dart';

void main() {
  group('水归主料', () {
    test('猜分组时水算主料', () {
      expect(guessIngredientGroup('开水'), '主料');
      expect(guessIngredientGroup('清水'), '主料');
      expect(guessIngredientGroup('水'), '主料');
    });

    test('水仍然不补量具', () {
      expect(guessIngredientUnit('开水', 1, null), isNull);
    });

    test('新建的库里面水就是主料', () {
      final db = AppDb.memory();
      final r = db.ingredientRules().firstWhere((e) => e.name == '开水');
      expect(r.grp, '主料');
      expect(r.unit, '');
    });
  });

  group('老库升级', () {
    test('库里还留着「调料」的内置行会被改成主料', () {
      final db = AppDb.memory();
      // 模拟旧版本留下的状态
      db.saveIngredientRule(name: '开水', grp: '调料', unit: '');
      db.setSetting('ingredient_rule_version', '0');

      db.syncBuiltinIngredientRules();

      final r = db.ingredientRules().firstWhere((e) => e.name == '开水');
      expect(r.grp, '主料');
    });

    test('用户手动改成别的分组的不会被改回来', () {
      final db = AppDb.memory();
      db.saveIngredientRule(name: '开水', grp: '辅料', unit: '');
      db.setSetting('ingredient_rule_version', '0');

      db.syncBuiltinIngredientRules();

      final r = db.ingredientRules().firstWhere((e) => e.name == '开水');
      expect(r.grp, '辅料');
    });

    test('迁移只跑一次', () {
      final db = AppDb.memory();
      db.syncBuiltinIngredientRules();
      expect(db.getSetting('ingredient_rule_version'), '2');
    });
  });

  group('步骤文字整理', () {
    test('屏幕折行会被接回去', () {
      final db = AppDb.memory();
      final id = db.saveRecipe(
        RecipeDraft(
          name: '测试菜',
          ingredients: [DraftIngredient(name: '排骨')],
          steps: [
            DraftStep(text: '锅里放底油，把冰糖放进去大火炒化，冰糖有一点\n'
                '颜色\n'
                '的时候，就放入葱姜八角翻炒片刻。'),
          ],
        ),
        'ceshi',
      );
      final n = db.normalizeStepText();
      expect(n, 1);
      final step = db.detail(id)!.steps.first;
      expect(step.text, '锅里放底油，把冰糖放进去大火炒化，冰糖有一点颜色的时候，就放入葱姜八角翻炒片刻。');
      expect(step.text.contains('\n'), isFalse);
    });

    test('本来就分好的段落不动', () {
      final db = AppDb.memory();
      final id = db.saveRecipe(
        RecipeDraft(
          name: '测试菜',
          ingredients: [DraftIngredient(name: '排骨')],
          steps: [
            DraftStep(text: '准备配料。\n碎碎念：八角一放，猪肉必香。'),
          ],
        ),
        'ceshi2',
      );
      expect(db.normalizeStepText(), 0);
      expect(db.detail(id)!.steps.first.text.split('\n').length, 2);
    });
  });
}
