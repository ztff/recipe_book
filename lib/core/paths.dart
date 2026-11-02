import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 图片目录（应用数据目录下的 images/），数据库里只存文件名，便于整库迁移。
late Directory appImageDir;

String imageFullPath(String fileName) => p.join(appImageDir.path, fileName);

bool _canWrite(Directory d) {
  try {
    d.createSync(recursive: true);
    final probe = File(p.join(d.path, '.write_probe'));
    probe.writeAsStringSync('ok');
    probe.deleteSync();
    return true;
  } catch (_) {
    return false;
  }
}

/// 解析一个真正可写的数据目录。
/// 首选各平台的「应用支持目录」；失败时依次退到 %APPDATA%、%LOCALAPPDATA%、
/// 程序所在目录下的 data_user（极少数被策略锁定的机器上仍能启动）。
Future<Directory> resolveDataDir() async {
  final env = Platform.environment;

  // 桌面端先用环境变量（同步、不经过平台通道），避免个别机器上
  // path_provider 的 COM 调用挂住或抛错。
  if (Platform.isWindows) {
    final desktopCandidates = <String>[
      if (env['APPDATA'] != null) p.join(env['APPDATA']!, 'com.yg', 'recipe_book'),
      if (env['LOCALAPPDATA'] != null) p.join(env['LOCALAPPDATA']!, 'com.yg', 'recipe_book'),
      p.join(File(Platform.resolvedExecutable).parent.path, 'data_user'),
    ];
    for (final c in desktopCandidates) {
      final d = Directory(c);
      if (_canWrite(d)) return d;
    }
  }

  try {
    final dir = await getApplicationSupportDirectory();
    if (_canWrite(dir)) return dir;
  } catch (_) {}

  final candidates = <String>[
    if (env['APPDATA'] != null) p.join(env['APPDATA']!, 'com.yg', 'recipe_book'),
    if (env['LOCALAPPDATA'] != null) p.join(env['LOCALAPPDATA']!, 'com.yg', 'recipe_book'),
    p.join(File(Platform.resolvedExecutable).parent.path, 'data_user'),
    p.join(Directory.systemTemp.path, 'recipe_book_data'),
  ];
  for (final c in candidates) {
    final d = Directory(c);
    if (_canWrite(d)) return d;
  }
  throw StateError('找不到可写的数据目录');
}
