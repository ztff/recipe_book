import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/data/db.dart';

RecipeDraft _draft({String? tips}) => RecipeDraft(
      name: '红烧排骨玉米',
      description: '正文',
      tips: tips,
      ingredients: [
        DraftIngredient(name: '排骨', qty: 800, unit: '克'),
        DraftIngredient(name: '八角', grp: '辅料', qty: 1, unit: '个'),
        DraftIngredient(name: '生抽', grp: '调料', qty: 2, unit: '汤匙'),
      ],
      steps: [DraftStep(text: '排骨焯水')],
    );

void main() {
  test('小贴士能存进去再读出来', () {
    final db = AppDb.memory();
    final id = db.saveRecipe(
      _draft(tips: '冰糖不用炒成糖色，稍微有点颜色就行'),
      'hongshaopaigu',
    );
    final d = db.detail(id)!;
    expect(d.recipe.tips, '冰糖不用炒成糖色，稍微有点颜色就行');
  });

  test('没写小贴士存成 null，不是空串', () {
    final db = AppDb.memory();
    final id = db.saveRecipe(_draft(), 'hongshaopaigu');
    expect(db.detail(id)!.recipe.tips, isNull);
  });

  test('改菜谱时小贴士能改掉也能清空', () {
    final db = AppDb.memory();
    final id = db.saveRecipe(_draft(tips: '先写一条'), 'hongshaopaigu');

    final first = db.detail(id)!;
    db.saveRecipe(
      RecipeDraft(
        id: id,
        name: first.recipe.name,
        tips: '改过了',
        ingredients: [DraftIngredient(name: '排骨')],
        steps: [DraftStep(text: '焯水')],
      ),
      'hongshaopaigu',
    );
    expect(db.detail(id)!.recipe.tips, '改过了');

    db.saveRecipe(
      RecipeDraft(
        id: id,
        name: first.recipe.name,
        tips: null,
        ingredients: [DraftIngredient(name: '排骨')],
        steps: [DraftStep(text: '焯水')],
      ),
      'hongshaopaigu',
    );
    expect(db.detail(id)!.recipe.tips, isNull);
  });

  test('用料分组跟着存', () {
    final db = AppDb.memory();
    final id = db.saveRecipe(_draft(tips: 'x'), 'hongshaopaigu');
    final d = db.detail(id)!;
    final byName = {for (final i in d.ingredients) i.name: i.grp};
    expect(byName['排骨'], '主料');
    expect(byName['八角'], '辅料');
    expect(byName['生抽'], '调料');
  });
}
