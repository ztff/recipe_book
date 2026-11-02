import 'package:lpinyin/lpinyin.dart';

/// 生成可检索键：拼音首字母 + 原文小写（离线，无网络）。
String searchKey(String input) {
  final raw = input.trim().toLowerCase();
  if (raw.isEmpty) return '';
  try {
    final initials = PinyinHelper.getShortPinyin(input).toLowerCase();
    return '$initials|$raw';
  } catch (_) {
    return '|$raw';
  }
}
