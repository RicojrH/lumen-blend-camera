import 'dart:async';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/sample_scene.dart';
import '../models/standee_asset.dart';
import '../services/lighting_probe_service.dart';
import '../services/perspective_engine.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/author_info_sheet.dart';
import '../widgets/harmonized_standee_view.dart';
import '../widgets/interactive_horizon_overlay.dart';
import '../widgets/lighting_hud_bar.dart';
import '../widgets/perspective_grid_painter.dart';
import 'asset_library_screen.dart';
import 'gallery_screen.dart';
import 'photo_editor_screen.dart';

/// Feature 1: Real-time Viewfinder Camera Screen (Default Main Interface).
/// - Supports real live camera viewfinder across iOS, Android, AND Web (`camera_web`)
/// - Instant 1-tap switcher between [实时相机] and [实景样片]
/// - Direct on-canvas Horizon drag (up/down/left/right) + Wing Rotation (`rollDeg`)
/// - Full 360-degree continuous grounded shadow & GPU physical lighting harmonization
class CameraBlendScreen extends StatefulWidget {
  final AppController controller;

  const CameraBlendScreen({super.key, required this.controller});

  @override
  State<CameraBlendScreen> createState() => _CameraBlendScreenState();
}

class _CameraBlendScreenState extends State<CameraBlendScreen>
    with WidgetsBindingObserver {
  final PerspectiveEngine _perspectiveEngine = PerspectiveEngine();
  final ImagePicker _imagePicker = ImagePicker();

  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  CameraController? _cameraController;
  bool _cameraInitializing = false;
  bool _cameraReady = false;
  String? _cameraError;
  Timer? _webVideoProbeTimer;

  DateTime _lastProbeTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isProbingFrame = false;

  ui.Image? _activeStandeeUiImage;
  String? _loadedStandeePath;

  bool _isCapturing = false;
  bool _flashVisible = false;
  bool _isDraggingStandee = false;
  bool _isAdjustingHorizon = false;
  bool _showQuickLightPanel = false;
  bool _showScenePicker = false;

  double _gestureStartScale = 1.0;
  double _gestureStartRot = 0.0;
  Offset _gestureStartAnchor = const Offset(0.5, 0.85);
  Offset _gestureStartFocal = Offset.zero;

  AppController get _ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ctrl.addListener(_onControllerChanged);
    _loadActiveStandeeImage();
    _initSensors();
    if (!_ctrl.mockSceneMode) {
      _initLiveCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.removeListener(_onControllerChanged);
    _perspectiveEngine.stopListening();
    _disposeCamera();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_ctrl.mockSceneMode) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      _initLiveCamera();
    }
  }

  void _onControllerChanged() {
    _loadActiveStandeeImage();
    if (mounted) setState(() {});
  }

  Future<void> _loadActiveStandeeImage() async {
    final standee = _ctrl.activeStandee;
    if (standee == null) {
      if (_activeStandeeUiImage != null && mounted) {
        setState(() {
          _activeStandeeUiImage = null;
          _loadedStandeePath = null;
        });
      }
      return;
    }
    if (_loadedStandeePath == standee.cutoutPath &&
        _activeStandeeUiImage != null) {
      return;
    }
    final decoded = await _ctrl.loadUiImageForFile(standee.cutoutPath);
    if (!mounted) return;
    setState(() {
      _activeStandeeUiImage = decoded;
      _loadedStandeePath = standee.cutoutPath;
    });
  }

  void _initSensors() {
    _perspectiveEngine.startListening(
      onUpdate: (pitchDeg, rollDeg, horizonY) {
        if (!_ctrl.perspective.sensorSyncEnabled || _ctrl.mockSceneMode) return;
        _ctrl.updatePerspective(
          _ctrl.perspective.copyWith(
            pitchDeg: pitchDeg,
            rollDeg: rollDeg,
            horizonY: horizonY,
          ),
        );
      },
    );
  }

  Future<void> _initLiveCamera() async {
    if (!_ctrl.supportsLiveCamera) {
      await _ctrl.setMockSceneMode(true);
      return;
    }
    if (_cameraInitializing) return;
    setState(() {
      _cameraInitializing = true;
      _cameraError = null;
    });

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (!mounted) return;
        setState(() {
          _cameraInitializing = false;
          _cameraReady = false;
          _cameraError = '未检测到摄像头设备（可接入摄像头后点击重试，或切换至左上角「图片」页）';
        });
        return;
      }
      // Prefer rear environment camera on phones if available
      final backIdx = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      if (backIdx >= 0 && _cameraIndex == 0) {
        _cameraIndex = backIdx;
      }
      await _startCameraController(_cameras[_cameraIndex % _cameras.length]);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraInitializing = false;
        _cameraReady = false;
        _cameraError = '无法获取摄像头权限或设备被占用，请允许浏览器/系统相机权限后重试';
      });
    }
  }

  Future<void> _startCameraController(CameraDescription desc) async {
    await _disposeCamera();
    final cam = CameraController(
      desc,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );
    try {
      await cam.initialize();
      // Native mobile supports zero-copy CameraImage stream; Web uses HTML5 <video> canvas sampler
      if (!kIsWeb && _ctrl.isMobilePlatform) {
        try {
          await cam.startImageStream(_onCameraStreamFrame);
        } catch (e) {
          debugPrint('ImageStream not supported on this device: $e');
        }
      } else if (kIsWeb) {
        _startWebVideoLightingTimer();
      }

      if (!mounted) {
        await cam.dispose();
        return;
      }
      setState(() {
        _cameraController = cam;
        _cameraReady = true;
        _cameraInitializing = false;
        _cameraError = null;
      });
    } catch (e) {
      await cam.dispose();
      if (!mounted) return;
      setState(() {
        _cameraReady = false;
        _cameraInitializing = false;
        _cameraError = '相机启动失败，请检查相机授权后点击重试';
      });
    }
  }

  void _startWebVideoLightingTimer() {
    _webVideoProbeTimer?.cancel();
    _webVideoProbeTimer = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) {
        if (!mounted ||
            _ctrl.mockSceneMode ||
            !_cameraReady ||
            !_ctrl.lighting.autoMatchEnabled) {
          return;
        }
        final rgb = _ctrl.storage.blobStore
            .sampleWebVideoRgbGrid(LightingProbeService.gridSize);
        if (rgb != null) {
          final probed = LightingProbeService.analyzeRgbBytesGrid(
            rgb,
            anchorX: _ctrl.placement.anchorX,
            anchorY: _ctrl.placement.anchorY,
            base: _ctrl.lighting,
          );
          _ctrl.applyProbedLighting(probed, smoothing: 0.32);
        }
      },
    );
  }

  Future<void> _disposeCamera() async {
    _webVideoProbeTimer?.cancel();
    _webVideoProbeTimer = null;
    final cam = _cameraController;
    _cameraController = null;
    _cameraReady = false;
    if (cam != null) {
      try {
        if (!kIsWeb && cam.value.isStreamingImages) {
          await cam.stopImageStream();
        }
      } catch (_) {}
      try {
        await cam.dispose();
      } catch (_) {}
    }
  }

  void _onCameraStreamFrame(CameraImage frame) {
    if (!_ctrl.lighting.autoMatchEnabled || _isProbingFrame) return;
    final now = DateTime.now();
    if (now.difference(_lastProbeTime).inMilliseconds < 650) return;

    _lastProbeTime = now;
    _isProbingFrame = true;
    try {
      final probed = LightingProbeService.analyzeCameraImage(
        frame,
        anchorX: _ctrl.placement.anchorX,
        anchorY: _ctrl.placement.anchorY,
        base: _ctrl.lighting,
      );
      _ctrl.applyProbedLighting(probed, smoothing: 0.28);
    } finally {
      _isProbingFrame = false;
    }
  }

  Future<void> _switchToLiveCameraMode() async {
    setState(() => _showScenePicker = false);
    if (!_ctrl.mockSceneMode && _cameraReady) return;
    await _ctrl.setMockSceneMode(false);
    await _initLiveCamera();
  }

  Future<void> _switchToSampleSceneMode() async {
    if (!_ctrl.mockSceneMode) {
      await _disposeCamera();
      await _ctrl.setMockSceneMode(true);
      setState(() {
        _showScenePicker = true;
        _showQuickLightPanel = false;
      });
    } else {
      setState(() {
        _showScenePicker = !_showScenePicker;
        _showQuickLightPanel = false;
      });
    }
  }

  Future<void> _switchCameraLens() async {
    if (_ctrl.mockSceneMode || _cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _startCameraController(_cameras[_cameraIndex]);
  }

  Future<void> _pickCustomBackgroundPhoto() async {
    try {
      final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      await _disposeCamera();
      await _ctrl.setCustomMockBackgroundBytes(bytes);
      setState(() => _showScenePicker = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入背景照片失败：$e')),
      );
    }
  }

  Future<void> _handleShutterCapture() async {
    if (_isCapturing) return;
    if (_ctrl.activeStandee == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先点击右下角「素材库」导入一张立绘')),
      );
      return;
    }

    setState(() {
      _isCapturing = true;
      _flashVisible = true;
    });
    Future.delayed(const Duration(milliseconds: 140), () {
      if (mounted) setState(() => _flashVisible = false);
    });

    try {
      late final Uint8List bytes;
      if (_ctrl.mockSceneMode) {
        bytes = await _ctrl.readCurrentMockBackgroundBytes();
      } else {
        final cam = _cameraController;
        if (cam == null || !_cameraReady || !cam.value.isInitialized) {
          throw Exception('实时相机尚未就绪，请先授权摄像头或切换至左上角「图片」页');
        }
        if (!kIsWeb && cam.value.isStreamingImages) {
          await cam.stopImageStream();
        }
        final xfile = await cam.takePicture();
        bytes = await xfile.readAsBytes();
        if (mounted && !_ctrl.mockSceneMode && !kIsWeb && _ctrl.isMobilePlatform) {
          try {
            await cam.startImageStream(_onCameraStreamFrame);
          } catch (_) {}
        }
      }

      final item = await _ctrl.captureAndBlend(backgroundBytes: bytes);
      if (!mounted) return;

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text('溶图完成：${item.title}'),
          action: SnackBarAction(
            label: '查看 / 精修',
            textColor: AppTheme.accentAmber,
            onPressed: () {
              ScaffoldMessenger.of(context).clearSnackBars();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PhotoEditorScreen(
                    controller: _ctrl,
                    initialItem: item,
                  ),
                ),
              );
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('拍摄溶图失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  void _openGallery() {
    ScaffoldMessenger.of(context).clearSnackBars();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GalleryScreen(controller: _ctrl),
      ),
    );
  }

  void _openAssetLibrary() {
    ScaffoldMessenger.of(context).clearSnackBars();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssetLibraryScreen(controller: _ctrl),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeStandee = _ctrl.activeStandee;
    final latestGallery = _ctrl.gallery.isNotEmpty ? _ctrl.gallery.first : null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Live Viewfinder Canvas + On-Canvas Horizon Drag/Rotate + Standee
          LayoutBuilder(
            builder: (context, constraints) {
              final viewportSize =
                  Size(constraints.maxWidth, constraints.maxHeight);
              return Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: (details) {
                      _gestureStartScale = _ctrl.placement.userScale;
                      _gestureStartRot = _ctrl.placement.rotationRad;
                      _gestureStartAnchor = Offset(
                        _ctrl.placement.anchorX,
                        _ctrl.placement.anchorY,
                      );
                      _gestureStartFocal = details.focalPoint;
                      setState(() => _isDraggingStandee = true);
                    },
                    onScaleUpdate: (details) {
                      final delta = details.focalPoint - _gestureStartFocal;
                      final nextX = (_gestureStartAnchor.dx +
                              delta.dx / viewportSize.width)
                          .clamp(0.06, 0.94);
                      final minY =
                          (_ctrl.perspective.horizonY + 0.04).clamp(0.18, 0.80);
                      final nextY = (_gestureStartAnchor.dy +
                              delta.dy / viewportSize.height)
                          .clamp(minY, 0.98);

                      final nextScale =
                          (_gestureStartScale * details.scale).clamp(0.28, 2.4);
                      final nextRot = details.pointerCount >= 2
                          ? (_gestureStartRot + details.rotation)
                              .clamp(-1.4, 1.4)
                          : _ctrl.placement.rotationRad;

                      _ctrl.updatePlacement(
                        _ctrl.placement.copyWith(
                          anchorX: nextX,
                          anchorY: nextY,
                          userScale: nextScale,
                          rotationRad: nextRot,
                        ),
                      );
                    },
                    onScaleEnd: (_) {
                      setState(() => _isDraggingStandee = false);
                      _ctrl.reProbeMockBackgroundAtAnchor();
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildBackgroundFeed(),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: PerspectiveGridPainter(
                                perspective: _ctrl.perspective,
                                placement: _ctrl.placement,
                                lighting: _ctrl.lighting,
                                highlightPlacement: _isDraggingStandee,
                                highlightHorizon: _isAdjustingHorizon,
                              ),
                            ),
                          ),
                        ),
                        if (_activeStandeeUiImage != null)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: HarmonizedStandeeView(
                                standeeImage: _activeStandeeUiImage!,
                                shaderProgram: _ctrl.harmonizeProgram,
                                viewportSize: viewportSize,
                                placement: _ctrl.placement,
                                perspective: _ctrl.perspective,
                                lighting: _ctrl.lighting,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Direct On-Canvas Horizon Drag & Rotation Overlay!
                  Positioned.fill(
                    child: InteractiveHorizonOverlay(
                      perspective: _ctrl.perspective,
                      onChanged: _ctrl.updatePerspective,
                      onActiveChanged: (active) {
                        if (mounted) {
                          setState(() => _isAdjustingHorizon = active);
                        }
                      },
                    ),
                  ),
                ],
              );
            },
          ),

          // 2. Top Pro-Camera HUD Bar
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        // Explicit 1-tap switcher: [相机 | 图片]
                        _CameraSourceToggle(
                          isMockMode: _ctrl.mockSceneMode,
                          onSelectCamera: _switchToLiveCameraMode,
                          onSelectMock: _switchToSampleSceneMode,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: LightingHudBar(
                                lighting: _ctrl.lighting,
                                perspective: _ctrl.perspective,
                                onTapTelemetry: () => setState(() {
                                  _showQuickLightPanel = !_showQuickLightPanel;
                                  _showScenePicker = false;
                                }),
                                onToggleAutoLight: () {
                                  _ctrl.updateLighting(
                                    _ctrl.lighting.copyWith(
                                      autoMatchEnabled:
                                          !_ctrl.lighting.autoMatchEnabled,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _TopIconButton(
                          icon: _ctrl.perspective.showGrid
                              ? Icons.grid_on_rounded
                              : Icons.grid_off_rounded,
                          active: _ctrl.perspective.showGrid,
                          tooltip: '透视网格与地平线手柄',
                          onTap: () => _ctrl.updatePerspective(
                            _ctrl.perspective.copyWith(
                              showGrid: !_ctrl.perspective.showGrid,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        _TopIconButton(
                          icon: Icons.alternate_email_rounded,
                          active: false,
                          tooltip: '作者：@没品人类之一',
                          onTap: () => AuthorInfoSheet.show(context, _ctrl),
                        ),
                      ],
                    ),
                    if (_showScenePicker && _ctrl.mockSceneMode)
                      _buildMockScenePickerDrawer(),
                  ],
                ),
              ),
            ),
          ),

          // 3. Right Side Quick Action Rail
          if (!_showScenePicker && !_showQuickLightPanel)
            Positioned(
              right: 12,
              top: MediaQuery.of(context).padding.top + 64,
              child: Column(
                children: [
                  _SideToolButton(
                    icon: Icons.flip_rounded,
                    label: '镜像',
                    active: _ctrl.placement.flipX,
                    onTap: () => _ctrl.updatePlacement(
                      _ctrl.placement.copyWith(flipX: !_ctrl.placement.flipX),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SideToolButton(
                    icon: Icons.straighten_rounded,
                    label: '近大远小',
                    active: _ctrl.placement.lockToPerspectiveScale,
                    onTap: () => _ctrl.updatePlacement(
                      _ctrl.placement.copyWith(
                        lockToPerspectiveScale:
                            !_ctrl.placement.lockToPerspectiveScale,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SideToolButton(
                    icon: Icons.wb_sunny_outlined,
                    label: '光影',
                    active: _showQuickLightPanel,
                    onTap: () => setState(() {
                      _showQuickLightPanel = !_showQuickLightPanel;
                      _showScenePicker = false;
                    }),
                  ),
                  const SizedBox(height: 8),
                  _SideToolButton(
                    icon: Icons.refresh_rounded,
                    label: '复位',
                    active: false,
                    onTap: () {
                      _ctrl.resetPlacement();
                      _ctrl.updatePerspective(
                        _ctrl.perspective.copyWith(
                          rollDeg: 0.0,
                          vanishingX: 0.50,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

          // 4. Bottom Deck: Quick Light Panel + Standee Strip + Camera Shutter Controls
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Color(0xB80A0C10),
                    Color(0xF20A0C10),
                  ],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_showQuickLightPanel) _buildQuickLightingPanel(),
                    _buildStandeeQuickStrip(activeStandee),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 2, 24, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _BottomDeckThumbButton(
                            controller: _ctrl,
                            label: '图库 (${_ctrl.gallery.length})',
                            imagePath: latestGallery?.displayPath,
                            fallbackIcon: Icons.photo_library_outlined,
                            onTap: _openGallery,
                          ),
                          GestureDetector(
                            onTap: _handleShutterCapture,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              width: 72,
                              height: 72,
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _isCapturing
                                      ? AppTheme.accentAmber
                                      : Colors.white,
                                  width: 3.2,
                                ),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _isCapturing
                                      ? AppTheme.accentAmber
                                      : Colors.white,
                                ),
                                child: _isCapturing
                                    ? const Center(
                                        child: SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Colors.black,
                                          ),
                                        ),
                                      )
                                    : const Icon(
                                        Icons.camera_rounded,
                                        color: Colors.black87,
                                        size: 28,
                                      ),
                              ),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!_ctrl.mockSceneMode && _cameras.length > 1) ...[
                                IconButton(
                                  onPressed: _switchCameraLens,
                                  tooltip: '切换前后摄像头',
                                  icon: const Icon(
                                    Icons.cameraswitch_rounded,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 2),
                              ],
                              _BottomDeckThumbButton(
                                controller: _ctrl,
                                label: '素材库',
                                imagePath: activeStandee?.cutoutPath,
                                fallbackIcon:
                                    Icons.face_retouching_natural_rounded,
                                accentBorder: true,
                                onTap: _openAssetLibrary,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Subtle creator watermark bar
                    GestureDetector(
                      onTap: () => AuthorInfoSheet.show(context, _ctrl),
                      child: const Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Text(
                          'By @没品人类之一 · B站 space.bilibili.com/396896138',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 10,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (_flashVisible)
            IgnorePointer(
              child: Container(color: Colors.white.withValues(alpha: 0.72)),
            ),
        ],
      ),
    );
  }

  Widget _buildBackgroundFeed() {
    if (_ctrl.mockSceneMode) {
      if (_ctrl.customBackgroundPath != null &&
          _ctrl.storage.blobStore.existsSync(_ctrl.customBackgroundPath!)) {
        return _ctrl.storage.blobStore.buildImage(
          _ctrl.customBackgroundPath!,
          fit: BoxFit.cover,
        );
      }
      return Image.asset(
        _ctrl.activeSampleScene.assetPath,
        fit: BoxFit.cover,
      );
    }

    if (_cameraReady &&
        _cameraController != null &&
        _cameraController!.value.isInitialized) {
      final pSize = _cameraController!.value.previewSize;
      // On Web, previewSize is already display-oriented (width x height);
      // on mobile portrait, sensor previewSize is landscape (height x width).
      final double previewW = pSize == null
          ? 1080
          : (kIsWeb ? pSize.width : pSize.height);
      final double previewH = pSize == null
          ? 1920
          : (kIsWeb ? pSize.height : pSize.width);

      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: previewW,
          height: previewH,
          child: CameraPreview(_cameraController!),
        ),
      );
    }

    return Container(
      color: AppTheme.bgObsidian,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_cameraInitializing)
            const CircularProgressIndicator(color: AppTheme.accentAmber)
          else
            const Icon(
              Icons.videocam_off_outlined,
              size: 46,
              color: AppTheme.textMuted,
            ),
          const SizedBox(height: 14),
          Text(
            _cameraInitializing
                ? '正在请求开启实时摄像头预览...'
                : (_cameraError ?? '等待开启摄像头权限...'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          if (!_cameraInitializing)
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accentAmber,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: _initLiveCamera,
                  icon: const Icon(Icons.videocam_rounded, size: 18),
                  label: const Text(
                    '重试开启相机',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _switchToSampleSceneMode,
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('打开图片页溶图'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildMockScenePickerDrawer() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xEB11151E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '图片页 · 选择或导入背景照片溶图',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _switchToLiveCameraMode,
                icon: const Icon(Icons.videocam_rounded, size: 15),
                label: const Text('切回实时相机', style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 76,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                GestureDetector(
                  onTap: _pickCustomBackgroundPhoto,
                  child: Container(
                    width: 102,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _ctrl.customBackgroundPath != null
                            ? AppTheme.accentAmber
                            : AppTheme.accentCyan.withValues(alpha: 0.55),
                        width: _ctrl.customBackgroundPath != null ? 2 : 1,
                      ),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_rounded,
                          color: AppTheme.accentCyan,
                          size: 23,
                        ),
                        SizedBox(height: 4),
                        Text(
                          '导入本地图片',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ...SampleScene.builtInScenes.map((scene) {
                  final selected = _ctrl.customBackgroundPath == null &&
                      _ctrl.activeSampleScene.id == scene.id;
                  return GestureDetector(
                    onTap: () async {
                      await _ctrl.selectSampleScene(scene);
                      if (mounted) setState(() => _showScenePicker = false);
                    },
                    child: Container(
                      width: 118,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? AppTheme.accentAmber
                              : AppTheme.borderSubtle,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset(scene.assetPath, fit: BoxFit.cover),
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Color(0xCC000000)],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 6,
                            right: 6,
                            bottom: 5,
                            child: Text(
                              scene.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickLightingPanel() {
    final l = _ctrl.lighting;
    final p = _ctrl.perspective;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xE810141D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text(
                '光影与地平线精调',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _showQuickLightPanel = false),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Icon(Icons.close_rounded,
                      size: 17, color: AppTheme.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Column(
                children: [
                  LightCompassDial(
                    azimuthDeg: l.lightAzimuthDeg,
                    size: 58,
                    onChanged: (deg) => _ctrl.updateLighting(
                      l.copyWith(lightAzimuthDeg: deg, autoMatchEnabled: false),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '360°光源 ${l.lightAzimuthDeg.round()}°',
                    style: const TextStyle(
                      color: AppTheme.accentAmber,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    _MiniSlider(
                      label: '色温 ${l.kelvin.round()}K',
                      value: l.kelvin,
                      min: 2700,
                      max: 9200,
                      onChanged: (v) => _ctrl.updateLighting(
                        l.copyWith(kelvin: v, autoMatchEnabled: false),
                      ),
                    ),
                    _MiniSlider(
                      label: '曝光 ${l.exposureEv.toStringAsFixed(2)}EV',
                      value: l.exposureEv,
                      min: -1.3,
                      max: 1.0,
                      onChanged: (v) => _ctrl.updateLighting(
                        l.copyWith(exposureEv: v, autoMatchEnabled: false),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          _MiniSlider(
            label: '地阴影 ${(l.shadowOpacity * 100).round()}%',
            value: l.shadowOpacity,
            min: 0.0,
            max: 1.0,
            onChanged: (v) => _ctrl.updateLighting(l.copyWith(shadowOpacity: v)),
          ),
          _MiniSlider(
            label: '光影融合度 ${(l.blendStrength * 100).round()}%',
            value: l.blendStrength,
            min: 0.0,
            max: 1.0,
            onChanged: (v) => _ctrl.updateLighting(l.copyWith(blendStrength: v)),
          ),
          _MiniSlider(
            label: '地平线倾角 ${p.rollDeg.toStringAsFixed(1)}°',
            value: p.rollDeg,
            min: -35.0,
            max: 35.0,
            onChanged: (v) => _ctrl.updatePerspective(
              p.copyWith(rollDeg: v, sensorSyncEnabled: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStandeeQuickStrip(StandeeAsset? active) {
    final items = _ctrl.standees;
    if (items.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 50,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: items.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == items.length) {
            return GestureDetector(
              onTap: _openAssetLibrary,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xB81B212E),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: AppTheme.borderSubtle),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.add_rounded, size: 17, color: AppTheme.accentCyan),
                    SizedBox(width: 4),
                    Text(
                      '导入立绘',
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          }

          final s = items[index];
          final selected = active?.id == s.id;
          return GestureDetector(
            onTap: () => _ctrl.selectStandee(s.id),
            child: Container(
              padding: const EdgeInsets.fromLTRB(5, 4, 11, 4),
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.accentAmber.withValues(alpha: 0.22)
                    : const Color(0xB8131720),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(
                  color: selected ? AppTheme.accentAmber : AppTheme.borderSubtle,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipOval(
                    child: Container(
                      width: 36,
                      height: 36,
                      color: AppTheme.surfaceElevated,
                      child: _ctrl.storage.blobStore.buildImage(
                        s.cutoutPath,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.person, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    s.name.split('·').first.trim(),
                    style: TextStyle(
                      color:
                          selected ? AppTheme.accentAmber : AppTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CameraSourceToggle extends StatelessWidget {
  final bool isMockMode;
  final VoidCallback onSelectCamera;
  final VoidCallback onSelectMock;

  const _CameraSourceToggle({
    required this.isMockMode,
    required this.onSelectCamera,
    required this.onSelectMock,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xCC0D1119),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onSelectCamera,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: !isMockMode
                    ? AppTheme.accentAmber.withValues(alpha: 0.22)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.videocam_rounded,
                    size: 13,
                    color:
                        !isMockMode ? AppTheme.accentAmber : AppTheme.textMuted,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '相机',
                    style: TextStyle(
                      color: !isMockMode
                          ? AppTheme.accentAmber
                          : AppTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: onSelectMock,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isMockMode
                    ? AppTheme.accentCyan.withValues(alpha: 0.22)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.photo_rounded,
                    size: 13,
                    color:
                        isMockMode ? AppTheme.accentCyan : AppTheme.textMuted,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '图片页',
                    style: TextStyle(
                      color: isMockMode
                          ? AppTheme.accentCyan
                          : AppTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopIconButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;

  const _TopIconButton({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 33,
          height: 33,
          decoration: BoxDecoration(
            color: const Color(0xCC0D1119),
            shape: BoxShape.circle,
            border: Border.all(
              color: active
                  ? AppTheme.accentCyan.withValues(alpha: 0.65)
                  : AppTheme.borderSubtle,
            ),
          ),
          child: Icon(
            icon,
            size: 16,
            color: active ? AppTheme.accentCyan : AppTheme.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _SideToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SideToolButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
        decoration: BoxDecoration(
          color: const Color(0xB80D1119),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active
                ? AppTheme.accentAmber.withValues(alpha: 0.7)
                : AppTheme.borderSubtle,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: active ? AppTheme.accentAmber : AppTheme.textPrimary,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: active ? AppTheme.accentAmber : AppTheme.textSecondary,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomDeckThumbButton extends StatelessWidget {
  final AppController controller;
  final String label;
  final String? imagePath;
  final IconData fallbackIcon;
  final bool accentBorder;
  final VoidCallback onTap;

  const _BottomDeckThumbButton({
    required this.controller,
    required this.label,
    required this.imagePath,
    required this.fallbackIcon,
    required this.onTap,
    this.accentBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasFile = imagePath != null &&
        controller.storage.blobStore.existsSync(imagePath!);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: accentBorder
                    ? AppTheme.accentAmber.withValues(alpha: 0.7)
                    : Colors.white38,
                width: 1.5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasFile
                ? controller.storage.blobStore.buildImage(
                    imagePath!,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  )
                : Icon(fallbackIcon, color: AppTheme.textPrimary, size: 22),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _MiniSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
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
        ],
      ),
    );
  }
}
