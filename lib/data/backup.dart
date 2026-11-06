import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../core/paths.dart';
import 'db.dart';

/// 打包数据库 + 图片成一个 zip，返回目标路径。
///
/// 只打数据库里真正引用到的图片，和自动备份保持一致；目录里删菜谱留下的
/// 孤儿文件不再混进去。
Future<String> exportBackup(AppDb db, String destPath) async {
  final encoder = ZipFileEncoder();
  encoder.create(destPath);
  final dbPath = db.dbFilePath;
  if (dbPath != null) {
    final f = File(dbPath);
    if (await f.exists()) await encoder.addFile(f, 'recipe_book.sqlite');
  }
  final used = db.referencedImages();
  if (await appImageDir.exists()) {
    for (final f in appImageDir.listSync().whereType<File>()) {
      final base = p.basename(f.path);
      if (!used.contains(base)) continue;
      await encoder.addFile(f, 'images/' + base);
    }
  }
  await encoder.close();
  return destPath;
}

/// 解包覆盖本地库。调用后必须重启应用，否则会读到已关闭的句柄。
Future<void> importBackup(File zipFile, AppDb db) async {
  final tmp = await Directory.systemTemp.createTemp('rb_backup');
  try {
    await extractFileToDisk(zipFile.path, tmp.path);
    final incoming = File(p.join(tmp.path, 'recipe_book.sqlite'));
    if (!await incoming.exists()) {
      throw Exception('备份包里没有 recipe_book.sqlite');
    }
    final dbPath = db.dbFilePath;
    if (dbPath == null) {
      throw Exception('数据库路径未知，无法导入');
    }
    db.close();
    await incoming.copy(dbPath);
    final imgSrc = Directory(p.join(tmp.path, 'images'));
    if (await imgSrc.exists()) {
      await appImageDir.create(recursive: true);
      for (final f in appImageDir.listSync().whereType<File>()) {
        try {
          await f.delete();
        } catch (_) {}
      }
      for (final f in imgSrc.listSync().whereType<File>()) {
        await f.copy(p.join(appImageDir.path, p.basename(f.path)));
      }
    }
  } finally {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  }
}
