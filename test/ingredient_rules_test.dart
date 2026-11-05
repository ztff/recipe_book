import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/core/ingredient_rules.dart';

void main() {
  group('没写分组时按常识猜', () {
    test('肉和菜是主料', () {
      expect(guessIngredientGroup('排骨'), '主料');
      expect(guessIngredientGroup('玉米'), '主料');
      expect(guessIngredientGroup('五花肉'), '主料');
    });

    test('葱姜蒜和香料是辅料', () {
      expect(guessIngredientGroup('姜片'), '辅料');
      expect(guessIngredientGroup('大葱'), '辅料');
      expect(guessIngredientGroup('八角'), '辅料');
      expect(guessIngredientGroup('干辣椒'), '辅料');
    });

    test('酱醋糖盐是调料', () {
      expect(guessIngredientGroup('生抽'), '调料');
      expect(guessIngredientGroup('老抽'), '调料');
      expect(guessIngredientGroup('蚝油'), '调料');
      expect(guessIngredientGroup('料酒'), '调料');
      expect(guessIngredientGroup('冰糖'), '调料');
    });

    test('水归主料', () {
      expect(guessIngredientGroup('开水'), '主料');
      expect(guessIngredientGroup('清水'), '主料');
    });

    test('油菜不会因为带个油字被当成调料', () {
      expect(guessIngredientGroup('油菜'), '主料');
    });
  });

  group('没写单位时补量具', () {
    test('液体调料按汤匙', () {
      expect(guessIngredientUnit('生抽', 2, null), '汤匙');
      expect(guessIngredientUnit('料酒', 1, null), '汤匙');
      expect(guessIngredientUnit('香油', 1, null), '汤匙');
      expect(guessIngredientUnit('蚝油', 2, null), '汤匙');
    });

    test('粉状调料按茶匙', () {
      expect(guessIngredientUnit('盐', 3, null), '茶匙');
      expect(guessIngredientUnit('味精', 1, null), '茶匙');
      expect(guessIngredientUnit('淀粉', 1, null), '茶匙');
      expect(guessIngredientUnit('五香粉', 1, null), '茶匙');
    });

    test('自己写了单位就不动', () {
      expect(guessIngredientUnit('生抽', 2, '勺'), '勺');
      expect(guessIngredientUnit('冰糖', 1, '小把'), '小把');
    });

    test('没数量的不补', () {
      expect(guessIngredientUnit('盐', null, null), isNull);
      expect(guessIngredientUnit('生抽', null, null), isNull);
    });

    test('水不补量具', () {
      expect(guessIngredientUnit('开水', 1, null), isNull);
    });

    test('普通食材不补', () {
      expect(guessIngredientUnit('排骨', 800, null), isNull);
    });
  });
}
