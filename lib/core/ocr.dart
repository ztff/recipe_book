import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// ML Kit 只在 Android / iOS 提供离线模型；桌面端返回 false，入口会被隐藏。
bool get ocrAvailable {
  if (kIsWeb) return false;
  return Platform.isAndroid || Platform.isIOS;
}

/// 识别图片里的中文文字，失败返回 null（不抛给调用方）。
Future<String?> recognizeText(File image) async {
  if (!ocrAvailable) return null;
  TextRecognizer? recognizer;
  try {
    recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    final input = InputImage.fromFilePath(image.path);
    final result = await recognizer.processImage(input);
    final text = result.text.trim();
    return text.isEmpty ? null : text;
  } catch (e) {
    debugPrint('ocr failed: ' + e.toString());
    return null;
  } finally {
    try {
      await recognizer?.close();
    } catch (_) {}
  }
}
