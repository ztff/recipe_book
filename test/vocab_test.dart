import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/core/vocab.dart';

void main() {
  test('保守纠错：形近字换成词表里的词', () {
    expect(fixTypos('渍炒红薯叶'), '清炒红薯叶');
    expect(fixTypos('卤味护盘'), '卤味拼盘');
  });

  test('不该动的不动', () {
    // 正确词原样保留
    expect(fixTypos('清炒红薯叶'), '清炒红薯叶');
    // 词表外的专有名词不动
    expect(fixTypos('然福子的薇'), '然福子的薇');
    // 单个形近字不在两字词里也不动
    expect(fixTypos('清'), '清');
    // 数字与标点不动
    expect(fixTypos('50克，2~3片'), '50克，2~3片');
  });

  test('词表打分能区分更像中文的结果', () {
    final good = vocabScore('清炒红薯叶');
    final bad = vocabScore('渍炒红薯叶');
    expect(good, greaterThan(bad));
    expect(vocabScore(' Ingredients '), 0);
  });
}
