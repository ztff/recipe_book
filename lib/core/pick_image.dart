import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import 'paths.dart';

const _imageTypes = [
  XTypeGroup(label: 'images', extensions: ['jpg', 'jpeg', 'png', 'webp']),
];

/// 选图并复制进应用私有目录，返回文件名（不含路径）。
Future<String?> pickAndStoreImage({bool fromCamera = false}) async {
  XFile? file;
  if (fromCamera && (Platform.isAndroid || Platform.isIOS)) {
    file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1800,
      imageQuality: 85,
    );
  } else if (Platform.isAndroid || Platform.isIOS) {
    file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1800,
      imageQuality: 85,
    );
  } else {
    file = await openFile(acceptedTypeGroups: _imageTypes);
  }
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  final stamp = DateTime.now().millisecondsSinceEpoch.toString();
  final ext = p.extension(file.path).isEmpty ? '.jpg' : p.extension(file.path).toLowerCase();
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
