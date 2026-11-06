import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/app_settings.dart';
import 'core/backup.dart';
import 'core/image_migrate.dart';
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
    loadSettings();
    _log('settings loaded');
    runApp(const RecipeApp());
    _log('runApp called');
    // 都不挡启动：等第一帧画完再在后台跑
    _backgroundJobs();
  } catch (e, st) {
    _log('STARTUP_ERROR: ' + e.toString() + '\n' + st.toString());
    runApp(BootErrorApp(message: e.toString()));
  }
}

/// 距上次备份超过 [BackupService.intervalDays] 天就悄悄备一份。
///
/// 失败不打扰用户：备份是保险，不是主流程；设置页里能看到上次备份时间和
/// 手动触发，真出问题时再管。
/// 启动后的后台杂活：先整理存量图片（腾空间），再按需备份。
Future<void> _backgroundJobs() async {
  try {
    await Future<void>.delayed(const Duration(seconds: 2));
    final n = await runImageMigration(appDb);
    await _blog('migrate converted=' + n.toString());
    final gone = await runOrphanCleanup(appDb);
    await _blog('orphans removed=' + gone.toString());
  } catch (e) {
    await _blog('migrate error ' + e.toString());
  }
  await _autoBackup();
}

Future<void> _autoBackup() async {
  try {
    await Future<void>.delayed(const Duration(seconds: 3));
    await _blog('tick');
    final due = await BackupService.shouldRun(
      appDb.getSetting(BackupService.settingKey),
    );
    await _blog('due=' + due.toString());
    if (!due) return;
    final r = await BackupService.run(
      snapshot: (path) => appDb.snapshotTo(path),
      onlyImages: appDb.referencedImages(),
    );
    await _blog('ok=' + r.ok.toString() + ' where=' + (r.where ?? '-') + ' bytes=' + r.bytes.toString() + ' err=' + (r.error ?? '-'));
    if (r.ok) {
      appDb.setSetting(
        BackupService.settingKey,
        DateTime.now().toIso8601String(),
      );
      _log('backup ok -> ' + (r.where ?? ''));
    } else {
      _log('backup failed: ' + (r.error ?? '?'));
    }
  } catch (e, st) {
    await _blog('error ' + e.toString() + ' | ' + st.toString().split('\n').take(3).join(' / '));
  }
}

/// 备份流程的日志。release 包里看不到控制台，写到外部目录的 backup.log，
/// 这样出问题时 adb 能直接拉走。
Future<void> _blog(String msg) async {
  final line = DateTime.now().toIso8601String() + '  ' + msg + '\n';
  for (final dir in await _logDirs()) {
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final f = File(p.join(dir.path, 'backup.log'));
      // 只在排查问题时有用，别让它无限长
      if (f.existsSync() && f.lengthSync() > 64 * 1024) {
        f.writeAsStringSync('', flush: true);
      }
      f.writeAsStringSync(line, mode: FileMode.append, flush: true);
      return;
    } catch (_) {}
  }
}

Future<List<Directory>> _logDirs() async {
  final out = <Directory>[];
  try {
    final d = await getExternalStorageDirectory();
    if (d != null) out.add(d);
  } catch (_) {}
  out.add(appImageDir.parent);
  return out;
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
