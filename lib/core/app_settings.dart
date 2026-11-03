import 'package:flutter/material.dart';

import '../data/db.dart';
import '../main.dart';
import 'theme.dart';

enum AppThemeMode { system, light, dark }

/// 列表排序方式，索引与列表页下拉菜单一致。
const kSortOptions = <(String, String)>[
  ('recent', '最近更新'),
  ('cook', '做得多'),
  ('fast', '用时短'),
  ('rating', '评分高'),
  ('name', '按名称'),
];

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.seedIndex = 0,
    this.textScale = 1.0,
    this.keepAwake = true,
    this.timerSound = true,
    this.timerVibrate = true,
    this.defaultSort = 'recent',
    this.ocrHighAccuracy = true,
  });

  final AppThemeMode themeMode;
  final int seedIndex;
  final double textScale;
  final bool keepAwake;
  final bool timerSound;
  final bool timerVibrate;
  final String defaultSort;

  /// 截屏识别是否用多尺度投票（更准，但耗时翻倍）。
  final bool ocrHighAccuracy;

  Color get seedColor {
    final i = seedIndex.clamp(0, kSeedColors.length - 1);
    return kSeedColors[i].$1;
  }

  ThemeMode get flutterMode => switch (themeMode) {
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
        AppThemeMode.system => ThemeMode.system,
      };

  AppSettings copyWith({
    AppThemeMode? themeMode,
    int? seedIndex,
    double? textScale,
    bool? keepAwake,
    bool? timerSound,
    bool? timerVibrate,
    String? defaultSort,
    bool? ocrHighAccuracy,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      seedIndex: seedIndex ?? this.seedIndex,
      textScale: textScale ?? this.textScale,
      keepAwake: keepAwake ?? this.keepAwake,
      timerSound: timerSound ?? this.timerSound,
      timerVibrate: timerVibrate ?? this.timerVibrate,
      defaultSort: defaultSort ?? this.defaultSort,
      ocrHighAccuracy: ocrHighAccuracy ?? this.ocrHighAccuracy,
    );
  }

  static AppSettings load(AppDb db) {
    String? g(String k) {
      try {
        return db.getSetting(k);
      } catch (_) {
        return null;
      }
    }

    return AppSettings(
      themeMode: AppThemeMode.values.firstWhere(
        (e) => e.name == (g('theme_mode') ?? 'system'),
        orElse: () => AppThemeMode.system,
      ),
      seedIndex: int.tryParse(g('seed_index') ?? '0') ?? 0,
      textScale: double.tryParse(g('text_scale') ?? '1') ?? 1.0,
      keepAwake: (g('keep_awake') ?? '1') == '1',
      timerSound: (g('timer_sound') ?? '1') == '1',
      timerVibrate: (g('timer_vibrate') ?? '1') == '1',
      defaultSort: g('default_sort') ?? 'recent',
      ocrHighAccuracy: (g('ocr_high_accuracy') ?? '1') == '1',
    );
  }

  void persist(AppDb db) {
    db.setSetting('theme_mode', themeMode.name);
    db.setSetting('seed_index', seedIndex.toString());
    db.setSetting('text_scale', textScale.toStringAsFixed(2));
    db.setSetting('keep_awake', keepAwake ? '1' : '0');
    db.setSetting('timer_sound', timerSound ? '1' : '0');
    db.setSetting('timer_vibrate', timerVibrate ? '1' : '0');
    db.setSetting('default_sort', defaultSort);
    db.setSetting('ocr_high_accuracy', ocrHighAccuracy ? '1' : '0');
  }
}

/// 全局设置：改一次，整个应用跟着重建。
final ValueNotifier<AppSettings> appSettings =
    ValueNotifier<AppSettings>(const AppSettings());

void loadSettings() {
  appSettings.value = AppSettings.load(appDb);
}

void updateSettings(AppSettings next) {
  appSettings.value = next;
  try {
    next.persist(appDb);
  } catch (_) {}
}
