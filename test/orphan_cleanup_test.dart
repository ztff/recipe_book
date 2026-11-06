import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:recipe_book/core/image_migrate.dart';
import 'package:recipe_book/data/backup.dart';
import 'package:recipe_book/core/paths.dart';
import 'package:recipe_book/data/db.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('orphan_test_');
    appImageDir = Directory(p.join(tmp.path, 'images'))..createSync();
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('删掉没被引用的图片，保留被引用的', () async {
    final db = AppDb.memory();
    db.saveRecipe(
      RecipeDraft(
        name: '测试菜',
        imagePath: 'keep.jpg',
        cuisine: '家常',
        taste: '咸鲜',
        difficulty: 1,
        minutes: 10,
        servings: 2,
        ingredients: [DraftIngredient(name: '盐', grp: '调料')],
        steps: [DraftStep(text: '放盐')],
      ),
      'ceshicai',
    );
    File(p.join(appImageDir.path, 'keep.jpg')).writeAsBytesSync([1, 2, 3]);
    File(p.join(appImageDir.path, 'orphan.jpg')).writeAsBytesSync([4, 5, 6]);
    File(p.join(appImageDir.path, '.tmp.keep.jpg')).writeAsBytesSync([7]);

    final removed = await runOrphanCleanup(db, force: true);

    expect(removed, 2, reason: '孤儿和图个残留都要删');
    expect(File(p.join(appImageDir.path, 'keep.jpg')).existsSync(), isTrue);
    expect(File(p.join(appImageDir.path, 'orphan.jpg')).existsSync(), isFalse);
    expect(
      File(p.join(appImageDir.path, '.tmp.keep.jpg')).existsSync(),
      isFalse,
    );
  });

  test('引用集为空时不动正常文件，只清临时残留', () async {
    final db = AppDb.memory();
    File(p.join(appImageDir.path, 'a.jpg')).writeAsBytesSync([1]);
    File(p.join(appImageDir.path, 'b.jpg')).writeAsBytesSync([2]);
    File(p.join(appImageDir.path, '.tmp.c.jpg')).writeAsBytesSync([3]);

    final removed = await runOrphanCleanup(db, force: true);

    expect(removed, 1, reason: '只删临时文件，正常图留下');
    expect(File(p.join(appImageDir.path, 'a.jpg')).existsSync(), isTrue);
    expect(File(p.join(appImageDir.path, 'b.jpg')).existsSync(), isTrue);
  });

  test('导出整库只打被引用的图片', () async {
    final db = AppDb.memory();
    db.saveRecipe(
      RecipeDraft(
        name: '有图菜',
        imagePath: 'cover.jpg',
        cuisine: '家常',
        taste: '咸鲜',
        difficulty: 1,
        minutes: 10,
        servings: 2,
        ingredients: [DraftIngredient(name: '盐', grp: '调料')],
        steps: [DraftStep(text: '放盐')],
      ),
      'youtucai',
    );
    File(p.join(appImageDir.path, 'cover.jpg')).writeAsBytesSync([1, 2, 3]);
    File(p.join(appImageDir.path, 'ghost.jpg')).writeAsBytesSync([4, 5, 6]);

    final zip = p.join(tmp.path, 'out.zip');
    await exportBackup(db, zip);

    final entries = ZipDecoder().decodeBytes(File(zip).readAsBytesSync())
        .files.map((f) => f.name).toList();
    expect(entries, contains('images/cover.jpg'));
    expect(entries, isNot(contains('images/ghost.jpg')));
  });

  test('删菜谱会连带它的图片清单一起返回', () {
    final db = AppDb.memory();
    final id = db.saveRecipe(
      RecipeDraft(
        name: '要删的菜',
        imagePath: 'cover.jpg',
        cuisine: '家常',
        taste: '咸鲜',
        difficulty: 1,
        minutes: 10,
        servings: 2,
        ingredients: [DraftIngredient(name: '盐', grp: '调料')],
        steps: [DraftStep(text: '放盐', imagePath: 'step0.jpg')],
      ),
      'yaoshancai',
    );
    final imgs = db.deleteRecipe(id);
    expect(imgs, containsAll(<String>['cover.jpg', 'step0.jpg']));
    expect(db.referencedImages(), isEmpty);
  });
}
