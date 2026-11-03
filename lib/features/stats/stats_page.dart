import 'package:flutter/material.dart';

import '../../main.dart';

/// 做菜统计：数量、次数、平均分、最常做的菜、最近记录。
class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = appDb.queryStats();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('统计')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Row(
            children: [
              _cell(context, '菜谱', s.totalRecipes.toString()),
              _cell(context, '做过', s.totalCooks.toString() + ' 次'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _cell(
                context,
                '平均分',
                s.averageRating == null
                    ? '—'
                    : s.averageRating!.toStringAsFixed(1),
              ),
              _cell(context, '近 30 天', s.cookedLast30Days.toString() + ' 次'),
            ],
          ),
          const SizedBox(height: 24),
          Text('最常做', style: Theme.of(context).textTheme.titleMedium),
          Card(
            color: scheme.surfaceContainerLow,
            child: s.topRecipes.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('还没有做过的菜'),
                  )
                : Column(
                    children: [
                      for (final t in s.topRecipes)
                        ListTile(
                          dense: true,
                          title: Text(t.name),
                          trailing: Text(t.count.toString() + ' 次'),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 20),
          Text('最近记录', style: Theme.of(context).textTheme.titleMedium),
          Card(
            color: scheme.surfaceContainerLow,
            child: s.recentCooks.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('还没有记录'),
                  )
                : Column(
                    children: [
                      for (final c in s.recentCooks)
                        ListTile(
                          dense: true,
                          title: Text(c.name),
                          subtitle: Text(
                            DateTime.fromMillisecondsSinceEpoch(c.at)
                                .toLocal()
                                .toString()
                                .substring(0, 16),
                          ),
                          trailing: c.rating == null
                              ? null
                              : Text('★' * c.rating!),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Card(
        color: scheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
