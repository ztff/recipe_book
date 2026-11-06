import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'paths.dart';

/// 一份已有备份。
class BackupItem {
  const BackupItem(this.name, this.size);

  final String name;
  final int size;
}

/// 备份结果。
class BackupOutcome {
  const BackupOutcome({this.where, this.bytes = 0, this.error});

  /// 成功时保存的位置（Download/recipe_book_backup/xxx.zip 这种）。
  final String? where;
  final int bytes;
  final String? error;

  bool get ok => where != null;
}

/// 自动备份：把库和配图打成一个 zip，放到用户自己能找到的地方。
///
/// 只写本地文件，不联网。Android 10 起走 MediaStore 写 Download，
/// 不需要任何存储权限。
class BackupService {
  BackupService._();

  static const MethodChannel _ch = MethodChannel('yg/backup');

  /// 保留几份；0 表示不删。图片转成 JPEG 后一份只有几 MB，不再限制数量。
  static const int keep = 0;

  /// 距上次备份超过这么多天才自动跑。
  static const int intervalDays = 7;

  static const String settingKey = 'last_backup_at';
  static const String _prefix = 'recipe_backup_';

  /// 是否到了该备份的时候。[lastRaw] 是 app_settings 里存的时间。
  ///
  /// 时间到了要备份；目标目录里一份都没有时也要补——用户可能手动删过，
  /// 或者换了台机器，光看时间戳会误以为还有备份。
  static Future<bool> shouldRun(String? lastRaw) async {
    final files = await list();
    if (files.isEmpty) return true;
    if (lastRaw == null || lastRaw.isEmpty) return true;
    final t = DateTime.tryParse(lastRaw);
    if (t == null) return true;
    return DateTime.now().difference(t).inDays >= intervalDays;
  }

  static DateTime? lastAt(String? lastRaw) =>
      lastRaw == null || lastRaw.isEmpty ? null : DateTime.tryParse(lastRaw);

  /// 跑一次备份。
  ///
  /// [snapshot] 负责把数据库导成一致快照到指定路径。
  /// [onlyImages] 是数据库里真正引用到的图片文件名；传了它，目录里那些
  /// 删菜谱时留下的孤儿文件就不会被打进备份。
  static Future<BackupOutcome> run({
    required void Function(String path) snapshot,
    Set<String>? onlyImages,
  }) async {
    Directory? tmpDir;
    try {
      final now = DateTime.now();
      final name = _prefix + _stamp(now) + '.zip';
      tmpDir = await Directory.systemTemp.createTemp('recipe_backup_');
      final dbTmp = p.join(tmpDir.path, 'recipe_book.sqlite');
      snapshot(dbTmp);

      // 库 + 图片一起打包，恢复后配图才还在
      final abs = <String>[dbTmp];
      final names = <String>['recipe_book.sqlite'];
      if (appImageDir.existsSync()) {
        for (final f in appImageDir.listSync().whereType<File>()) {
          final base = p.basename(f.path);
          if (base.startsWith('.')) continue;
          if (onlyImages != null && !onlyImages.contains(base)) continue;
          abs.add(f.path);
          names.add('images/' + base);
        }
      }

      final zipPath = p.join(tmpDir.path, name);
      await Isolate.run(() => _zipTo(abs, names, zipPath));

      final size = File(zipPath).lengthSync();
      final where = await _ch.invokeMethod<String>('save', {
        'path': zipPath,
        'name': name,
      });
      if (where == null) {
        return const BackupOutcome(error: '写入备份目录失败');
      }
      await _prune();
      return BackupOutcome(where: where, bytes: size);
    } catch (e) {
      return BackupOutcome(error: e.toString());
    } finally {
      try {
        tmpDir?.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  /// 已有的备份，新的在前。
  static Future<List<BackupItem>> list() async {
    try {
      final r = await _ch.invokeListMethod<dynamic>('list');
      final out = <BackupItem>[];
      for (final item in r ?? const []) {
        if (item is Map) {
          final n = item['name'] as String?;
          final s = (item['size'] as num?)?.toInt() ?? 0;
          if (n != null) out.add(BackupItem(n, s));
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// 所有备份的总体积（字节）。
  static Future<int> totalSize() async {
    final items = await list();
    return items.fold<int>(0, (a, b) => a + b.size);
  }

  /// 只留最新的 [keep] 份；[keep] 为 0 时一份都不删。
  static Future<void> _prune() async {
    if (keep <= 0) return;
    try {
      final items = await list();
      if (items.length <= keep) return;
      await _ch.invokeMethod<int>('delete', {
        'names': items.sublist(keep).map((e) => e.name).toList(),
      });
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
}

/// 在独立 isolate 里打包，图片多的时候不卡界面。
///
/// 用同步版：archive 4.x 的 addFile / close 是 Future，同步函数里不 await
/// 的话 isolate 直接结束，zip 里只剩一个 22 字节的空壳。
void _zipTo(List<String> abs, List<String> names, String out) {
  final enc = ZipFileEncoder();
  enc.create(out);
  try {
    for (var i = 0; i < abs.length; i++) {
      final f = File(abs[i]);
      if (!f.existsSync()) continue;
      enc.addFileSync(f, names[i]);
    }
  } finally {
    enc.closeSync();
  }
}
