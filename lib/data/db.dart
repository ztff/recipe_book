import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../core/ingredient_rules.dart';
import '../core/paths.dart';
import '../core/screenshot_parser.dart';

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
    this.tips,
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

  /// 小贴士：成品图下方的补充说明，可能有多行。
  final String? tips;
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
        tips: r['tips'] as String?,
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
    this.imagePath,
  });

  final int id;
  final int recipeId;
  final int position;
  final String text;
  final int? timerSeconds;
  final String? imagePath;

  factory StepRow.fromRow(Row r) => StepRow(
        id: r['id'] as int,
        recipeId: r['recipe_id'] as int,
        position: (r['position'] as int?) ?? 0,
        text: r['text'] as String,
        timerSeconds: r['timer_seconds'] as int?,
        imagePath: r['image_path'] as String?,
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
  DraftStep({required this.text, this.timerSeconds, this.imagePath});
  final String text;
  final int? timerSeconds;
  final String? imagePath;
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
    this.tips,
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
  final String? tips;
  final List<String> tags;
  final List<DraftIngredient> ingredients;
  final List<DraftStep> steps;
}

/// 一条可维护的识别规则：某个食材归哪一组、没写单位时补什么。
class IngredientRuleRow {
  IngredientRuleRow({
    required this.id,
    required this.name,
    required this.grp,
    required this.unit,
    required this.builtin,
    required this.enabled,
  });

  final int id;
  final String name;
  final String grp;
  final String unit;
  final bool builtin;
  final bool enabled;

  factory IngredientRuleRow.fromRow(Row r) => IngredientRuleRow(
        id: r['id'] as int,
        name: r['name'] as String,
        grp: (r['grp'] as String?) ?? '',
        unit: (r['unit'] as String?) ?? '',
        builtin: ((r['builtin'] as int?) ?? 0) == 1,
        enabled: ((r['enabled'] as int?) ?? 1) == 1,
      );
}

class StatsSummary {
  StatsSummary({
    required this.totalRecipes,
    required this.totalCooks,
    required this.averageRating,
    required this.cookedLast30Days,
    required this.topRecipes,
    required this.recentCooks,
  });

  final int totalRecipes;
  final int totalCooks;
  final double? averageRating;
  final int cookedLast30Days;
  final List<({int id, String name, int count})> topRecipes;
  final List<({int at, int? rating, String name})> recentCooks;
}

class AppDb {
  AppDb._(this._db) {
    _db.execute('PRAGMA foreign_keys = ON');
    _migrate();
  }

  final Database _db;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  String? dbFilePath;

  /// 导出一份一致的库快照到 [path]。
  ///
  /// 直接复制 .sqlite 在 WAL 模式下可能拿到半截事务，VACUUM INTO 会先
  /// 整理成单文件再写，备份才靠得住。
  void snapshotTo(String path) {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
    _db.execute('VACUUM INTO ?', [path]);
  }

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

  /// 把内置规则补进数据库。只插不存在的，用户改过的一律不碰。
  void syncBuiltinIngredientRules() {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final r in builtinIngredientRules()) {
      _db.execute(
        'INSERT OR IGNORE INTO ingredient_rules (name, grp, unit, builtin, enabled, updated_at) '
        'VALUES (?,?,?,1,1,?)',
        [r.name, r.grp, r.unit, now],
      );
    }
    _migrateIngredientRuleValues();
  }

  /// 内置规则本身改了口径（比如水从调料改主料）时，把还停在旧值的行跟一下。
  /// 用户手动改成别的分组的，一律不碰。
  void _migrateIngredientRuleValues() {
    final raw = getSetting('ingredient_rule_version');
    final version = raw == null ? 0 : (int.tryParse(raw) ?? 0);
    if (version >= 2) return;
    for (final w in kWaterNames) {
      _db.execute(
        "UPDATE ingredient_rules SET grp = '主料' "
        "WHERE name = ? AND builtin = 1 AND grp = '调料'",
        [w],
      );
    }
    setSetting('ingredient_rule_version', '2');
  }

  List<IngredientRuleRow> ingredientRules({String keyword = ''}) {
    final k = keyword.trim();
    final rows = k.isEmpty
        ? _db.select('SELECT * FROM ingredient_rules ORDER BY grp, name')
        : _db.select(
            "SELECT * FROM ingredient_rules WHERE name LIKE ? ORDER BY grp, name",
            ['%' + k + '%'],
          );
    return rows.map(IngredientRuleRow.fromRow).toList();
  }

  /// 识别时用：只要启用的，转成解析器认识的规则集。
  IngredientRuleSet ingredientRuleSet() {
    final rows = _db.select(
      'SELECT name, grp, unit FROM ingredient_rules WHERE enabled = 1',
    );
    return IngredientRuleSet(rows.map(
      (r) => IngredientRule(
        r['name'] as String,
        (r['grp'] as String?) ?? '',
        (r['unit'] as String?) ?? '',
      ),
    ));
  }

  /// 新增或按名字覆盖一条规则。
  void saveIngredientRule({
    required String name,
    required String grp,
    required String unit,
    bool enabled = true,
  }) {
    final n = name.trim();
    if (n.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _db.execute(
      'INSERT INTO ingredient_rules (name, grp, unit, builtin, enabled, updated_at) '
      'VALUES (?,?,?,0,?,?) '
      'ON CONFLICT(name) DO UPDATE SET grp=excluded.grp, unit=excluded.unit, enabled=excluded.enabled, updated_at=excluded.updated_at',
      [n, grp, unit, enabled ? 1 : 0, now],
    );
  }

  void setIngredientRuleEnabled(int id, bool enabled) {
    _db.execute(
      'UPDATE ingredient_rules SET enabled = ? WHERE id = ?',
      [enabled ? 1 : 0, id],
    );
  }

  void deleteIngredientRule(int id) {
    _db.execute('DELETE FROM ingredient_rules WHERE id = ?', [id]);
  }

  /// 恢复出厂：清空后重新灌内置，用户自己加的就没了。
  void resetIngredientRules() {
    _db.execute('DELETE FROM ingredient_rules');
    syncBuiltinIngredientRules();
  }

  /// 把已经存下来的步骤按「句末标点才换行」重新整理一遍。
  /// 老版本导入的步骤是屏幕折行原样存的，读起来断得很碎。
  /// 返回改动的步骤数。
  int normalizeStepText() {
    final rows = _db.select('SELECT id, text FROM steps ORDER BY id');
    var changed = 0;
    _db.execute('BEGIN');
    try {
      for (final r in rows) {
        final text = r['text'] as String;
        final fixed = joinBySentence(text.split('\n'));
        if (fixed == text) continue;
        _db.execute('UPDATE steps SET text = ? WHERE id = ?', [fixed, r['id']]);
        changed++;
      }
      _db.execute('COMMIT');
    } catch (e) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    return changed;
  }

  /// 拿所有菜谱的用料按当前规则重算分组和单位。
  /// 返回改动的条数。会覆盖手改过的分组，调用前要确认。
  int reapplyIngredientRules() {
    final rules = ingredientRuleSet();
    final rows = _db.select(
      'SELECT id, name, unit FROM ingredients ORDER BY id',
    );
    var changed = 0;
    _db.execute('BEGIN');
    try {
      for (final r in rows) {
        final name = r['name'] as String;
        final rule = rules.lookup(name);
        if (rule == null) continue;
        final unit = r['unit'] as String?;
        final blank = unit == null || unit.trim().isEmpty;
        final newUnit = blank && rule.unit.isNotEmpty ? rule.unit : unit;
        final newGrp = rule.grp.isNotEmpty ? rule.grp : null;
        if (newGrp == null && newUnit == unit) continue;

        final old = _db.select(
          'SELECT grp FROM ingredients WHERE id = ?',
          [r['id']],
        );
        final oldGrp = (old.isEmpty ? null : old.first['grp'] as String?);
        if (newGrp != null && newGrp != oldGrp) changed++;
        _db.execute(
          'UPDATE ingredients SET grp = COALESCE(?, grp), unit = ? WHERE id = ?',
          [newGrp, newUnit, r['id']],
        );
      }
      _db.execute('COMMIT');
    } catch (e) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    return changed;
  }

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
        tips TEXT,
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
        timer_seconds INTEGER,
        image_path TEXT
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
      CREATE TABLE IF NOT EXISTS ingredient_rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        grp TEXT NOT NULL DEFAULT '',
        unit TEXT NOT NULL DEFAULT '',
        builtin INTEGER NOT NULL DEFAULT 0,
        enabled INTEGER NOT NULL DEFAULT 1,
        updated_at INTEGER
      );
      CREATE UNIQUE INDEX IF NOT EXISTS idx_ing_rule_name ON ingredient_rules(name);
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_ing_recipe ON ingredients(recipe_id);
    ''');
    _ensureColumn('steps', 'image_path', 'TEXT');
    _ensureColumn('recipes', 'tips', 'TEXT');
    syncBuiltinIngredientRules();
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_step_recipe ON steps(recipe_id);
      CREATE INDEX IF NOT EXISTS idx_log_recipe ON cook_logs(recipe_id);
    ''');
  }

  /// 老库升级：表已经存在时 CREATE TABLE IF NOT EXISTS 不会补新列。
  void _ensureColumn(String table, String column, String type) {
    final info = _db.select('PRAGMA table_info(' + table + ')');
    final exists = info.any((r) => (r['name'] as String?) == column);
    if (!exists) {
      _db.execute('ALTER TABLE ' + table + ' ADD COLUMN ' + column + ' ' + type);
    }
  }

  String? getSetting(String key) {
    final rows = _db.select('SELECT value FROM app_settings WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void setSetting(String key, String value) {
    _db.execute(
      'INSERT INTO app_settings(key, value) VALUES(?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key, value],
    );
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
      // 除了菜名、拼音、标签，也匹配用料：搜「排骨」能找出用到排骨的菜。
      where.add('(search_key LIKE ? OR lower(name) LIKE ? OR tags_text LIKE ? OR '
          'id IN (SELECT recipe_id FROM ingredients WHERE lower(name) LIKE ?))');
      args.addAll([q, q, q, q]);
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

  /// 统计页用的汇总数据。
  StatsSummary queryStats() {
    final total = _db.select('SELECT COUNT(*) AS c FROM recipes').first['c'] as int;
    final cooked = _db
        .select('SELECT COALESCE(SUM(cook_count), 0) AS c FROM recipes')
        .first['c'] as int;
    final avg = _db
        .select('SELECT AVG(last_rating) AS r FROM recipes WHERE last_rating IS NOT NULL')
        .first['r'];
    final doneLast30 = _db.select(
      'SELECT COUNT(*) AS c FROM cook_logs WHERE cooked_at >= ?',
      [DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch],
    ).first['c'] as int;
    final top = _db
        .select(
          'SELECT id, name, cook_count FROM recipes WHERE cook_count > 0 '
          'ORDER BY cook_count DESC, name ASC LIMIT 5',
        )
        .map((r) => (
              id: r['id'] as int,
              name: r['name'] as String,
              count: r['cook_count'] as int,
            ))
        .toList();
    final recent = _db
        .select(
          'SELECT l.cooked_at, l.rating, r.name FROM cook_logs l '
          'JOIN recipes r ON r.id = l.recipe_id ORDER BY l.cooked_at DESC LIMIT 10',
        )
        .map((r) => (
              at: r['cooked_at'] as int,
              rating: (r['rating'] as num?)?.toInt(),
              name: r['name'] as String,
            ))
        .toList();
    return StatsSummary(
      totalRecipes: total,
      totalCooks: cooked,
      averageRating: (avg as num?)?.toDouble(),
      cookedLast30Days: doneLast30,
      topRecipes: top,
      recentCooks: recent,
    );
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
          'INSERT INTO recipes (name, search_key, description, cuisine, taste, difficulty, minutes, servings, image_path, tips, tags_text, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
          [
            d.name, searchKeyOfName, d.description, d.cuisine, d.taste, d.difficulty,
            d.minutes, d.servings, d.imagePath, d.tips, d.tags.join(','), now, now,
          ],
        );
        id = _db.lastInsertRowId;
      } else {
        id = d.id!;
        _db.execute(
          'UPDATE recipes SET name=?, search_key=?, description=?, cuisine=?, taste=?, difficulty=?, minutes=?, servings=?, image_path=?, tips=?, tags_text=?, updated_at=? WHERE id=?',
          [
            d.name, searchKeyOfName, d.description, d.cuisine, d.taste, d.difficulty,
            d.minutes, d.servings, d.imagePath, d.tips, d.tags.join(','), now, id,
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
          'INSERT INTO steps (recipe_id, position, text, timer_seconds, image_path) VALUES (?,?,?,?,?)',
          [id, i, s.text, s.timerSeconds, s.imagePath],
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

  /// 删掉菜谱，返回它引用过的图片文件名（调用方负责删文件）。
  ///
  /// 以前只删记录不管图片，删一道菜就在 images/ 里留下几兆的死文件，
  /// 攒了快两百个。现在把清单交出去，由调用方删。
  List<String> deleteRecipe(int id) {
    final imgs = <String>[];
    for (final r in _db.select(
      'SELECT image_path AS p FROM recipes WHERE id = ? AND image_path IS NOT NULL',
      [id],
    )) {
      final v = r['p'] as String?;
      if (v != null && v.isNotEmpty) imgs.add(v);
    }
    for (final r in _db.select(
      'SELECT image_path AS p FROM steps WHERE recipe_id = ? AND image_path IS NOT NULL',
      [id],
    )) {
      final v = r['p'] as String?;
      if (v != null && v.isNotEmpty) imgs.add(v);
    }
    _db.execute('DELETE FROM recipes WHERE id = ?', [id]);
    _ping();
    return imgs;
  }

  /// 图片改名后同步引用。迁移时把 .png 换成 .jpg 要用。
  void renameImageReferences(String from, String to) {
    _db.execute('UPDATE recipes SET image_path = ? WHERE image_path = ?', [to, from]);
    _db.execute('UPDATE steps SET image_path = ? WHERE image_path = ?', [to, from]);
  }

  /// 所有被引用的图片文件名（菜谱封面 + 步骤图）。
  Set<String> referencedImages() {
    final out = <String>{};
    for (final r in _db.select(
      'SELECT image_path AS p FROM recipes WHERE image_path IS NOT NULL '
      'UNION SELECT image_path FROM steps WHERE image_path IS NOT NULL',
    )) {
      final v = r['p'] as String?;
      if (v != null && v.isNotEmpty) out.add(v);
    }
    return out;
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
