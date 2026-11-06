import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// 图片重编码（原生实现）。
///
/// 截图裁出来的步骤图存 PNG 的话一张 900~1500 KB，同样画面存 JPEG q85
/// 只要 120~200 KB。封面是整张长截图，等比缩会把宽度压成一条细线，
/// 所以单独用居中裁切生成列表用的小方块。
const MethodChannel _ch = MethodChannel('yg/image');

/// 步骤图长边上限。菜谱详情里最大也就铺满屏宽，1600 足够。
const int kStepMaxSide = 1600;

/// 封面缩略图边长。
const int kCoverSide = 400;

const int _quality = 85;

bool get imageToolAvailable {
  if (kIsWeb) return false;
  return Platform.isAndroid;
}

/// 等比缩到长边 [maxSide] 并存成 JPEG，返回文件大小；失败返回 null。
Future<int?> shrinkToJpeg(
  String srcPath,
  String dstPath, {
  int maxSide = kStepMaxSide,
}) async {
  if (!imageToolAvailable) return null;
  try {
    final ok = await _ch.invokeMethod<bool>('toJpeg', {
      'src': srcPath,
      'dst': dstPath,
      'quality': _quality,
      'maxSide': maxSide,
    });
    if (ok != true) return null;
    final f = File(dstPath);
    return f.existsSync() ? f.lengthSync() : null;
  } catch (e) {
    debugPrint('shrinkToJpeg failed: ' + e.toString());
    return null;
  }
}

/// 从中心裁一个方块存成 JPEG，返回文件大小；失败返回 null。
Future<int?> makeThumbnail(
  String srcPath,
  String dstPath, {
  int side = kCoverSide,
}) async {
  if (!imageToolAvailable) return null;
  try {
    final ok = await _ch.invokeMethod<bool>('thumbnail', {
      'src': srcPath,
      'dst': dstPath,
      'side': side,
      'quality': _quality,
    });
    if (ok != true) return null;
    final f = File(dstPath);
    return f.existsSync() ? f.lengthSync() : null;
  } catch (e) {
    debugPrint('makeThumbnail failed: ' + e.toString());
    return null;
  }
}

/// 把 [srcPath] 转成同目录下的 .jpg，删掉原文件，返回新文件名。
///
/// 失败时原文件保持不动，返回 null。
Future<String?> convertToJpegInPlace(String srcPath) async {
  final dir = p.dirname(srcPath);
  final stem = p.basenameWithoutExtension(srcPath);
  final dstName = stem + '.jpg';
  final dst = p.join(dir, dstName);
  if (p.equals(srcPath, dst)) {
    // 已经是 .jpg 的，直接原地重编码到临时文件再替换
    final tmp = p.join(dir, stem + '.tmp.jpg');
    final n = await shrinkToJpeg(srcPath, tmp);
    if (n == null) return null;
    try {
      File(tmp).renameSync(srcPath);
    } catch (_) {
      return null;
    }
    return dstName;
  }
  final n = await shrinkToJpeg(srcPath, dst);
  if (n == null) return null;
  try {
    File(srcPath).deleteSync();
  } catch (_) {}
  return dstName;
}
