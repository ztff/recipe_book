import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_settings.dart';
import '../../core/constants.dart';
import '../../core/ocr.dart';
import '../../core/paths.dart';
import '../../core/pick_image.dart';
import '../../core/pinyin.dart';
import '../../core/screenshot_parser.dart';
import '../../data/db.dart';
import '../../main.dart';

class _IngEdit {
  _IngEdit({String name = '', String qty = '', this.grp = '主料', this.unit = '克'})
      : nameCtrl = TextEditingController(text: name),
        qtyCtrl = TextEditingController(text: qty);

  final TextEditingController nameCtrl;
  final TextEditingController qtyCtrl;
  String grp;
  String unit;

  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
  }
}

class _ImportEdit {
  const _ImportEdit({
    required this.name,
    required this.description,
    required this.ingredients,
    required this.steps,
  });

  final String name;
  final String description;
  final String ingredients;
  final String steps;
}

class _StepEdit {
  _StepEdit({String text = '', this.timerSeconds, this.imagePath})
      : textCtrl = TextEditingController(text: text);

  final TextEditingController textCtrl;
  int? timerSeconds;
  String? imagePath;

  void dispose() => textCtrl.dispose();
}

class RecipeEditPage extends StatefulWidget {
  const RecipeEditPage({super.key, this.recipeId});

  final int? recipeId;

  @override
  State<RecipeEditPage> createState() => _RecipeEditPageState();
}

class _RecipeEditPageState extends State<RecipeEditPage> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  String _cuisine = '家常';
  String _taste = '咸鲜';
  int _difficulty = 1;
  int _minutes = 30;
  int _servings = 2;
  String? _imagePath;
  final List<String> _tags = [];
  final List<_IngEdit> _ings = [];
  final List<_StepEdit> _steps = [];
  bool _loading = true;
  bool _ocrBusy = false;
  String _ocrStatus = '';

  bool get _isNew => widget.recipeId == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    if (widget.recipeId != null) {
      final d = appDb.detail(widget.recipeId!);
      if (d != null) {
        _nameCtrl.text = d.recipe.name;
        _descCtrl.text = d.recipe.description ?? '';
        _cuisine = d.recipe.cuisine;
        _taste = d.recipe.taste;
        _difficulty = d.recipe.difficulty;
        _minutes = d.recipe.minutes;
        _servings = d.recipe.servings;
        _imagePath = d.recipe.imagePath;
        _tags.addAll(d.recipe.tags);
        for (final i in d.ingredients) {
          _ings.add(_IngEdit(
            name: i.name,
            qty: i.qty == null ? '' : _trimNum(i.qty!),
            grp: i.grp,
            unit: i.unit ?? '克',
          ));
        }
        for (final s in d.steps) {
          _steps.add(_StepEdit(
          text: s.text,
          timerSeconds: s.timerSeconds,
          imagePath: s.imagePath,
        ));
        }
      }
    }
    if (_ings.isEmpty) _ings.add(_IngEdit());
    if (_steps.isEmpty) _steps.add(_StepEdit());
    setState(() => _loading = false);
  }

  String _trimNum(double v) {
    if ((v - v.roundToDouble()).abs() < 0.001) return v.round().toString();
    return v.toString();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _tagCtrl.dispose();
    for (final i in _ings) {
      i.dispose();
    }
    for (final s in _steps) {
      s.dispose();
    }
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickImage() async {
    final name = await pickAndStoreImage();
    if (name == null) return;
    setState(() => _imagePath = name);
  }

  Future<void> _showRawText(String text, {bool downscaled = false}) async {
    final lines = text.split('\n').length;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('识别到的原始文字'),
        content: SizedBox(
          width: double.maxFinite,
          height: 340,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (downscaled) ...[
                Text(
                  '图很长，已压缩识别；如有漏字，分两段截会更准',
                  style: TextStyle(fontSize: 12, color: Theme.of(c).colorScheme.error),
                ),
                const SizedBox(height: 8),
              ],
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    text,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (c.mounted) Navigator.pop(c);
              _snack('已复制 ' + lines.toString() + ' 行到剪贴板');
            },
            child: const Text('复制全部'),
          ),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<File?> _pickSourceImage() async {
    if (Platform.isAndroid || Platform.isIOS) {
      // 不压缩：长截图被压扁后字就没了，交给切片识别去处理高度
      final f = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (f == null) return null;
      return File(f.path);
    }
    final res = await FilePicker.pickFiles(
      dialogTitle: '选择含菜谱的图片',
      type: FileType.image,
    );
    if (res.isEmpty || res.first.path == null) return null;
    return File(res.first.path!);
  }

  Future<void> _importFromImage() async {
    setState(() {
      _ocrBusy = true;
      _ocrStatus = '正在准备图片';
    });
    try {
      final file = await _pickSourceImage();
      if (file == null) {
        setState(() => _ocrBusy = false);
        return;
      }
      if (mounted) setState(() => _ocrStatus = '正在读取图片…');

      final layout = await recognizeLayout(
        file,
        highAccuracy: appSettings.value.ocrHighAccuracy,
        onProgress: (done, total) {
          if (mounted) {
            setState(() => _ocrStatus =
                '正在识别 ' + done.toString() + '/' + total.toString());
          }
        },
      );
      if (layout == null) {
        if (!mounted) return;
        setState(() {
          _ocrBusy = false;
          _ocrStatus = '';
        });
        _snack('没读到文字，换张更清晰的图（正对、光足、别糊）');
        return;
      }

      final parsed = parseScreenRecipe(layout);
      if (parsed.isEmpty) {
        if (!mounted) return;
        setState(() {
          _ocrBusy = false;
          _ocrStatus = '';
        });
        await _showRawText(layout.plainText, downscaled: layout.downscaled);
        _snack('读到了字，但没认出菜谱结构，可以手动填');
        return;
      }

      // 整图先存一份到应用目录，后面裁步骤图用这份副本
      final stored = await pickAndStoreImage(prePicked: file, preserveSize: true);
      final src = stored == null ? file : File(imageFullPath(stored));

      if (mounted) setState(() => _ocrStatus = '正在裁步骤图');
      final crops = <String?>[];
      for (var i = 0; i < parsed.steps.length; i++) {
        final rect = parsed.steps[i].imageRect;
        crops.add(rect == null ? null : await _saveStepCrop(src, rect, i));
      }

      if (!mounted) return;
      setState(() {
        _ocrBusy = false;
        _ocrStatus = '';
      });

      final edited = await _askConfirmImport(parsed);
      if (edited == null) {
        _snack('已取消导入');
        return;
      }

      setState(() {
        if (edited.name.isNotEmpty && _nameCtrl.text.trim().isEmpty) {
          _nameCtrl.text = edited.name;
        }
        if (edited.description.isNotEmpty && _descCtrl.text.trim().isEmpty) {
          _descCtrl.text = edited.description;
        }
        for (final i in _ings) {
          i.dispose();
        }
        _ings.clear();
        for (final line in edited.ingredients.split('\n')) {
          final t = line.trim();
          if (t.isEmpty) continue;
          final parts = t.split(RegExp(r'\s+'));
          final qty = parts.length > 1 ? double.tryParse(parts[1]) : null;
          _ings.add(_IngEdit(
            name: parts.first,
            qty: qty == null ? '' : _trimNum(qty),
            unit: parts.length > 2 && parts[2].isNotEmpty ? parts[2] : '克',
          ));
        }
        for (final s in _steps) {
          s.dispose();
        }
        _steps.clear();
        final blocks = edited.steps
            .split(RegExp(r'\n\s*\n'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        for (var i = 0; i < blocks.length; i++) {
          _steps.add(_StepEdit(
            text: blocks[i],
            imagePath: i < crops.length ? crops[i] : null,
          ));
        }
        if (_ings.isEmpty) _ings.add(_IngEdit());
        if (_steps.isEmpty) _steps.add(_StepEdit());
        if (stored != null) _imagePath = stored;
      });
      _snack('已填入 ' +
          parsed.summary +
          (parsed.droppedLines > 0
              ? '，跳过 ' + parsed.droppedLines.toString() + ' 行广告/界面'
              : '') +
          '，请逐条核对');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ocrBusy = false;
        _ocrStatus = '';
      });
      _snack('识别失败：' + e.toString());
    }
  }

  Future<String?> _saveStepCrop(File source, Rect rect, int index) async {
    final name = 'step_' +
        DateTime.now().millisecondsSinceEpoch.toString() +
        '_' +
        index.toString() +
        '.jpg';
    final ok =
        await cropRegionToFile(source, rect.top, rect.bottom, imageFullPath(name));
    return ok ? name : null;
  }

  Future<_ImportEdit?> _askConfirmImport(ScreenRecipe parsed) async {
    final nameCtrl = TextEditingController(text: parsed.name ?? '');
    final descCtrl = TextEditingController(text: parsed.description ?? '');
    final ingCtrl = TextEditingController(
      text: parsed.ingredients
          .map((i) {
            final q = i.qty == null ? '' : _trimNum(i.qty!);
            return [i.name, q, i.unit ?? ''].where((e) => e.isNotEmpty).join(' ');
          })
          .join('\n'),
    );
    final stepCtrl = TextEditingController(
      text: parsed.steps.map((s) => s.text).join('\n\n'),
    );
    final notes = <String>[
      parsed.summary,
      if (parsed.droppedLines > 0)
        '已跳过 ' + parsed.droppedLines.toString() + ' 行广告/界面文字',
      if (!parsed.nameConfident && (parsed.name?.isNotEmpty ?? false))
        '菜名是从标题原样取的，改一下更准',
      '用料一行一条：名称 数量 单位；步骤之间空一行',
    ];
    final result = await showDialog<_ImportEdit>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('确认导入'),
        content: SizedBox(
          width: double.maxFinite,
          height: 430,
          child: ListView(
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '菜名'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '说明',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ingCtrl,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: '用料',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: stepCtrl,
                minLines: 6,
                maxLines: null,
                decoration: const InputDecoration(
                  labelText: '步骤',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              for (final n in notes)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(n, style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(
              c,
              _ImportEdit(
                name: nameCtrl.text.trim(),
                description: descCtrl.text.trim(),
                ingredients: ingCtrl.text,
                steps: stepCtrl.text,
              ),
            ),
            child: const Text('填入'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    descCtrl.dispose();
    ingCtrl.dispose();
    stepCtrl.dispose();
    return result;
  }

  void _addTag() {
    final v = _tagCtrl.text.trim();
    if (v.isEmpty) return;
    if (!_tags.contains(v)) setState(() => _tags.add(v));
    _tagCtrl.clear();
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('先给这道菜起个名字');
      return;
    }
    final ings = <DraftIngredient>[];
    for (final e in _ings) {
      final n = e.nameCtrl.text.trim();
      if (n.isEmpty) continue;
      final raw = e.qtyCtrl.text.trim();
      final q = raw.isEmpty ? null : double.tryParse(raw);
      ings.add(DraftIngredient(
        name: n,
        grp: e.grp,
        qty: q,
        unit: e.unit.trim().isEmpty ? null : e.unit.trim(),
      ));
    }
    final steps = <DraftStep>[];
    for (final s in _steps) {
      final t = s.textCtrl.text.trim();
      if (t.isEmpty) continue;
      steps.add(DraftStep(
        text: t,
        timerSeconds: s.timerSeconds,
        imagePath: s.imagePath,
      ));
    }
    if (steps.isEmpty) {
      _snack('至少写一个步骤');
      return;
    }
    final desc = _descCtrl.text.trim();
    final draft = RecipeDraft(
      id: widget.recipeId,
      name: name,
      description: desc.isEmpty ? null : desc,
      cuisine: _cuisine,
      taste: _taste,
      difficulty: _difficulty,
      minutes: _minutes,
      servings: _servings,
      imagePath: _imagePath,
      tags: List<String>.from(_tags),
      ingredients: ings,
      steps: steps,
    );
    appDb.saveRecipe(draft, searchKey(name));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? '记一道菜' : '编辑菜谱'),
        actions: [
          if (ocrAvailable)
            IconButton(
              tooltip: '从图片识别菜谱',
              onPressed: _ocrBusy ? null : _importFromImage,
              icon: _ocrBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.document_scanner_outlined),
            ),
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_ocrBusy) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _ocrStatus.isEmpty ? '正在识别…' : _ocrStatus,
                      style: TextStyle(color: scheme.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ],
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              height: 150,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: _imagePath == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined,
                            size: 32, color: scheme.onSurfaceVariant),
                        const SizedBox(height: 6),
                        Text('加一张成品图（可选）',
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                      ],
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(imageFullPath(_imagePath!)),
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => Container()),
                        Positioned(
                          right: 8,
                          top: 8,
                          child: IconButton.filledTonal(
                            onPressed: () => setState(() => _imagePath = null),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: '菜名', hintText: '例如 西红柿炒鸡蛋'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            maxLines: 2,
            decoration: const InputDecoration(labelText: '一句话说明（可选）'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _cuisine,
                  decoration: const InputDecoration(labelText: '菜系'),
                  items: [
                    for (final c in kCuisines)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) => setState(() => _cuisine = v ?? '家常'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _taste,
                  decoration: const InputDecoration(labelText: '口味'),
                  items: [
                    for (final t in kTastes)
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (v) => setState(() => _taste = v ?? '咸鲜'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('难度', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            segments: [
              for (var i = 0; i < kDifficultyLabels.length; i++)
                ButtonSegment(value: i + 1, label: Text(kDifficultyLabels[i])),
            ],
            selected: {_difficulty},
            onSelectionChanged: (s) => setState(() => _difficulty = s.first),
          ),
          const SizedBox(height: 16),
          Text('总用时（分钟）', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          DropdownButtonFormField<int>(
            initialValue: _minutes,
            items: [
              for (final m in const [10, 15, 20, 25, 30, 45, 60, 90, 120, 180])
                DropdownMenuItem(value: m, child: Text(m.toString() + ' 分钟')),
            ],
            onChanged: (v) => setState(() => _minutes = v ?? 30),
          ),
          const SizedBox(height: 16),
          Text('几人份', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (var i = 1; i <= 6; i++)
                ChoiceChip(
                  label: Text(i.toString() + ' 人'),
                  selected: _servings == i,
                  onSelected: (_) => setState(() => _servings = i),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('标签', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tagCtrl,
                  decoration: const InputDecoration(hintText: '快手 / 下饭 / 招待…'),
                  onSubmitted: (_) => _addTag(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(onPressed: _addTag, child: const Text('加')),
            ],
          ),
          if (_tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in _tags)
                    InputChip(
                      label: Text(t),
                      onDeleted: () => setState(() => _tags.remove(t)),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 22),
          Row(
            children: [
              Icon(Icons.egg_alt_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Text('食材', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _ings.add(_IngEdit())),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('加一行'),
              ),
            ],
          ),
          for (var i = 0; i < _ings.length; i++) _ingRow(i),
          const SizedBox(height: 22),
          Row(
            children: [
              Icon(Icons.format_list_numbered, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Text('步骤', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _steps.add(_StepEdit())),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('加一步'),
              ),
            ],
          ),
          for (var i = 0; i < _steps.length; i++) _stepCard(i),
        ],
      ),
    );
  }

  Widget _ingRow(int index) {
    final e = _ings[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () {
              final i = kIngredientGroups.indexOf(e.grp);
              setState(() => e.grp = kIngredientGroups[(i + 1) % kIngredientGroups.length]);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(e.grp, style: const TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 4,
            child: TextField(
              controller: e.nameCtrl,
              decoration: const InputDecoration(hintText: '名称'),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 58,
            child: TextField(
              controller: e.qtyCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: const InputDecoration(hintText: '数量'),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 86,
            child: DropdownButtonFormField<String>(
              initialValue: e.unit,
              isDense: true,
              items: [
                const DropdownMenuItem(value: '', child: Text('无')),
                for (final u in kUnits) DropdownMenuItem(value: u, child: Text(u)),
              ],
              onChanged: (v) => setState(() => e.unit = v ?? ''),
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _ings.removeAt(index);
                e.dispose();
                if (_ings.isEmpty) _ings.add(_IngEdit());
              });
            },
            icon: const Icon(Icons.remove_circle_outline, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _stepCard(int index) {
    final s = _steps[index];
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 11,
                  backgroundColor: scheme.primaryContainer,
                  child: Text((index + 1).toString(),
                      style: const TextStyle(fontSize: 11)),
                ),
                const Spacer(),
                IconButton(
                  onPressed: index == 0
                      ? null
                      : () => setState(() {
                            final tmp = _steps[index - 1];
                            _steps[index - 1] = _steps[index];
                            _steps[index] = tmp;
                          }),
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  tooltip: '上移',
                ),
                IconButton(
                  onPressed: index == _steps.length - 1
                      ? null
                      : () => setState(() {
                            final tmp = _steps[index + 1];
                            _steps[index + 1] = _steps[index];
                            _steps[index] = tmp;
                          }),
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  tooltip: '下移',
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _steps.removeAt(index);
                    s.dispose();
                    if (_steps.isEmpty) _steps.add(_StepEdit());
                  }),
                  icon: const Icon(Icons.remove_circle_outline, size: 18),
                ),
              ],
            ),
            TextField(
              controller: s.textCtrl,
              maxLines: null,
              minLines: 2,
              decoration: const InputDecoration(
                hintText: '这一步做什么…',
                border: InputBorder.none,
              ),
            ),
            if (s.imagePath != null)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      File(imageFullPath(s.imagePath!)),
                      width: double.infinity,
                      height: 140,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Material(
                      color: scheme.surface.withValues(alpha: 0.85),
                      shape: const CircleBorder(),
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 16),
                        tooltip: '去掉这一步的配图',
                        onPressed: () => setState(() => s.imagePath = null),
                      ),
                    ),
                  ),
                ],
              ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _pickStepImage(index),
                  icon: const Icon(Icons.image_outlined, size: 16),
                  label: Text(
                    s.imagePath == null ? '配图' : '换图',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const Spacer(),
              ],
            ),
            Wrap(
              spacing: 6,
              children: [
                for (final opt in const [null, 60, 180, 300, 600, 1200])
                  ChoiceChip(
                    label: Text(opt == null ? '不用计时' : _timerLabel(opt)),
                    selected: s.timerSeconds == opt,
                    onSelected: (_) => setState(() => s.timerSeconds = opt),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickStepImage(int index) async {
    final stored = await pickAndStoreImage();
    if (stored == null) return;
    if (!mounted) return;
    setState(() => _steps[index].imagePath = stored);
  }

  String _timerLabel(int sec) {
    if (sec < 60) return sec.toString() + ' 秒';
    if (sec % 60 == 0) return (sec ~/ 60).toString() + ' 分';
    return (sec ~/ 60).toString() + ' 分 ' + (sec % 60).toString() + ' 秒';
  }
}
