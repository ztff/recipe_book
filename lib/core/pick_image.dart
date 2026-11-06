import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import 'image_tool.dart';
import 'paths.dart';

/// 封面缩略图边长。菜谱列表是方块，详情页顶部也就铺满屏宽，
/// 800 足够；原图那种 1080x13454 的长截图整张存下来一张就两三兆。
const int kCoverStoreSide = 800;

/// 选图并复制进应用私有目录，返回文件名（不含路径）。
///
/// [preserveSize] 为 true 时原样保存——识别文字要靠原始像素，
/// 缩过之后小字会糊。普通封面走缩略图。
Future<String?> pickAndStoreImage({
  bool fromCamera = false,
  File? prePicked,
  bool preserveSize = false,
}) async {
  if (prePicked != null) return _store(prePicked, asCover: !preserveSize);
  String? srcPath;
  if (Platform.isAndroid || Platform.isIOS) {
    final file = await ImagePicker().pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      // 长截图做文字识别时不能被压缩，否则字会被缩糊
      maxWidth: preserveSize ? null : 1800,
      imageQuality: preserveSize ? null : 85,
    );
    if (file == null) return null;
    srcPath = file.path;
  } else {
    final res = await FilePicker.pickFiles(
      dialogTitle: '选择菜谱图片',
      type: FileType.image,
    );
    if (res.isEmpty) return null;
    srcPath = res.first.path;
  }
  if (srcPath == null) return null;
  return _store(File(srcPath), asCover: !preserveSize);
}

Future<String?> _store(File source, {bool asCover = false}) async {
  final stamp = DateTime.now().millisecondsSinceEpoch.toString();
  if (asCover && imageToolAvailable) {
    // 居中裁一个方块存 JPEG。整张长截图存下来又占地方，列表里也只显示一块。
    final name = stamp + '.jpg';
    final dest = p.join(appImageDir.path, name);
    final n = await makeThumbnail(source.path, dest, side: kCoverStoreSide);
    if (n != null) {
      debugPrint('cover stored: ' + dest);
      return name;
    }
    // 裁切失败就退回原样复制
  }
  final bytes = await source.readAsBytes();
  final ext = p.extension(source.path).isEmpty ? '.jpg' : p.extension(source.path).toLowerCase();
  final name = stamp + ext;
  final dest = File(p.join(appImageDir.path, name));
  await dest.writeAsBytes(bytes, flush: true);
  debugPrint('image stored: ' + dest.path);
  return name;
}

/// 删除不再引用的图片文件（忽略错误）。
Future<void> deleteImageQuietly(String? fileName) async {
  if (fileName == null || fileName.isEmpty) return;
  try {
    final f = File(imageFullPath(fileName));
    if (await f.exists()) await f.delete();
  } catch (_) {}
}
