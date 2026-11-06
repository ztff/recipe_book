import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/core/ocr_progress.dart';

void main() {
  test('第一片回来前只报片数，不报秒数', () {
    expect(ocrProgressText(0, 8, 0), '正在识别…');
    expect(ocrProgressText(0, 8, 3000), '正在识别…');
    expect(ocrProgressText(-1, 8, 3000), '正在识别…');
  });

  test('没有耗时数据时只报片数', () {
    expect(ocrProgressText(3, 8, 0), '正在识别 3/8 片');
  });

  test('按已完成片的平均速度外推剩余时间', () {
    // 3 片花了 3000ms，平均 1 秒一片，剩 5 片约 5 秒
    expect(ocrProgressText(3, 8, 3000), '正在识别 3/8 片 · 还剩约 5 秒');
    // 4 片花了 8000ms，平均 2 秒一片，剩 4 片约 8 秒
    expect(ocrProgressText(4, 8, 8000), '正在识别 4/8 片 · 还剩约 8 秒');
  });

  test('最后一片显示马上就好的', () {
    expect(ocrProgressText(7, 8, 7000), '正在识别 7/8 片 · 马上就好的');
  });

  test('剩余不到一秒也显示马上就好的', () {
    // 8 片花 8000ms，剩 1 片但按 900ms 算不足一秒
    expect(ocrProgressText(8, 9, 8000), '正在识别 8/9 片 · 马上就好的');
  });

  test('全部完成时不带剩余时间', () {
    expect(ocrProgressText(8, 8, 8000), '正在识别 8/8 片');
  });

  test('单片图直接完成', () {
    expect(ocrProgressText(1, 1, 500), '正在识别 1/1 片');
  });
}
