import 'package:flutter/material.dart';

/// 可选主题色（顺序即设置页里的排列顺序，索引会被持久化）。
const kSeedColors = <(Color, String)>[
  (Color(0xFFD2601A), '葱油橙'),
  (Color(0xFF3F7D4E), '青蔬绿'),
  (Color(0xFF2C6E9B), '海盐蓝'),
  (Color(0xFF7B5EA7), '紫苏紫'),
  (Color(0xFFB03A2E), '辣子红'),
  (Color(0xFF2F8A86), '青瓷青'),
];

ThemeData buildTheme(Brightness brightness, {Color seed = const Color(0xFFD2601A)}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: scheme.surfaceTint,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: true,
    ),
  );
}
