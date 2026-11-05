import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../data/db.dart';
import '../../main.dart';

/// 识别规则维护：某个食材归主料/辅料/调料，以及没写单位时补什么。
/// 这些在识别完截图后会被自动套用。
class IngredientRulesPage extends StatefulWidget {
  const IngredientRulesPage({super.key});

  @override
  State<IngredientRulesPage> createState() => _IngredientRulesPageState();
}

class _IngredientRulesPageState extends State<IngredientRulesPage> {
  final _search = TextEditingController();
  String _filter = '全部';
  List<IngredientRuleRow> _rows = const [];
  bool _loading = true;

  static const _filters = ['全部', '主料', '辅料', '调料', '自定义'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _load() {
    setState(() {
      _rows = appDb.ingredientRules(keyword: _search.text);
      _loading = false;
    });
  }

  List<IngredientRuleRow> get _visible {
    switch (_filter) {
      case '主料':
      case '辅料':
      case '调料':
        return _rows.where((e) => e.grp == _filter).toList();
      case '自定义':
        return _rows.where((e) => !e.builtin).toList();
      default:
        return _rows;
    }
  }

  Future<void> _edit({IngredientRuleRow? row}) async {
    final nameCtrl = TextEditingController(text: row?.name ?? '');
    var grp = row?.grp ?? '调料';
    var unit = row?.unit ?? '';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(row == null ? '新增规则' : '编辑规则'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '食材名',
                    hintText: '例如 生抽',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
                const Text('归到哪一组'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final g in [...kIngredientGroups, '不管'])
                      ChoiceChip(
                        label: Text(g),
                        selected: (g == '不管' ? '' : g) == grp,
                        onSelected: (_) =>
                            setLocal(() => grp = g == '不管' ? '' : g),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('没写单位时补什么'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    for (final u in ['不管', ...kUnits])
                      ChoiceChip(
                        label: Text(u),
                        selected: (u == '不管' ? '' : u) == unit,
                        onSelected: (_) =>
                            setLocal(() => unit = u == '不管' ? '' : u),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            if (row != null && !row.builtin)
              TextButton(
                onPressed: () {
                  appDb.deleteIngredientRule(row.id);
                  Navigator.of(ctx).pop(false);
                },
                child: Text('删除', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      appDb.saveIngredientRule(
        name: nameCtrl.text,
        grp: grp,
        unit: unit,
        enabled: row?.enabled ?? true,
      );
    }
    nameCtrl.dispose();
    if (mounted) _load();
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('恢复内置规则？'),
        content: const Text('你新增和改过的规则都会丢掉，回到出厂状态。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    appDb.resetIngredientRules();
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('识别规则'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'reset') _reset();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'reset', child: Text('恢复内置规则')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      hintText: '搜食材名',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (_) => _load(),
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final f in _filters)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(f),
                            selected: _filter == f,
                            onSelected: (_) => setState(() => _filter = f),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: _visible.isEmpty
                      ? Center(
                          child: Text(
                            '没有匹配的规则',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _visible.length,
                          itemBuilder: (context, i) {
                            final r = _visible[i];
                            final bits = <String>[
                              if (r.grp.isNotEmpty) r.grp,
                              if (r.unit.isNotEmpty) '默认 ' + r.unit,
                            ];
                            return ListTile(
                              dense: true,
                              title: Text(r.name),
                              subtitle: Text(
                                bits.isEmpty ? '不分组，不补单位' : bits.join(' · '),
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: Switch(
                                value: r.enabled,
                                onChanged: (v) {
                                  appDb.setIngredientRuleEnabled(r.id, v);
                                  _load();
                                },
                              ),
                              onTap: () => _edit(row: r),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
