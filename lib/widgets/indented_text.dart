import 'package:flutter/widgets.dart';

/// 多行文字：第一行顶格，换行后的每一行自动缩进。
///
/// Flutter 的 Text 没有悬挂缩进，这里按行拆开手动补左侧留白，
/// 视觉上就是「换行符自动缩进」。
class IndentedText extends StatelessWidget {
  const IndentedText(
    this.text, {
    super.key,
    this.style,
    this.indent = 16,
  });

  final String text;
  final TextStyle? style;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    if (lines.length == 1) {
      return Text(text, style: style);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < lines.length; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : indent),
            child: Text(lines[i], style: style),
          ),
      ],
    );
  }
}
