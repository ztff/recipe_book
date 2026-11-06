import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../data/db.dart';
import 'image_tool.dart';
import 'paths.dart';
import 'pick_image.dart';

/// 存量图片整理：把早期存下来的大图换成省空间的格式。
///
/// 之前步骤图写着 .jpg 但内容是 PNG（Flutter 的 toByteData 只出 PNG），
/// 一张一千多 KB；封面则是整张 1080x13454 的长截图原样存进来，一张两三兆。
/// 这里一次性转掉，转完打上版本号不再重复。
const String kMigrateKey = 'image_migrate_version';
const String kMigrateVersion = '1';

/// 孤儿清理的时间戳和间隔。删菜谱、换封面这些路径已经当场删图了，
/// 这里只兜底扫一遍（比如老版本留下的、或某次删除中途失败）。
const String kCleanKey = 'image_cleanup_at';
const int kCleanDays = 7;

bool _isPng(File f) {
  try {
    final raf = f.openSync();
    try {
      raf.setPositionSync(0);
      final head = raf.readSync(8);
      return head.length >= 8 &&
          head[0] == 0x89 &&
          head[1] == 0x50 &&
          head[2] == 0x4E &&
          head[3] == 0x47;
    } finally {
      raf.closeSync();
    }
  } catch (_) {
    return false;
  }
}

/// 删掉 images/ 里没有被任何菜谱引用的文件。返回删掉的个数。
///
/// 引用集为空时只清临时文件——宁可留几个孤儿，也不能因为一次意外读到空集
/// 就把用户的照片全删了。
Future<int> runOrphanCleanup(AppDb db, {bool force = false}) async {
  try {
    final last = db.getSetting(kCleanKey);
    if (!force && last != null && last.isNotEmpty) {
      final t = DateTime.tryParse(last);
      if (t != null && DateTime.now().difference(t).inDays < kCleanDays) return 0;
    }
    if (!appImageDir.existsSync()) {
      db.setSetting(kCleanKey, DateTime.now().toIso8601String());
      return 0;
    }
    final used = db.referencedImages();
    var removed = 0;
    for (final f in appImageDir.listSync().whereType<File>()) {
      final base = p.basename(f.path);
      final isTemp = base.startsWith('.') || base.contains('.tmp.');
      if (used.isEmpty) {
        if (!isTemp) continue;
      } else if (used.contains(base)) {
        continue;
      }
      try {
        f.deleteSync();
        removed++;
      } catch (_) {}
    }
    db.setSetting(kCleanKey, DateTime.now().toIso8601String());
    if (removed > 0) {
      debugPrint('orphan cleanup removed ' + removed.toString());
    }
    return removed;
  } catch (e) {
    debugPrint('orphan cleanup failed: ' + e.toString());
    return 0;
  }
}

/// 跑一次迁移。返回处理了多少个文件。
Future<int> runImageMigration(AppDb db) async {
  if (!imageToolAvailable) return 0;
  if (db.getSetting(kMigrateKey) == kMigrateVersion) return 0;
  const tag = '_c800';
  var done = 0;
  try {
    if (!appImageDir.existsSync()) {
      db.setSetting(kMigrateKey, kMigrateVersion);
      return 0;
    }
    final files = appImageDir.listSync().whereType<File>().toList();
    debugPrint('migrate start, ' + files.length.toString() + ' files');
    for (var idx = 0; idx < files.length; idx++) {
      final f = files[idx];
      if (idx % 20 == 0) debugPrint('migrate ' + idx.toString() + '/' + files.length.toString());
      final base = p.basename(f.path);
      if (base.startsWith('.') || base.contains('.tmp.')) continue;
      final isStep = base.startsWith('step_');
      final stem = p.basenameWithoutExtension(base);

      if (isStep) {
        // 步骤图：PNG 内容转成真正的 JPEG
        if (!_isPng(f)) continue;
        final newName = stem + '.jpg';
        final dst = p.join(appImageDir.path, newName);
        final n = await shrinkToJpeg(f.path, dst);
        if (n == null) continue;
        if (!p.equals(f.path, dst)) {
          try {
            f.deleteSync();
          } catch (_) {}
          db.renameImageReferences(base, newName);
        }
        done++;
      } else {
        // 封面：已经是裁过的就跳过，避免反复压缩
        if (stem.endsWith(tag)) continue;
        final newName = stem + tag + '.jpg';
        final dst = p.join(appImageDir.path, newName);
        final n = await makeThumbnail(f.path, dst, side: kCoverStoreSide);
        if (n == null) continue;
        try {
          f.deleteSync();
        } catch (_) {}
        db.renameImageReferences(base, newName);
        done++;
      }
    }
    // 只处理仍被引用的图，孤儿文件顺手清掉
    final used = db.referencedImages();
    for (final f in appImageDir.listSync().whereType<File>()) {
      final base = p.basename(f.path);
      if (base.startsWith('.')) continue;
      if (used.contains(base)) continue;
      try {
        f.deleteSync();
      } catch (_) {}
    }
    db.setSetting(kMigrateKey, kMigrateVersion);
    debugPrint('image migration done, converted ' + done.toString());
  } catch (e) {
    // 失败就不打版本号，下次启动再试
    debugPrint('image migration failed: ' + e.toString());
  }
  return done;
}
