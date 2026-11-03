import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'vocab.dart';

/// 原生 PaddleOCR 通道（PP-OCRv4 det + rec 跑在 ONNX Runtime 上）。
const MethodChannel _ocrChannel = MethodChannel('yg/ocr');

/// 当前正在跑的任务的进度回调；原生侧分片完成一片就回报一次。
OcrProgress? _activeProgress;
int _lastTotal = 0;

void _ensureProgressBridge() {
  if (_bridgeReady) return;
  _bridgeReady = true;
  _ocrChannel.setMethodCallHandler((call) async {
    if (call.method == 'progress') {
      final args = call.arguments;
      if (args is Map) {
        final done = (args['done'] as num?)?.toInt() ?? 0;
        final total = (args['total'] as num?)?.toInt() ?? 1;
        _lastTotal = total;
        _activeProgress?.call(done, total);
      }
    }
    return null;
  });
}

bool _bridgeReady = false;

/// 当前只有 Android 侧接了本地 OCR 模型；桌面端入口会被隐藏。
bool get ocrAvailable {
  if (kIsWeb) return false;
  return Platform.isAndroid;
}

/// Flutter 解码图片时最长边封顶 8192，超过会被等比缩小。
/// 裁剪配图时要按这个比例把原图坐标换算回去。
const int kMaxDecodeSide = 8192;

typedef OcrProgress = void Function(int done, int total);

/// 一行识别结果，带它在整张图里的位置。
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
/// 分片、检测、识别都在原生侧完成，不经过 Flutter 解码，
/// 所以不受 8192px 降采样的限制。
Future<OcrLayout?> recognizeLayout(
  File image, {
  OcrProgress? onProgress,
  bool highAccuracy = true,
}) async {
  if (!ocrAvailable) return null;
  return recognizeLayoutNative(image, onProgress: onProgress);
}

/// 走原生 PP-OCRv4。
Future<OcrLayout?> recognizeLayoutNative(
  File image, {
  OcrProgress? onProgress,
}) async {
  try {
    _ensureProgressBridge();
    _activeProgress = onProgress;
    _lastTotal = 1;
    onProgress?.call(0, 1);
    final raw = await _ocrChannel.invokeMapMethod<String, dynamic>(
      'recognize',
      {'path': image.path},
    );
    onProgress?.call(
      _lastTotal > 0 ? _lastTotal : 1,
      _lastTotal > 0 ? _lastTotal : 1,
    );
    _activeProgress = null;
    if (raw == null) return null;
    final width = (raw['width'] as num?)?.toInt() ?? 0;
    final height = (raw['height'] as num?)?.toInt() ?? 0;
    final list = (raw['lines'] as List?) ?? const [];
    final lines = <OcrLine>[];
    for (final item in list) {
      if (item is! Map) continue;
      final text = (item['text'] as String?)?.trim() ?? '';
      if (text.isEmpty) continue;
      lines.add(OcrLine(
        text: fixTypos(text),
        left: (item['left'] as num).toDouble(),
        top: (item['top'] as num).toDouble(),
        right: (item['right'] as num).toDouble(),
        bottom: (item['bottom'] as num).toDouble(),
      ));
    }
    if (lines.isEmpty) return null;
    debugPrint('ocr native: ' +
        width.toString() +
        'x' +
        height.toString() +
        ' lines: ' +
        lines.length.toString());
    return OcrLayout(
      lines: _tidy(lines),
      width: width > 0 ? width : 1,
      height: height > 0 ? height : 1,
    );
  } catch (e) {
    debugPrint('ocr native failed: ' + e.toString());
    return null;
  }
}

/// 兼容旧调用点。
Future<OcrText?> recognizeText(File image, {OcrProgress? onProgress}) async {
  final layout = await recognizeLayout(image, onProgress: onProgress);
  if (layout == null) return null;
  return OcrText(layout.plainText, downscaled: layout.downscaled);
}

/// 按 y 排序 + 去掉相邻重复行。
List<OcrLine> _tidy(List<OcrLine> lines) {
  final sorted = [...lines]..sort((a, b) {
      final d = a.top.compareTo(b.top);
      if (d != 0) return d;
      return a.left.compareTo(b.left);
    });
  final out = <OcrLine>[];
  for (final line in sorted) {
    final dup = out.any((e) =>
        (e.top - line.top).abs() < 20 &&
        (e.left - line.left).abs() < 20 &&
        e.text == line.text);
    if (!dup) out.add(line);
  }
  return out;
}

Future<Uint8List> _encodePng(ui.Image img) async {
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<Uint8List> _cropToPng(ui.Image src, int top, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final srcRect = ui.Rect.fromLTWH(
    0,
    top.toDouble(),
    src.width.toDouble(),
    height.toDouble(),
  );
  final dstRect = ui.Rect.fromLTWH(
    0,
    0,
    src.width.toDouble(),
    height.toDouble(),
  );
  canvas.drawImageRect(src, srcRect, dstRect, ui.Paint());
  final picture = recorder.endRecording();
  final cropped = await picture.toImage(src.width, height);
  try {
    return await _encodePng(cropped);
  } finally {
    cropped.dispose();
    picture.dispose();
  }
}

/// 把原图上的一段纵向区域裁出来存成图片文件。
///
/// [top] / [bottom] 用的是原图像素坐标（和 [recognizeLayout] 返回的坐标一致）。
/// 原图高度超过 8192 时 Flutter 解码会等比缩小，这里按 [sourceHeight] 换算回去。
Future<bool> cropRegionToFile(
  File source,
  double top,
  double bottom,
  String destPath, {
  int? sourceHeight,
}) async {
  ui.Codec? codec;
  ui.Image? img;
  try {
    codec = await ui.instantiateImageCodec(await source.readAsBytes());
    img = (await codec.getNextFrame()).image;
    final scale = (sourceHeight != null && sourceHeight > 0)
        ? img.height / sourceHeight
        : 1.0;
    final t = (top * scale).round().clamp(0, img.height - 1);
    final b = (bottom * scale).round().clamp(t + 1, img.height);
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
