import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 框一张图（步骤配图 / 封面）。
///
/// 坐标分两套，别混：
/// - 左右是横向的，横向不滚动，直接用原图像素 [_left] / [_right]；
/// - 上下是纵向的，纵向会滚动，所以框钉在屏幕上（[_frameTopPx] /
///   [_frameBottomPx]，逻辑像素），滚图找位置，框不动。
///
/// 这样做是因为长截图动辄十几屏：框跟着图走的话，滚两下框就出视野了，
/// 想对齐某一段很别扭。钉在屏幕上就是「窗口固定、内容滑动」。
///
/// 四条边和四个角都能拖，角同时改一条横边和一条竖边。
///
/// 返回值约定：
/// - Rect：用这个范围裁（原图像素坐标）
/// - Rect.zero：明确的「不要这张」
/// - null：返回键退出，什么都没决定
class StepCropPage extends StatefulWidget {
  const StepCropPage({
    super.key,
    required this.source,
    required this.imageWidth,
    required this.imageHeight,
    required this.initial,
    required this.stepIndex,
    required this.stepText,
    this.title,
  });

  final File source;
  final double imageWidth;
  final double imageHeight;
  final Rect? initial;
  final int stepIndex;
  final String stepText;

  /// 标题栏文字。封面图传「封面图」，步骤配图留空走「第 N 步配图」。
  final String? title;

  @override
  State<StepCropPage> createState() => _StepCropPageState();
}

class _StepCropPageState extends State<StepCropPage> {
  final _scroll = ScrollController();

  /// 左右边界，原图像素。
  late double _left;
  late double _right;

  /// 上下边界，屏幕逻辑像素（相对视口顶部）。
  ///
  /// 必须给初值不能留空：它们在 LayoutBuilder 里初始化，而 build 阶段
  /// 列里其它孩子会先构建，可空加 ! 会直接崩成白屏。
  double _frameTopPx = 160;
  double _frameBottomPx = 480;

  /// 原图自带的框，用来实现「用自动的」。
  Rect? _auto;

  /// 显示比例：1 逻辑像素 = 多少原图像素。
  double _scale = 1;

  /// 上次布局的视口高度，拖动时要用。
  double _vh = 800;

  /// 上次布局的滚动偏移和缩放，底部状态文字要用。
  double _lastOffset = 0;
  double _lastVw = 0;

  bool _inited = false;

  /// 首帧先把内容藏着，等滚到自动框的位置再放出来。
  /// 不然会看到「顶部一闪，然后跳过去」。
  bool _ready = false;

  double get _w => widget.imageWidth;
  double get _h => widget.imageHeight;

  /// 最小高度（屏幕像素）和最小宽度（原图像素）。
  static const double _minFrameH = 64;
  static const double _minW = 80;

  /// 抓取区大小。视觉上看不见，但手指落在附近就能拖。
  static const double _grabLine = 44;
  static const double _grabCorner = 48;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _auto = widget.initial;
    _left = _auto?.left ?? _w * 0.06;
    _right = _auto?.right ?? _w * 0.94;
    if (_left < 0) _left = 0;
    if (_right > _w) _right = _w;
    if (_right - _left < _minW) {
      _left = 0;
      _right = _w;
    }
  }

  void _onScroll() {
    // 框钉在屏幕上不动，但暗区在滚动内容里，得跟着重画
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// 第一次拿到视口尺寸时：把框摆到屏幕中间，并滚到自动框的位置。
  /// 打开时把框和滚动偏移一起解出来，让自动框真正落进框里。
  ///
  /// 这两件事必须一起算：框钉在屏幕上，光摆框不滚图，框里就不是那一
  /// 段；光滚图不摆框，顶部又够不着。解法是让
  ///   (frameTop + offset) / scale == a.top
  /// 先试着不滚动（框顶就等于自动框头部的屏幕位置），放不下就让框贴
  /// 底、把差额滚出来；图不够长滚不到时，反过来按最大滚动量定框位置。
  void _initFrame(double vh, double scale, double displayH) {
    if (_inited) return;
    _inited = true;
    _vh = vh;
    final plan = _planFrame(vh, scale, displayH);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        // 算完必须写回去。之前只用了 plan.scrollTo，plan.top 直接丢掉，
        // 框就一直停在字段初值 160 上，和自动框差了一截。
        _frameTopPx = plan.top;
        _frameBottomPx = plan.top + plan.height;
        _ready = true;
      });
      if (plan.scrollTo > 0 && _scroll.hasClients) {
        _scroll.jumpTo(plan.scrollTo);
      }
    });
  }

  ({double top, double height, double scrollTo}) _planFrame(
    double vh,
    double scale,
    double displayH,
  ) {
    final maxScroll = math.max(0.0, displayH - vh);
    final a = _auto;
    if (a == null) {
      final h = math.max(_minFrameH, vh * 0.40);
      return (top: (vh - h) / 2, height: h, scrollTo: 0);
    }
    final h =
        ((a.bottom - a.top) * scale).clamp(_minFrameH, vh * 0.85).toDouble();
    final wantTop = a.top * scale;
    var top = wantTop;
    var target = 0.0;
    if (top + h > vh) {
      top = vh - h;
      target = wantTop - top;
      if (target > maxScroll) {
        target = maxScroll;
        top = wantTop - target;
      }
      if (top < 0) top = 0;
    }
    return (top: top, height: h, scrollTo: target.clamp(0.0, maxScroll));
  }

  double _worldTop(double offset) =>
      ((_frameTopPx + offset) / _scale).clamp(0.0, _h);
  double _worldBottom(double offset) =>
      ((_frameBottomPx + offset) / _scale).clamp(0.0, _h);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title ?? ('第 ' + (widget.stepIndex + 1).toString() + ' 步配图'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop<Rect?>(Rect.zero),
            child: const Text('不要这张'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, outer) {
          return Column(
            children: [
              Container(
                width: double.infinity,
                color: scheme.surfaceContainerLow,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.stepText.trim().isNotEmpty) ...[
                      Text(
                        widget.stepText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      '框固定在屏幕上：拖图片去找位置，拖四边或四角改框。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (c, box) {
                    final vw = box.maxWidth;
                    final vh = box.maxHeight;
                    final displayH = vw * (_h / _w);
                    final scale = displayH / _h;
                    _scale = scale;
                    _vh = vh;
                    _initFrame(vh, scale, displayH);

                    final offset =
                        _scroll.hasClients ? _scroll.offset : 0.0;
                    _lastOffset = offset;
                    _lastVw = vw;
                    final ft = _frameTopPx;
                    final fb = _frameBottomPx;
                    final leftX = _left * scale;
                    final rightX = _right * scale;

                    // 暗区在滚动内容里 → 内容坐标（加偏移）
                    final dimTop = ft + offset;
                    final dimBottom = fb + offset;

                    return Opacity(
                      opacity: _ready ? 1 : 0,
                      child: Stack(
                      children: [
                        SingleChildScrollView(
                          controller: _scroll,
                          child: SizedBox(
                            width: vw,
                            height: math.max(displayH, vh),
                            child: Stack(
                              children: [
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  width: vw,
                                  height: displayH,
                                  child: Image.file(
                                    widget.source,
                                    width: vw,
                                    height: displayH,
                                    fit: BoxFit.fill,
                                  ),
                                ),
                                _dim(left: 0, right: 0, top: 0, height: dimTop),
                                _dim(
                                  left: 0,
                                  right: 0,
                                  top: dimBottom,
                                  height:
                                      math.max(0.0, displayH - dimBottom),
                                ),
                                _dim(
                                  left: 0,
                                  width: leftX,
                                  top: dimTop,
                                  height: math.max(0.0, dimBottom - dimTop),
                                ),
                                _dim(
                                  left: rightX,
                                  right: 0,
                                  top: dimTop,
                                  height: math.max(0.0, dimBottom - dimTop),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // 框线钉在屏幕上（视口坐标，不加偏移）
                        _hline(top: ft, x0: leftX, x1: rightX, isTop: true),
                        _hline(top: fb, x0: leftX, x1: rightX, isTop: false),
                        _vline(at: leftX, frameTop: ft, frameBottom: fb, isLeft: true),
                        _vline(at: rightX, frameTop: ft, frameBottom: fb, isLeft: false),
                        _corner(x: leftX, y: ft, isLeft: true, isTop: true),
                        _corner(x: rightX, y: ft, isLeft: false, isTop: true),
                        _corner(x: leftX, y: fb, isLeft: true, isTop: false),
                        _corner(x: rightX, y: fb, isLeft: false, isTop: false),
                      ],
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Text(
                        '高 ' +
                            (_worldBottom(_lastOffset).round() -
                                    _worldTop(_lastOffset).round())
                                .toString() +
                            ' px',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const Spacer(),
                      OutlinedButton(
                        onPressed: _resetToAuto,
                        child: const Text('用自动的'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: () {
                          final off = _lastOffset;
                          final t = math.min(_worldTop(off), _worldBottom(off));
                          final b = math.max(_worldTop(off), _worldBottom(off));
                          Navigator.of(context).pop<Rect?>(
                            Rect.fromLTRB(_left, t, _right, b),
                          );
                        },
                        child: const Text('就这段'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _dim({
    double? left,
    double? right,
    double? width,
    required double top,
    required double height,
  }) {
    if (height <= 0) return const SizedBox.shrink();
    return Positioned(
      left: left,
      right: right,
      width: width,
      top: top,
      height: height,
      child: const IgnorePointer(child: ColoredBox(color: Color(0xCC000000))),
    );
  }

  void _resetToAuto() {
    final a = _auto;
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final displayH = _w == 0 ? 0.0 : _lastVw * (_h / _w);
    final plan = _planFrame(_vh, _scale, displayH);
    setState(() {
      if (a != null) {
        _left = a.left.clamp(0.0, _w);
        _right = a.right.clamp(0.0, _w);
        if (_right - _left < _minW) {
          _left = 0;
          _right = _w;
        }
      } else {
        _left = _w * 0.06;
        _right = _w * 0.94;
      }
      _frameTopPx = plan.top;
      _frameBottomPx = plan.top + plan.height;
    });
    if (_scroll.hasClients && plan.scrollTo != offset) {
      _scroll.jumpTo(plan.scrollTo);
    }
  }

  /// 横线：管上下，拖动改屏幕坐标。
  Widget _hline({
    required double top,
    required double x0,
    required double x1,
    required bool isTop,
  }) {
    return Positioned(
      left: x0,
      width: math.max(0.0, x1 - x0),
      top: top - _grabLine / 2,
      height: _grabLine,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (d) => setState(() {
          if (isTop) {
            _frameTopPx = (_frameTopPx + d.delta.dy)
                .clamp(0.0, _frameBottomPx - _minFrameH);
          } else {
            _frameBottomPx = (_frameBottomPx + d.delta.dy)
                .clamp(_frameTopPx + _minFrameH, _vh);
          }
        }),
        child: Center(
          child: Container(
            width: math.max(0.0, x1 - x0),
            height: 3,
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 3)],
            ),
          ),
        ),
      ),
    );
  }

  /// 竖线：管左右，拖动改原图像素。
  Widget _vline({
    required double at,
    required double frameTop,
    required double frameBottom,
    required bool isLeft,
  }) {
    const grab = _grabLine;
    double left;
    Alignment lineAlign;
    if (isLeft && at < grab) {
      left = at;
      lineAlign = Alignment.centerLeft;
    } else if (!isLeft && at > _w * _scale - grab) {
      left = at - grab;
      lineAlign = Alignment.centerRight;
    } else {
      left = at - grab / 2;
      lineAlign = Alignment.center;
    }
    return Positioned(
      top: frameTop,
      height: math.max(0.0, frameBottom - frameTop),
      left: left,
      width: grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => setState(() {
          if (isLeft) {
            _left = (_left + d.delta.dx / _scale)
                .clamp(0.0, math.max(0.0, _right - _minW));
          } else {
            _right = (_right + d.delta.dx / _scale)
                .clamp(math.min(_w, _left + _minW), _w);
          }
        }),
        child: Align(
          alignment: lineAlign,
          child: Container(
            width: 3,
            height: math.max(0.0, frameBottom - frameTop),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 3)],
            ),
          ),
        ),
      ),
    );
  }

  /// 角：一次改一条横边和一条竖边。
  Widget _corner({
    required double x,
    required double y,
    required bool isLeft,
    required bool isTop,
  }) {
    const g = _grabCorner;
    return Positioned(
      left: x - g / 2,
      top: y - g / 2,
      width: g,
      height: g,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) => setState(() {
          if (isTop) {
            _frameTopPx = (_frameTopPx + d.delta.dy)
                .clamp(0.0, _frameBottomPx - _minFrameH);
          } else {
            _frameBottomPx = (_frameBottomPx + d.delta.dy)
                .clamp(_frameTopPx + _minFrameH, _vh);
          }
          if (isLeft) {
            _left = (_left + d.delta.dx / _scale)
                .clamp(0.0, math.max(0.0, _right - _minW));
          } else {
            _right = (_right + d.delta.dx / _scale)
                .clamp(math.min(_w, _left + _minW), _w);
          }
        }),
        child: Center(
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black54, width: 1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}
