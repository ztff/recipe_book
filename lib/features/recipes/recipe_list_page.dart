import 'package:flutter/material.dart';

import '../../core/app_settings.dart';
import '../../core/constants.dart';
import '../../data/db.dart';
import '../../main.dart';
import '../../widgets/recipe_card.dart';
import 'recipe_detail_page.dart';
import 'recipe_edit_page.dart';

class RecipeListPage extends StatefulWidget {
  const RecipeListPage({super.key});

  @override
  State<RecipeListPage> createState() => _RecipeListPageState();
}

class _RecipeListPageState extends State<RecipeListPage> {
  final _searchCtrl = TextEditingController();
  String _q = '';
  String? _cuisine;
  int? _maxMinutes;
  String _sort = appSettings.value.defaultSort;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<RecipeRow> _filter(List<RecipeRow> rows) {
    final q = _q.trim().toLowerCase();
    final out = rows.where((r) {
      if (q.isNotEmpty) {
        final hit = r.name.toLowerCase().contains(q) ||
            r.searchKey.contains(q) ||
            r.tagsText.toLowerCase().contains(q);
        if (!hit) return false;
      }
      if (_cuisine != null && r.cuisine != _cuisine) return false;
      if (_maxMinutes != null && r.minutes > _maxMinutes!) return false;
      return true;
    }).toList();
    if (_sort == 'cook') {
      out.sort((a, b) => b.cookCount.compareTo(a.cookCount));
    } else if (_sort == 'fast') {
      out.sort((a, b) => a.minutes.compareTo(b.minutes));
    } else if (_sort == 'rating') {
      out.sort((a, b) => (b.lastRating ?? 0).compareTo(a.lastRating ?? 0));
    } else if (_sort == 'name') {
      out.sort((a, b) => a.name.compareTo(b.name));
    } else {
      out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    return out;
  }

  Future<void> _openEditor({RecipeRow? existing}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RecipeEditPage(recipeId: existing?.id)),
    );
    if (changed == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的食谱'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '排序',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'recent', child: Text('最近更新')),
              PopupMenuItem(value: 'cook', child: Text('做得多')),
              PopupMenuItem(value: 'fast', child: Text('用时短')),
              PopupMenuItem(value: 'rating', child: Text('评分高')),
              PopupMenuItem(value: 'name', child: Text('按名称')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('记一道菜'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: '搜菜名、拼音首字母或标签',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _q = '');
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                FilterChip(
                  label: const Text('全部'),
                  selected: _cuisine == null && _maxMinutes == null,
                  onSelected: (_) => setState(() {
                    _cuisine = null;
                    _maxMinutes = null;
                  }),
                ),
                const SizedBox(width: 6),
                for (final c in kCuisines) ...[
                  FilterChip(
                    label: Text(c),
                    selected: _cuisine == c,
                    onSelected: (v) => setState(() => _cuisine = v ? c : null),
                  ),
                  const SizedBox(width: 6),
                ],
                for (final m in kDurations) ...[
                  FilterChip(
                    label: Text('≤' + m.toString() + '分'),
                    selected: _maxMinutes == m,
                    onSelected: (v) => setState(() => _maxMinutes = v ? m : null),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<RecipeRow>>(
              stream: appDb.watchRecipes(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = _filter(snap.data!);
                if (rows.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.menu_book_outlined,
                            size: 48, color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 12),
                        Text(snap.data!.isEmpty ? '还没有菜谱' : '没有匹配的菜'),
                        const SizedBox(height: 12),
                        if (snap.data!.isEmpty)
                          FilledButton.icon(
                            onPressed: () => _openEditor(),
                            icon: const Icon(Icons.add),
                            label: const Text('记第一道菜'),
                          ),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    return RecipeCard(
                      recipe: r,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RecipeDetailPage(recipeId: r.id),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
