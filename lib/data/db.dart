import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../core/paths.dart';

class RecipeRow {
  RecipeRow({
    required this.id,
    required this.name,
    required this.searchKey,
    this.description,
    required this.cuisine,
    required this.taste,
    required this.difficulty,
    required this.minutes,
    required this.servings,
    this.imagePath,
    required this.tagsText,
    required this.cookCount,
    this.lastCookedAt,
    this.lastRating,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final String searchKey;
  final String? description;
  final String cuisine;
  final String taste;
  final int difficulty;
  final int minutes;
  final int servings;
  final String? imagePath;
  final String tagsText;
  final int cookCount;
  final DateTime? lastCookedAt;
  final int? lastRating;
  final DateTime createdAt;
  final DateTime updatedAt;

  List<String> get tags =>
      tagsText.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  factory RecipeRow.fromRow(Row r) => RecipeRow(
        id: r['id'] as int,
        name: r['name'] as String,
        searchKey: (r['search_key'] as String?) ?? '',
        description: r['description'] as String?,
        cuisine: (r['cuisine'] as String?) ?? '家常',
        taste: (r['taste'] as String?) ?? '咸鲜',
        difficulty: (r['difficulty'] as int?) ?? 1,
        minutes: (r['minutes'] as int?) ?? 30,
        servings: (r['servings'] as int?) ?? 2,
        imagePath: r['image_path'] as String?,
        tagsText: (r['tags_text'] as String?) ?? '',
        cookCount: (r['cook_count'] as int?) ?? 0,
        lastCookedAt: _dt(r['last_cooked_at']),
        lastRating: r['last_rating'] as int?,
        createdAt: _dt(r['created_at']) ?? DateTime.now(),
        updatedAt: _dt(r['updated_at']) ?? DateTime.now(),
      );
}

DateTime? _dt(Object? v) => v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);

class IngredientRow {
  IngredientRow({
    required this.id,
    required this.recipeId,
    required this.grp,
    required this.name,
    this.qty,
    this.unit,
    required this.position,
  });

  final int id;
  final int recipeId;
  final String grp;
  final String name;
  final double? qty;
  final String? unit;
  final int position;

  factory IngredientRow.fromRow(Row r) => IngredientRow(
        id: r['id'] as int,
        recipeId: r['recipe_id'] as int,
        grp: (r['grp'] as String?) ?? '主料',
        name: r['name'] as String,
        qty: (r['qty'] as num?)?.toDouble(),
        unit: r['unit'] as String?,
        position: (r['position'] as int?) ?? 0,
      );
}

class StepRow {
  StepRow({
    required this.id,
    required this.recipeId,
    required this.position,
    required this.text,
    this.timerSeconds,
  });

  final int id;
  final int recipeId;
  final int position;
  final String text;
  final int? timerSeconds;

  factory StepRow.fromRow(Row r) => StepRow(
        id: r['id'] as int,
        recipeId: r['recipe_id'] as int,
        position: (r['position'] as int?) ?? 0,
        text: r['text'] as String,
        timerSeconds: r['timer_seconds'] as int?,
      );
}

class CookLogRow {
  CookLogRow({required this.id, required this.recipeId, required this.cookedAt, this.rating, this.note});
  final int id;
  final int recipeId;
  final DateTime cookedAt;
  final int? rating;
  final String? note;

  factory CookLogRow.fromRow(Row r) => CookLogRow(
        id: r['id'] as int,
        recipeId: r['recipe_id'] as int,
        cookedAt: _dt(r['cooked_at']) ?? DateTime.now(),
        rating: r['rating'] as int?,
        note: r['note'] as String?,
      );
}

class ShoppingRow {
  ShoppingRow({required this.id, required this.name, this.qty, this.unit, required this.checked, required this.sortGroup});
  final int id;
  final String name;
  final double? qty;
  final String? unit;
  final bool checked;
  final int sortGroup;

  factory ShoppingRow.fromRow(Row r) => ShoppingRow(
        id: r['id'] as int,
        name: r['name'] as String,
        qty: (r['qty'] as num?)?.toDouble(),
        unit: r['unit'] as String?,
        checked: ((r['checked'] as int?) ?? 0) == 1,
        sortGroup: (r['sort_group'] as int?) ?? 0,
      );
}

class RecipeDetail {
  RecipeDetail({required this.recipe, required this.ingredients, required this.steps, required this.logs});
  final RecipeRow recipe;
  final List<IngredientRow> ingredients;
  final List<StepRow> steps;
  final List<CookLogRow> logs;
}

class DraftIngredient {
  DraftIngredient({required this.name, this.grp = '主料', this.qty, this.unit});
  final String name;
  final String grp;
  final double? qty;
  final String? unit;
}

class DraftStep {
  DraftStep({required this.text, this.timerSeconds});
  final String text;
  final int? timerSeconds;
}

class RecipeDraft {
  RecipeDraft({
    this.id,
    required this.name,
    this.description,
    this.cuisine = '家常',
    this.taste = '咸鲜',
    this.difficulty = 1,
    this.minutes = 30,
    this.servings = 2,
    this.imagePath,
    this.tags = const [],
    required this.ingredients,
    required this.steps,
  });

  final int? id;
  final String name;
  final String? description;
  final String cuisine;
  final String taste;
  final int difficulty;
  final int minutes;
  final int servings;
  final String? imagePath;
  final List<String> tags;
  final List<DraftIngredient> ingredients;
  final List<DraftStep> steps;
}

class AppDb {
  AppDb._(this._db) {
    _db.execute('PRAGMA foreign_keys = ON');
    _migrate();
  }

  final Database _db;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  String? dbFilePath;

  static Future<AppDb> open({Directory? dataDir}) async {
    final dir = dataDir ?? await resolveDataDir();
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'recipe_book.sqlite'));
    final instance = AppDb._(sqlite3.open(file.path));
    instance.dbFilePath = file.path;
    return instance;
  }

  /// 测试/临时库用（内存）
  factory AppDb.memory() => AppDb._(sqlite3.openInMemory());

  void _migrate() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS recipes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        search_key TEXT NOT NULL DEFAULT '',
        description TEXT,
        cuisine TEXT NOT NULL DEFAULT '家常',
        taste TEXT NOT NULL DEFAULT '咸鲜',
        difficulty INTEGER NOT NULL DEFAULT 1,
        minutes INTEGER NOT NULL DEFAULT 30,
        servings INTEGER NOT NULL DEFAULT 2,
        image_path TEXT,
        tags_text TEXT NOT NULL DEFAULT '',
        cook_count INTEGER NOT NULL DEFAULT 0,
        last_cooked_at INTEGER,
        last_rating INTEGER,
        created_at INTEGER,
        updated_at INTEGER
      );
      CREATE TABLE IF NOT EXISTS ingredients (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recipe_id INTEGER NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
        grp TEXT NOT NULL DEFAULT '主料',
        name TEXT NOT NULL,
        qty REAL,
        unit TEXT,
        position INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE IF NOT EXISTS steps (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recipe_id INTEGER NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
        position INTEGER NOT NULL DEFAULT 0,
        text TEXT NOT NULL,
        timer_seconds INTEGER
      );
      CREATE TABLE IF NOT EXISTS cook_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recipe_id INTEGER NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
        cooked_at INTEGER,
        rating INTEGER,
        note TEXT
      );
      CREATE TABLE IF NOT EXISTS shopping_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        qty REAL,
        unit TEXT,
        checked INTEGER NOT NULL DEFAULT 0,
        sort_group INTEGER NOT NULL DEFAULT 0
      );
      CREATE INDEX IF NOT EXISTS idx_ing_recipe ON ingredients(recipe_id);
      CREATE INDEX IF NOT EXISTS idx_step_recipe ON steps(recipe_id);
      CREATE INDEX IF NOT EXISTS idx_log_recipe ON cook_logs(recipe_id);
    ''');
  }

  void _ping() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Stream<List<T>> _watch<T>(List<T> Function() query) async* {
    yield query();
    await for (final _ in _changes.stream) {
      yield query();
    }
  }

  Stream<List<RecipeRow>> watchRecipes() => _watch(queryRecipes);

  List<RecipeRow> queryRecipes({
    String search = '',
    String? cuisine,
    String? tag,
    int? maxMinutes,
    String sort = 'recent',
  }) {
    final where = <String>[];
    final args = <Object?>[];
    if (search.trim().isNotEmpty) {
      final q = '%' + search.trim().toLowerCase() + '%';
      where.add('(search_key LIKE ? OR lower(name) LIKE ? OR tags_text LIKE ?)');
      args.addAll([q, q, q]);
    }
    if (cuisine != null && cuisine.isNotEmpty) {
      where.add('cuisine = ?');
      args.add(cuisine);
    }
    if (tag != null && tag.isNotEmpty) {
      where.add("(',' || tags_text || ',') LIKE ?");
      args.add('%,' + tag + ',%');
    }
    if (maxMinutes != null) {
      where.add('minutes <= ?');
      args.add(maxMinutes);
    }
    final orderBy = switch (sort) {
      'cook' => 'cook_count DESC, name ASC',
      'fast' => 'minutes ASC, name ASC',
      'rating' => 'last_rating DESC NULLS LAST, name ASC',
      _ => 'updated_at DESC, name ASC',
    };
    final sql = StringBuffer('SELECT * FROM recipes');
    if (where.isNotEmpty) sql.write(' WHERE ' + where.join(' AND '));
    sql.write(' ORDER BY ' + orderBy);
    return _db.select(sql.toString(), args).map(RecipeRow.fromRow).toList();
  }

  RecipeRow? recipeById(int id) {
    final rows = _db.select('SELECT * FROM recipes WHERE id = ?', [id]);
    return rows.isEmpty ? null : RecipeRow.fromRow(rows.first);
  }

  RecipeDetail? detail(int id) {
    final r = recipeById(id);
    if (r == null) return null;
    return RecipeDetail(
      recipe: r,
      ingredients: _db
          .select('SELECT * FROM ingredients WHERE recipe_id = ? ORDER BY position', [id])
          .map(IngredientRow.fromRow)
          .toList(),
      steps: _db
          .select('SELECT * FROM steps WHERE recipe_id = ? ORDER BY position', [id])
          .map(StepRow.fromRow)
          .toList(),
      logs: _db
          .select('SELECT * FROM cook_logs WHERE recipe_id = ? ORDER BY cooked_at DESC', [id])
          .map(CookLogRow.fromRow)
          .toList(),
    );
  }

  int saveRecipe(RecipeDraft d, String searchKeyOfName) {
    final now = DateTime.now().millisecondsSinceEpoch;
    int id;
    _db.execute('BEGIN');
    try {
      if (d.id == null) {
        _db.execute(
          'INSERT INTO recipes (name, search_key, description, cuisine, taste, difficulty, minutes, servings, image_path, tags_text, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
          [
            d.name, searchKeyOfName, d.description, d.cuisine, d.taste, d.difficulty,
            d.minutes, d.servings, d.imagePath, d.tags.join(','), now, now,
          ],
        );
        id = _db.lastInsertRowId;
      } else {
        id = d.id!;
        _db.execute(
          'UPDATE recipes SET name=?, search_key=?, description=?, cuisine=?, taste=?, difficulty=?, minutes=?, servings=?, image_path=?, tags_text=?, updated_at=? WHERE id=?',
          [
            d.name, searchKeyOfName, d.description, d.cuisine, d.taste, d.difficulty,
            d.minutes, d.servings, d.imagePath, d.tags.join(','), now, id,
          ],
        );
        _db.execute('DELETE FROM ingredients WHERE recipe_id = ?', [id]);
        _db.execute('DELETE FROM steps WHERE recipe_id = ?', [id]);
      }
      for (var i = 0; i < d.ingredients.length; i++) {
        final ing = d.ingredients[i];
        _db.execute(
          'INSERT INTO ingredients (recipe_id, grp, name, qty, unit, position) VALUES (?,?,?,?,?,?)',
          [id, ing.grp, ing.name, ing.qty, ing.unit, i],
        );
      }
      for (var i = 0; i < d.steps.length; i++) {
        final s = d.steps[i];
        _db.execute(
          'INSERT INTO steps (recipe_id, position, text, timer_seconds) VALUES (?,?,?,?)',
          [id, i, s.text, s.timerSeconds],
        );
      }
      _db.execute('COMMIT');
    } catch (e) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    _ping();
    return id;
  }

  void deleteRecipe(int id) {
    _db.execute('DELETE FROM recipes WHERE id = ?', [id]);
    _ping();
  }

  void setImagePath(int id, String? path) {
    _db.execute('UPDATE recipes SET image_path = ? WHERE id = ?', [path, id]);
    _ping();
  }

  void markCooked(int id, int? rating, String? note) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _db.execute(
      'INSERT INTO cook_logs (recipe_id, cooked_at, rating, note) VALUES (?,?,?,?)',
      [id, now, rating, note],
    );
    final r = recipeById(id);
    _db.execute(
      'UPDATE recipes SET cook_count = ?, last_cooked_at = ?, last_rating = ? WHERE id = ?',
      [(r?.cookCount ?? 0) + 1, now, rating, id],
    );
    _ping();
  }

  List<String> allTags() {
    final out = <String>[];
    for (final row in _db.select('SELECT tags_text FROM recipes')) {
      final t = (row['tags_text'] as String?) ?? '';
      for (final part in t.split(',')) {
        final v = part.trim();
        if (v.isNotEmpty && !out.contains(v)) out.add(v);
      }
    }
    out.sort();
    return out;
  }

  List<RecipeRow> allRecipes() =>
      _db.select('SELECT * FROM recipes ORDER BY name').map(RecipeRow.fromRow).toList();

  List<IngredientRow> ingredientsOf(int recipeId) => _db
      .select('SELECT * FROM ingredients WHERE recipe_id = ? ORDER BY position', [recipeId])
      .map(IngredientRow.fromRow)
      .toList();

  Stream<List<ShoppingRow>> watchShopping() => _watch(shoppingItems);
  List<ShoppingRow> shoppingItems() => _db
      .select('SELECT * FROM shopping_items ORDER BY sort_group, name')
      .map(ShoppingRow.fromRow)
      .toList();

  void replaceShopping(List<({String name, double? qty, String? unit, int group})> items) {
    _db.execute('DELETE FROM shopping_items');
    for (final i in items) {
      _db.execute(
        'INSERT INTO shopping_items (name, qty, unit, checked, sort_group) VALUES (?,?,?,0,?)',
        [i.name, i.qty, i.unit, i.group],
      );
    }
    _ping();
  }

  void toggleShopping(int id, bool checked) {
    _db.execute('UPDATE shopping_items SET checked = ? WHERE id = ?', [checked ? 1 : 0, id]);
    _ping();
  }

  void clearShopping() {
    _db.execute('DELETE FROM shopping_items');
    _ping();
  }

  void wipeAll() {
    _db.execute('DELETE FROM shopping_items');
    _db.execute('DELETE FROM cook_logs');
    _db.execute('DELETE FROM steps');
    _db.execute('DELETE FROM ingredients');
    _db.execute('DELETE FROM recipes');
    _ping();
  }

  void close() {
    _changes.close();
    _db.close();
  }
}
