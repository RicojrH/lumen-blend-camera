import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/app_settings.dart';
import '../models/blend_recipe.dart';
import '../models/gallery_item.dart';
import '../services/ai_relighting_service.dart';
import '../services/lighting_probe_service.dart';
import '../services/perspective_engine.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/before_after_slider.dart';
import '../widgets/harmonized_standee_view.dart';
import '../widgets/interactive_horizon_overlay.dart';
import '../widgets/lighting_hud_bar.dart';
import '../widgets/perspective_grid_painter.dart';
import 'ai_engine_screen.dart';

enum _CompareViewMode { liveEdit, compareOriginal, compareAi }

/// Feature 2b: Full-screen Non-Destructive Photo Adjustment & Re-Blend Studio ("再次溶图").
/// - Live GPU preview over the preserved original background photo
/// - Adjust all physical lighting, shadow, optical DOF/grain, and placement/perspective parameters
/// - Swap anime standee directly onto the same photo OR load back into Camera Viewfinder
/// - Run optional Cloud / Custom AI Deep Relighting (Gemini / OpenAI / IC-Light)
/// - Interactive Before/After split slider comparison + save overwrite / save copy / export to album
class PhotoEditorScreen extends StatefulWidget {
  final AppController controller;
  final GalleryItem initialItem;

  const PhotoEditorScreen({
    super.key,
    required this.controller,
    required this.initialItem,
  });

  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  late GalleryItem _item;
  late BlendRecipe _recipe;

  ui.Image? _standeeUiImage;
  String? _loadedStandeePath;
  double _bgAspectRatio = 9 / 16;

  int _activeTab = 0; // 0=光影, 1=阴影光学, 2=再次溶图(换立绘/透视), 3=AI精修
  _CompareViewMode _viewMode = _CompareViewMode.liveEdit;
  bool _showGrid = false;
  bool _isSaving = false;
  bool _isRunningAi = false;
  bool _hasUnsavedChanges = false;

  // Multi-touch placement baseline
  double _startScale = 1.0;
  double _startRot = 0.0;
  Offset _startAnchor = const Offset(0.5, 0.85);
  Offset _startFocal = Offset.zero;

  AppController get _ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    _item = widget.initialItem;
    _recipe = _item.recipe;
    if (_item.hasAiEnhancement && _item.preferAiVersion) {
      _viewMode = _CompareViewMode.compareAi;
    }
    _loadResources();
  }

  Future<void> _loadResources() async {
    await _loadStandeeImage(_recipe.standeeId);
    try {
      final bytes = await _ctrl.storage.blobStore.readBytes(_item.backgroundPath);
      if (bytes != null) {
        final decoded = await decodeImageFromList(bytes);
        if (mounted && decoded.height > 0) {
          setState(() => _bgAspectRatio = decoded.width / decoded.height);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadStandeeImage(String standeeId) async {
    final standee = _ctrl.findStandeeById(standeeId);
    if (standee == null) return;
    if (_loadedStandeePath == standee.cutoutPath && _standeeUiImage != null) return;
    final imgUi = await _ctrl.loadUiImageForFile(standee.cutoutPath);
    if (!mounted) return;
    setState(() {
      _standeeUiImage = imgUi;
      _loadedStandeePath = standee.cutoutPath;
    });
  }

  void _updateRecipe(BlendRecipe next) {
    setState(() {
      _recipe = next;
      _hasUnsavedChanges = true;
      if (_viewMode == _CompareViewMode.compareAi) {
        _viewMode = _CompareViewMode.liveEdit;
      }
    });
  }

  Future<void> _reProbeLightingFromBackground() async {
    try {
      final bytes = await _ctrl.storage.blobStore.readBytes(_item.backgroundPath);
      if (bytes == null) return;
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return;
      final probed = LightingProbeService.analyzeImage(
        decoded,
        anchorX: _recipe.placement.anchorX,
        anchorY: _recipe.placement.anchorY,
        base: _recipe.lighting,
      );
      _updateRecipe(_recipe.copyWith(lighting: probed));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已重新采样环境光：${probed.kelvin.round()}K · 主光 ${probed.lightAzimuthDeg.round()}°',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('环境光分析失败：$e')),
      );
    }
  }

  Future<void> _saveRender({required bool asNewCopy}) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final updated = await _ctrl.reRenderGalleryItem(
        item: _item,
        newRecipe: _recipe,
        saveAsNewCopy: asNewCopy,
      );
      if (!mounted) return;
      setState(() {
        if (!asNewCopy) _item = updated;
        _hasUnsavedChanges = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(asNewCopy ? '已另存为新溶图成品' : '已高清渲染并保存修改'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('渲染保存失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _runAiDeepRelight() async {
    if (_isRunningAi) return;
    if (!_ctrl.settings.isAiConfigured) {
      await AiEngineScreen.push(context, _ctrl);
      if (!mounted || !_ctrl.settings.isAiConfigured) return;
    }

    setState(() => _isRunningAi = true);
    try {
      final updated = await _ctrl.runAiDeepRelight(
        item: _item,
        activeRecipe: _recipe,
      );
      if (!mounted) return;
      setState(() {
        _item = updated;
        _hasUnsavedChanges = false;
        _viewMode = _CompareViewMode.compareAi;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 深度光影溶图完成！可左右滑动对比效果')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI 深度溶图失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _isRunningAi = false);
    }
  }

  Future<void> _exportCurrent() async {
    // Save unsaved edits first so exported photo reflects latest adjustments
    if (_hasUnsavedChanges) {
      await _saveRender(asNewCopy: false);
    }
    final targetPath = _viewMode == _CompareViewMode.compareAi && _item.hasAiEnhancement
        ? _item.aiEnhancedPath!
        : _item.displayPath;
    final msg = await _ctrl.storage.exportToSystemAlbum(targetPath);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _reopenInCamera() async {
    await _ctrl.loadGalleryItemIntoCamera(_item.copyWith(recipe: _recipe));
    if (!mounted) return;
    // Pop back to root CameraBlendScreen
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgObsidian,
      appBar: AppBar(
        title: Text(
          _item.title,
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          IconButton(
            tooltip: '对比模式切换',
            icon: Icon(
              _viewMode == _CompareViewMode.liveEdit
                  ? Icons.compare_rounded
                  : Icons.edit_rounded,
              color: _viewMode == _CompareViewMode.liveEdit
                  ? AppTheme.textPrimary
                  : AppTheme.accentAmber,
            ),
            onPressed: () {
              setState(() {
                if (_viewMode == _CompareViewMode.liveEdit) {
                  _viewMode = _item.hasAiEnhancement
                      ? _CompareViewMode.compareAi
                      : _CompareViewMode.compareOriginal;
                } else {
                  _viewMode = _CompareViewMode.liveEdit;
                }
              });
            },
          ),
          IconButton(
            tooltip: '导出至系统相册',
            icon: const Icon(Icons.download_rounded),
            onPressed: _isSaving ? null : _exportCurrent,
          ),
          PopupMenuButton<String>(
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded, color: AppTheme.accentAmber),
            color: AppTheme.surfaceElevated,
            onSelected: (v) {
              if (v == 'overwrite') {
                _saveRender(asNewCopy: false);
              } else if (v == 'copy') {
                _saveRender(asNewCopy: true);
              } else if (v == 'camera') {
                _reopenInCamera();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'overwrite', child: Text('高清渲染并覆盖保存')),
              PopupMenuItem(value: 'copy', child: Text('另存为新溶图作品')),
              PopupMenuItem(value: 'camera', child: Text('带入相机再次溶图')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Live Interactive Preview Canvas (or Before/After Comparison Curtain)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: AspectRatio(
                  aspectRatio: _bgAspectRatio.clamp(0.45, 1.8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: _buildCanvasPreview(),
                  ),
                ),
              ),
            ),
          ),

          // 2. Bottom Non-Destructive Adjustment Deck
          Container(
            decoration: const BoxDecoration(
              color: AppTheme.surfaceDark,
              border: Border(top: BorderSide(color: AppTheme.borderSubtle)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Tab Switcher
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                    child: Row(
                      children: [
                        _EditorTabButton(
                          label: '光影匹配',
                          icon: Icons.wb_sunny_outlined,
                          selected: _activeTab == 0,
                          onTap: () => setState(() => _activeTab = 0),
                        ),
                        _EditorTabButton(
                          label: '阴影光学',
                          icon: Icons.blur_on_rounded,
                          selected: _activeTab == 1,
                          onTap: () => setState(() => _activeTab = 1),
                        ),
                        _EditorTabButton(
                          label: '再次溶图',
                          icon: Icons.switch_account_outlined,
                          selected: _activeTab == 2,
                          onTap: () => setState(() => _activeTab = 2),
                        ),
                        _EditorTabButton(
                          label: 'AI 精修',
                          icon: Icons.auto_awesome_rounded,
                          selected: _activeTab == 3,
                          accent: true,
                          onTap: () => setState(() => _activeTab = 3),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(
                    height: 214,
                    child: _buildActiveTabPanel(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvasPreview() {
    final bgWidget = _ctrl.storage.blobStore.buildImage(
      _item.backgroundPath,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(color: Colors.black),
    );

    Widget buildLiveComposite() {
      return LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (d) {
              _startScale = _recipe.placement.userScale;
              _startRot = _recipe.placement.rotationRad;
              _startAnchor = Offset(
                _recipe.placement.anchorX,
                _recipe.placement.anchorY,
              );
              _startFocal = d.focalPoint;
            },
            onScaleUpdate: (d) {
              final delta = d.focalPoint - _startFocal;
              final nx = (_startAnchor.dx + delta.dx / size.width).clamp(0.05, 0.95);
              final ny = (_startAnchor.dy + delta.dy / size.height).clamp(0.22, 0.98);
              final ns = (_startScale * d.scale).clamp(0.25, 2.5);
              final nr = d.pointerCount >= 2
                  ? (_startRot + d.rotation).clamp(-1.2, 1.2)
                  : _recipe.placement.rotationRad;

              _updateRecipe(
                _recipe.copyWith(
                  placement: _recipe.placement.copyWith(
                    anchorX: nx,
                    anchorY: ny,
                    userScale: ns,
                    rotationRad: nr,
                  ),
                ),
              );
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                bgWidget,
                if (_showGrid)
                  CustomPaint(
                    painter: PerspectiveGridPainter(
                      perspective: _recipe.perspective.copyWith(showGrid: true),
                      placement: _recipe.placement,
                      lighting: _recipe.lighting,
                    ),
                  ),
                if (_standeeUiImage != null)
                  HarmonizedStandeeView(
                    standeeImage: _standeeUiImage!,
                    shaderProgram: _ctrl.harmonizeProgram,
                    viewportSize: size,
                    placement: _recipe.placement,
                    perspective: _recipe.perspective,
                    lighting: _recipe.lighting,
                  ),
                if (_showGrid)
                  Positioned.fill(
                    child: InteractiveHorizonOverlay(
                      perspective: _recipe.perspective.copyWith(showGrid: true),
                      onChanged: (nextP) =>
                          _updateRecipe(_recipe.copyWith(perspective: nextP)),
                    ),
                  ),
              ],
            ),
          );
        },
      );
    }

    if (_viewMode == _CompareViewMode.compareOriginal) {
      return BeforeAfterSlider(
        beforeLabel: '原始环境照片',
        afterLabel: '端侧物理溶图',
        beforeChild: bgWidget,
        afterChild: buildLiveComposite(),
      );
    }

    if (_viewMode == _CompareViewMode.compareAi && _item.hasAiEnhancement) {
      return BeforeAfterSlider(
        beforeLabel: '端侧物理溶图',
        afterLabel: 'AI 深度光影重绘',
        beforeChild: _ctrl.storage.blobStore.buildImage(
          _item.compositePath,
          fit: BoxFit.cover,
        ),
        afterChild: _ctrl.storage.blobStore.buildImage(
          _item.aiEnhancedPath!,
          fit: BoxFit.cover,
        ),
      );
    }

    return buildLiveComposite();
  }

  Widget _buildActiveTabPanel() {
    switch (_activeTab) {
      case 0:
        return _buildLightingTab();
      case 1:
        return _buildShadowOpticsTab();
      case 2:
        return _buildReBlendTab();
      default:
        return _buildAiRelightTab();
    }
  }

  Widget _buildLightingTab() {
    final l = _recipe.lighting;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      children: [
        Row(
          children: [
            LightCompassDial(
              azimuthDeg: l.lightAzimuthDeg,
              size: 108,
              onChanged: (deg) => _updateRecipe(
                _recipe.copyWith(lighting: l.copyWith(lightAzimuthDeg: deg)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '光源方向：${l.lightAzimuthDeg.round()}°',
                    style: const TextStyle(
                      color: AppTheme.accentAmber,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    '拖动圆盘太阳点，自由调整受光面和影子投射方向',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _reProbeLightingFromBackground,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      side: const BorderSide(color: AppTheme.accentAmber),
                    ),
                    icon: const Icon(Icons.colorize_rounded,
                        size: 15, color: AppTheme.accentAmber),
                    label: const Text(
                      '一键自动匹配环境光',
                      style: TextStyle(fontSize: 11.5, color: AppTheme.accentAmber),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ParamSlider(
          label: '画面冷暖 (暖↔冷)',
          valueText: '${l.kelvin.round()}K',
          value: l.kelvin,
          min: 2600,
          max: 9500,
          onChanged: (v) => _updateRecipe(_recipe.copyWith(lighting: l.copyWith(kelvin: v))),
        ),
        _ParamSlider(
          label: '人物明暗 (暗↔亮)',
          valueText: '${l.exposureEv >= 0 ? '+' : ''}${l.exposureEv.toStringAsFixed(2)}',
          value: l.exposureEv,
          min: -1.4,
          max: 1.2,
          onChanged: (v) => _updateRecipe(_recipe.copyWith(lighting: l.copyWith(exposureEv: v))),
        ),
        _ParamSlider(
          label: '明暗反差',
          valueText: l.contrast.toStringAsFixed(2),
          value: l.contrast,
          min: 0.65,
          max: 1.40,
          onChanged: (v) => _updateRecipe(_recipe.copyWith(lighting: l.copyWith(contrast: v))),
        ),
        _ParamSlider(
          label: '色彩鲜艳度',
          valueText: '${(l.saturation * 100).round()}%',
          value: l.saturation,
          min: 0.45,
          max: 1.40,
          onChanged: (v) => _updateRecipe(_recipe.copyWith(lighting: l.copyWith(saturation: v))),
        ),
        _ParamSlider(
          label: '暗部柔和 (去死黑)',
          valueText: '${(l.blackLift * 100).round()}%',
          value: l.blackLift,
          min: 0.0,
          max: 0.24,
          onChanged: (v) => _updateRecipe(_recipe.copyWith(lighting: l.copyWith(blackLift: v))),
        ),
        _ParamSlider(
          label: '侧边受光强度',
          valueText: '${(l.directionalStrength * 100).round()}%',
          value: l.directionalStrength,
          min: 0.0,
          max: 1.0,
          onChanged: (v) => _updateRecipe(
            _recipe.copyWith(lighting: l.copyWith(directionalStrength: v)),
          ),
        ),
        _ParamSlider(
          label: '环境反光染色',
          valueText: '${(l.ambientStrength * 100).round()}%',
          value: l.ambientStrength,
          min: 0.0,
          max: 0.85,
          onChanged: (v) => _updateRecipe(
            _recipe.copyWith(lighting: l.copyWith(ambientStrength: v)),
          ),
        ),
        _ParamSlider(
          label: '边缘融光 (去生硬)',
          valueText: '${(l.lightWrap * 100).round()}%',
          value: l.lightWrap,
          min: 0.0,
          max: 1.0,
          onChanged: (v) => _updateRecipe(_recipe.copyWith(lighting: l.copyWith(lightWrap: v))),
        ),
        _ParamSlider(
          label: '整体融合强度',
          valueText: '${(l.blendStrength * 100).round()}%',
          value: l.blendStrength,
          min: 0.0,
          max: 1.0,
          onChanged: (v) => _updateRecipe(_recipe.copyWith(lighting: l.copyWith(blendStrength: v))),
        ),
      ],
    );
  }

  Widget _buildShadowOpticsTab() {
    final l = _recipe.lighting;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      children: [
        _ParamSlider(
          label: '影子深浅',
          valueText: '${(l.shadowOpacity * 100).round()}%',
          value: l.shadowOpacity,
          min: 0.0,
          max: 1.0,
          onChanged: (v) => _updateRecipe(_recipe.copyWith(lighting: l.copyWith(shadowOpacity: v))),
        ),
        _ParamSlider(
          label: '影子虚化程度',
          valueText: '${(l.shadowSoftness * 100).round()}%',
          value: l.shadowSoftness,
          min: 0.05,
          max: 1.0,
          onChanged: (v) => _updateRecipe(_recipe.copyWith(lighting: l.copyWith(shadowSoftness: v))),
        ),
        _ParamSlider(
          label: '影子长短 (光源高低)',
          valueText: '${l.lightElevationDeg.round()}°',
          value: l.lightElevationDeg,
          min: 12,
          max: 78,
          onChanged: (v) => _updateRecipe(
            _recipe.copyWith(lighting: l.copyWith(lightElevationDeg: v)),
          ),
        ),
        _ParamSlider(
          label: '人物虚化 (匹配景深)',
          valueText: '${l.dofBlur.toStringAsFixed(1)}px',
          value: l.dofBlur,
          min: 0.0,
          max: 5.5,
          onChanged: (v) => _updateRecipe(_recipe.copyWith(lighting: l.copyWith(dofBlur: v))),
        ),
        _ParamSlider(
          label: '照片颗粒感',
          valueText: '${(l.filmGrain * 100).round()}%',
          value: l.filmGrain,
          min: 0.0,
          max: 0.28,
          onChanged: (v) => _updateRecipe(_recipe.copyWith(lighting: l.copyWith(filmGrain: v))),
        ),
      ],
    );
  }

  Widget _buildReBlendTab() {
    final standees = _ctrl.standees;
    final p = _recipe.perspective;
    final pl = _recipe.placement;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      children: [
        const Text(
          '在当前实景中更换二次元立绘（直接在画面上拖动/双指缩放）：',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 62,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: standees.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, idx) {
              final s = standees[idx];
              final selected = _recipe.standeeId == s.id;
              return GestureDetector(
                onTap: () {
                  _updateRecipe(_recipe.copyWith(standeeId: s.id));
                  _loadStandeeImage(s.id);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.accentAmber.withValues(alpha: 0.2)
                        : AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? AppTheme.accentAmber : AppTheme.borderSubtle,
                    ),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 42,
                          height: 48,
                          child: _ctrl.storage.blobStore.buildImage(
                            s.cutoutPath,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 74),
                        child: Text(
                          s.name.split('·').first.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? AppTheme.accentAmber
                                : AppTheme.textPrimary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            FilterChip(
              label: const Text('透视网格'),
              selected: _showGrid,
              onSelected: (v) => setState(() => _showGrid = v),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('左右翻转'),
              selected: pl.flipX,
              onSelected: (v) => _updateRecipe(
                _recipe.copyWith(placement: pl.copyWith(flipX: v)),
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _reopenInCamera,
              icon: const Icon(Icons.camera_rounded, size: 16),
              label: const Text('进相机重溶', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        if (_showGrid)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: Wrap(
              spacing: 6,
              children: PerspectiveMode.values.map((m) {
                return ChoiceChip(
                  label: Text(m.label),
                  selected: p.mode == m,
                  onSelected: (_) => _updateRecipe(
                    _recipe.copyWith(perspective: p.copyWith(mode: m)),
                  ),
                );
              }).toList(),
            ),
          ),
        _ParamSlider(
          label: '地平线高低',
          valueText: '${(p.horizonY * 100).round()}%',
          value: p.horizonY,
          min: 0.14,
          max: 0.76,
          onChanged: (v) => _updateRecipe(
            _recipe.copyWith(
              perspective: p.copyWith(
                horizonY: v,
                pitchDeg: PerspectiveEngine.horizonYToPitchDeg(v),
              ),
            ),
          ),
        ),
        _ParamSlider(
          label: '地平线倾斜角度',
          valueText: '${p.rollDeg.toStringAsFixed(1)}°',
          value: p.rollDeg,
          min: -35.0,
          max: 35.0,
          onChanged: (v) => _updateRecipe(
            _recipe.copyWith(perspective: p.copyWith(rollDeg: v)),
          ),
        ),
      ],
    );
  }

  Widget _buildAiRelightTab() {
    final s = _ctrl.settings;
    final previewPrompt = AiRelightingService.buildLightingAwarePrompt(
      lighting: _recipe.lighting,
      basePrompt: s.customRelightPrompt,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      children: [
        Row(
          children: [
            Icon(
              s.isAiConfigured ? Icons.check_circle_rounded : Icons.info_outline_rounded,
              size: 16,
              color: s.isAiConfigured ? AppTheme.accentMint : AppTheme.accentAmber,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                s.isAiConfigured
                    ? '当前接口：${s.aiProvider.displayName} (${s.effectiveModel})'
                    : '尚未填写 AI 密钥，点击右侧配置 Gemini / OpenAI / IC-Light',
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12.5),
              ),
            ),
            TextButton(
              onPressed: () async {
                await AiEngineScreen.push(context, _ctrl);
                if (mounted) setState(() {});
              },
              child: const Text('AI 引擎接入', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.borderSubtle),
          ),
          child: Text(
            '自动注入物理光影参数 Prompt：\n$previewPrompt',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accentAmber,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _isRunningAi ? null : _runAiDeepRelight,
                icon: _isRunningAi
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(
                  _isRunningAi ? '正在执行 AI 深度光影重绘...' : '一键 AI 深度溶图精修',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            if (_item.hasAiEnhancement) ...[
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _viewMode = _viewMode == _CompareViewMode.compareAi
                        ? _CompareViewMode.liveEdit
                        : _CompareViewMode.compareAi;
                  });
                },
                child: Text(
                  _viewMode == _CompareViewMode.compareAi ? '返回编辑' : '对比 AI',
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _EditorTabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool accent;
  final VoidCallback onTap;

  const _EditorTabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = accent ? AppTheme.accentMint : AppTheme.accentAmber;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? activeColor.withValues(alpha: 0.16)
                : AppTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? activeColor : AppTheme.borderSubtle,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: selected ? activeColor : AppTheme.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? activeColor : AppTheme.textSecondary,
                  fontSize: 11.5,
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

class _ParamSlider extends StatelessWidget {
  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _ParamSlider({
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 48,
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
