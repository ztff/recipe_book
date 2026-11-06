import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/ocr.dart';
import '../core/paths.dart';

/// 识别原始行留档。
///
/// 出问题时（丢行、认错字、拆错列）光看解析结果是查不出所以然的，
/// 这里把原生侧吐回来的每一行原样记下来：文本、坐标、置信度、出自第几片。
/// 只留最近 [keep] 份，避免长期使用后堆满存储。
class OcrRawStore {
  OcrRawStore._();

  static const int keep = 10;

  static Directory get _dir => Directory(p.join(appImageDir.parent.path, 'ocr_raw'));

  /// Android 上再存一份到应用外部目录（/sdcard/Android/data/<包名>/files/ocr_raw），
  /// 这样出问题时用 adb 就能直接拉走，不用在手机上手动导出。
  static Future<Directory?> _externalDir() async {
    if (!Platform.isAndroid) return null;
    try {
      final ext = await getExternalStorageDirectory();
      if (ext == null) return null;
      final sub = Directory(p.join(ext.path, 'ocr_raw'));
      if (!sub.existsSync()) sub.createSync(recursive: true);
      return sub;
    } catch (_) {
      return null;
    }
  }

  /// 存一份，返回写入的文件；失败时返回 null，不影响正常识别流程。
  static Future<File?> save(
    OcrLayout layout, {
    String? sourceImage,
    String? recipeName,
  }) async {
    try {
      final dir = _dir;
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final now = DateTime.now();
      final name = 'ocr_' + _stamp(now) + '.json';
      final file = File(p.join(dir.path, name));
      final data = <String, Object?>{
        'savedAt': now.toIso8601String(),
        'appVersion': null,
        'sourceImage': sourceImage,
        'recipeName': recipeName,
        'width': layout.width,
        'height': layout.height,
        'downscaled': layout.downscaled,
        'lineCount': layout.lines.length,
        'lines': [
          for (final l in layout.lines)
            <String, Object?>{
              'text': l.text,
              'left': _r(l.left),
              'top': _r(l.top),
              'right': _r(l.right),
              'bottom': _r(l.bottom),
              'score': l.score == null ? null : _r(l.score!),
              'tile': l.tile,
              if (l.alt != null) 'alt': l.alt,
            },
        ],
        // 解析器看到的是同一批行，这里顺手把纯文本也存一份，
        // 导出来直接在手机上就能读。
        'plainText': layout.plainText,
        // 检测到但置信度不够被丢的行，用来区分「没发现」和「认不准」
        'droppedCount': layout.droppedLines.length,
        'droppedLines': [
          for (final l in layout.droppedLines)
            <String, Object?>{
              'text': l.text,
              'left': _r(l.left),
              'top': _r(l.top),
              'right': _r(l.right),
              'bottom': _r(l.bottom),
              'score': l.score == null ? null : _r(l.score!),
              'tile': l.tile,
            },
        ],
      };
      final body = const JsonEncoder.withIndent('  ').convert(data);
      await file.writeAsString(body);
      // 外部目录能写就再放一份，方便 adb 直接取
      try {
        final ext = await _externalDir();
        if (ext != null) {
          await File(p.join(ext.path, name)).writeAsString(body);
          final old = ext
              .listSync()
              .whereType<File>()
              .where((e) => e.path.endsWith('.json'))
              .toList()
            ..sort((a, b) => b.path.compareTo(a.path));
          for (final e in old.skip(keep)) {
            try {
              await e.delete();
            } catch (_) {}
          }
        }
      } catch (_) {}
      await _prune();
      return file;
    } catch (_) {
      return null;
    }
  }

  /// 最近的若干份，新的在前。
  static List<File> list() {
    try {
      final dir = _dir;
      if (!dir.existsSync()) return const [];
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      return files;
    } catch (_) {
      return const [];
    }
  }

  static File? latest() {
    final all = list();
    return all.isEmpty ? null : all.first;
  }

  static int get count => list().length;

  /// 只留最近 [keep] 份。
  static Future<void> _prune() async {
    try {
      final all = list();
      if (all.length <= keep) return;
      for (final f in all.sublist(keep)) {
        try {
          await f.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return t.year.toString() +
        two(t.month) +
        two(t.day) +
        '_' +
        two(t.hour) +
        two(t.minute) +
        two(t.second);
  }

  /// 坐标保留一位小数就够了，整份文件小一半。
  static double _r(double v) => (v * 10).roundToDouble() / 10;
}
