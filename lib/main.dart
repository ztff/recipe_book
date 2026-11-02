import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/paths.dart';
import 'core/theme.dart';
import 'data/db.dart';
import 'data/seed.dart';

late final AppDb appDb;

/// 启动期日志：写到可执行文件旁边，便于排查"窗口一闪就没"的问题。
void _log(String msg) {
  try {
    final dir = File(Platform.resolvedExecutable).parent.path;
    final f = File(p.join(dir, 'startup.log'));
    f.writeAsStringSync(
      DateTime.now().toIso8601String() + '  ' + msg + '\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _log('main start');
  try {
    final dataDir = await resolveDataDir();
    _log('dataDir=' + dataDir.path);
    appImageDir = Directory(p.join(dataDir.path, 'images'));
    await appImageDir.create(recursive: true);
    _log('imageDir ready');
    appDb = await AppDb.open(dataDir: dataDir);
    _log('db opened at ' + (appDb.dbFilePath ?? '?'));
    final seeded = await ensureSeed(appDb);
    _log('seed=' + seeded.toString());
    runApp(const RecipeApp());
    _log('runApp called');
  } catch (e, st) {
    _log('STARTUP_ERROR: ' + e.toString() + '\n' + st.toString());
    runApp(BootErrorApp(message: e.toString()));
  }
}

class BootErrorApp extends StatelessWidget {
  const BootErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              const Text('启动失败', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 8),
              SelectableText(message),
              const SizedBox(height: 16),
              const Text('详细堆栈已写入程序目录下的 startup.log'),
            ],
          ),
        ),
      ),
    );
  }
}
