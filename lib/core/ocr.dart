import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// ML Kit 只在 Android / iOS 提供离线模型；桌面端返回 false，入口会被隐藏。
bool get ocrAvailable {
  if (kIsWeb) return false;
  return Platform.isAndroid || Platform.isIOS;
}

/// 单张切片的高度：太大时 ML Kit 会把整图缩小到模型输入尺寸，
/// 文字被压到几个像素就认不出来了，所以必须自己切。
const int _tileHeight = 1400;

/// 相邻切片的重叠高度，避免一行正好被切成两半。
const int _overlap = 80;

/// 高度小于这个值就不切，一次识别完。
const int _singleShotLimit = 2000;

typedef OcrProgress = void Function(int done, int total);

/// 识别结果：文字 + 是否因为图太长被框架压缩过。
class OcrText {
  const OcrText(this.text, {this.downscaled = false});
  final String text;
  final bool downscaled;
}

/// Flutter 解码图片时最长边封顶 8192，超过会被等比缩小。
const int kMaxDecodeSide = 8192;

/// 识别图片里的中文文字。
///
/// 长截图会按高度切片分别识别再拼接；失败返回 null，不抛给调用方。
Future<OcrText?> recognizeText(File image, {OcrProgress? onProgress}) async {
  if (!ocrAvailable) return null;
  ui.Codec? codec;
  ui.Image? source;
  TextRecognizer? recognizer;
  try {
    final bytes = await image.readAsBytes();
    codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    source = frame.image;

    recognizer = TextRecognizer(script: TextRecognitionScript.chinese);

    if (source.height <= _singleShotLimit) {
      onProgress?.call(1, 1);
      final text = await _recognizeImage(recognizer, source);
      if (text == null || text.isEmpty) return null;
      return OcrText(text);
    }

    final downscaled = source.height >= kMaxDecodeSide;

    debugPrint('ocr source: ' + source.width.toString() + 'x' + source.height.toString());
    final step = _tileHeight - _overlap;
    final total = math
        .max(1, ((source.height - _overlap) / step).ceil())
        .clamp(1, 120);
    debugPrint('ocr tiles: ' + total.toString());
    onProgress?.call(0, total);
    final parts = <String>[];
    var done = 0;
    var top = 0;
    while (top < source.height) {
      final h = math.min(_tileHeight, source.height - top);
      final tile = await _cropToPng(source, top, h);
      final text = await _recognizePng(recognizer, tile);
      if (text != null && text.isNotEmpty) parts.add(text);
      done++;
      onProgress?.call(math.min(done, total), total);
      if (top + h >= source.height) break;
      top += step;
    }
    final merged = _mergeTiles(parts);
    debugPrint('ocr lines: ' +
        merged.split('\n').length.toString() +
        ' chars: ' +
        merged.length.toString());
    if (merged.isEmpty) return null;
    return OcrText(merged, downscaled: downscaled);
  } catch (e) {
    debugPrint('ocr failed: ' + e.toString());
    return null;
  } finally {
    try {
      await recognizer?.close();
    } catch (_) {}
    source?.dispose();
    try {
      codec?.dispose();
    } catch (_) {}
  }
}

Future<String?> _recognizeImage(TextRecognizer rec, ui.Image img) async {
  final png = await _encodePng(img);
  return _recognizePng(rec, png);
}

Future<String?> _recognizePng(TextRecognizer rec, Uint8List png) async {
  final path = Directory.systemTemp.path +
      '/ocr_' +
      DateTime.now().microsecondsSinceEpoch.toString() +
      '.png';
  final tmp = File(path);
  try {
    await tmp.writeAsBytes(png, flush: true);
    final result = await rec.processImage(InputImage.fromFilePath(tmp.path));
    return result.text.trim();
  } finally {
    try {
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {}
  }
}

Future<Uint8List> _cropToPng(ui.Image src, int top, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImageRect(
    src,
    ui.Rect.fromLTWH(0, top.toDouble(), src.width.toDouble(), height.toDouble()),
    ui.Rect.fromLTWH(0, 0, src.width.toDouble(), height.toDouble()),
    ui.Paint(),
  );
  final picture = recorder.endRecording();
  final cropped = await picture.toImage(src.width, height);
  try {
    return await _encodePng(cropped);
  } finally {
    cropped.dispose();
    picture.dispose();
  }
}

Future<Uint8List> _encodePng(ui.Image img) async {
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// 拼接各切片：重叠区里的重复行要丢掉，否则同一行会出现两次。
String _mergeTiles(List<String> parts) {
  final lines = <String>[];
  for (final part in parts) {
    final tileLines = part
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (tileLines.isEmpty) continue;
    var skip = 0;
    final maxCheck = math.min(6, tileLines.length);
    for (var k = maxCheck; k >= 1; k--) {
      if (lines.length < k) continue;
      if (_sameLines(lines.sublist(lines.length - k), tileLines.sublist(0, k))) {
        skip = k;
        break;
      }
    }
    lines.addAll(tileLines.sublist(skip));
  }
  return lines.join('\n');
}

bool _sameLines(List<String> tail, List<String> head) {
  for (var i = 0; i < tail.length; i++) {
    final a = tail[i].replaceAll(RegExp(r'\s'), '');
    final b = head[i].replaceAll(RegExp(r'\s'), '');
    if (a == b || a.contains(b) || b.contains(a)) continue;
    return false;
  }
  return true;
}
