import 'dart:math' as math;
import 'dart:ui';

import 'ingredient_rules.dart';
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
  ScreenIngredient({required this.name, this.qty, this.unit, this.group = ''});

  /// 主料 / 辅料 / 调料。菜谱自带分组标题时用菜谱的，没有就按常识猜。
  final String group;
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
  // 电商/外卖广告卡片：朴朴超市、30分钟快送、到手价 这类整块文案
  '超市', '快送', '到手价', '快至', '免配送', '抢购', '秒杀',
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
/// 所有认得的单位。带数量和不带数量的正则都拼这一段，免得改漏。
const String _unitWords =
    '千克|毫升|汤匙|茶匙|小把|大勺|小勺|小碗|适量|少许|克|g|G|kg|ml|mL|升|'
    '斤|两|个|只|片|根|棵|把|勺|碗|杯|块|条|瓣|颗|粒|包|袋|瓶|盒|张|朵|撮|'
    '段|壶|盅|碟|罐|扎|筒|铲|盘|层|捏';

final RegExp _amountOnly = RegExp(
  r'^(\d+([~\-—]\d+)?)\s*(' + _unitWords + r')$',
);

/// 「一段」「半勺」「两大勺」这类中文数量词。
final RegExp _cnAmount = RegExp(
  r'^(.+?)\s*((?:半|一|二|两|三|四|五|六|七|八|九|十|几)?[大中小]?\s*'
  r'(?:' + _unitWords + r'))$',
);

/// 整行只有数量：「4勺」「一壶」「半勺」「壶」「4」。
/// PaddleOCR 经常把名称和数量拆成两行，这种行要能挂回上一条。
/// 返回 (数量, 单位)，不是数量行返回 null。
(double?, String?)? _qtyOnly(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;

  final bare = RegExp(r'^(\d+(?:\.\d+)?)$').firstMatch(t);
  if (bare != null) return (double.tryParse(bare.group(1)!), null);

  // 单独一个中文数字：「一」「半」「两」。单位在另一行的话就是这种拆法。
  final cnBare = RegExp(r'^([半一二两三四五六七八九十])$').firstMatch(t);
  if (cnBare != null) return (_cnDigits[cnBare.group(1)!], null);

  final numUnit =
      RegExp(r'^(\d+(?:\.\d+)?)\s*(' + _unitWords + r')$').firstMatch(t);
  if (numUnit != null) {
    return (double.tryParse(numUnit.group(1)!), numUnit.group(2));
  }

  final cn = RegExp(
    r'^((?:半|一|二|两|三|四|五|六|七|八|九|十|几)?[大中小]?\s*(?:' +
        _unitWords +
        r'))$',
  ).firstMatch(t);
  if (cn != null) {
    final split = _splitCnAmount(cn.group(1)!);
    return (split.$1, split.$2.isEmpty ? null : split.$2);
  }
  return null;
}

/// 「任意多少」「按口味调料」这类没法量化的写法。
final RegExp _vagueAmount = RegExp(r'^(.+?)\s*(适量|少许|若干|任意多少|随意|按口味.*|依口味.*)$');

bool _hasAny(String text, List<String> keys) => keys.any((k) => text.contains(k));

/// 中文数量词转成数字：「一小把」→ (1, 小把)、「半勺」→ (0.5, 勺)。
/// 「几勺」这种约数返回 (null, 勺)。
const Map<String, double> _cnDigits = {
  '半': 0.5,
  '一': 1,
  '二': 2,
  '两': 2,
  '三': 3,
  '四': 4,
  '五': 5,
  '六': 6,
  '七': 7,
  '八': 8,
  '九': 9,
  '十': 10,
};

(double?, String) _splitCnAmount(String token) {
  final t = token.trim();
  if (t.isEmpty) return (null, t);
  final v = _cnDigits[t[0]];
  if (v == null) return (null, t);
  return (v, t.substring(1).trim());
}

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
    // 截图时页面在滚动会留下重影：同一视觉行里，某段文字的横向范围
    // 整个落在另一段里面，那是残影不是内容。真实的两列布局
    //（名称 / 数量）左右是分开的，不会被判成包含。
    // 残影和正常分列（名称 / 数量）在坐标上长得一样，靠内容区分：
    // 残影的字一定来自同行那段正文，正常两列各说各的。
    final kept = <OcrLine>[];
    for (final piece in row) {
      final swallowed = kept.any((k) =>
          piece.left >= k.left - 2 &&
          piece.right <= k.right + 2 &&
          _charOverlap(piece.text, k.text) >= 0.3);
      if (swallowed) continue;
      kept.add(piece);
    }
    final buf = StringBuffer();
    for (final piece in kept) {
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
/// [rules] 传数据库里的规则集，不传就用内置的。
ScreenRecipe parseScreenRecipe(OcrLayout layout, {IngredientRuleSet? rules}) {
  if (layout.isEmpty) return ScreenRecipe();

  final usable = <OcrLine>[];
  var dropped = 0;
  // 用料区的起点全靠标题行定位，但标题行常常带着界面按钮
  //（「用料  丢进菜篮子」），会被下面的界面词整行吃掉，
  // 所以在过滤之前先把它认出来。
  double? ingTop;
  for (final line in _joinContinuation(_mergeRowFragments(layout.lines))) {
    final t = line.text.trim();
    if (t.isEmpty) continue;
    if (ingTop == null && _isIngredientHeaderLine(t)) {
      ingTop = line.top;
      dropped++;
      continue;
    }
    if (_hasAny(t, _adKeywords) || _hasAny(t, _uiKeywords)) {
      dropped++;
      continue;
    }
    // 状态栏：时钟、电量、信号格之类，不能当成菜名。
    // 只在截图最顶上判，否则用料区里「4」这种只剩数字的数量行会被误杀。
    if (line.top < 150 && _isStatusChrome(t)) {
      dropped++;
      continue;
    }
    usable.add(line);
  }
  if (usable.isEmpty) return ScreenRecipe(droppedLines: dropped);

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
  // 广告卡片常常夹在正文和「用料」之间（朴朴超市那种），一行行往上收
  // 会把商品名「上装」当成说明就断掉了。按行距突变切块，取最靠近用料、
  // 且整块都像正文的那一块。
  if (headLines.length > 1) {
    final blocks = <List<OcrLine>>[];
    var cur = <OcrLine>[];
    double? prev;
    for (var i = headLines.length - 1; i >= 1; i--) {
      final line = headLines[i];
      final h = (line.bottom - line.top).clamp(1.0, 400.0);
      if (prev != null && (prev - line.top) > h * 2.4) {
        if (cur.isNotEmpty) blocks.add(cur);
        cur = <OcrLine>[];
      }
      cur.add(line);
      prev = line.top;
    }
    if (cur.isNotEmpty) blocks.add(cur);

    for (final block in blocks) {
      // 紧挨着用料的那一行如果本身就是噪声（广告卡片的「上装」），
      // 说明这一块是广告，整块跳过。
      if (_isNoise(block.first.text.trim())) continue;
      final picked = <OcrLine>[];
      for (final e in block) {
        if (_isNoise(e.text.trim())) break;
        picked.add(e);
      }
      if (picked.isEmpty) continue;
      // 广告卡片里孤零零一行「高弹扩容，不紧勒保暖无束缚」也像中文，
      // 但真正的说明至少是两行连续正文，或者一行够长的句子。
      if (picked.length == 1 && picked.first.text.trim().length < 15) {
        continue;
      }
      // 屏幕宽度造成的折行不算分段：上一行没有句末标点就接上。
      final parts = <String>[];
      for (final e in picked.reversed) {
        final t = e.text.trim();
        if (parts.isNotEmpty && !_endsSentence(parts.last)) {
          parts[parts.length - 1] = parts.last + t;
        } else {
          parts.add(t);
        }
      }
      description = parts.join('\n');
      break;
    }
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
    var curGroup = '';
    for (var i = 0; i < ingLines.length; i++) {
      final t = ingLines[i].text.trim();
      // 「主料」「调料」这类小标题单独占一行，切换后面几行的归属。
      final head = t.replaceAll(RegExp(r'[：:（(].*$'), '').trim();
      if (head.length <= 4 && kIngredientGroupHeaders.contains(head)) {
        curGroup = head;
        continue;
      }
      if (ingredients.isEmpty && _ingredientHeaders.any((h) => t.contains(h))) continue;

      // 「名称」和「数量」被识别成两行时，数量行会单独出现。
      // 这一步要排在长度过滤之前，否则只认出「4」的那种行会被当成单字丢掉。
      final q = _qtyOnly(t);
      if (q != null && ingredients.isNotEmpty) {
        final last = ingredients.last;
        // 数量和单位可能分两行下来，各自补各自缺的那半。
        final takeQty = q.$1 != null && last.qty == null;
        final takeUnit =
            q.$2 != null && (last.unit == null || last.unit!.isEmpty);
        if (takeQty || takeUnit) {
          ingredients.removeLast();
          ingredients.add(ScreenIngredient(
            name: last.name,
            qty: takeQty ? q.$1 : last.qty,
            unit: takeUnit ? q.$2 : last.unit,
            group: last.group,
          ));
          continue;
        }
      }

      if (t.length < 2) continue;
      final parsed = _parseAmount(t);
      if (parsed != null) {
        ingredients.add(ScreenIngredient(
          name: parsed.name,
          qty: parsed.qty,
          unit: parsed.unit,
          group: curGroup,
        ));
        continue;
      }
      // 「葱 一段」「五花肉 任意多少」「盐 按口味调料」：数量是文字不是数字
      final cn = _cnAmount.firstMatch(t);
      if (cn != null && (cn.group(1) ?? '').trim().isNotEmpty) {
        final split = _splitCnAmount(cn.group(2) ?? '');
        ingredients.add(ScreenIngredient(
          name: (cn.group(1) ?? '').trim(),
          qty: split.$1,
          unit: split.$2.isEmpty ? null : split.$2,
          group: curGroup,
        ));
        continue;
      }
      final vague = _vagueAmount.firstMatch(t);
      if (vague != null && (vague.group(1) ?? '').trim().isNotEmpty) {
        ingredients.add(ScreenIngredient(
          name: (vague.group(1) ?? '').trim(),
          unit: vague.group(2),
          group: curGroup,
        ));
        continue;
      }
      if (t.length <= 20 && !_isJunkName(t)) {
        ingredients.add(ScreenIngredient(name: t, group: curGroup));
      }
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
    steps.add(ScreenStep(text: _joinBySentence(body), imageRect: rect));
  }

  // 小贴士
  String? tips;
  if (tipsTop != null) {
    final body = usable
        .where((e) => e.top > tipsTop!)
        .map((e) => e.text.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (body.isNotEmpty) tips = _joinBySentence(body);
  }

  return ScreenRecipe(
    name: name == null ? null : fixTypos(name),
    nameConfident: nameConfident,
    description: description == null ? null : fixTypos(description),
    ingredients: [
      for (final i in ingredients) _finalizeIngredient(i, rules),
    ],
    steps: [
      for (final s in steps)
        ScreenStep(text: fixTypos(s.text), imageRect: s.imageRect),
    ],
    tips: tips == null ? null : fixTypos(tips),
    droppedLines: dropped,
  );
}

/// OCR 按屏幕宽度断行，一句话常被切成两半。上一行没写完就接上，
/// 只在句末标点处换行，显示出来才像人写的。
String joinBySentence(List<String> lines) => _joinBySentence(lines);

String _joinBySentence(List<String> lines) {
  final parts = <String>[];
  for (final raw in lines) {
    final t = raw.trim();
    if (t.isEmpty) continue;
    if (parts.isNotEmpty && !_endsSentence(parts.last)) {
      parts[parts.length - 1] = parts.last + t;
    } else {
      parts.add(t);
    }
  }
  return parts.join('\n');
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

/// 用料标题行。整行等于标题，或者标题后面跟的是界面按钮文字
///（「用料  丢进菜篮子」）。「主料是排骨」这种正文不算。
bool _isIngredientHeaderLine(String text) {
  for (final h in _ingredientHeaders) {
    if (text == h) return true;
    if (text.startsWith(h) && _hasAny(text.substring(h.length), _uiKeywords)) {
      return true;
    }
  }
  return false;
}

/// 明显的识别噪声：太短、或中文占比过低（广告卡上的乱码）。
/// 状态栏/系统界面残留：时钟、电量、信号格、纯编号行。
///
/// 判据是「把数字和标点全去掉以后什么都不剩」，这样
/// 5:07、87%、5:07 87%、12、3. 都会被丢掉，而 500克、20分钟 会留下。
bool _isStatusChrome(String text) {
  if (text.isEmpty) return false;
  final stripped = text.replaceAll(RegExp(r'[0-9:：%．.\-\s+/、]'), '');
  return stripped.isEmpty;
}

/// 片段里有几成的字也在 [host] 里出现过。界面滚动留下的文字残影
/// 通常和正文高度重合，「红薯叶」和「1把」这种正常分列几乎为 0。
double _charOverlap(String piece, String host) {
  final chars = piece.replaceAll(RegExp(r'[\s，。、！？：；（）()·]'), '').split('');
  if (chars.isEmpty) return 0;
  final hostSet = host.split('').toSet();
  final hit = chars.where(hostSet.contains).length;
  return hit / chars.length;
}

/// 这行是不是说完了（句末标点）。用来判断下一行是折行还是新段落。
bool _endsSentence(String s) {
  if (s.isEmpty) return true;
  return RegExp(r'[。！？!?…~～」》）)]$').hasMatch(s);
}

bool _isNoise(String text) {
  final t = text.trim();
  if (t.length < 8) return true;
  final chinese = RegExp(r'[\u4e00-\u9fa5]').allMatches(t).length;
  return chinese < t.length * 0.6;
}

/// 词法解析完再统一修错字、补分组、补量具。
/// 菜谱自己写了分组的就尊重菜谱，没写的按常识猜。
ScreenIngredient _finalizeIngredient(ScreenIngredient i, IngredientRuleSet? rules) {
  final name = fixTypos(i.name);
  final rule = (rules ?? IngredientRuleSet.builtin).lookup(name);

  // 菜谱自己写了分组的最优先，其次是数据库规则，最后才按常识猜。
  final grp = i.group.isNotEmpty
      ? i.group
      : (rule != null && rule.grp.isNotEmpty
          ? rule.grp
          : guessIngredientGroup(name));

  // 命中规则就完全按规则来：规则里的单位是空的，意思就是「这个别补」。
  final blank = i.unit == null || i.unit!.trim().isEmpty;
  final String? unit;
  if (rule != null) {
    unit = blank && rule.unit.isNotEmpty ? rule.unit : i.unit;
  } else {
    unit = guessIngredientUnit(name, i.qty, i.unit);
  }
  // 名字尾巴上挂着的「一」「半」，其实是数量。
  final fixed = splitTrailingQuantity(name, unit, i.qty);
  return ScreenIngredient(
    name: fixed.name,
    qty: fixed.qty,
    unit: unit,
    group: grp,
  );
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
