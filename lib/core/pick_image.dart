import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import 'paths.dart';

/// 选图并复制进应用私有目录，返回文件名（不含路径）。
Future<String?> pickAndStoreImage({bool fromCamera = false, File? prePicked}) async {
  if (prePicked != null) return _store(prePicked);
  String? srcPath;
  if (Platform.isAndroid || Platform.isIOS) {
    final file = await ImagePicker().pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1800,
      imageQuality: 85,
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
  return _store(File(srcPath));
}

Future<String?> _store(File source) async {
  final bytes = await source.readAsBytes();
  final stamp = DateTime.now().millisecondsSinceEpoch.toString();
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
