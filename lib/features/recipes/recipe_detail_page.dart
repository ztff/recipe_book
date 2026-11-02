import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/paths.dart';
import '../../core/pick_image.dart';
import '../../core/units.dart';
import '../../data/db.dart';
import '../../main.dart';
import '../cook/cook_mode_page.dart';
import 'recipe_edit_page.dart';

class RecipeDetailPage extends StatefulWidget {
  const RecipeDetailPage({super.key, required this.recipeId});

  final int recipeId;

  @override
  State<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends State<RecipeDetailPage> {
  RecipeDetail? _detail;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() => _detail = appDb.detail(widget.recipeId));
  }

  Future<void> _edit() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RecipeEditPage(recipeId: widget.recipeId)),
    );
    if (changed == true && mounted) _reload();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除这道菜？'),
        content: const Text('食材、步骤和做菜记录会一起删掉，不能恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      appDb.deleteRecipe(widget.recipeId);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _pickImage({bool camera = false}) async {
    final name = await pickAndStoreImage(fromCamera: camera);
    if (name == null) return;
    appDb.setImagePath(widget.recipeId, name);
    if (mounted) _reload();
  }

  void _imageOptions() {
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (Platform.isAndroid || Platform.isIOS)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('拍一张'),
                onTap: () {
                  Navigator.pop(c);
                  _pickImage(camera: true);
                },
              ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册/文件选'),
              onTap: () {
                Navigator.pop(c);
                _pickImage();
              },
            ),
            if (_detail?.recipe.imagePath != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('移除图片'),
                onTap: () {
                  Navigator.pop(c);
                  appDb.setImagePath(widget.recipeId, null);
                  _reload();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    if (d == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('这道菜已被删除')),
      );
    }
    final r = d.recipe;
    final scheme = Theme.of(context).colorScheme;
    final hasImage = r.imagePath != null && r.imagePath!.isNotEmpty;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: hasImage ? 230 : 0,
            actions: [
              IconButton(onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
              IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline)),
            ],
            flexibleSpace: hasImage
                ? FlexibleSpaceBar(
                    background: GestureDetector(
                      onTap: _imageOptions,
                      child: Image.file(
                        File(imageFullPath(r.imagePath!)),
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => Container(color: scheme.surfaceContainerHighest),
                      ),
                    ),
                  )
                : null,
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Row(
                  children: [
                    Expanded(
                      child: Text(r.name,
                          style: Theme.of(context).textTheme.headlineSmall),
                    ),
                    if (!hasImage)
                      IconButton(
                        onPressed: _imageOptions,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                      ),
                  ],
                ),
                if (r.description != null && r.description!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(r.description!,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Meta(icon: Icons.restaurant, text: r.cuisine),
                    _Meta(icon: Icons.local_fire_department_outlined, text: r.taste),
                    _Meta(icon: Icons.schedule, text: r.minutes.toString() + ' 分钟'),
                    _Meta(icon: Icons.trending_up, text: difficultyLabel(r.difficulty)),
                    _Meta(icon: Icons.people_outline, text: r.servings.toString() + ' 人份'),
                    if (r.cookCount > 0)
                      _Meta(icon: Icons.repeat, text: '做过 ' + r.cookCount.toString() + ' 次'),
                  ],
                ),
                if (r.tags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in r.tags) Chip(label: Text(t), visualDensity: VisualDensity.compact),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                _sectionTitle(context, '食材', icon: Icons.egg_alt_outlined),
                const SizedBox(height: 8),
                ..._ingredientGroups(context, d),
                const SizedBox(height: 20),
                _sectionTitle(context, '步骤', icon: Icons.format_list_numbered),
                const SizedBox(height: 8),
                ..._stepTiles(context, d),
                if (d.logs.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _sectionTitle(context, '做过的记录', icon: Icons.history),
                  const SizedBox(height: 8),
                  for (final log in d.logs.take(5)) _logTile(context, log),
                ],
              ]),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: d.steps.isEmpty
              ? null
              : () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => CookModePage(detail: d)),
                  );
                  if (mounted) _reload();
                },
          icon: const Icon(Icons.local_fire_department),
          label: Text(d.steps.isEmpty ? '还没有步骤，先编辑' : '开始烹饪'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text, {IconData? icon}) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
        ],
        Text(text, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }

  List<Widget> _ingredientGroups(BuildContext context, RecipeDetail d) {
    final widgets = <Widget>[];
    for (final g in kIngredientGroups) {
      final items = d.ingredients.where((i) => i.grp == g).toList();
      if (items.isEmpty) continue;
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Text(g,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                )),
      ));
      for (final i in items) {
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: Text(i.name)),
              Text(
                kVagueUnits.contains(i.unit)
                    ? (i.unit ?? '')
                    : (i.qty == null && (i.unit == null || i.unit!.isEmpty)
                        ? ''
                        : (formatQty(i.qty) +
                            (i.unit == null || i.unit!.isEmpty ? '' : ' ' + i.unit!))),
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ));
      }
    }
    if (widgets.isEmpty) {
      widgets.add(Text('还没有食材',
          style: TextStyle(color: Theme.of(context).colorScheme.outline)));
    }
    return widgets;
  }

  List<Widget> _stepTiles(BuildContext context, RecipeDetail d) {
    if (d.steps.isEmpty) {
      return [
        Text('还没有步骤',
            style: TextStyle(color: Theme.of(context).colorScheme.outline)),
      ];
    }
    final scheme = Theme.of(context).colorScheme;
    return [
      for (var i = 0; i < d.steps.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Text((i + 1).toString(),
                    style: TextStyle(fontSize: 13, color: scheme.onPrimaryContainer)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.steps[i].text, style: const TextStyle(height: 1.45)),
                    if (d.steps[i].timerSeconds != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(Icons.timer_outlined, size: 14, color: scheme.primary),
                            const SizedBox(width: 4),
                            Text(_fmt(d.steps[i].timerSeconds!),
                                style: TextStyle(fontSize: 12, color: scheme.primary)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _logTile(BuildContext context, CookLogRow log) {
    final rating = log.rating ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(log.cookedAt.toLocal().toString().substring(0, 16),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 10),
          for (var i = 1; i <= 5; i++)
            Icon(i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 15,
                color: i <= rating
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outlineVariant),
          if (log.note != null && log.note!.isNotEmpty)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(log.note!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
        ],
      ),
    );
  }

  String _fmt(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return m.toString().padLeft(2, '0') + ':' + s.toString().padLeft(2, '0');
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(text,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
