import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../../core/image_tool.dart';
import '../../core/ocr.dart';
import '../../core/ocr_progress.dart';
import 'step_crop_page.dart';
import 'step_crop_review_page.dart';
import '../../core/paths.dart';
import '../../core/pick_image.dart';
import '../../core/pinyin.dart';
import '../../core/ingredient_rules.dart';
import '../../core/screenshot_parser.dart';
import '../../data/db.dart';
import '../../data/ocr_raw_store.dart';
import '../../main.dart';
import '../../widgets/cover_actions.dart';

class _IngEdit {
  _IngEdit({
    String name = '',
    String qty = '',
    this.grp = '主料',
    this.unit = '克',
    this.low = false,
  })  : nameCtrl = TextEditingController(text: name),
        qtyCtrl = TextEditingController(text: qty);

  final TextEditingController nameCtrl;
  final TextEditingController qtyCtrl;
  String grp;
  String unit;

  /// 识别置信度偏低，卡片上会标出来提醒核对。
  bool low;

  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
  }
}

class _StepEdit {
  _StepEdit({String text = '', this.timerSeconds, this.imagePath, this.low = false})
      : textCtrl = TextEditingController(text: text);

  final TextEditingController textCtrl;
  int? timerSeconds;
  String? imagePath;
  bool low;

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
  final _tipsCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  String _cuisine = '家常';
  String _taste = '咸鲜';
  int _difficulty = 1;
  int _minutes = 30;

  /// 预设时长 + 菜谱自己的时长。老数据里有 35、70 这种不在预设里的值，
  /// 不补进去 DropdownButton 会因为找不到匹配项直接断言失败。
  List<int> get _minuteOptions {
    final list = <int>{10, 15, 20, 25, 30, 45, 60, 90, 120, 180, _minutes}.toList()
      ..sort();
    return list;
  }
  int _servings = 2;
  String? _imagePath;
  final List<String> _tags = [];
  final List<_IngEdit> _ings = [];
  final List<_StepEdit> _steps = [];
  bool _loading = true;
  bool _ocrBusy = false;
  String _ocrStatus = '';

  /// 识别计时，用来估算剩余时间。只统计本次识别的分片速度。
  Stopwatch? _ocrWatch;

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
        _tipsCtrl.text = d.recipe.tips ?? '';
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
    // 带着「撤销」的提示条属于这个页面的临时状态，页面没了就收掉，
    // 否则返回列表后还能点，回调会打到已销毁的 State 上。
    _messenger?.clearSnackBars();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _tipsCtrl.dispose();
    _tagCtrl.dispose();
    for (final i in _ings) {
      i.dispose();
    }
    for (final s in _steps) {
      s.dispose();
    }
    super.dispose();
  }

  ScaffoldMessengerState? _messenger;

  void _snack(String msg, {VoidCallback? undo}) {
    final m = ScaffoldMessenger.of(context);
    _messenger = m;
    m.showSnackBar(SnackBar(
      content: Text(msg),
      duration: Duration(seconds: undo == null ? 4 : 8),
      action: undo == null
          ? null
          : SnackBarAction(label: '撤销', onPressed: undo),
    ));
  }

  Future<void> _pickImage({bool camera = false}) async {
    final name = await pickAndStoreImage(fromCamera: camera);
    if (name == null) return;
    final file = File(imageFullPath(name));

    // 裁剪页要知道原图尺寸才能算显示比例
    double w = 0;
    double h = 0;
    ui.Codec? codec;
    ui.Image? img;
    try {
      codec = await ui.instantiateImageCodec(await file.readAsBytes());
      img = (await codec.getNextFrame()).image;
      w = img.width.toDouble();
      h = img.height.toDouble();
    } catch (e) {
      // 解不出来就直接用原图当封面，别让用户白选一次
      debugPrint('cover decode failed: ' + e.toString());
      if (mounted) setState(() => _imagePath = name);
      return;
    } finally {
      img?.dispose();
      try {
        codec?.dispose();
      } catch (_) {}
    }
    if (!mounted) return;

    final r = await Navigator.of(context).push<Rect?>(
      MaterialPageRoute(
        builder: (_) => StepCropPage(
          source: file,
          imageWidth: w,
          imageHeight: h,
          initial: null,
          stepIndex: 0,
          stepText: '',
          title: '封面图',
        ),
      ),
    );
    if (!mounted) return;

    // 返回键退出：什么都没决定，原图留着当封面
    if (r == null) {
      setState(() => _imagePath = name);
      return;
    }
    // 明确点了「不要这张」：这次不设封面
    if (r == Rect.zero) {
      _discardImage(name);
      setState(() => _imagePath = null);
      return;
    }
    final cropped = await _cropCover(file, r, h.round());
    if (!mounted) return;
    if (cropped == null) {
      // 裁失败就用原图，别把用户选的图弄丢
      setState(() => _imagePath = name);
      return;
    }
    _discardImage(name);
    setState(() => _imagePath = cropped);
  }

  /// 点封面时弹「拍一张 / 从相册选 / 移除图片」。详情页不再管封面，
  /// 三个操作都收在这里，桌面端没有相机就不显示「拍一张」。
  Future<void> _coverOptions() async {
    final action = await showCoverActions(
      context,
      allowCamera: Platform.isAndroid || Platform.isIOS,
      hasImage: _imagePath != null,
    );
    if (action == null || !mounted) return;
    switch (action) {
      case CoverAction.camera:
        await _pickImage(camera: true);
      case CoverAction.gallery:
        await _pickImage();
      case CoverAction.remove:
        setState(() => _imagePath = null);
    }
  }

  void _discardImage(String name) {
    try {
      File(imageFullPath(name)).deleteSync();
    } catch (_) {}
  }

  /// 按框裁一张封面。流程和步骤图一样：先出 PNG，再让原生转 JPEG。
  Future<String?> _cropCover(File src, Rect rect, int sourceHeight) async {
    final name =
        'cover_' + DateTime.now().millisecondsSinceEpoch.toString() + '.jpg';
    final finalPath = imageFullPath(name);
    final tmp = finalPath + '.tmp.png';
    final ok = await cropRegionToFile(
      src,
      rect,
      tmp,
      sourceHeight: sourceHeight,
    );
    if (!ok) return null;
    final n = await shrinkToJpeg(tmp, finalPath);
    if (n == null) {
      try {
        File(tmp).renameSync(finalPath);
      } catch (_) {}
      return name;
    }
    try {
      File(tmp).deleteSync();
    } catch (_) {}
    return name;
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

  /// 原生每识别完一片回报一次。
  void _onOcrProgress(int done, int total) {
    if (!mounted) return;
    final ms = _ocrWatch?.elapsedMilliseconds ?? 0;
    setState(() => _ocrStatus = ocrProgressText(done, total, ms));
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

      // 计时从真正开始识别算起。放到选图之前的话，用户在相册里停留的
      // 几十秒会被算进「每片耗时」，剩余时间能估出四五十秒。
      _ocrWatch = Stopwatch()..start();
      final layout = await recognizeLayout(
        file,
        onProgress: (done, total) => _onOcrProgress(done, total),
      );
      _ocrWatch?.stop();
      if (layout == null) {
        if (!mounted) return;
        setState(() {
          _ocrBusy = false;
          _ocrStatus = '';
        });
        _snack('没读到文字，换张更清晰的图（正对、光足、别糊）');
        return;
      }

      // 用数据库里的规则，设置里改过的分组和单位立刻生效。
      final parsed = parseScreenRecipe(layout, rules: appDb.ingredientRuleSet());
      if (parsed.isEmpty) {
        // 解析失败时最需要留档
        await OcrRawStore.save(layout, sourceImage: file.path);
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

      // 原始行留档，出问题时能在设置里导出来看
      await OcrRawStore.save(
        layout,
        sourceImage: file.path,
        recipeName: parsed.name,
      );

      if (mounted) {
        setState(() => _ocrStatus = '识别完了，正在裁步骤图');
      }
      final rects = <Rect?>[];
      final crops = <String?>[];
      for (var i = 0; i < parsed.steps.length; i++) {
        final rect = parsed.steps[i].imageRect;
        rects.add(rect);
        crops.add(rect == null
            ? null
            : await _saveStepCrop(src, rect, i, layout.height));
      }

      if (!mounted) return;
      setState(() {
        _ocrBusy = false;
        _ocrStatus = '';
      });

      // 自动框只是「这一步区域里最大的空白块」，经常框歪。截完先让用户
      // 过一眼，不满意的当场拖四条边重截。
      // 封面先按自动检测的成品图位置裁一张，用户在检查页里还能调
      final coverBox = <String?>[
        parsed.coverRect == null
            ? null
            : await _saveStepCrop(src, parsed.coverRect!, -1, layout.height),
      ];
      if (!mounted) return;
      if (crops.any((c) => c != null) || coverBox[0] != null) {
        final reviewed = await Navigator.of(context).push<List<String?>>(
          MaterialPageRoute(
            builder: (_) => StepCropReviewPage(
              source: src,
              imageWidth: layout.width.toDouble(),
              imageHeight: layout.height.toDouble(),
              texts: parsed.steps.map((s) => s.text).toList(),
              rects: rects,
              crops: crops,
              coverBox: coverBox,
              coverRect: parsed.coverRect,
              onCoverChanged: (name) {
                if (mounted) setState(() => _imagePath = name);
              },
              onRecrop: (rect, index) =>
                  _saveStepCrop(src, rect, index, layout.height),
            ),
          ),
        );
        if (!mounted) return;
        if (reviewed != null) {
          for (var i = 0; i < crops.length && i < reviewed.length; i++) {
            crops[i] = reviewed[i];
          }
        }
      }

      // 直接覆盖表单，不再弹确认框；同时留一份快照给「撤销」。
      final snapshot = _snapshotForm();

      setState(() {
        if (parsed.name != null && parsed.name!.isNotEmpty) {
          _nameCtrl.text = parsed.name!;
        }
        if (parsed.description != null && parsed.description!.isNotEmpty) {
          _descCtrl.text = parsed.description!;
        }
        if (parsed.tips != null && parsed.tips!.isNotEmpty) {
          _tipsCtrl.text = parsed.tips!;
        }
        for (final i in _ings) {
          i.dispose();
        }
        _ings.clear();
        for (final i in parsed.ingredients) {
          _ings.add(_IngEdit(
            name: i.name,
            qty: i.qty == null ? '' : _trimNum(i.qty!),
            grp: i.group.isEmpty ? '主料' : i.group,
            unit: i.unit ?? (i.qty == null ? '' : '克'),
            low: i.low,
          ));
        }
        for (final s in _steps) {
          s.dispose();
        }
        _steps.clear();
        for (var i = 0; i < parsed.steps.length; i++) {
          _steps.add(_StepEdit(
            text: parsed.steps[i].text,
            imagePath: i < crops.length ? crops[i] : null,
            low: parsed.steps[i].low,
          ));
        }
        if (_ings.isEmpty) _ings.add(_IngEdit());
        if (_steps.isEmpty) _steps.add(_StepEdit());
        // 检查配图页可能已经选好封面了，别拿源图盖掉它
        if (stored != null && _imagePath == null) _imagePath = stored;
      });
      _snack(
        '已识别 ' +
            parsed.summary +
            (parsed.droppedLines > 0
                ? '，跳过 ' + parsed.droppedLines.toString() + ' 行广告/界面'
                : '') +
            '，检查一下再保存',
        undo: () => _restoreForm(snapshot),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ocrBusy = false;
        _ocrStatus = '';
      });
      _snack('识别失败：' + e.toString());
    }
  }

  /// 导入前的表单快照，用于撤销。
  List<Object?> _snapshotForm() => [
        _nameCtrl.text,
        _descCtrl.text,
        [for (final i in _ings) [i.nameCtrl.text, i.qtyCtrl.text, i.unit, i.grp, i.low]],
        [for (final s in _steps) [s.textCtrl.text, s.timerSeconds, s.imagePath, s.low]],
        _imagePath,
        _tipsCtrl.text,
      ];

  void _restoreForm(List<Object?> snap) {
    if (!mounted) return;
    setState(() {
      _nameCtrl.text = snap[0] as String;
      _descCtrl.text = snap[1] as String;
      final ings = snap[2] as List;
      for (final i in _ings) {
        i.dispose();
      }
      _ings.clear();
      for (final raw in ings) {
        final v = raw as List;
        _ings.add(_IngEdit(
          name: v[0] as String,
          qty: v[1] as String,
          grp: v[3] as String,
          unit: v[2] as String,
          low: v.length > 4 && v[4] == true,
        ));
      }
      final steps = snap[3] as List;
      for (final s in _steps) {
        s.dispose();
      }
      _steps.clear();
      for (final raw in steps) {
        final v = raw as List;
        _steps.add(_StepEdit(
          text: v[0] as String,
          timerSeconds: v[1] as int?,
          imagePath: v[2] as String?,
          low: v.length > 3 && v[3] == true,
        ));
      }
      _imagePath = snap[4] as String?;
      _tipsCtrl.text = snap[5] as String;
      if (_ings.isEmpty) _ings.add(_IngEdit());
      if (_steps.isEmpty) _steps.add(_StepEdit());
    });
    _snack('已还原到导入前');
  }

  Future<String?> _saveStepCrop(
    File source,
    Rect rect,
    int index,
    int sourceHeight,
  ) async {
    final prefix = index < 0 ? 'cover_' : 'step_';
    final name = prefix +
        DateTime.now().millisecondsSinceEpoch.toString() +
        '_' +
        index.toString() +
        '.jpg';
    final finalPath = imageFullPath(name);
    // cropRegionToFile 只能写 PNG（Flutter 的 toByteData 只支持 PNG），
    // 先落临时文件再让原生转成 JPEG。步骤图是照片，PNG 一张要 1 MB 多。
    final tmp = finalPath + '.tmp.png';
    final ok = await cropRegionToFile(
      source,
      rect,
      tmp,
      sourceHeight: sourceHeight,
    );
    if (!ok) return null;
    final n = await shrinkToJpeg(tmp, finalPath);
    if (n == null) {
      // 转码失败就把 PNG 留下，图不能丢
      try {
        File(tmp).renameSync(finalPath);
      } catch (_) {}
      return name;
    }
    try {
      File(tmp).deleteSync();
    } catch (_) {}
    return name;
  }

  void _addTag() {
    final v = _tagCtrl.text.trim();
    if (v.isEmpty) return;
    if (!_tags.contains(v)) setState(() => _tags.add(v));
    _tagCtrl.clear();
  }

  Future<void> _save() async {
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
      tips: _tipsCtrl.text.trim().isEmpty ? null : _tipsCtrl.text.trim(),
      tags: List<String>.from(_tags),
      ingredients: ings,
      steps: steps,
    );
    // 保存前记下旧的图片，保存后再删。编辑时换封面/换步骤图会留下旧文件，
    // 但中途放弃编辑时不能删，所以只能等到这里。
    final before = <String>{};
    if (widget.recipeId != null) {
      final d = appDb.detail(widget.recipeId!);
      if (d != null) {
        if (d.recipe.imagePath != null) before.add(d.recipe.imagePath!);
        for (final s in d.steps) {
          if (s.imagePath != null) before.add(s.imagePath!);
        }
      }
    }
    final savedId = appDb.saveRecipe(draft, searchKey(name));
    if (before.isNotEmpty) {
      final after = appDb.referencedImages();
      for (final n in before) {
        if (!after.contains(n)) await deleteImageQuietly(n);
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(savedId);
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
            onTap: _coverOptions,
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
          const SizedBox(height: 12),
          TextField(
            controller: _tipsCtrl,
            maxLines: 4,
            minLines: 1,
            decoration: const InputDecoration(
              labelText: '小贴士（可选）',
              hintText: '火候、替换食材、翻车教训都写这儿',
              alignLabelWithHint: true,
            ),
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
            initialValue: _minuteOptions.contains(_minutes) ? _minutes : null,
            items: [
              for (final m in _minuteOptions)
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
                onPressed: _applyRulesToForm,
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: const Text('整理'),
              ),
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

  /// 识别置信度偏低时的小标，点一下收掉。
  Widget _lowMark(VoidCallback onDismiss) => Tooltip(
        message: '这行的字识别得没把握，核对一下',
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onDismiss,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 2),
            child: Icon(Icons.error_outline, size: 16, color: Color(0xFFE69138)),
          ),
        ),
      );

  Widget _ingRow(int index) {
    final e = _ings[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (e.low) _lowMark(() => setState(() => e.low = false)),
          GestureDetector(
            onTap: () async {
              final picked = await _askChoice(
                title: '用料分组',
                options: kIngredientGroups,
                current: e.grp,
                hint: '自定义分组',
              );
              if (picked != null && mounted) setState(() => e.grp = picked);
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
              decoration: InputDecoration(
                hintText: '名称',
                enabledBorder: e.low
                    ? OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0xFFE69138)),
                        borderRadius: BorderRadius.circular(4),
                      )
                    : null,
              ),
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
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () async {
                final picked = await _askChoice(
                  title: '单位',
                  options: kUnits,
                  current: e.unit,
                  hint: '自定义单位',
                  allowEmpty: true,
                );
                if (picked != null && mounted) setState(() => e.unit = picked);
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                ),
                child: Text(
                  e.unit.isEmpty ? '无' : e.unit,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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
                if (s.low) ...[
                  const SizedBox(width: 6),
                  _lowMark(() => setState(() => s.low = false)),
                ],
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
                for (final opt in _timerPresets)
                  ChoiceChip(
                    label: Text(opt == null ? '不用计时' : _timerLabel(opt)),
                    selected: s.timerSeconds == opt,
                    onSelected: (_) => setState(() => s.timerSeconds = opt),
                  ),
                ChoiceChip(
                  label: Text(
                    _isCustomTimer(s.timerSeconds)
                        ? _timerLabel(s.timerSeconds!) + ' 自定义'
                        : '自定义',
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: _isCustomTimer(s.timerSeconds),
                  onSelected: (_) => _pickCustomTimer(index),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 按识别规则重排当前表单：用料分组、缺的单位，以及步骤的换行。
  /// 只改这一份表单，保存才落库。
  void _applyRulesToForm() {
    final rules = appDb.ingredientRuleSet();
    var touched = 0;
    setState(() {
      for (final e in _ings) {
        final name = e.nameCtrl.text.trim();
        if (name.isEmpty) continue;
        final rule = rules.lookup(name);
        if (rule != null) {
          if (rule.grp.isNotEmpty && e.grp != rule.grp) {
            e.grp = rule.grp;
            touched++;
          }
          if (rule.unit.isNotEmpty && e.unit.trim().isEmpty) {
            e.unit = rule.unit;
            touched++;
          }
        }
        // 「开水一」+ 壶 这种，把尾巴上的数字还原成数量
        final qty = double.tryParse(e.qtyCtrl.text.trim());
        final fixed = splitTrailingQuantity(name, e.unit, qty);
        if (fixed.name != name) {
          e.nameCtrl.text = fixed.name;
          touched++;
        }
        if (fixed.qty != null && qty == null) {
          e.qtyCtrl.text = _trimNum(fixed.qty!);
          touched++;
        }
      }
      for (final s in _steps) {
        final text = s.textCtrl.text;
        final fixed = joinBySentence(text.split('\n'));
        if (fixed != text) {
          s.textCtrl.text = fixed;
          touched++;
        }
      }
    });
    _snack(
      touched == 0 ? '已经是整理好的状态了' : '整理了 ' + touched.toString() + ' 处',
    );
  }

  /// 分组 / 单位这类「常用几个 + 想自己填也行」的选择。
  Future<String?> _askChoice({
    required String title,
    required List<String> options,
    required String current,
    String hint = '自定义',
    bool allowEmpty = false,
  }) async {
    final ctrl = TextEditingController();
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (allowEmpty)
                      ChoiceChip(
                        label: const Text('无'),
                        selected: current.isEmpty,
                        onSelected: (_) => Navigator.of(ctx).pop(''),
                      ),
                    for (final o in options)
                      ChoiceChip(
                        label: Text(o),
                        selected: o == current,
                        onSelected: (_) => Navigator.of(ctx).pop(o),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: ctrl,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (v) {
                          final t = v.trim();
                          if (t.isNotEmpty) Navigator.of(ctx).pop(t);
                        },
                        decoration: InputDecoration(
                          labelText: hint,
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        final t = ctrl.text.trim();
                        if (t.isNotEmpty) Navigator.of(ctx).pop(t);
                      },
                      child: const Text('确定'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<void> _pickStepImage(int index) async {
    final stored = await pickAndStoreImage();
    if (stored == null) return;
    if (!mounted) return;
    setState(() => _steps[index].imagePath = stored);
  }

  /// 常用时长：1 / 3 / 5 / 10 / 30 分钟，其余的走最后那个「自定义」。
  static const List<int?> _timerPresets = [
    null,
    60,
    180,
    300,
    600,
    1800,
  ];

  bool _isCustomTimer(int? sec) => sec != null && !_timerPresets.contains(sec);

  Future<void> _pickCustomTimer(int index) async {
    final current = _steps[index].timerSeconds ?? 300;
    final hourCtrl = TextEditingController(text: (current ~/ 3600).toString());
    final ctrl = TextEditingController(
      text: ((current % 3600) ~/ 60).toString(),
    );
    final secCtrl = TextEditingController(
      text: (current % 60).toString().padLeft(2, '0'),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义计时'),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: TextField(
                controller: hourCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '时'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '分'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: secCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '秒'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final h = int.tryParse(hourCtrl.text.trim()) ?? 0;
    final m = int.tryParse(ctrl.text.trim()) ?? 0;
    final s = int.tryParse(secCtrl.text.trim()) ?? 0;
    final total = (h * 3600 + m * 60 + s).clamp(5, 24 * 3600);
    if (mounted) setState(() => _steps[index].timerSeconds = total);
  }

  String _timerLabel(int sec) {
    if (sec < 60) return sec.toString() + ' 秒';
    if (sec >= 3600) {
      final h = sec ~/ 3600;
      final m = (sec % 3600) ~/ 60;
      final s = sec % 60;
      final out = h.toString() + ' 时';
      if (m == 0 && s == 0) return out;
      if (s == 0) return out + ' ' + m.toString() + ' 分';
      return out + ' ' + m.toString() + ' 分 ' + s.toString() + ' 秒';
    }
    if (sec % 60 == 0) return (sec ~/ 60).toString() + ' 分';
    return (sec ~/ 60).toString() + ' 分 ' + (sec % 60).toString() + ' 秒';
  }
}
