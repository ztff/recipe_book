/// 从 OCR 出来的整段文字里，尽量抽出菜名、食材、步骤。
///
/// 原则：宁可少抽，不要乱抽——抽错的成本高于没抽到，用户还得逐条删。
library;

class ParsedIngredient {
  const ParsedIngredient({required this.name, this.qty, this.unit});
  final String name;
  final double? qty;
  final String? unit;
}

class ParsedRecipe {
  const ParsedRecipe({this.name, this.ingredients = const [], this.steps = const []});
  final String? name;
  final List<ParsedIngredient> ingredients;
  final List<String> steps;

  bool get isEmpty => name == null && ingredients.isEmpty && steps.isEmpty;

  int get filledCount => (name == null ? 0 : 1) + ingredients.length + steps.length;
}

const _ingredientHeaders = ['食材', '用料', '配料', '原料', '材料', '调料', '食材清单', '用料清单'];
const _stepHeaders = ['步骤', '做法', '制作', '烹饪过程', '流程', '制作步骤'];

const _vagueUnits = ['适量', '少许', '若干'];
const _knownUnits = [
  '千克', '毫升', '公斤', '汤匙', '茶匙', '大勺', '小勺',
  '克', '斤', '两', '升', '勺', '碗', '杯', '个', '根', '瓣', '片',
  '只', '枚', '条', '块', '把', '颗', '粒', '包', '袋', '张', '段',
  'g', 'kg', 'ml', 'l',
];

ParsedRecipe parseRecipeText(String raw) {
  final lines = raw
      .split(RegExp(r'[\r\n]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  if (lines.isEmpty) return const ParsedRecipe();

  String? name;
  final first = lines.first.replaceAll(RegExp(r'[：:]+$'), '').trim();
  if (first.isNotEmpty && first.length <= 24 && !_looksLikeNumbered(first)) {
    name = first;
  }

  var ingStart = -1;
  var stepStart = -1;
  for (var i = 1; i < lines.length; i++) {
    final l = lines[i].replaceAll(RegExp(r'[：:\s]'), '');
    if (ingStart < 0 && _ingredientHeaders.contains(l)) {
      ingStart = i;
      continue;
    }
    if (stepStart < 0 && _stepHeaders.any((h) => l == h || l.startsWith(h))) {
      stepStart = i;
      continue;
    }
  }

  final ingLines = <String>[];
  final stepLines = <String>[];
  if (stepStart >= 0) {
    final from = ingStart >= 0 ? ingStart + 1 : 1;
    if (stepStart > from) ingLines.addAll(lines.sublist(from, stepStart));
    stepLines.addAll(lines.sublist(stepStart + 1));
  } else if (ingStart >= 0) {
    ingLines.addAll(lines.sublist(ingStart + 1));
  } else {
    for (var i = 1; i < lines.length; i++) {
      final l = lines[i];
      if (_looksLikeNumbered(l)) {
        stepLines.add(l);
      } else if (_looksLikeIngredient(l)) {
        ingLines.add(l);
      }
    }
  }

  final ingredients = <ParsedIngredient>[];
  for (final l in ingLines) {
    final p = _parseIngredient(l);
    if (p != null) ingredients.add(p);
  }

  final steps = <String>[];
  for (final l in stepLines) {
    final t = l.replaceAll(RegExp(r'^[0-9]{1,2}\s*[.、．)：:)]\s*'), '').trim();
    if (t.isEmpty) continue;
    if (_stepHeaders.contains(t.replaceAll(RegExp(r'[：:\s]'), ''))) continue;
    steps.add(t);
  }

  return ParsedRecipe(name: name, ingredients: ingredients, steps: steps);
}

bool _looksLikeNumbered(String line) =>
    RegExp(r'^[（(]?[0-9]{1,2}[)）.、．]').hasMatch(line);

bool _looksLikeIngredient(String line) {
  if (line.length > 40) return false;
  if (_vagueUnits.any(line.endsWith)) return true;
  if (RegExp(r'[0-9]').hasMatch(line) &&
      _knownUnits.any((u) => line.contains(u))) {
    return true;
  }
  return false;
}

ParsedIngredient? _parseIngredient(String raw) {
  var t = raw.replaceAll(RegExp(r'^[•·▪\-*\u2022]+\s*'), '').trim();
  t = t.replaceAll(RegExp(r'[：:]'), ' ').trim();
  if (t.isEmpty || t.length > 40) return null;

  for (final v in _vagueUnits) {
    if (t.endsWith(v)) {
      final n = t.substring(0, t.length - v.length).trim();
      if (n.isEmpty) return null;
      return ParsedIngredient(name: n, unit: v);
    }
  }

  final m = RegExp(r'^(.+?)\s*([0-9]+(?:\.[0-9]+)?)\s*([^\s0-9]{0,4})$').firstMatch(t);
  if (m == null) {
    if (t.length <= 12 && !RegExp(r'[0-9]').hasMatch(t)) {
      return ParsedIngredient(name: t);
    }
    return null;
  }
  final n = m.group(1)!.trim();
  if (n.isEmpty) return null;
  final unit = m.group(3)!.trim();
  return ParsedIngredient(
    name: n,
    qty: double.tryParse(m.group(2)!),
    unit: unit.isEmpty ? null : unit,
  );
}
