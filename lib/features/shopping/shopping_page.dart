import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/units.dart';
import '../../data/db.dart';
import '../../main.dart';

class ShoppingPage extends StatefulWidget {
  const ShoppingPage({super.key});

  @override
  State<ShoppingPage> createState() => _ShoppingPageState();
}

class _ShoppingPageState extends State<ShoppingPage> {
  final Set<int> _selected = {};

  void _generate() {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先勾几道菜')),
      );
      return;
    }
    final rows = <({String name, double? qty, String? unit})>[];
    for (final id in _selected) {
      for (final i in appDb.ingredientsOf(id)) {
        rows.add((name: i.name, qty: i.qty, unit: i.unit));
      }
    }
    final merged = mergeIngredients(rows);
    appDb.replaceShopping([
      for (final m in merged)
        (name: m.name, qty: m.qty, unit: m.unit, group: 0),
    ]);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('生成 ' + merged.length.toString() + ' 条采购项')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('采购清单'),
        actions: [
          IconButton(
            tooltip: '清空清单',
            onPressed: () => appDb.clearShopping(),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: StreamBuilder<List<RecipeRow>>(
        stream: appDb.watchRecipes(),
        builder: (context, recSnap) {
          final recipes = recSnap.data ?? const <RecipeRow>[];
          return StreamBuilder<List<ShoppingRow>>(
            stream: appDb.watchShopping(),
            builder: (context, shopSnap) {
              final shop = shopSnap.data ?? const <ShoppingRow>[];
              final done = shop.where((s) => s.checked).length;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Text('选几道菜', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in recipes)
                        FilterChip(
                          label: Text(r.name),
                          selected: _selected.contains(r.id),
                          onSelected: (v) => setState(() {
                            if (v) {
                              _selected.add(r.id);
                            } else {
                              _selected.remove(r.id);
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _generate,
                        icon: const Icon(Icons.playlist_add_check),
                        label: const Text('生成采购清单'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => setState(_selected.clear),
                        child: const Text('清空选择'),
                      ),
                    ],
                  ),
                  const Divider(height: 28),
                  Row(
                    children: [
                      Text('清单', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(width: 8),
                      if (shop.isNotEmpty)
                        Text(done.toString() + ' / ' + shop.length.toString(),
                            style: TextStyle(color: scheme.outline)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (shop.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: Text('还没有采购项，勾几道菜点「生成采购清单」',
                            style: TextStyle(color: scheme.outline)),
                      ),
                    )
                  else
                    for (final s in shop)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: s.checked,
                        onChanged: (v) => appDb.toggleShopping(s.id, v ?? false),
                        title: Text(
                          s.name,
                          style: s.checked
                              ? TextStyle(
                                  decoration: TextDecoration.lineThrough,
                                  color: scheme.outline,
                                )
                              : null,
                        ),
                        secondary: Text(
                          kVagueUnits.contains(s.unit)
                              ? (s.unit ?? '')
                              : ((s.qty == null ? '' : formatQty(s.qty)) +
                                  (s.unit == null ? '' : ' ' + s.unit!)),
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
