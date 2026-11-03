import 'package:flutter/material.dart';

import 'core/app_settings.dart';
import 'core/theme.dart';
import 'features/recipes/recipe_list_page.dart';
import 'features/settings/settings_page.dart';
import 'features/shopping/shopping_page.dart';
import 'features/stats/stats_page.dart';

class RecipeApp extends StatelessWidget {
  const RecipeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppSettings>(
      valueListenable: appSettings,
      builder: (context, s, _) => MaterialApp(
        title: '我的食谱',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light, seed: s.seedColor),
        darkTheme: buildTheme(Brightness.dark, seed: s.seedColor),
        themeMode: s.flutterMode,
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.linear(s.textScale)),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const HomeShell(),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _pages = [
    RecipeListPage(),
    ShoppingPage(),
    StatsPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 900;
      if (wide) {
        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                labelType: NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Icon(Icons.menu_book, color: Theme.of(context).colorScheme.primary),
                ),
                destinations: const [
                  NavigationRailDestination(
                      icon: Icon(Icons.restaurant_menu), label: Text('菜谱')),
                  NavigationRailDestination(
                      icon: Icon(Icons.shopping_basket_outlined), label: Text('采购')),
                  NavigationRailDestination(
                      icon: Icon(Icons.insights_outlined), label: Text('统计')),
                  NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined), label: Text('设置')),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: IndexedStack(index: _index, children: _pages),
              ),
            ],
          ),
        );
      }
      return Scaffold(
        body: IndexedStack(index: _index, children: _pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.restaurant_menu), label: '菜谱'),
            NavigationDestination(icon: Icon(Icons.shopping_basket_outlined), label: '采购'),
            NavigationDestination(icon: Icon(Icons.insights_outlined), label: '统计'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), label: '设置'),
          ],
        ),
      );
    });
  }
}
