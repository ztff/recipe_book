import 'dart:io';

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/paths.dart';
import '../data/db.dart';

class RecipeCard extends StatelessWidget {
  const RecipeCard({super.key, required this.recipe, required this.onTap});

  final RecipeRow recipe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasImage = recipe.imagePath != null && recipe.imagePath!.isNotEmpty;
    return Card(
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 84,
                  height: 84,
                  child: hasImage
                      ? Image.file(
                          File(imageFullPath(recipe.imagePath!)),
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => _placeholder(scheme),
                        )
                      : _placeholder(scheme),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            recipe.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (recipe.lastRating != null)
                          Row(
                            children: [
                              Icon(Icons.star_rounded, size: 16, color: scheme.primary),
                              const SizedBox(width: 2),
                              Text(recipe.lastRating.toString(),
                                  style: Theme.of(context).textTheme.labelMedium),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      recipe.cuisine +
                          ' · ' +
                          recipe.taste +
                          ' · ' +
                          recipe.minutes.toString() +
                          ' 分钟 · ' +
                          difficultyLabel(recipe.difficulty),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final t in recipe.tags.take(3)) _MiniChip(text: t),
                        if (recipe.cookCount > 0)
                          _MiniChip(
                            text: '做过 ' +
                                recipe.cookCount.toString() +
                                ' 次' +
                                _lastText(recipe.lastCookedAt),
                            highlight: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _lastText(DateTime? d) {
    if (d == null) return '';
    final days = DateTime.now().difference(d).inDays;
    if (days <= 0) return '（今天）';
    if (days == 1) return '（昨天）';
    if (days < 30) return '（' + days.toString() + ' 天前）';
    return '（' + (days ~/ 30).toString() + ' 个月前）';
  }

  Widget _placeholder(ColorScheme scheme) => Container(
        color: scheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(Icons.ramen_dining_outlined,
            color: scheme.onSurfaceVariant, size: 28),
      );
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.text, this.highlight = false});
  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: highlight ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: highlight ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
