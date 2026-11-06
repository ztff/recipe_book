import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:recipe_book/core/ocr.dart';
import 'package:recipe_book/core/paths.dart';
import 'package:recipe_book/core/update_checker.dart';
import 'package:recipe_book/data/ocr_raw_store.dart';

OcrLayout layoutOf(List<String> texts) => OcrLayout(
      lines: [
        for (var i = 0; i < texts.length; i++)
          OcrLine(
            text: texts[i],
            top: 100.0 + i * 50,
            bottom: 140.0 + i * 50,
            left: 40,
            right: 700,
            score: 0.9,
            tile: i ~/ 3,
          ),
      ],
      width: 1080,
      height: 3000,
    );

void main() {
  group('更新入口', () {
    test('地址指向 release 页', () {
      expect(kReleasePage.contains('github.com/ztff/recipe_book'), isTrue);
      expect(kReleasePage.contains('releases'), isTrue);
    });
  });

  group('识别留档', () {
    late Directory tmp;

    setUpAll(() {
      tmp = Directory.systemTemp.createTempSync('ocr_raw_test');
      appImageDir = Directory(p.join(tmp.path, 'images'))..createSync();
    });

    tearDownAll(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('存一份能读回来', () async {
      for (final f in OcrRawStore.list()) {
        f.deleteSync();
      }
      final file = await OcrRawStore.save(
        layoutOf(['红烧排骨', '用料', '开水']),
        sourceImage: '/tmp/a.png',
        recipeName: '红烧排骨',
      );
      expect(file, isNotNull);
      expect(file!.existsSync(), isTrue);

      final text = file.readAsStringSync();
      expect(text.contains('红烧排骨'), isTrue);
      expect(text.contains('开水'), isTrue);
      expect(text.contains('"tile"'), isTrue);
      expect(text.contains('"score"'), isTrue);
    });

    test('只留最近 10 份', () async {
      for (final f in OcrRawStore.list()) {
        f.deleteSync();
      }
      for (var i = 0; i < 13; i++) {
        await OcrRawStore.save(layoutOf(['第' + i.toString() + '次']));
        // 文件名精确到秒，隔开一点避免同名覆盖
        await Future<void>.delayed(const Duration(milliseconds: 1100));
      }
      expect(OcrRawStore.count, 10);
      final latest = OcrRawStore.latest();
      expect(latest, isNotNull);
      expect(latest!.readAsStringSync().contains('第12次'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
