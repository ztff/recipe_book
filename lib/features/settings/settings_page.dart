import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';


import '../../core/app_settings.dart';
import '../../core/backup.dart';
import '../../core/paths.dart';
import '../../core/theme.dart';
import '../../core/update_checker.dart';
import '../../data/backup.dart';
import '../../data/ocr_raw_store.dart';
import '../../data/seed.dart';
import '../../main.dart';
import 'ingredient_rules_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;
  bool _needsRestart = false;
  String _version = '';
  int _ocrRawCount = 0;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _refreshBackup();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 扫目录很便宜，但没必要每次 build 都扫
    _ocrRawCount = OcrRawStore.count;
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = info.version);
    } catch (_) {
      // 读不到版本号不影响其他功能
    }
  }

  void _apply(AppSettings next) {
    updateSettings(next);
    setState(() {});
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _reapplyRules() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('重新套用识别规则？'),
        content: const Text('会按当前规则重排所有菜谱的用料分组和单位，你手改过的会被覆盖。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('开始'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final ings = appDb.reapplyIngredientRules();
    final steps = appDb.normalizeStepText();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('改了 ' + ings.toString() + ' 条用料、' + steps.toString() + ' 个步骤'),
      ),
    );
  }

  bool _backupBusy = false;
String? _lastBackup;
List<BackupItem> _backupFiles = const [];

String _backupSubtitle() {
  if (_backupBusy) return '正在打包…';
  final t = BackupService.lastAt(_lastBackup);
  final when = t == null
      ? '还没备份过'
      : '上次 ' + _fmtTime(t) + '，每 ' + BackupService.intervalDays.toString() + ' 天自动一次';
  if (_backupFiles.isEmpty) {
    return when + '\n下载/recipe_book_backup 里暂无文件';
  }
  final total = _backupFiles.fold<int>(0, (a, b) => a + b.size);
  final keep = '下载/recipe_book_backup 有 ' +
      _backupFiles.length.toString() +
      ' 份，共 ' +
      _fmtSize(total) +
      '（不限份数）';
  return when + '\n' + keep;
}

String _fmtTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return t.year.toString() + '-' + two(t.month) + '-' + two(t.day) +
      ' ' + two(t.hour) + ':' + two(t.minute);
}

Future<void> _refreshBackup() async {
  final last = appDb.getSetting(BackupService.settingKey);
  final files = await BackupService.list();
  if (!mounted) return;
  setState(() {
    _lastBackup = last;
    _backupFiles = files;
  });
}

Future<void> _backupNow() async {
  setState(() => _backupBusy = true);
  final r = await BackupService.run(
    snapshot: (path) => appDb.snapshotTo(path),
    onlyImages: appDb.referencedImages(),
  );
  if (!mounted) return;
  setState(() => _backupBusy = false);
  if (r.ok) {
    appDb.setSetting(
      BackupService.settingKey,
      DateTime.now().toIso8601String(),
    );
    await _refreshBackup();
    if (!mounted) return;
    _snack('已备份到 ' + (r.where ?? '') + '（' + _fmtSize(r.bytes) + '）');
  } else {
    _snack('备份失败：' + (r.error ?? '未知原因'));
  }
}

String _fmtSize(int b) {
  if (b < 1024) return b.toString() + ' B';
  if (b < 1024 * 1024) return (b / 1024).toStringAsFixed(0) + ' KB';
  return (b / 1024 / 1024).toStringAsFixed(1) + ' MB';
}

Future<void> _exportOcrRaw() async {
    final latest = OcrRawStore.latest();
    if (latest == null) {
      _snack('还没有识别记录，先去导入一张截图');
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = await latest.readAsBytes();
      final name = p.basename(latest.path);
      final uri = await FilePicker.saveFile(
        dialogTitle: '保存识别记录',
        fileName: name,
        bytes: bytes,
        mimeType: 'application/json',
      );
      if (!mounted) return;
      setState(() => _ocrRawCount = OcrRawStore.count);
      _snack(uri == null ? '已取消保存' : '识别记录已保存，发给开发者就能定位问题');
    } catch (e) {
      if (mounted) _snack('导出失败：' + e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 应用自己不发网络请求：只是把发布页交给系统浏览器。
  Future<void> _openRelease() async {
    final ok = await openReleasePage();
    if (!mounted) return;
    if (ok) {
      _snack('已打开更新页面，看看有没有新版本');
    } else {
      _snack('打不开浏览器，手动访问 ' + kReleasePage);
    }
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    File? tmp;
    try {
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      final name = 'recipe_book_' + stamp + '.zip';
      // 先打包到临时目录，再交给系统「保存到文件」对话框，由用户决定落在哪
      final tmpDir = await getTemporaryDirectory();
      tmp = File(p.join(tmpDir.path, name));
      await exportBackup(appDb, tmp.path);
      final bytes = await tmp.readAsBytes();
      final uri = await FilePicker.saveFile(
        dialogTitle: '保存备份文件',
        fileName: name,
        bytes: bytes,
        mimeType: 'application/zip',
      );
      if (!mounted) return;
      if (uri == null) {
        _snack('已取消保存');
      } else {
        _snack('备份已保存，请自行放到网盘或另一台设备上');
      }
    } catch (e) {
      if (mounted) _snack('导出失败：' + e.toString());
    } finally {
      try {
        if (tmp != null && await tmp.exists()) await tmp.delete();
      } catch (_) {}
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final res = await FilePicker.pickFiles(
      dialogTitle: '选择备份文件',
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (res.isEmpty) return;
    final picked = res.first.path;
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      await importBackup(File(picked), appDb);
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
        content: const Text('会删掉现有全部菜谱、记录、采购清单和图片文件。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('重置')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    await reseed(appDb);
    if (await appImageDir.exists()) {
      for (final f in appImageDir.listSync().whereType<File>()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
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
    final s = appSettings.value;
    // 导入后数据库句柄已关闭，此时不能再查询，直接给重启提示页
    if (_needsRestart) {
      return Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, size: 56, color: scheme.primary),
                const SizedBox(height: 18),
                Text('导入完成', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                const Text('备份已覆盖本地数据库，需要重新打开应用才会生效。',
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => SystemNavigator.pop(),
                  icon: const Icon(Icons.power_settings_new),
                  label: const Text('立即退出'),
                ),
                const SizedBox(height: 10),
                Text('退出后手动打开应用即可看到恢复的数据',
                    style: TextStyle(fontSize: 12, color: scheme.outline)),
              ],
            ),
          ),
        ),
      );
    }
    int recipeCount = 0;
    int cookCount = 0;
    try {
      final recipes = appDb.allRecipes();
      recipeCount = recipes.length;
      cookCount = recipes.fold<int>(0, (s, r) => s + r.cookCount);
    } catch (_) {}
    // 按数据库引用数算，不是目录文件数：备份里只打被引用的，
    // 两个数字要能对得上，不然看到「图片 30」而备份只有 28 会把人搞糊涂。
    final images = appDb.referencedImages().length;
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
                  Expanded(child: _stat('菜谱', recipeCount.toString())),
                  Expanded(child: _stat('图片', images.toString())),
                  Expanded(
                    child: _stat('做菜记录', cookCount.toString()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('识别', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Card(
            color: scheme.surfaceContainerLow,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.rule_outlined),
                  title: const Text('识别规则'),
                  subtitle: const Text('哪些算调料、没写单位时按什么勺算'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const IngredientRulesPage(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.sync_outlined),
                  title: const Text('重新套用规则'),
                  subtitle: const Text('按当前规则重排已有用料的分组和单位'),
                  onTap: _reapplyRules,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('导出识别记录'),
                  subtitle: Text(_ocrRawCount == 0
                      ? '还没识别过；识别一次后会留档，出问题可导出排查'
                      : '最近 ' + _ocrRawCount.toString() + ' 次识别的原始行'),
                  onTap: _busy ? null : _exportOcrRaw,
                ),
              ],
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
                  leading: const Icon(Icons.history),
                  title: const Text('备份到 Download'),
                  subtitle: Text(_backupSubtitle()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy || _backupBusy ? null : _backupNow,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.upload_file_outlined),
                  title: const Text('导出整库备份'),
                  subtitle: const Text('自己选保存位置'),
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
          Text('外观', style: Theme.of(context).textTheme.titleMedium),
          Card(
            color: scheme.surfaceContainerLow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Text('主题模式', style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: SegmentedButton<AppThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: AppThemeMode.system, label: Text('跟随系统')),
                      ButtonSegment(value: AppThemeMode.light, label: Text('浅色')),
                      ButtonSegment(value: AppThemeMode.dark, label: Text('深色')),
                    ],
                    selected: {s.themeMode},
                    onSelectionChanged: (v) => _apply(s.copyWith(themeMode: v.first)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Text('主题色',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < kSeedColors.length; i++)
                        Tooltip(
                          message: kSeedColors[i].$2,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => _apply(s.copyWith(seedIndex: i)),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: kSeedColors[i].$1,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  width: s.seedIndex == i ? 3 : 0,
                                  color: scheme.onSurface,
                                ),
                              ),
                              child: s.seedIndex == i
                                  ? const Icon(Icons.check, size: 18, color: Colors.white)
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.format_size),
                  title: Text('字号  ' + (s.textScale * 100).round().toString() + '%'),
                  subtitle: Slider(
                    value: s.textScale,
                    min: 0.85,
                    max: 1.35,
                    divisions: 10,
                    label: (s.textScale * 100).round().toString() + '%',
                    onChanged: (v) => _apply(s.copyWith(textScale: v)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('烹饪模式', style: Theme.of(context).textTheme.titleMedium),
          Card(
            color: scheme.surfaceContainerLow,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.screen_lock_portrait_outlined),
                  title: const Text('保持屏幕常亮'),
                  subtitle: const Text('做菜时不让屏幕自动熄灭'),
                  value: s.keepAwake,
                  onChanged: (v) => _apply(s.copyWith(keepAwake: v)),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.volume_up_outlined),
                  title: const Text('计时到点响提示音'),
                  value: s.timerSound,
                  onChanged: (v) => _apply(s.copyWith(timerSound: v)),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.vibration),
                  title: const Text('计时到点震动'),
                  subtitle: const Text('手机端生效'),
                  value: s.timerVibrate,
                  onChanged: (v) => _apply(s.copyWith(timerVibrate: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('截图识别', style: Theme.of(context).textTheme.titleMedium),
          Card(
            color: scheme.surfaceContainerLow,
            child: const ListTile(
              leading: Icon(Icons.auto_awesome_outlined),
              title: Text('本地 PaddleOCR'),
              subtitle: Text('PP-OCRv4 模型随安装包一起放着，识别全在手机上完成，不联网。'
                  '长图会先分片再逐片识别，约 10 秒。'),
            ),
          ),
          const SizedBox(height: 20),
          Text('菜谱列表', style: Theme.of(context).textTheme.titleMedium),
          Card(
            color: scheme.surfaceContainerLow,
            child: ListTile(
              leading: const Icon(Icons.sort),
              title: const Text('默认排序'),
              subtitle: Text(kSortOptions
                  .firstWhere((o) => o.$1 == s.defaultSort,
                      orElse: () => kSortOptions.first)
                  .$2),
              trailing: DropdownButton<String>(
                value: s.defaultSort,
                underline: const SizedBox.shrink(),
                items: [
                  for (final o in kSortOptions)
                    DropdownMenuItem(value: o.$1, child: Text(o.$2)),
                ],
                onChanged: (v) {
                  if (v != null) _apply(s.copyWith(defaultSort: v));
                },
              ),
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(_version.isEmpty
                            ? '我的食谱'
                            : '我的食谱 v' + _version),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _openRelease,
                        child: const Text('获取更新'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('完全离线：不联网、无账号、无上传。所有菜谱、照片与记录都只保存在这台设备上。'
                      '「获取更新」只是交给浏览器打开发布页，应用自己不联网。',
                      style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45)),
                  const SizedBox(height: 6),
                  Text('本项目代码由 AI 辅助编写，以 MIT 协议开源。',
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
