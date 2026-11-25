import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import '../models/app_settings.dart';
import '../models/blend_recipe.dart';
import '../models/gallery_item.dart';
import '../models/sample_scene.dart';
import '../models/standee_asset.dart';
import '../services/ai_relighting_service.dart';
import '../services/compositor_engine.dart';
import '../services/lighting_probe_service.dart';
import '../services/storage_service.dart';

/// Central reactive controller for LumenBlend Camera across iOS, Android, Desktop, and Web.
class AppController extends ChangeNotifier {
  final StorageService storage = StorageService();
  final Uuid _uuid = const Uuid();

  bool _initialized = false;
  bool get initialized => _initialized;

  List<StandeeAsset> _standees = [];
  List<StandeeAsset> get standees => List.unmodifiable(_standees);

  List<GalleryItem> _gallery = [];
  List<GalleryItem> get gallery => List.unmodifiable(_gallery);

  AppSettings _settings = const AppSettings();
  AppSettings get settings => _settings;

  ui.FragmentProgram? _harmonizeProgram;
  ui.FragmentProgram? get harmonizeProgram => _harmonizeProgram;

  String? _activeStandeeId;
  PlacementTransform _placement = const PlacementTransform();
  PerspectiveState _perspective = const PerspectiveState();
  LightingProfile _lighting = const LightingProfile();

  bool _mockSceneMode = false;
  SampleScene _activeSampleScene = SampleScene.builtInScenes.first;
  String? _customBackgroundPath;

  final Map<String, ui.Image> _uiImageCache = {};

  StandeeAsset? get activeStandee {
    if (_standees.isEmpty) return null;
    if (_activeStandeeId != null) {
      final idx = _standees.indexWhere((s) => s.id == _activeStandeeId);
      if (idx >= 0) return _standees[idx];
    }
    return _standees.first;
  }

  PlacementTransform get placement => _placement;
  PerspectiveState get perspective => _perspective;
  LightingProfile get lighting => _lighting;
  bool get mockSceneMode => _mockSceneMode;
  SampleScene get activeSampleScene => _activeSampleScene;
  String? get customBackgroundPath => _customBackgroundPath;

  BlendRecipe get currentRecipe => BlendRecipe(
        standeeId: activeStandee?.id ?? '',
        placement: _placement,
        perspective: _perspective,
        lighting: _lighting,
      );

  bool get isMobilePlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// True on platforms where `camera` plugin supports live viewfinder (Android, iOS, and Web).
  bool get supportsLiveCamera {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<void> initialize() async {
    if (_initialized) return;

    await storage.init();
    _settings = await storage.loadSettings();

    try {
      _harmonizeProgram =
          await ui.FragmentProgram.fromAsset('shaders/harmonize.frag');
    } catch (e) {
      debugPrint('FragmentProgram load fallback: $e');
    }

    _standees = await storage.loadOrSeedStandees();
    _gallery = await storage.loadGallery();

    if (_standees.isNotEmpty) {
      _activeStandeeId = _standees.first.id;
    }

    // Pre-calibrate baseline lighting from first sample scene, then start in Live Camera mode
    // whenever supported (Android, iOS, Web), falling back gracefully if no camera hardware exists.
    await selectSampleScene(_activeSampleScene, notify: false);
    _mockSceneMode = !supportsLiveCamera;

    _initialized = true;
    notifyListeners();
  }

  Future<ui.Image?> loadUiImageForFile(String path, {bool forceReload = false}) async {
    if (!forceReload && _uiImageCache.containsKey(path)) {
      return _uiImageCache[path];
    }
    try {
      final bytes = await storage.blobStore.readBytes(path);
      if (bytes == null) return null;
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      _uiImageCache[path] = frame.image;
      return frame.image;
    } catch (e) {
      debugPrint('Failed decoding ui.Image from $path: $e');
      return null;
    }
  }

  void invalidateImageCache(String path) {
    _uiImageCache.remove(path);
    storage.blobStore.evictImageCache(path);
  }

  void selectStandee(String id) {
    if (_activeStandeeId == id) return;
    _activeStandeeId = id;
    notifyListeners();
  }

  StandeeAsset? findStandeeById(String id) {
    final idx = _standees.indexWhere((e) => e.id == id);
    if (idx >= 0) return _standees[idx];
    return _standees.isNotEmpty ? _standees.first : null;
  }

  void updatePlacement(PlacementTransform next) {
    _placement = next;
    notifyListeners();
  }

  void updatePerspective(PerspectiveState next) {
    _perspective = next;
    notifyListeners();
  }

  void updateLighting(LightingProfile next) {
    _lighting = next;
    notifyListeners();
  }

  void applyProbedLighting(LightingProfile probed, {double smoothing = 0.30}) {
    if (!_lighting.autoMatchEnabled) return;
    _lighting = _lighting.lerpTo(probed, smoothing);
    notifyListeners();
  }

  void resetPlacement() {
    _placement = PlacementTransform(
      anchorX: _mockSceneMode ? _activeSampleScene.defaultAnchorX : 0.50,
      anchorY: _mockSceneMode ? _activeSampleScene.defaultAnchorY : 0.85,
      userScale: 1.0,
    );
    notifyListeners();
  }

  Future<void> setMockSceneMode(bool enabled) async {
    _mockSceneMode = enabled;
    if (enabled) {
      await _probeCurrentMockBackground();
    }
    notifyListeners();
  }

  Future<void> selectSampleScene(SampleScene scene, {bool notify = true}) async {
    _activeSampleScene = scene;
    _customBackgroundPath = null;
    _perspective = scene.defaultPerspective.copyWith(
      showGrid: _perspective.showGrid,
      sensorSyncEnabled: _perspective.sensorSyncEnabled,
    );
    _placement = _placement.copyWith(
      anchorX: scene.defaultAnchorX,
      anchorY: scene.defaultAnchorY,
    );
    await _probeCurrentMockBackground();
    if (notify) notifyListeners();
  }

  Future<void> setCustomMockBackgroundBytes(Uint8List bytes) async {
    final path = await storage.writeGalleryFile('custom_bg', bytes, ext: 'jpg');
    _customBackgroundPath = path;
    _mockSceneMode = true;
    await _probeCurrentMockBackground();
    notifyListeners();
  }

  Future<void> _probeCurrentMockBackground() async {
    try {
      final bytes = await readCurrentMockBackgroundBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        final probed = LightingProbeService.analyzeImage(
          decoded,
          anchorX: _placement.anchorX,
          anchorY: _placement.anchorY,
          base: _lighting,
        );
        _lighting = probed;
      }
    } catch (e) {
      debugPrint('Mock background probe error: $e');
    }
  }

  Future<void> reProbeMockBackgroundAtAnchor() async {
    if (!_mockSceneMode || !_lighting.autoMatchEnabled) return;
    await _probeCurrentMockBackground();
    notifyListeners();
  }

  Future<Uint8List> readCurrentMockBackgroundBytes() async {
    if (_customBackgroundPath != null) {
      final customBytes = await storage.blobStore.readBytes(_customBackgroundPath!);
      if (customBytes != null) return customBytes;
    }
    final data = await rootBundle.load(_activeSampleScene.assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<GalleryItem> captureAndBlend({
    required Uint8List backgroundBytes,
    bool autoProbeBeforeRender = true,
  }) async {
    final standee = activeStandee;
    if (standee == null) {
      throw Exception('请先在素材库添加至少一张二次元立绘');
    }

    LightingProfile finalLighting = _lighting;
    if (autoProbeBeforeRender && _lighting.autoMatchEnabled) {
      final decodedBg = img.decodeImage(backgroundBytes);
      if (decodedBg != null) {
        finalLighting = LightingProbeService.analyzeImage(
          decodedBg,
          anchorX: _placement.anchorX,
          anchorY: _placement.anchorY,
          base: _lighting,
        );
        _lighting = finalLighting;
      }
    }

    final recipe = BlendRecipe(
      standeeId: standee.id,
      placement: _placement,
      perspective: _perspective,
      lighting: finalLighting,
    );

    final standeeBytes = await storage.blobStore.readBytes(standee.cutoutPath);
    if (standeeBytes == null) {
      throw Exception('立绘素材文件读取失败');
    }
    final compositeBytes = await CompositorEngine.renderComposite(
      backgroundBytes: backgroundBytes,
      standeePngBytes: standeeBytes,
      recipe: recipe,
      maxDimension: _settings.maxExportDimension,
    );

    final bgPath =
        await storage.writeGalleryFile('bg', backgroundBytes, ext: 'jpg');
    final compPath =
        await storage.writeGalleryFile('comp', compositeBytes, ext: 'jpg');

    final now = DateTime.now();
    final item = GalleryItem(
      id: _uuid.v4(),
      title:
          '${standee.name.split('·').first.trim()} · ${now.month}/${now.day} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      compositePath: compPath,
      backgroundPath: bgPath,
      recipe: recipe,
      createdAt: now,
      updatedAt: now,
    );

    _gallery = [item, ..._gallery];
    await storage.saveGallery(_gallery);
    notifyListeners();
    return item;
  }

  Future<GalleryItem> reRenderGalleryItem({
    required GalleryItem item,
    required BlendRecipe newRecipe,
    bool saveAsNewCopy = false,
  }) async {
    final standee = findStandeeById(newRecipe.standeeId);
    if (standee == null) {
      throw Exception('未找到对应的立绘素材');
    }

    final bgBytes = await storage.blobStore.readBytes(item.backgroundPath);
    final standeeBytes = await storage.blobStore.readBytes(standee.cutoutPath);
    if (bgBytes == null || standeeBytes == null) {
      throw Exception('原始背景或立绘素材丢失');
    }
    final compBytes = await CompositorEngine.renderComposite(
      backgroundBytes: bgBytes,
      standeePngBytes: standeeBytes,
      recipe: newRecipe,
      maxDimension: _settings.maxExportDimension,
    );

    if (saveAsNewCopy) {
      final newBgPath =
          await storage.writeGalleryFile('bg', bgBytes, ext: 'jpg');
      final newCompPath =
          await storage.writeGalleryFile('comp', compBytes, ext: 'jpg');
      final now = DateTime.now();
      final copy = GalleryItem(
        id: _uuid.v4(),
        title: '${item.title} (重溶)',
        compositePath: newCompPath,
        backgroundPath: newBgPath,
        recipe: newRecipe,
        createdAt: now,
        updatedAt: now,
      );
      _gallery = [copy, ..._gallery];
      await storage.saveGallery(_gallery);
      notifyListeners();
      return copy;
    } else {
      final newCompPath =
          await storage.writeGalleryFile('comp', compBytes, ext: 'jpg');
      await storage.blobStore.deletePath(item.compositePath);

      final updated = item.copyWith(
        compositePath: newCompPath,
        recipe: newRecipe,
        preferAiVersion: false,
        updatedAt: DateTime.now(),
      );
      _gallery = _gallery.map((e) => e.id == item.id ? updated : e).toList();
      await storage.saveGallery(_gallery);
      notifyListeners();
      return updated;
    }
  }

  Future<GalleryItem> runAiDeepRelight({
    required GalleryItem item,
    required BlendRecipe activeRecipe,
  }) async {
    final standee = findStandeeById(activeRecipe.standeeId);
    if (standee == null) {
      throw Exception('未找到立绘素材');
    }

    final bgBytes = await storage.blobStore.readBytes(item.backgroundPath);
    final standeeBytes = await storage.blobStore.readBytes(standee.cutoutPath);
    if (bgBytes == null || standeeBytes == null) {
      throw Exception('背景或立绘读取失败');
    }
    final compBytes = await CompositorEngine.renderComposite(
      backgroundBytes: bgBytes,
      standeePngBytes: standeeBytes,
      recipe: activeRecipe,
      maxDimension: 1536,
    );

    final aiBytes = await AiRelightingService.relightComposite(
      settings: _settings,
      compositeBytes: compBytes,
      backgroundBytes: bgBytes,
      standeeBytes: standeeBytes,
      recipe: activeRecipe,
    );

    final aiPath = await storage.writeGalleryFile('ai', aiBytes, ext: 'png');
    final updated = item.copyWith(
      aiEnhancedPath: aiPath,
      aiProviderTag: _settings.aiProvider.displayName,
      preferAiVersion: true,
      recipe: activeRecipe,
      updatedAt: DateTime.now(),
    );
    _gallery = _gallery.map((e) => e.id == item.id ? updated : e).toList();
    await storage.saveGallery(_gallery);
    notifyListeners();
    return updated;
  }

  Future<void> toggleGalleryAiPreference(GalleryItem item, bool preferAi) async {
    final updated = item.copyWith(preferAiVersion: preferAi);
    _gallery = _gallery.map((e) => e.id == item.id ? updated : e).toList();
    await storage.saveGallery(_gallery);
    notifyListeners();
  }

  Future<void> deleteGalleryItem(GalleryItem item) async {
    await storage.deleteGalleryFiles(item);
    _gallery = _gallery.where((e) => e.id != item.id).toList();
    await storage.saveGallery(_gallery);
    notifyListeners();
  }

  Future<void> loadGalleryItemIntoCamera(GalleryItem item) async {
    _customBackgroundPath = item.backgroundPath;
    _mockSceneMode = true;
    _activeStandeeId = item.recipe.standeeId;
    _placement = item.recipe.placement;
    _perspective = item.recipe.perspective;
    _lighting = item.recipe.lighting;
    notifyListeners();
  }

  Future<StandeeAsset> saveMattedStandee({
    required String name,
    required Uint8List cutoutPngBytes,
    required Uint8List? originalBytes,
    required int width,
    required int height,
    required String matteMethod,
    String? overwriteId,
  }) async {
    final saved = await storage.createStandeeFile(
      name: name,
      cutoutPngBytes: cutoutPngBytes,
      originalBytes: originalBytes,
      width: width,
      height: height,
      matteMethod: matteMethod,
      overwriteId: overwriteId,
    );
    invalidateImageCache(saved.cutoutPath);

    if (overwriteId != null && _standees.any((e) => e.id == overwriteId)) {
      _standees = _standees.map((e) => e.id == overwriteId ? saved : e).toList();
    } else {
      _standees = [saved, ..._standees];
    }
    _activeStandeeId = saved.id;
    await storage.saveStandees(_standees);
    notifyListeners();
    return saved;
  }

  Future<void> renameStandee(StandeeAsset asset, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    _standees = _standees
        .map((e) => e.id == asset.id ? e.copyWith(name: trimmed) : e)
        .toList();
    await storage.saveStandees(_standees);
    notifyListeners();
  }

  Future<void> deleteStandee(StandeeAsset asset) async {
    await storage.deleteStandeeFiles(asset);
    invalidateImageCache(asset.cutoutPath);
    _standees = _standees.where((e) => e.id != asset.id).toList();
    if (_activeStandeeId == asset.id) {
      _activeStandeeId = _standees.isNotEmpty ? _standees.first.id : null;
    }
    await storage.saveStandees(_standees);
    notifyListeners();
  }

  Future<void> updateSettings(AppSettings next) async {
    _settings = next;
    await storage.saveSettings(next);
    notifyListeners();
  }
}
