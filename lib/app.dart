import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'features/recipes/recipe_list_page.dart';
import 'features/settings/settings_page.dart';
import 'features/shopping/shopping_page.dart';

class RecipeApp extends StatelessWidget {
  const RecipeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '我的食谱',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomeShell(),
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
            NavigationDestination(icon: Icon(Icons.settings_outlined), label: '设置'),
          ],
        ),
      );
    });
  }
}
