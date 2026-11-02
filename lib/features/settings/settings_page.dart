import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/paths.dart';
import '../../data/backup.dart';
import '../../data/seed.dart';
import '../../main.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;
  bool _needsRestart = false;

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      final suggested = 'recipe_book_' + stamp + '.zip';
      String path;
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final loc = await getSaveLocation(suggestedName: suggested);
        if (loc == null) {
          setState(() => _busy = false);
          return;
        }
        path = loc.path;
      } else {
        final dir = await getApplicationDocumentsDirectory();
        path = p.join(dir.path, suggested);
      }
      await exportBackup(appDb, path);
      if (mounted) _snack('已导出：' + path);
    } catch (e) {
      if (mounted) _snack('导出失败：' + e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final f = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'zip', extensions: ['zip']),
    ]);
    if (f == null) return;
    setState(() => _busy = true);
    try {
      await importBackup(File(f.path), appDb);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _needsRestart = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('导入失败：' + e.toString());
    }
  }

  Future<void> _reseed() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('重置为示例菜谱？'),
        content: const Text('会删掉现有全部菜谱、记录和采购清单。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('重置')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    await reseed(appDb);
    if (mounted) {
      setState(() => _busy = false);
      _snack('已恢复示例数据');
    }
  }

  Future<void> _wipe() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('清空全部数据？'),
        content: const Text('菜谱、做菜记录、采购清单都会被删除，图片文件也会清掉。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('清空')),
        ],
      ),
    );
    if (ok != true) return;
    appDb.wipeAll();
    if (await appImageDir.exists()) {
      for (final f in appImageDir.listSync().whereType<File>()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    if (mounted) _snack('已清空');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final recipes = appDb.allRecipes();
    final images = appImageDir.existsSync() ? appImageDir.listSync().length : 0;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_needsRestart)
            Card(
              color: scheme.errorContainer,
              child: ListTile(
                leading: Icon(Icons.info_outline, color: scheme.onErrorContainer),
                title: Text('导入完成，请重启应用',
                    style: TextStyle(color: scheme.onErrorContainer)),
                subtitle: Text('数据库文件已被替换，重启后才会读到新数据',
                    style: TextStyle(color: scheme.onErrorContainer)),
              ),
            ),
          Card(
            color: scheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(child: _stat('菜谱', recipes.length.toString())),
                  Expanded(child: _stat('图片', images.toString())),
                  Expanded(
                    child: _stat(
                      '做菜记录',
                      recipes
                          .fold<int>(0, (s, r) => s + r.cookCount)
                          .toString(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('数据与备份', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Card(
            color: scheme.surfaceContainerLow,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.upload_file_outlined),
                  title: const Text('导出整库备份'),
                  subtitle: const Text('数据库 + 全部图片打包成 zip'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : _export,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('从备份导入'),
                  subtitle: const Text('覆盖当前全部数据，导入后需重启'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : _import,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.restart_alt),
                  title: const Text('恢复示例菜谱'),
                  subtitle: const Text('清空后重新灌入 8 道示例菜'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : _reseed,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
                  title: Text('清空全部数据', style: TextStyle(color: scheme.error)),
                  onTap: _busy ? null : _wipe,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('关于', style: Theme.of(context).textTheme.titleMedium),
          Card(
            color: scheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('我的食谱 v1.0.0'),
                  const SizedBox(height: 6),
                  Text('完全离线：不联网、无账号、无上传。所有菜谱、照片与记录都只保存在这台设备上。',
                      style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45)),
                  const SizedBox(height: 10),
                  Text('数据库：' + (appDb.dbFilePath ?? '内存库'),
                      style: TextStyle(fontSize: 11, color: scheme.outline)),
                  Text('图片目录：' + appImageDir.path,
                      style: TextStyle(fontSize: 11, color: scheme.outline)),
                ],
              ),
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 2),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
