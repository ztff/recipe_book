import 'package:flutter/material.dart';

/// 封面图能做的三件事。详情页不提供，只在编辑页点封面时弹出。
enum CoverAction { camera, gallery, remove }

/// 点封面弹出的操作菜单，返回 null 表示用户什么都没选（点遮罩或返回键）。
///
/// [allowCamera] 桌面端传 false——桌面没有相机，别摆个按不动的选项；
/// [hasImage] 为 false 时不显示「移除图片」，没有图可移除。
Future<CoverAction?> showCoverActions(
  BuildContext context, {
  required bool allowCamera,
  required bool hasImage,
}) {
  return showModalBottomSheet<CoverAction>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (allowCamera)
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍一张'),
              onTap: () => Navigator.pop(c, CoverAction.camera),
            ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('从相册/文件选'),
            onTap: () => Navigator.pop(c, CoverAction.gallery),
          ),
          if (hasImage)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('移除图片'),
              onTap: () => Navigator.pop(c, CoverAction.remove),
            ),
        ],
      ),
    ),
  );
}
