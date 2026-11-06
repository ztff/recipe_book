/// 用料分组与量具补全规则。
///
/// 下厨房这类菜谱绝大多数不写单位（「生抽 2 勺」还好，「生抽」直接不写就
/// 很常见），也不分组。这里按常识补：液体调料按汤匙（15ml）算，粉状调料
/// 按茶匙（5ml）算，葱姜蒜和香料归辅料。
library;

import 'vocab.dart';

/// 液状 / 酱状，默认按汤匙算。
const Set<String> kLiquidSeasonings = {
  '生抽', '老抽', '酱油', '豉油', '蚝油', '耗油', '蒸鱼豉油', '味极鲜',
  '料酒', '黄酒', '花雕', '米酒', '白酒', '啤酒',
  '陈醋', '香醋', '米醋', '白醋', '醋', '果醋',
  '香油', '芝麻油', '食用油', '花生油', '菜籽油', '橄榄油', '玉米油', '色拉油',
  '辣椒油', '花椒油', '葱油', '猪油', '黄油',
  '豆瓣酱', '甜面酱', '黄豆酱', '沙茶酱', '番茄酱', '番茄沙司', '沙拉酱', '芝麻酱',
  '蒜蓉辣酱', '辣椒酱', '豆豉酱', '叉烧酱', '排骨酱', '海鲜酱', '腐乳汁',
  '蜂蜜', '柠檬汁', '水淀粉', '淀粉水', '湿淀粉',
};

/// 粉状 / 细颗粒，默认按茶匙算。
const Set<String> kPowderSeasonings = {
  '盐', '食盐', '细盐', '海盐',
  '糖', '白糖', '砂糖', '细砂糖', '红糖粉', '糖粉',
  '味精', '鸡精', '鸡粉', '鸡汁',
  '胡椒粉', '白胡椒', '黑胡椒', '花椒粉', '辣椒粉', '辣椒面', '咖喱粉',
  '淀粉', '生粉', '玉米淀粉', '红薯淀粉', '土豆淀粉',
  '酵母', '泡打粉', '小苏打', '食用碱',
  '孜然', '孜然粉', '五香粉', '十三香', '椒盐', '咖喱', '肉桂粉', '香蒜粉',
};

/// 水：归主料（炖煮用的液体，量通常不小），但别给它补「汤匙」这种量具。
const Set<String> kWaterNames = {
  '水', '开水', '清水', '热水', '温水', '凉水', '冰水', '冷水', '纯净水', '自来水',
};

/// 葱姜蒜和干香料：起味不占肚子，归辅料。
const Set<String> kAromaticIngredients = {
  '葱', '小葱', '香葱', '大葱', '洋葱', '京葱', '葱花', '葱段', '葱白', '葱结',
  '姜', '生姜', '老姜', '姜片', '姜末', '姜丝', '姜块', '姜蓉',
  '蒜', '大蒜', '蒜头', '蒜瓣', '蒜末', '蒜片', '蒜蓉', '蒜粒',
  '香菜', '香芹', '芹菜段', '薄荷', '罗勒', '紫苏',
  '八角', '桂皮', '香叶', '花椒', '麻椒', '干辣椒', '小米椒', '小米辣',
  '草果', '白芷', '丁香', '茴香', '陈皮', '山柰', '肉蔻', '豆蔻', '良姜',
  '枸杞', '红枣', '当归', '党参', '黄芪',
};

/// 用料区里可能出现的分组小标题。
const Set<String> kIngredientGroupHeaders = {
  '主料', '辅料', '调料', '配料', '腌料', '腌肉料', '酱汁', '浇汁', '料汁',
  '调味料', '调味汁', '配菜', '点缀', '装饰', '汤料', '面糊', '馅料', '油盐',
};

/// 名称是否命中某张表：整名相等，或者表里的词出现在名称里。
bool _hit(String name, Set<String> table) {
  if (table.contains(name)) return true;
  for (final k in table) {
    if (k.length >= 2 && name.contains(k)) return true;
  }
  return false;
}

/// 菜谱没写分组时，按常识猜这一条属于哪一组。
String guessIngredientGroup(String name) {
  final n = name.trim();
  if (n.isEmpty) return '主料';
  // 葱姜蒜优先：花椒油是调料，但花椒是辅料，先看名字里有没有香料本体。
  if (_hit(n, kAromaticIngredients)) return '辅料';
  if (kWaterNames.contains(n)) return '主料';
  if (_hit(n, kPowderSeasonings) || _hit(n, kLiquidSeasonings)) return '调料';
  // 兜底看总词表：冰糖这种块状调料两个量具表里都没有，但确实是调料。
  if (kSeasonings.contains(n)) return '调料';
  return '主料';
}

/// 菜谱没写单位时，按常识补一个。
/// 只对「有数量、没单位」的生效，写了「适量」的不补。
String? guessIngredientUnit(String name, double? qty, String? unit) {
  if (qty == null) return unit;
  if (unit != null && unit.trim().isNotEmpty) return unit;
  final n = name.trim();
  if (kWaterNames.contains(n)) return unit;
  if (_hit(n, kPowderSeasonings)) return '茶匙';
  if (_hit(n, kLiquidSeasonings)) return '汤匙';
  return null;
}

/// 中文数字转数值。解析器和规则层共用一份。
const Map<String, double> kCnNumber = {
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

/// OCR 常把汉字「一」认成一横，真机上见过 `—壶`（破折号）代替「一壶」。
/// 这些码位统一折回「一」再解析。注意不收 ASCII 连字符 `-`，
/// 那是「1-2 个」这种区间的正常写法。
const List<String> _dashLike = [
  '\u2012', // figure dash
  '\u2013', // en dash
  '\u2014', // em dash
  '\u2015', // horizontal bar
  '\u2212', // minus sign
  '\uFF0D', // fullwidth hyphen-minus
];

/// 把认错成横线的汉字「一」折回来。
String normalizeCnDash(String s) {
  var out = s;
  for (final c in _dashLike) {
    out = out.replaceAll(c, '一');
  }
  return out;
}

/// 「开水一」+ 单位「壶」这种拆法：OCR 把数量那个「一」粘到名字尾巴上了。
/// 只有「有单位、没数量」时才拆，免得把「三文鱼」这类正常名字切坏。
({String name, double? qty}) splitTrailingQuantity(
  String name,
  String? unit,
  double? qty,
) {
  final n = name.trim();
  if (qty != null) return (name: n, qty: qty);
  if (unit == null || unit.trim().isEmpty) return (name: n, qty: qty);
  if (n.length < 2) return (name: n, qty: qty);
  final tail = n[n.length - 1];
  final v = kCnNumber[tail] ?? (_dashLike.contains(tail) ? 1.0 : null);
  if (v == null) return (name: n, qty: qty);
  return (name: n.substring(0, n.length - 1), qty: v);
}

/// 可维护的一条规则：某个食材归哪一组、没写单位时补什么。
/// 空字符串表示「不管这一项」，不是「清空」。
class IngredientRule {
  const IngredientRule(this.name, this.grp, this.unit);

  final String name;
  final String grp;
  final String unit;
}

/// 上面那几张表拍平成一个列表，首次启动灌进数据库。
/// 之后一切以数据库为准，用户改了不会被覆盖。
List<IngredientRule> builtinIngredientRules() {
  final out = <IngredientRule>[];
  for (final n in kLiquidSeasonings) {
    out.add(IngredientRule(n, '调料', '汤匙'));
  }
  for (final n in kPowderSeasonings) {
    out.add(IngredientRule(n, '调料', '茶匙'));
  }
  for (final n in kAromaticIngredients) {
    out.add(IngredientRule(n, '辅料', ''));
  }
  for (final n in kWaterNames) {
    out.add(IngredientRule(n, '主料', ''));
  }
  return out;
}

/// 识别时用的规则集。先查完全同名的，再按「长词优先」做包含匹配
/// （「花椒油」优先于「花椒」）。
class IngredientRuleSet {
  IngredientRuleSet(Iterable<IngredientRule> rules)
      : _exact = {for (final r in rules) r.name: r},
        _partial = (rules.where((r) => r.name.length >= 2).toList()
          ..sort((a, b) => b.name.length.compareTo(a.name.length)));

  final Map<String, IngredientRule> _exact;
  final List<IngredientRule> _partial;

  /// 没有数据库时的兜底（测试、首次启动）。
  static final builtin = IngredientRuleSet(builtinIngredientRules());

  IngredientRule? lookup(String name) {
    final n = name.trim();
    if (n.isEmpty) return null;
    final exact = _exact[n];
    if (exact != null) return exact;
    for (final r in _partial) {
      if (n.contains(r.name)) return r;
    }
    return null;
  }
}
