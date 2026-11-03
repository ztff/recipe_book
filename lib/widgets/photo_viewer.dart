import 'dart:io';

import 'package:flutter/material.dart';

/// 点开图片看大图，支持双指缩放。
Future<void> showPhotoViewer(
  BuildContext context,
  String filePath, {
  String? caption,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: InteractiveViewer(
              maxScale: 5,
              child: Image.file(
                File(filePath),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('图片打不开了', style: TextStyle(color: Colors.white)),
                ),
              ),
            ),
          ),
          if (caption != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                caption,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    ),
  );
}
