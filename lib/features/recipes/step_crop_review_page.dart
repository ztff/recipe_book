import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/paths.dart';
import 'step_crop_page.dart';

/// 识别完成后让用户过一眼自动截的配图，不满意的可以重新框。
///
/// 自动检测只是「在这一步的区域里找最大空白块」，经常框到跨步骤的图或者
/// 空白处。全部逐张手动框太累，所以先跑自动，这里只给机会改。
class StepCropReviewPage extends StatefulWidget {
  const StepCropReviewPage({
    super.key,
    required this.source,
    required this.imageWidth,
    required this.imageHeight,
    required this.texts,
    required this.rects,
    required this.crops,
    required this.onRecrop,
    this.coverBox,
    this.coverRect,
    this.onCoverChanged,
  });

  final File source;
  final double imageWidth;
  final double imageHeight;
  final List<String> texts;
  final List<Rect?> rects;

  /// 已经裁好的文件名，和 [rects] 一一对应，null 表示这一步没有图。
  final List<String?> crops;

  /// 按新框重裁一张，返回文件名；返回 null 表示这张不要了。
  /// index 传 -1 表示裁的是封面。
  final Future<String?> Function(Rect rect, int index) onRecrop;

  /// 封面文件名，单元素容器。用户在这里调整后由调用方读走。
  final List<String?>? coverBox;

  /// 封面自动检测出来的位置。
  final Rect? coverRect;

  /// 封面被换掉/去掉之后通知调用方（编辑页据此更新封面卡片）。
  final ValueChanged<String?>? onCoverChanged;

  @override
  State<StepCropReviewPage> createState() => _StepCropReviewPageState();
}

class _StepCropReviewPageState extends State<StepCropReviewPage> {
  late List<String?> _crops;
  late List<Rect?> _rects;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _crops = List<String?>.from(widget.crops);
    _rects = List<Rect?>.from(widget.rects);
  }

  Future<void> _adjust(int i) async {
    if (_busy) return;
    final r = await Navigator.of(context).push<Rect?>(
      MaterialPageRoute(
        builder: (_) => StepCropPage(
          source: widget.source,
          imageWidth: widget.imageWidth,
          imageHeight: widget.imageHeight,
          initial: _rects[i],
          stepIndex: i,
          stepText: widget.texts[i],
        ),
      ),
    );
    if (!mounted) return;
    // null 表示用户按了返回键，什么都没决定——别把已有的图当「不要」删掉
    if (r == null) return;
    setState(() => _busy = true);
    try {
      if (r == Rect.zero) {
        // 用户明确点了「不要这张」：清掉已裁的文件
        final old = _crops[i];
        setState(() {
          _crops[i] = null;
          _rects[i] = null;
        });
        if (old != null) {
          try {
            final f = File(imageFullPath(old));
            if (f.existsSync()) await f.delete();
          } catch (_) {}
        }
      } else {
        final old = _crops[i];
        final name = await widget.onRecrop(r, i);
        if (!mounted) return;
        setState(() {
          _crops[i] = name;
          _rects[i] = r;
        });
        // 重裁成功才删旧的，失败时还能用原来的
        if (name != null && old != null && old != name) {
          try {
            final f = File(imageFullPath(old));
            if (f.existsSync()) await f.delete();
          } catch (_) {}
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 封面那一行。放在最前面，因为它通常就是长截图最上面的成品大图。
  Widget _coverCard(ColorScheme scheme) {
    final box = widget.coverBox;
    final name = box == null ? null : box[0];
    return Card(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 84,
                height: 84,
                child: name == null
                    ? ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: Center(
                          child: Text('无图',
                              style: TextStyle(
                                  fontSize: 12, color: scheme.outline)),
                        ),
                      )
                    : Image.file(
                        File(imageFullPath(name)),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => ColoredBox(
                          color: scheme.surfaceContainerHighest,
                          child: Center(
                            child: Text('读不到',
                                style: TextStyle(
                                    fontSize: 12, color: scheme.error)),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('封面',
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(color: scheme.primary)),
                  const SizedBox(height: 4),
                  Text(
                    '一般是长截图最上面那张成品图。不需要就点「调整」后选「不要这张」。',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _busy ? null : _adjustCover,
              child: Text(name == null ? '框选' : '调整'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _adjustCover() async {
    final box = widget.coverBox;
    if (box == null || _busy) return;
    final r = await Navigator.of(context).push<Rect?>(
      MaterialPageRoute(
        builder: (_) => StepCropPage(
          source: widget.source,
          imageWidth: widget.imageWidth,
          imageHeight: widget.imageHeight,
          // 封面没有单独记位置，一直用自动检测到的成品图位置当起点。
          // 之前这里写成「有封面就给 null」，导致第二次点「调整」时框退回到
          // 屏幕正中 40% 的兜底值，和成品图完全对不上。
          initial: widget.coverRect,
          stepIndex: 0,
          stepText: '',
          title: '封面图',
        ),
      ),
    );
    if (!mounted || r == null) return;
    setState(() => _busy = true);
    try {
      final old = box[0];
      if (r == Rect.zero) {
        box[0] = null;
        widget.onCoverChanged?.call(null);
        if (old != null) {
          try {
            File(imageFullPath(old)).deleteSync();
          } catch (_) {}
        }
      } else {
        final name = await widget.onRecrop(r, -1);
        if (!mounted) return;
        box[0] = name;
        widget.onCoverChanged?.call(name);
        if (name != null && old != null && old != name) {
          try {
            File(imageFullPath(old)).deleteSync();
          } catch (_) {}
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kept = _crops.where((c) => c != null).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('检查配图'),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(_crops),
            child: const Text('完成'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: scheme.surfaceContainerLow,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Text(
              kept == 0
                  ? '这张图没截到配图，可以直接完成'
                  : '截了 ' + kept.toString() + ' 张。不满意就点「调整」，四条边都能拖。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: widget.texts.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (c, i) {
                if (i == 0) return _coverCard(scheme);
                final idx = i - 1;
                final name = _crops[idx];
                return Card(
                  color: scheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 84,
                            height: 84,
                            child: name == null
                                ? ColoredBox(
                                    color: scheme.surfaceContainerHighest,
                                    child: Center(
                                      child: Text('无图',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: scheme.outline)),
                                    ),
                                  )
                                : Image.file(
                                    File(imageFullPath(name)),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => ColoredBox(
                                      color: scheme.surfaceContainerHighest,
                                      child: Center(
                                        child: Text('读不到',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: scheme.error)),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('第 ' + (idx + 1).toString() + ' 步',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(color: scheme.primary)),
                              const SizedBox(height: 4),
                              Text(
                                widget.texts[idx].trim().isEmpty
                                    ? '（没有文字）'
                                    : widget.texts[idx],
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          children: [
                            TextButton(
                              onPressed: _busy ? null : () => _adjust(idx),
                              child: Text(name == null ? '框选' : '调整'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
