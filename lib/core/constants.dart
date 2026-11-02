const List<String> kCuisines = [
  '家常', '川菜', '粤菜', '湘菜', '江浙', '西北', '东北', '西式', '日韩', '汤羹', '烘焙', '其他',
];

const List<String> kTastes = ['咸鲜', '香辣', '麻辣', '酸甜', '清淡', '酱香', '甜', '酸辣'];

const List<String> kDifficultyLabels = ['简单', '适中', '有点难'];

const List<int> kDurations = [15, 30, 60, 120];

const List<String> kIngredientGroups = ['主料', '辅料', '调料'];

const List<String> kUnits = [
  '克', '千克', '毫升', '升', '个', '瓣', '片', '根', '颗', '把', '碗',
  '汤匙', '茶匙', '杯', '适量', '少许',
];

/// 无数量单位（不做数值合并）
const Set<String> kVagueUnits = {'适量', '少许'};

String difficultyLabel(int d) =>
    kDifficultyLabels[(d - 1).clamp(0, kDifficultyLabels.length - 1)];
