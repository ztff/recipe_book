import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/paths.dart';
import '../../widgets/photo_viewer.dart';
import '../../core/pick_image.dart';
import '../../core/servings_scale.dart';
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

  /// 份量缩放。null 表示按菜谱原始份量显示；退出页面就丢，
  /// 数据库里的配方永远不动。
  int? _servingsOverride;

  int get _shownServings =>
      _servingsOverride ?? _detail?.recipe.servings ?? 2;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _detail = appDb.detail(widget.recipeId);
      _servingsOverride = null;
    });
  }

  void _bumpServings(int delta) {
    final base = _detail?.recipe.servings ?? 2;
    final next = (_shownServings + delta).clamp(kMinServings, kMaxServings);
    setState(() {
      // 转回原始份量就清掉覆盖值，避免显示「2 人份」却是被换算过的状态
      _servingsOverride = next == base ? null : next;
    });
  }

  Future<void> _edit() async {
    final savedId = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => RecipeEditPage(recipeId: widget.recipeId)),
    );
    if (savedId != null && mounted) _reload();
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
      final imgs = appDb.deleteRecipe(widget.recipeId);
      for (final n in imgs) {
        await deleteImageQuietly(n);
      }
      if (mounted) Navigator.of(context).pop();
    }
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
                      onTap: () => showPhotoViewer(
                        context,
                        imageFullPath(r.imagePath!),
                        caption: r.name,
                      ),
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
                    _Meta(
                        icon: Icons.people_outline,
                        text: _shownServings.toString() + ' 人份'),
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
                _sectionTitle(
                  context,
                  '食材',
                  icon: Icons.egg_alt_outlined,
                  trailing: _servingsStepper(context, d),
                ),
                const SizedBox(height: 8),
                ..._ingredientGroups(context, d),
                const SizedBox(height: 20),
                _sectionTitle(context, '步骤', icon: Icons.format_list_numbered),
                const SizedBox(height: 8),
                ..._stepTiles(context, d),
                if (r.tips != null && r.tips!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _sectionTitle(context, '小贴士', icon: Icons.lightbulb_outline),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      r.tips!.trim(),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
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

  Widget _sectionTitle(BuildContext context, String text,
      {IconData? icon, Widget? trailing}) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
        ],
        Text(text, style: Theme.of(context).textTheme.titleMedium),
        if (trailing != null) ...[const Spacer(), trailing],
      ],
    );
  }

  /// 食材标题右侧的份量调节。减到原始份量时把覆盖值清掉。
  Widget _servingsStepper(BuildContext context, RecipeDetail d) {
    final scheme = Theme.of(context).colorScheme;
    final base = d.recipe.servings;
    final cur = _shownServings;
    final changed = cur != base;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          padding: EdgeInsets.zero,
          iconSize: 18,
          onPressed: cur > kMinServings ? () => _bumpServings(-1) : null,
          icon: const Icon(Icons.remove_circle_outline),
          tooltip: '减少份量',
        ),
        Text(
          cur.toString() + ' 人份',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: changed ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: changed ? FontWeight.w600 : null,
              ),
        ),
        if (changed)
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 34),
            padding: EdgeInsets.zero,
            iconSize: 16,
            onPressed: () => setState(() => _servingsOverride = null),
            icon: const Icon(Icons.restart_alt),
            tooltip: '回到原始份量',
          ),
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          padding: EdgeInsets.zero,
          iconSize: 18,
          onPressed: cur < kMaxServings ? () => _bumpServings(1) : null,
          icon: const Icon(Icons.add_circle_outline),
          tooltip: '增加份量',
        ),
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
                scaledQtyText(
                    i.qty, i.unit, d.recipe.servings, _shownServings),
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
                    Text(
                      d.steps[i].text,
                      style: const TextStyle(height: 1.45),
                    ),
                    if (d.steps[i].imagePath != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: GestureDetector(
                          onTap: () => showPhotoViewer(
                            context,
                            imageFullPath(d.steps[i].imagePath!),
                            caption: '第 ' + (i + 1).toString() + ' 步',
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(
                              File(imageFullPath(d.steps[i].imagePath!)),
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ),
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
