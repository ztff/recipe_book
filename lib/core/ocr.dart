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

/// Flutter 解码图片时最长边封顶 8192，超过会被等比缩小。
const int kMaxDecodeSide = 8192;

typedef OcrProgress = void Function(int done, int total);

/// 一行识别结果，带它在整张图里的纵向位置。
///
/// 图文混排的截图（小红书那种）只按返回顺序拼会乱序，
/// 必须靠 top 自己按从上到下重排。
class OcrLine {
  const OcrLine({
    required this.text,
    required this.top,
    required this.bottom,
    required this.left,
    required this.right,
  });

  final String text;
  final double top;
  final double bottom;
  final double left;
  final double right;

  double get height => bottom - top;
}

/// 整张图的识别结果：按阅读顺序排好的行 + 原图尺寸。
class OcrLayout {
  const OcrLayout({
    required this.lines,
    required this.width,
    required this.height,
    this.downscaled = false,
  });

  final List<OcrLine> lines;
  final int width;
  final int height;
  final bool downscaled;

  String get plainText => lines.map((e) => e.text).join('\n');
  bool get isEmpty => lines.isEmpty;
}

/// 兼容旧调用点：只要文字。
class OcrText {
  const OcrText(this.text, {this.downscaled = false});
  final String text;
  final bool downscaled;
}

/// 识别整张图，保留每一行的坐标。
///
/// 长截图会按高度切片分别识别，再把各片坐标换算回整图坐标后统一排序。
Future<OcrLayout?> recognizeLayout(
  File image, {
  OcrProgress? onProgress,
}) async {
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
      final lines = await _recognizeImage(recognizer, source, 0);
      if (lines.isEmpty) return null;
      return OcrLayout(
        lines: _tidy(lines),
        width: source.width,
        height: source.height,
      );
    }

    final downscaled = source.height >= kMaxDecodeSide;
    final step = _tileHeight - _overlap;
    final total = math
        .max(1, ((source.height - _overlap) / step).ceil())
        .clamp(1, 120);
    debugPrint('ocr source: ' +
        source.width.toString() +
        'x' +
        source.height.toString() +
        ' tiles: ' +
        total.toString());
    onProgress?.call(0, total);

    final all = <OcrLine>[];
    var done = 0;
    var top = 0;
    while (top < source.height) {
      final h = math.min(_tileHeight, source.height - top);
      final tile = await _cropToPng(source, top, h);
      final lines = await _recognizePng(recognizer, tile, top.toDouble());
      all.addAll(lines);
      done++;
      onProgress?.call(math.min(done, total), total);
      if (top + h >= source.height) break;
      top += step;
    }
    if (all.isEmpty) return null;
    return OcrLayout(
      lines: _tidy(all),
      width: source.width,
      height: source.height,
      downscaled: downscaled,
    );
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

/// 兼容旧调用点。
Future<OcrText?> recognizeText(File image, {OcrProgress? onProgress}) async {
  final layout = await recognizeLayout(image, onProgress: onProgress);
  if (layout == null) return null;
  return OcrText(layout.plainText, downscaled: layout.downscaled);
}

/// 按 y 排序 + 去掉切片重叠造成的重复行。
List<OcrLine> _tidy(List<OcrLine> lines) {
  final sorted = [...lines]..sort((a, b) {
      final d = a.top.compareTo(b.top);
      if (d != 0) return d;
      return a.left.compareTo(b.left);
    });
  final out = <OcrLine>[];
  for (final line in sorted) {
    if (line.text.trim().isEmpty) continue;
    var duplicate = false;
    for (final kept in out) {
      if ((kept.top - line.top).abs() > 36) continue;
      final a = kept.text.replaceAll(RegExp(r'\s'), '');
      final b = line.text.replaceAll(RegExp(r'\s'), '');
      if (a == b || (a.length > 3 && (a.contains(b) || b.contains(a)))) {
        duplicate = true;
        break;
      }
    }
    if (!duplicate) out.add(line);
  }
  return out;
}

Future<List<OcrLine>> _recognizeImage(
  TextRecognizer rec,
  ui.Image img,
  double yOffset,
) async {
  final png = await _encodePng(img);
  return _recognizePng(rec, png, yOffset);
}

Future<List<OcrLine>> _recognizePng(
  TextRecognizer rec,
  Uint8List png,
  double yOffset,
) async {
  final path = Directory.systemTemp.path +
      '/ocr_' +
      DateTime.now().microsecondsSinceEpoch.toString() +
      '.png';
  final tmp = File(path);
  try {
    await tmp.writeAsBytes(png, flush: true);
    final result = await rec.processImage(InputImage.fromFilePath(tmp.path));
    final lines = <OcrLine>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        final box = line.boundingBox;
        final text = line.text.trim();
        if (text.isEmpty) continue;
        lines.add(OcrLine(
          text: text,
          top: box.top + yOffset,
          bottom: box.bottom + yOffset,
          left: box.left,
          right: box.right,
        ));
      }
    }
    return lines;
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

/// 把原图上的一段纵向区域裁出来存成图片文件。
///
/// 坐标系与 [recognizeLayout] 返回的坐标一致（即解码后的像素坐标）。
Future<bool> cropRegionToFile(
  File source,
  double top,
  double bottom,
  String destPath,
) async {
  ui.Codec? codec;
  ui.Image? img;
  try {
    codec = await ui.instantiateImageCodec(await source.readAsBytes());
    img = (await codec.getNextFrame()).image;
    final t = top.round().clamp(0, img.height - 1);
    final b = bottom.round().clamp(t + 1, img.height);
    if (b - t < 40) return false;
    final png = await _cropToPng(img, t, b - t);
    await File(destPath).writeAsBytes(png, flush: true);
    return true;
  } catch (e) {
    debugPrint('crop failed: ' + e.toString());
    return false;
  } finally {
    img?.dispose();
    try {
      codec?.dispose();
    } catch (_) {}
  }
}
