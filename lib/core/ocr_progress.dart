/// 识别进度文案。
///
/// [done] 已完成分片、[total] 总分片、[elapsedMs] 本次识别已耗时。
/// 剩余时间按已完成片的平均速度外推：done 片花 elapsedMs，每片就是
/// elapsedMs/done，剩 total-done 片再乘回去。
///
/// 第一片回来前不报秒数——除以 0 会得到无穷，显示「还剩约 NaN 秒」。
String ocrProgressText(int done, int total, int elapsedMs) {
  if (done <= 0 || total <= 0) return '正在识别…';
  final buf = StringBuffer('正在识别 ')..write(done)..write('/')..write(total)..write(' 片');
  final left = total - done;
  if (left <= 0) return buf.toString();
  if (elapsedMs <= 0) return buf.toString();

  final remainMs = elapsedMs / done * left;
  // 最后一片或不到一秒时给句人话，别显示「还剩约 0 秒」像卡住了
  if (left <= 1 || remainMs < 1000) {
    buf.write(' · 马上就好的');
  } else {
    buf
      ..write(' · 还剩约 ')
      ..write((remainMs / 1000).ceil())
      ..write(' 秒');
  }
  return buf.toString();
}
