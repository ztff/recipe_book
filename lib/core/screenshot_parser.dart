import 'dart:math' as math;
import 'dart:ui';

import 'ocr.dart';
import 'vocab.dart';

/// 从手机长截图里解析出来的一道菜。
class ScreenRecipe {
  ScreenRecipe({
    this.name,
    this.nameConfident = false,
    this.description,
    this.ingredients = const [],
    this.steps = const [],
    this.tips,
    this.droppedLines = 0,
  });

  final String? name;
  final bool nameConfident;
  final String? description;
  final List<ScreenIngredient> ingredients;
  final List<ScreenStep> steps;
  final String? tips;
  final int droppedLines;

  bool get isEmpty =>
      (name == null || name!.isEmpty) && ingredients.isEmpty && steps.isEmpty;

  int get imageCount => steps.where((e) => e.imageRect != null).length;

  String get summary {
    final parts = <String>[];
    if (ingredients.isNotEmpty) parts.add(ingredients.length.toString() + ' 条用料');
    if (steps.isNotEmpty) parts.add(steps.length.toString() + ' 个步骤');
    if (imageCount > 0) parts.add(imageCount.toString() + ' 张步骤图');
    if (tips != null) parts.add('1 段小贴士');
    return parts.isEmpty ? '什么都没认出来' : parts.join('、');
  }
}

class ScreenIngredient {
  ScreenIngredient({required this.name, this.qty, this.unit});
  final String name;
  final double? qty;
  final String? unit;

  String get display {
    final q = qty == null ? '' : (qty! % 1 == 0 ? qty!.toInt().toString() : qty!.toString());
    if (q.isEmpty) {
      // 没有数字时 unit 里存的是「一段」「适量」这种整串数量
      return unit == null ? name : name + ' ' + unit!;
    }
    return name + ' ' + q + (unit ?? '');
  }
}

class ScreenStep {
  ScreenStep({required this.text, this.imageRect});
  final String text;

  /// 该步骤配图在整张截图里的位置；没检测到就是 null。
  final Rect? imageRect;
}

/// 广告/推广行的关键词，命中就丢掉。
const List<String> _adKeywords = [
  '广告', '旗舰店', '自营', '京东', '淘宝', '天猫', '拼多多', '抖音',
  '券后', '领券', '优惠券', '包邮', '立即购买', '去看看', '点击', '打开',
  '品牌', '种草', '下单', '折扣', '特价', '限时', '¥', '￥', '赞助',
];

/// 明显是界面元素、不该进菜谱的行。
const List<String> _uiKeywords = [
  '关注', '已关注', '点赞', '收藏', '评论', '综合评分',
  '丢进菜篮子', '菜篮子', '篮子', '加入清单', '去购买',
];

const List<String> _ingredientHeaders = ['用料', '食材', '配料', '原料', '材料', '主料', '调料'];
const List<String> _tipsHeaders = ['小贴士', '贴士', '提示', '注意事项', 'tips', 'Tips'];

final RegExp _stepHeader = RegExp(r'^(步骤|第)\s*(\d+)\s*(步)?');
final RegExp _ingredientAmount = RegExp(
  r'^(.+?)\s*(\d+(?:[.٫]\d+)?|[\d.]+\s*[~\-—]\s*[\d.]+)\s*(克|g|G|千克|kg|斤|两|毫升|ml|mL|升|个|只|片|根|棵|把|勺|汤匙|茶匙|碗|杯|块|条|瓣|颗|粒|包|袋|瓶|盒|张|朵|撮|小把|大勺|小勺)?$',
);
final RegExp _amountOnly = RegExp(
  r'^(\d+([~\-—]\d+)?)\s*(克|g|G|千克|kg|斤|两|毫升|ml|mL|升|个|只|片|根|棵|把|勺|汤匙|茶匙|碗|杯|块|条|瓣|颗|粒|包|袋|瓶|盒|张|朵|撮|小把|大勺|小勺|适量|少许)$',
);

/// 「一段」「半勺」「两大勺」这类中文数量词。
final RegExp _cnAmount = RegExp(
  r'^(.+?)s*((?:半|一|二|两|三|四|五|六|七|八|九|十|几)?[大中小]?(?:勺|汤匙|茶匙|碗|杯|个|只|片|根|棵|把|块|条|瓣|颗|粒|包|袋|瓶|盒|张|朵|撮|段))$',
);

/// 「任意多少」「按口味调料」这类没法量化的写法。
final RegExp _vagueAmount = RegExp(r'^(.+?)s*(适量|少许|若干|任意多少|随意|按口味.*|依口味.*)$');

bool _hasAny(String text, List<String> keys) => keys.any((k) => text.contains(k));

/// 括号没闭合的续行（「1个（孩子吃我没」+「放)」）合回上一行。
List<OcrLine> _joinContinuation(List<OcrLine> lines) {
  final out = <OcrLine>[];
  final open = RegExp(r'[（(]');
  final close = RegExp(r'[）)]');
  for (final line in lines) {
    final t = line.text.trim();
    final prev = out.isEmpty ? null : out.last;
    final tailLike = t.length <= 4 && close.hasMatch(t);
    if (tailLike && prev != null) {
      final opens = open.allMatches(prev.text).length;
      final closes = close.allMatches(prev.text).length;
      if (opens > closes) {
        out.removeLast();
        out.add(OcrLine(
          text: prev.text + t,
          top: prev.top,
          bottom: line.bottom,
          left: prev.left,
          right: line.right,
        ));
        continue;
      }
    }
    out.add(line);
  }
  return out;
}

/// PaddleOCR 会把同一行的「名称」和「数量」拆成两个框分别返回，
/// ML Kit 则合成一行。这里按纵向重叠把碎片合回去，解析逻辑才不用改两套。
List<OcrLine> _mergeRowFragments(List<OcrLine> lines) {
  if (lines.isEmpty) return lines;
  final sorted = [...lines]..sort((a, b) => a.top.compareTo(b.top));
  final rows = <List<OcrLine>>[];
  for (final line in sorted) {
    final h = (line.bottom - line.top).clamp(1.0, 1e6);
    var placed = false;
    for (final row in rows) {
      final ref = row.first;
      final refH = (ref.bottom - ref.top).clamp(1.0, 1e6);
      final overlap =
          math.min(line.bottom, ref.bottom) - math.max(line.top, ref.top);
      if (overlap > math.min(h, refH) * 0.6) {
        row.add(line);
        placed = true;
        break;
      }
    }
    if (!placed) rows.add([line]);
  }

  const numberish = r'^[\d半一二两三四五六七八九十]+';
  final out = <OcrLine>[];
  for (final row in rows) {
    if (row.length == 1) {
      out.add(row.first);
      continue;
    }
    row.sort((a, b) => a.left.compareTo(b.left));
    final buf = StringBuffer();
    for (final piece in row) {
      final t = piece.text.trim();
      if (t.isEmpty) continue;
      if (buf.isEmpty) {
        buf.write(t);
      } else if (RegExp(numberish).hasMatch(t) ||
          _amountOnly.hasMatch(t) ||
          _cnAmount.hasMatch(t) ||
          _vagueAmount.hasMatch(t)) {
        buf.write(' ');
        buf.write(t);
      } else {
        buf.write(t);
      }
    }
    out.add(OcrLine(
      text: buf.toString(),
      top: row.map((e) => e.top).reduce(math.min),
      bottom: row.map((e) => e.bottom).reduce(math.max),
      left: row.map((e) => e.left).reduce(math.min),
      right: row.map((e) => e.right).reduce(math.max),
    ));
  }
  out.sort((a, b) {
    final d = a.top.compareTo(b.top);
    return d != 0 ? d : a.left.compareTo(b.left);
  });
  return out;
}

/// 把整张截图的识别结果解析成一道菜。
ScreenRecipe parseScreenRecipe(OcrLayout layout) {
  if (layout.isEmpty) return ScreenRecipe();

  final usable = <OcrLine>[];
  var dropped = 0;
  for (final line in _joinContinuation(_mergeRowFragments(layout.lines))) {
    final t = line.text.trim();
    if (t.isEmpty) continue;
    if (_hasAny(t, _adKeywords) || _hasAny(t, _uiKeywords)) {
      dropped++;
      continue;
    }
    usable.add(line);
  }
  if (usable.isEmpty) return ScreenRecipe(droppedLines: dropped);

  double? ingTop;
  double? tipsTop;
  final stepHeads = <MapEntry<double, int>>[];
  for (final line in usable) {
    final t = line.text.trim();
    if (ingTop == null && _ingredientHeaders.any((h) => t == h || t.startsWith(h))) {
      ingTop = line.top;
      continue;
    }
    if (tipsTop == null && _hasAny(t, _tipsHeaders) && t.length <= 8) {
      tipsTop = line.top;
      continue;
    }
    final m = _stepHeader.firstMatch(t);
    if (m != null && t.length <= 12) {
      final n = int.tryParse(m.group(2) ?? '') ?? (stepHeads.length + 1);
      stepHeads.add(MapEntry(line.top, n));
    }
  }

  // 菜名：最上面那几行里的第一行
  final headLimit = ingTop ?? (usable.length > 3 ? usable[3].top : layout.height.toDouble());
  final headLines = usable.where((e) => e.top < headLimit).toList();
  var name = headLines.isEmpty ? null : headLines.first.text.trim();
  var nameConfident = false;
  String? description;

  // 说明一定紧贴「用料」标题上方，广告和账号名都在更上面。
  // 所以从最靠近用料的一行往前收，遇到断行就停。
  if (headLines.length > 1) {
    final tail = <String>[];
    double? prevTop;
    for (var i = headLines.length - 1; i >= 1; i--) {
      final line = headLines[i];
      final t = line.text.trim();
      if (_isNoise(t)) break;
      final h = (line.bottom - line.top).clamp(1.0, 400.0);
      if (prevTop != null && (prevTop - line.top) > h * 2.4) break;
      tail.insert(0, t);
      prevTop = line.top;
    }
    if (tail.isNotEmpty) description = tail.join('\n');
  }
  final cleaned = cleanDishName(name);
  if (cleaned != null && cleaned != name) {
    name = cleaned;
    nameConfident = true;
  }

  // 用料
  final ingredients = <ScreenIngredient>[];
  if (ingTop != null) {
    final endY = _firstAfter(stepHeads, tipsTop, layout.height.toDouble(), ingTop);
    final ingLines = usable.where((e) => e.top >= ingTop! && e.top < endY).toList();
    for (var i = 0; i < ingLines.length; i++) {
      final t = ingLines[i].text.trim();
      if (ingredients.isEmpty && _ingredientHeaders.any((h) => t.contains(h))) continue;
      if (t.length < 2) continue;
      // 「名称」和「数量」被识别成两行时，数量行单独出现，先认这种
      final amount = _amountOnly.firstMatch(t);
      if (amount != null) {
        if (ingredients.isNotEmpty) {
          final last = ingredients.removeLast();
          ingredients.add(ScreenIngredient(
            name: last.name,
            qty: double.tryParse((amount.group(1) ?? '').split(RegExp(r'[~\-—]')).first),
            unit: amount.group(3),
          ));
        }
        continue;
      }
      final parsed = _parseAmount(t);
      if (parsed != null) {
        ingredients.add(parsed);
        continue;
      }
      // 「葱 一段」「五花肉 任意多少」「盐 按口味调料」：数量是文字不是数字
      final cn = _cnAmount.firstMatch(t);
      if (cn != null && (cn.group(1) ?? '').trim().isNotEmpty) {
        ingredients.add(ScreenIngredient(
          name: (cn.group(1) ?? '').trim(),
          unit: cn.group(2),
        ));
        continue;
      }
      final vague = _vagueAmount.firstMatch(t);
      if (vague != null && (vague.group(1) ?? '').trim().isNotEmpty) {
        ingredients.add(ScreenIngredient(
          name: (vague.group(1) ?? '').trim(),
          unit: vague.group(2),
        ));
        continue;
      }
      if (t.length <= 20 && !_isJunkName(t)) ingredients.add(ScreenIngredient(name: t));
    }
  }

  // 步骤
  final steps = <ScreenStep>[];
  for (var i = 0; i < stepHeads.length; i++) {
    final startY = stepHeads[i].key;
    final nextTop = i + 1 < stepHeads.length ? stepHeads[i + 1].key : null;
    final endY = math.min(
      nextTop ?? (tipsTop ?? layout.height.toDouble()),
      tipsTop != null && tipsTop > startY ? tipsTop : double.infinity,
    );
    final body = usable
        .where((e) => e.top > startY && e.top < endY)
        .map((e) => e.text.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final rect = _findImageBlock(layout, startY, endY, body);
    steps.add(ScreenStep(text: body.join('\n'), imageRect: rect));
  }

  // 小贴士
  String? tips;
  if (tipsTop != null) {
    final body = usable
        .where((e) => e.top > tipsTop!)
        .map((e) => e.text.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (body.isNotEmpty) tips = body.join('\n');
  }

  return ScreenRecipe(
    name: name == null ? null : fixTypos(name),
    nameConfident: nameConfident,
    description: description == null ? null : fixTypos(description),
    ingredients: [
      for (final i in ingredients)
        ScreenIngredient(name: fixTypos(i.name), qty: i.qty, unit: i.unit),
    ],
    steps: [
      for (final s in steps)
        ScreenStep(text: fixTypos(s.text), imageRect: s.imageRect),
    ],
    tips: tips == null ? null : fixTypos(tips),
    droppedLines: dropped,
  );
}

double _firstAfter(
  List<MapEntry<double, int>> stepHeads,
  double? tipsTop,
  double fallback,
  double afterY,
) {
  final candidates = <double>[
    if (stepHeads.isNotEmpty) stepHeads.first.key,
    ?tipsTop,
  ].where((e) => e > afterY).toList()
    ..sort();
  return candidates.isEmpty ? fallback : candidates.first;
}

/// 食材名：只要不是乱码（中文占比过低）就收。
bool _isJunkName(String text) {
  final t = text.trim();
  if (t.length < 2) return true;
  final chinese = RegExp(r'[\u4e00-\u9fa5]').allMatches(t).length;
  return chinese < t.length * 0.5;
}

/// 明显的识别噪声：太短、或中文占比过低（广告卡上的乱码）。
bool _isNoise(String text) {
  final t = text.trim();
  if (t.length < 8) return true;
  final chinese = RegExp(r'[\u4e00-\u9fa5]').allMatches(t).length;
  return chinese < t.length * 0.6;
}

ScreenIngredient? _parseAmount(String text) {
  final m = _ingredientAmount.firstMatch(text);
  if (m == null) return null;
  // 「2~3片」这种区间只取下限，和 _amountOnly 分支保持一致。
  final raw = (m.group(2) ?? '').split(RegExp(r'[~\-—]')).first.trim();
  final qty = double.tryParse(raw);
  if (qty == null) return null;
  final name = (m.group(1) ?? '').trim();
  if (name.isEmpty) return null;
  return ScreenIngredient(name: name, qty: qty, unit: m.group(3));
}

/// 在一段区域里找出最大的「没有文字」的空白块，大概率就是配图。
Rect? _findImageBlock(OcrLayout layout, double startY, double endY, List<String> body) {
  final occupied = <List<double>>[];
  for (final line in layout.lines) {
    if (line.bottom < startY || line.top > endY) continue;
    occupied.add([line.top, line.bottom]);
  }
  occupied.sort((a, b) => a[0].compareTo(b[0]));
  final merged = <List<double>>[];
  for (final o in occupied) {
    if (merged.isEmpty || o[0] > merged.last[1] + 6) {
      merged.add([o[0], o[1]]);
    } else {
      merged.last[1] = math.max(merged.last[1], o[1]);
    }
  }

  const minGap = 140.0;
  var bestGap = 0.0;
  var bestTop = 0.0;
  var cursor = startY;
  void consider(double gap, double top) {
    if (gap > bestGap) {
      bestGap = gap;
      bestTop = top;
    }
  }

  for (final m in merged) {
    consider(m[0] - cursor, cursor);
    cursor = math.max(cursor, m[1]);
  }
  consider(endY - cursor, cursor);
  if (bestGap < minGap) return null;

  final bottom = math.min(bestTop + bestGap, endY);
  return Rect.fromLTRB(
    layout.width * 0.04,
    bestTop,
    layout.width * 0.96,
    bottom,
  );
}

/// 把「脆嫩好吃的清炒红薯叶，拿肉都不换！」压成「清炒红薯叶」。
String? cleanDishName(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  if (s.isEmpty) return null;
  s = s.replaceAll(RegExp(r'^[\s\d.、]+'), '');

  const dishWords = [
    '炒', '炖', '煮', '蒸', '烧', '焖', '烤', '拌', '炸', '煎', '卤', '熬', '煲', '焗',
    '汤', '粥', '面', '饭', '饼', '包子', '饺子', '卷', '丝', '片', '丁', '块', '羹',
    '鸡', '鸭', '牛', '羊', '猪', '鱼', '虾', '蟹', '蛋', '豆腐', '肉', '菜', '叶',
    '瓜', '椒', '菇', '藕', '茄', '笋', '豆', '萝卜', '土豆', '排骨', '土豆丝',
  ];

  final segments = s
      .split(RegExp(r'[，,。！!？?；;、|\s]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  if (segments.isEmpty) return null;

  String? best;
  var bestScore = 0;
  for (final seg in segments) {
    final cleaned = seg.trim();
    if (cleaned.length < 2 || cleaned.length > 12) continue;
    var score = 0;
    for (final w in dishWords) {
      if (cleaned.contains(w)) score += w.length;
    }
    if (score > bestScore) {
      bestScore = score;
      best = cleaned;
    }
  }
  if (best == null || bestScore == 0) return null;

  // 「脆嫩好吃的清炒红薯叶」这种标题：从最后一个烹饪动词往前留一个字截断
  const verbs = ['炒', '炖', '煮', '蒸', '烧', '焖', '烤', '拌', '炸', '煎', '卤', '熬', '煲', '焗'];
  if (best.length > 6) {
    for (final v in verbs) {
      final idx = best.indexOf(v);
      if (idx > 2 && best.length - idx <= 8) {
        final start = math.max(0, idx - 1);
        final cut = best.substring(start);
        if (cut.length >= 2) return cut;
      }
    }
  }
  return best;
}
