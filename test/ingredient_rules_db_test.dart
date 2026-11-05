import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/core/ingredient_rules.dart';
import 'package:recipe_book/data/db.dart';

void main() {
  test('首次打开就把内置规则灌进数据库', () {
    final db = AppDb.memory();
    final rows = db.ingredientRules();
    expect(rows.length, greaterThan(100));
    final shengchou = rows.firstWhere((e) => e.name == '生抽');
    expect(shengchou.grp, '调料');
    expect(shengchou.unit, '汤匙');
    expect(shengchou.builtin, isTrue);
    expect(shengchou.enabled, isTrue);

    final jiang = rows.firstWhere((e) => e.name == '姜');
    expect(jiang.grp, '辅料');
    expect(jiang.unit, '');
  });

  test('重复迁移不会灌两遍', () {
    final db = AppDb.memory();
    final first = db.ingredientRules().length;
    db.syncBuiltinIngredientRules();
    db.syncBuiltinIngredientRules();
    expect(db.ingredientRules().length, first);
  });

  test('改过的规则不会被下次迁移覆盖', () {
    final db = AppDb.memory();
    db.saveIngredientRule(name: '生抽', grp: '主料', unit: '勺');
    db.syncBuiltinIngredientRules();
    final r = db.ingredientRules().firstWhere((e) => e.name == '生抽');
    expect(r.grp, '主料');
    expect(r.unit, '勺');
    expect(db.ingredientRules().where((e) => e.name == '生抽').length, 1);
  });

  test('新增的规则标记成自定义', () {
    final db = AppDb.memory();
    db.saveIngredientRule(name: '秘制酱', grp: '调料', unit: '茶匙');
    final r = db.ingredientRules().firstWhere((e) => e.name == '秘制酱');
    expect(r.builtin, isFalse);
  });

  test('停用的规则不进识别规则集', () {
    final db = AppDb.memory();
    final row = db.ingredientRules().firstWhere((e) => e.name == '生抽');
    db.setIngredientRuleEnabled(row.id, false);
    final set = db.ingredientRuleSet();
    expect(set.lookup('生抽'), isNull);
    // 别的还在
    expect(set.lookup('老抽'), isNotNull);
  });

  test('恢复内置会把自定义的清掉', () {
    final db = AppDb.memory();
    db.saveIngredientRule(name: '秘制酱', grp: '调料', unit: '茶匙');
    expect(db.ingredientRules().any((e) => e.name == '秘制酱'), isTrue);
    db.resetIngredientRules();
    expect(db.ingredientRules().any((e) => e.name == '秘制酱'), isFalse);
    expect(db.ingredientRules().any((e) => e.name == '生抽'), isTrue);
  });

  test('规则集匹配：长词优先', () {
    final set = ruleSetFromDb();
    // 「花椒油」是调料汤匙，「花椒」是辅料不补单位
    expect(set.lookup('花椒油')!.grp, '调料');
    expect(set.lookup('花椒油')!.unit, '汤匙');
    expect(set.lookup('花椒')!.grp, '辅料');
  });

  test('重新套用规则会改已有用料', () {
    final db = AppDb.memory();
    final id = db.saveRecipe(
      RecipeDraft(
        name: '测试菜',
        ingredients: [
          DraftIngredient(name: '生抽', qty: 2),
          DraftIngredient(name: '姜片', qty: 3),
        ],
        steps: [DraftStep(text: '炒')],
      ),
      'ceshi',
    );
    final before = db.detail(id)!;
    expect(before.ingredients.every((e) => e.grp == '主料'), isTrue);

    final n = db.reapplyIngredientRules();
    expect(n, 2);

    final after = db.detail(id)!;
    final byName = {for (final i in after.ingredients) i.name: i};
    expect(byName['生抽']!.grp, '调料');
    expect(byName['生抽']!.unit, '汤匙');
    expect(byName['姜片']!.grp, '辅料');
  });

  test('没命中规则的用料保持原样', () {
    final db = AppDb.memory();
    final id = db.saveRecipe(
      RecipeDraft(
        name: '测试菜',
        ingredients: [
          DraftIngredient(name: '我不认识的食材', grp: '辅料', qty: 1, unit: '个'),
        ],
        steps: [DraftStep(text: '炒')],
      ),
      'ceshi2',
    );
    db.reapplyIngredientRules();
    final i = db.detail(id)!.ingredients.first;
    expect(i.grp, '辅料');
    expect(i.unit, '个');
  });
}

IngredientRuleSet ruleSetFromDb() {
  final db = AppDb.memory();
  return db.ingredientRuleSet();
}
