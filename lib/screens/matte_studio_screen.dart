import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/sample_scene.dart';
import '../models/standee_asset.dart';
import '../services/auto_matte_engine.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/checkerboard_painter.dart';

enum _PreviewBackdrop { checkerboard, dark, light, realScene }

/// Feature 3b: Interactive Hybrid Auto-Matting Studio.
/// - Instant Anime Line-Aware & Smart Border Flood & Chroma Key background removal (pure Dart Isolate)
/// - Optional On-Device ONNX AI Matting (RMBG-1.4 / IS-Net-Anime / U2Net)
/// - Real-time Defringe (去白边), Feather, Edge Shrink & Tolerance controls
/// - Interactive Erase / Restore / Magic Wand / Eyedropper refinement tools with Undo stack
class MatteStudioScreen extends StatefulWidget {
  final AppController controller;
  final Uint8List sourceBytes;
  final String initialName;
  final String? overwriteAssetId;

  const MatteStudioScreen({
    super.key,
    required this.controller,
    required this.sourceBytes,
    required this.initialName,
    this.overwriteAssetId,
  });

  @override
  State<MatteStudioScreen> createState() => _MatteStudioScreenState();
}

class _MatteStudioScreenState extends State<MatteStudioScreen> {
  late final TextEditingController _nameCtrl;

  MatteConfig _config = const MatteConfig(
    mode: MatteMode.animeLineAware,
    tolerance: 30.0,
    softness: 18.0,
    featherRadius: 1.0,
    defringeStrength: 0.85,
    edgeShrink: 1,
    autoCrop: false, // Keep uncropped during live interactive brush editing, auto-crop on final save!
  );

  MatteBrushTool _activeTool = MatteBrushTool.none;
  double _brushRadius = 0.04;
  _PreviewBackdrop _backdrop = _PreviewBackdrop.checkerboard;

  final List<MatteStroke> _strokes = [];
  List<Offset> _currentStrokePoints = [];

  MatteResult? _previewResult;
  bool _isProcessing = true;
  bool _isSaving = false;
  String? _errorText;
  double _sourceAspect = 0.66;
  img.Image? _decodedSourceForEyedropper;

  Timer? _debounceTimer;
  int _requestToken = 0;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _decodeSourceMeta();
    _scheduleMatte(immediate: true);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _decodeSourceMeta() {
    final decoded = img.decodeImage(widget.sourceBytes);
    if (decoded != null && decoded.height > 0) {
      _decodedSourceForEyedropper = decoded;
      _sourceAspect = decoded.width / decoded.height;
    }
  }

  Future<void> _configureOnnxPathDialog() async {
    final ctrl = TextEditingController(
      text: widget.controller.settings.onnxModelPath,
    );
    int inputSize = widget.controller.settings.onnxInputSize;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: AppTheme.surfaceDark,
          title: const Text('配置本地 ONNX 抠图模型'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  labelText: '本地 .onnx 模型路径',
                  hintText: '/path/to/rmbg-1.4.onnx 或 isnet-anime.onnx',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('320px'),
                    selected: inputSize == 320,
                    onSelected: (_) => setModalState(() => inputSize = 320),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('1024px'),
                    selected: inputSize == 1024,
                    onSelected: (_) => setModalState(() => inputSize = 1024),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      await widget.controller.updateSettings(
        widget.controller.settings.copyWith(
          onnxModelPath: ctrl.text.trim(),
          onnxInputSize: inputSize,
        ),
      );
      if (mounted) _scheduleMatte(immediate: true);
    }
    ctrl.dispose();
  }

  void _scheduleMatte({bool immediate = false}) {
    _debounceTimer?.cancel();
    if (immediate) {
      _runMattePreview();
    } else {
      _debounceTimer = Timer(const Duration(milliseconds: 220), _runMattePreview);
    }
  }

  Future<void> _runMattePreview() async {
    final token = ++_requestToken;
    setState(() {
      _isProcessing = true;
      _errorText = null;
    });

    try {
      final result = await AutoMatteEngine.processBytes(
        inputBytes: widget.sourceBytes,
        config: _config.copyWith(autoCrop: false),
        strokes: _strokes,
        onnxModelPath: widget.controller.settings.onnxModelPath,
        onnxInputSize: widget.controller.settings.onnxInputSize,
        maxDimension: 1000, // Fast responsive preview resolution
      );

      if (!mounted || token != _requestToken) return;
      setState(() {
        _previewResult = result;
        _isProcessing = false;
      });
    } on OnnxModelNotConfiguredException catch (e) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _isProcessing = false;
        _errorText = e.message;
      });
    } catch (e) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _isProcessing = false;
        _errorText = '抠图处理失败：$e';
      });
    }
  }

  Future<void> _saveToLibrary() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      // High-res final render with clean auto-crop
      final finalMatte = await AutoMatteEngine.processBytes(
        inputBytes: widget.sourceBytes,
        config: _config.copyWith(autoCrop: true),
        strokes: _strokes,
        onnxModelPath: widget.controller.settings.onnxModelPath,
        onnxInputSize: widget.controller.settings.onnxInputSize,
        maxDimension: 1800,
      );

      final name = _nameCtrl.text.trim().isEmpty ? '二次元立绘' : _nameCtrl.text.trim();
      final StandeeAsset saved = await widget.controller.saveMattedStandee(
        name: name,
        cutoutPngBytes: finalMatte.pngBytes,
        originalBytes: widget.sourceBytes,
        width: finalMatte.width,
        height: finalMatte.height,
        matteMethod: finalMatte.methodUsed,
        overwriteId: widget.overwriteAssetId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存立绘失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _handleCanvasTapOrDraw(Offset localPos, Size canvasSize, {required bool isEnd}) {
    final nx = (localPos.dx / canvasSize.width).clamp(0.0, 1.0);
    final ny = (localPos.dy / canvasSize.height).clamp(0.0, 1.0);

    if (_activeTool == MatteBrushTool.eyedropper) {
      if (isEnd && _decodedSourceForEyedropper != null) {
        final src = _decodedSourceForEyedropper!;
        final px = (nx * src.width).round().clamp(0, src.width - 1);
        final py = (ny * src.height).round().clamp(0, src.height - 1);
        final p = src.getPixel(px, py);
        final pickedColor = Color.fromARGB(
          255,
          p.r.toInt(),
          p.g.toInt(),
          p.b.toInt(),
        );
        setState(() {
          _config = _config.copyWith(
            mode: MatteMode.chromaKey,
            keyColorValue: pickedColor.toARGB32(),
          );
        });
        _scheduleMatte(immediate: true);
      }
      return;
    }

    if (_activeTool == MatteBrushTool.magicWand) {
      if (isEnd) {
        setState(() {
          _strokes.add(
            MatteStroke(
              tool: MatteBrushTool.magicWand,
              points: [Offset(nx, ny)],
              wandTolerance: _config.tolerance,
            ),
          );
        });
        _scheduleMatte(immediate: true);
      }
      return;
    }

    if (_activeTool == MatteBrushTool.erase ||
        _activeTool == MatteBrushTool.restore) {
      setState(() {
        _currentStrokePoints = [..._currentStrokePoints, Offset(nx, ny)];
      });
      if (isEnd && _currentStrokePoints.isNotEmpty) {
        setState(() {
          _strokes.add(
            MatteStroke(
              tool: _activeTool,
              points: List<Offset>.from(_currentStrokePoints),
              radiusNormalized: _brushRadius,
            ),
          );
          _currentStrokePoints = [];
        });
        _scheduleMatte(immediate: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgObsidian,
      appBar: AppBar(
        title: const Text('智能立绘抠图'),
        actions: [
          if (_strokes.isNotEmpty)
            IconButton(
              tooltip: '撤销上一笔',
              icon: const Icon(Icons.undo_rounded),
              onPressed: () {
                setState(() => _strokes.removeLast());
                _scheduleMatte(immediate: true);
              },
            ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accentAmber,
                foregroundColor: Colors.black,
              ),
              onPressed: (_isSaving || _previewResult == null) ? null : _saveToLibrary,
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Text('保存素材', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Name & Preview Backdrop Switcher Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      controller: _nameCtrl,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '立绘名称',
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        filled: true,
                        fillColor: AppTheme.surfaceDark,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppTheme.borderSubtle),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SegmentedButton<_PreviewBackdrop>(
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 6),
                    ),
                  ),
                  segments: const [
                    ButtonSegment(
                      value: _PreviewBackdrop.checkerboard,
                      icon: Icon(Icons.grid_4x4_rounded, size: 15),
                    ),
                    ButtonSegment(
                      value: _PreviewBackdrop.dark,
                      icon: Icon(Icons.dark_mode_rounded, size: 15),
                    ),
                    ButtonSegment(
                      value: _PreviewBackdrop.light,
                      icon: Icon(Icons.light_mode_rounded, size: 15),
                    ),
                    ButtonSegment(
                      value: _PreviewBackdrop.realScene,
                      icon: Icon(Icons.landscape_rounded, size: 15),
                    ),
                  ],
                  selected: {_backdrop},
                  onSelectionChanged: (s) => setState(() => _backdrop = s.first),
                ),
              ],
            ),
          ),

          // 2. Interactive Cutout Inspection & Brush Canvas
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: AspectRatio(
                  aspectRatio: _sourceAspect.clamp(0.42, 1.7),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildBackdrop(),
                        _buildInteractiveMatteCanvas(),
                        if (_isProcessing)
                          Container(
                            color: Colors.black38,
                            alignment: Alignment.center,
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                    color: AppTheme.accentAmber),
                                SizedBox(height: 10),
                                Text(
                                  '正在执行自动抠图与边缘去白边...',
                                  style: TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        if (_errorText != null)
                          Container(
                            color: const Color(0xDD0A0C10),
                            padding: const EdgeInsets.all(20),
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.warning_amber_rounded,
                                    color: AppTheme.accentAmber, size: 36),
                                const SizedBox(height: 10),
                                Text(
                                  _errorText!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: AppTheme.textPrimary, fontSize: 13),
                                ),
                                const SizedBox(height: 14),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    OutlinedButton(
                                      onPressed: _configureOnnxPathDialog,
                                      child: const Text('指定本地 .onnx 文件'),
                                    ),
                                    FilledButton(
                                      onPressed: () {
                                        setState(() {
                                          _config = _config.copyWith(
                                            mode: MatteMode.animeLineAware,
                                          );
                                        });
                                        _scheduleMatte(immediate: true);
                                      },
                                      child: const Text('改用二次元护线抠图'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 3. Controls & Refinement Tool Deck
          Container(
            decoration: const BoxDecoration(
              color: AppTheme.surfaceDark,
              border: Border(top: BorderSide(color: AppTheme.borderSubtle)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 256,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  children: [
                    // Mode selector
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: MatteMode.values.map((m) {
                          final selected = _config.mode == m;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(m.label),
                              selected: selected,
                              onSelected: (_) {
                                setState(() => _config = _config.copyWith(mode: m));
                                _scheduleMatte(immediate: true);
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: Text(
                        _config.mode.description,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 11),
                      ),
                    ),

                    // Interactive Manual Refinement Tools
                    Row(
                      children: [
                        _ToolChip(
                          icon: Icons.pan_tool_alt_outlined,
                          label: '缩放查看',
                          selected: _activeTool == MatteBrushTool.none,
                          onTap: () =>
                              setState(() => _activeTool = MatteBrushTool.none),
                        ),
                        _ToolChip(
                          icon: Icons.cleaning_services_outlined,
                          label: '擦除背景',
                          selected: _activeTool == MatteBrushTool.erase,
                          onTap: () =>
                              setState(() => _activeTool = MatteBrushTool.erase),
                        ),
                        _ToolChip(
                          icon: Icons.brush_rounded,
                          label: '恢复主体',
                          selected: _activeTool == MatteBrushTool.restore,
                          onTap: () =>
                              setState(() => _activeTool = MatteBrushTool.restore),
                        ),
                        _ToolChip(
                          icon: Icons.auto_fix_normal_rounded,
                          label: '魔棒去洞',
                          selected: _activeTool == MatteBrushTool.magicWand,
                          onTap: () => setState(
                              () => _activeTool = MatteBrushTool.magicWand),
                        ),
                        _ToolChip(
                          icon: Icons.colorize_rounded,
                          label: '吸色去背',
                          selected: _activeTool == MatteBrushTool.eyedropper,
                          onTap: () => setState(
                              () => _activeTool = MatteBrushTool.eyedropper),
                        ),
                      ],
                    ),

                    if (_activeTool == MatteBrushTool.erase ||
                        _activeTool == MatteBrushTool.restore)
                      _MatteSlider(
                        label: '画笔大小',
                        valueText: '${(_brushRadius * 100).round()}%',
                        value: _brushRadius,
                        min: 0.012,
                        max: 0.12,
                        onChanged: (v) => setState(() => _brushRadius = v),
                      ),

                    if (_config.mode != MatteMode.onnxAi) ...[
                      _MatteSlider(
                        label: '背景容差',
                        valueText: _config.tolerance.round().toString(),
                        value: _config.tolerance,
                        min: 6,
                        max: 95,
                        onChanged: (v) {
                          setState(() => _config = _config.copyWith(tolerance: v));
                          _scheduleMatte();
                        },
                      ),
                      _MatteSlider(
                        label: '边缘过渡柔和',
                        valueText: _config.softness.round().toString(),
                        value: _config.softness,
                        min: 2,
                        max: 45,
                        onChanged: (v) {
                          setState(() => _config = _config.copyWith(softness: v));
                          _scheduleMatte();
                        },
                      ),
                    ],
                    _MatteSlider(
                      label: '去白边溢色净化',
                      valueText: '${(_config.defringeStrength * 100).round()}%',
                      value: _config.defringeStrength,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (v) {
                        setState(
                            () => _config = _config.copyWith(defringeStrength: v));
                        _scheduleMatte();
                      },
                    ),
                    _MatteSlider(
                      label: '边缘收缩 (防杂边)',
                      valueText: '${_config.edgeShrink}px',
                      value: _config.edgeShrink.toDouble(),
                      min: 0,
                      max: 3,
                      divisions: 3,
                      onChanged: (v) {
                        setState(
                            () => _config = _config.copyWith(edgeShrink: v.round()));
                        _scheduleMatte();
                      },
                    ),
                    _MatteSlider(
                      label: '透明羽化半径',
                      valueText: '${_config.featherRadius.toStringAsFixed(1)}px',
                      value: _config.featherRadius,
                      min: 0.0,
                      max: 3.5,
                      onChanged: (v) {
                        setState(
                            () => _config = _config.copyWith(featherRadius: v));
                        _scheduleMatte();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackdrop() {
    switch (_backdrop) {
      case _PreviewBackdrop.checkerboard:
        return const CustomPaint(painter: CheckerboardPainter(cellSize: 12));
      case _PreviewBackdrop.dark:
        return Container(color: const Color(0xFF0A0D14));
      case _PreviewBackdrop.light:
        return Container(color: const Color(0xFFF3F4F6));
      case _PreviewBackdrop.realScene:
        return Image.asset(
          SampleScene.builtInScenes.first.assetPath,
          fit: BoxFit.cover,
        );
    }
  }

  Widget _buildInteractiveMatteCanvas() {
    final previewBytes = _previewResult?.pngBytes;
    final imageWidget = previewBytes != null
        ? Image.memory(
            previewBytes,
            fit: BoxFit.fill,
            gaplessPlayback: true,
          )
        : Image.memory(
            widget.sourceBytes,
            fit: BoxFit.fill,
            opacity: const AlwaysStoppedAnimation(0.5),
          );

    if (_activeTool == MatteBrushTool.none) {
      return InteractiveViewer(
        minScale: 0.8,
        maxScale: 5.0,
        child: imageWidget,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) =>
              _handleCanvasTapOrDraw(d.localPosition, size, isEnd: true),
          onPanStart: (d) {
            _currentStrokePoints = [];
            _handleCanvasTapOrDraw(d.localPosition, size, isEnd: false);
          },
          onPanUpdate: (d) =>
              _handleCanvasTapOrDraw(d.localPosition, size, isEnd: false),
          onPanEnd: (_) {
            if (_currentStrokePoints.isNotEmpty) {
              _handleCanvasTapOrDraw(
                Offset(
                  _currentStrokePoints.last.dx * size.width,
                  _currentStrokePoints.last.dy * size.height,
                ),
                size,
                isEnd: true,
              );
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              imageWidget,
              if (_currentStrokePoints.isNotEmpty)
                CustomPaint(
                  painter: _LiveBrushPreviewPainter(
                    points: _currentStrokePoints,
                    radiusNorm: _brushRadius,
                    isRestore: _activeTool == MatteBrushTool.restore,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _LiveBrushPreviewPainter extends CustomPainter {
  final List<Offset> points;
  final double radiusNorm;
  final bool isRestore;

  const _LiveBrushPreviewPainter({
    required this.points,
    required this.radiusNorm,
    required this.isRestore,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth =
        (radiusNorm * 2.0 * (size.width < size.height ? size.width : size.height))
            .clamp(8.0, 120.0);
    final paint = Paint()
      ..color = (isRestore ? AppTheme.accentMint : AppTheme.accentRose)
          .withValues(alpha: 0.45)
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (points.length == 1) {
      canvas.drawCircle(
        Offset(points.first.dx * size.width, points.first.dy * size.height),
        strokeWidth * 0.5,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    final path = Path()
      ..moveTo(points.first.dx * size.width, points.first.dy * size.height);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx * size.width, points[i].dy * size.height);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _LiveBrushPreviewPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.radiusNorm != radiusNorm;
}

class _ToolChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToolChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2.5),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.accentCyan.withValues(alpha: 0.2)
                : AppTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppTheme.accentCyan : AppTheme.borderSubtle,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? AppTheme.accentCyan : AppTheme.textSecondary,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? AppTheme.accentCyan : AppTheme.textSecondary,
                  fontSize: 9.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MatteSlider extends StatelessWidget {
  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  const _MatteSlider({
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              valueText,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
