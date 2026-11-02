import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/db.dart';
import '../../main.dart';

class CookModePage extends StatefulWidget {
  const CookModePage({super.key, required this.detail});

  final RecipeDetail detail;

  @override
  State<CookModePage> createState() => _CookModePageState();
}

class _CookModePageState extends State<CookModePage> {
  final _pc = PageController();
  final _focus = FocusNode();
  int _index = 0;
  Timer? _ticker;
  int _remain = 0;

  List<StepRow> get _steps => widget.detail.steps;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WakelockPlus.disable();
    _pc.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _goto(int i) {
    if (i < 0 || i >= _steps.length) return;
    _pc.animateToPage(i,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  void _startTimer([int? seconds]) {
    final sec = seconds ?? _steps[_index].timerSeconds;
    if (sec == null || sec <= 0) return;
    _ticker?.cancel();
    setState(() => _remain = sec);
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _remain -= 1;
        if (_remain <= 0) {
          t.cancel();
          _ticker = null;
          _remain = 0;
          _alarm();
        }
      });
    });
  }

  void _pauseTimer() {
    _ticker?.cancel();
    _ticker = null;
    setState(() {});
  }

  void _resetTimer() {
    _ticker?.cancel();
    _ticker = null;
    setState(() => _remain = _steps[_index].timerSeconds ?? 0);
  }

  void _alarm() {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('这一步的时间到了'), duration: Duration(seconds: 4)),
    );
  }

  void _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.arrowRight) {
      _goto(_index + 1);
    } else if (k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.arrowLeft) {
      _goto(_index - 1);
    } else if (k == LogicalKeyboardKey.space) {
      if (_ticker != null) {
        _pauseTimer();
      } else if (_remain > 0) {
        _startTimer(_remain);
      } else {
        _startTimer();
      }
    } else if (k == LogicalKeyboardKey.escape) {
      _finish();
    }
  }

  Future<void> _finish() async {
    _ticker?.cancel();
    _ticker = null;
    final result = await showDialog<({int rating, String? note})>(
      context: context,
      builder: (c) => _RateDialog(recipeName: widget.detail.recipe.name),
    );
    if (!mounted) return;
    if (result != null) {
      appDb.markCooked(widget.detail.recipe.id, result.rating, result.note);
    }
    Navigator.of(context).pop();
  }

  String _fmt(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return m.toString().padLeft(2, '0') + ':' + s.toString().padLeft(2, '0');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final step = _steps[_index];
    final hasTimer = step.timerSeconds != null && step.timerSeconds! > 0;
    final running = _ticker != null;
    final shown = running || _remain > 0 ? _remain : (step.timerSeconds ?? 0);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.detail.recipe.name),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text((_index + 1).toString() + ' / ' + _steps.length.toString()),
            ),
          ),
        ],
      ),
      body: KeyboardListener(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(
          children: [
            LinearProgressIndicator(
              value: (_index + 1) / _steps.length,
              minHeight: 4,
            ),
            Expanded(
              child: PageView.builder(
                controller: _pc,
                onPageChanged: (i) {
                  setState(() {
                    _index = i;
                    _remain = 0;
                    _ticker?.cancel();
                    _ticker = null;
                  });
                },
                itemCount: _steps.length,
                itemBuilder: (c, i) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('第 ' + (i + 1).toString() + ' 步',
                            style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 14),
                        Text(
                          _steps[i].text,
                          style: const TextStyle(fontSize: 26, height: 1.55),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (hasTimer || _remain > 0)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Icon(Icons.timer_outlined, color: scheme.onPrimaryContainer),
                    const SizedBox(width: 10),
                    Text(
                      _fmt(shown),
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const Spacer(),
                    if (running)
                      FilledButton.tonalIcon(
                        onPressed: _pauseTimer,
                        icon: const Icon(Icons.pause),
                        label: const Text('暂停'),
                      )
                    else
                      FilledButton.tonalIcon(
                        onPressed: () => _startTimer(_remain > 0 ? _remain : null),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('计时'),
                      ),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: _resetTimer,
                      icon: const Icon(Icons.restart_alt),
                      tooltip: '重置',
                    ),
                  ],
                ),
              ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _index == 0 ? null : () => _goto(_index - 1),
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('上一步'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _index == _steps.length - 1
                        ? FilledButton.icon(
                            onPressed: _finish,
                            icon: const Icon(Icons.check),
                            label: const Text('做完了'),
                          )
                        : FilledButton.icon(
                            onPressed: () => _goto(_index + 1),
                            icon: const Icon(Icons.chevron_right),
                            label: const Text('下一步'),
                          ),
                  ),
                ],
              ),
            ),
            if (Platform.isWindows || Platform.isMacOS || Platform.isLinux)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '↑↓ 或 ←→ 翻步 · 空格 计时 · Esc 结束',
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RateDialog extends StatefulWidget {
  const _RateDialog({required this.recipeName});
  final String recipeName;

  @override
  State<_RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<_RateDialog> {
  int _rating = 0;
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('这次做得怎么样？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  onPressed: () => setState(() => _rating = i),
                  icon: Icon(
                    i <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 30,
                  ),
                ),
            ],
          ),
          TextField(
            controller: _noteCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: '下次改进一句话（可不填）',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, (rating: 0, note: null)),
          child: const Text('跳过'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            (
              rating: _rating,
              note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim()
            ),
          ),
          child: const Text('记录'),
        ),
      ],
    );
  }
}
