import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/app_settings.dart';
import '../models/gallery_item.dart';
import '../models/standee_asset.dart';
import '../platform/blob_store.dart';
import 'auto_matte_engine.dart';

/// Cross-platform persistence service (iOS / Android / Desktop / Web)
/// backed by `PlatformBlobStore` + `SharedPreferences`.
class StorageService {
  static const _assetsKey = 'lumen_standee_assets_v1';
  static const _galleryKey = 'lumen_gallery_items_v1';
  static const _settingsKey = 'lumen_app_settings_v1';
  static const _seededKey = 'lumen_built_in_seeded_v1';

  final Uuid _uuid = const Uuid();
  final PlatformBlobStore blobStore = createPlatformBlobStore();
  late final SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await blobStore.init();
  }

  /// Loads standee assets and automatically seeds built-in anime samples on first run
  /// (and re-seeds cleanly in memory when running in Web browser sessions).
  Future<List<StandeeAsset>> loadOrSeedStandees() async {
    final existing = await loadStandees();
    final validExisting =
        existing.where((e) => blobStore.existsSync(e.cutoutPath)).toList();
    final seeded = _prefs.getBool(_seededKey) ?? false;

    if (seeded && validExisting.isNotEmpty) {
      return validExisting;
    }

    final samples = <({String asset, String name, String id})>[
      (
        id: 'builtin_mira',
        name: '米拉 · 银发相机少女',
        asset: 'assets/samples/standees/standee_mira.jpg',
      ),
      (
        id: 'builtin_ren',
        name: '凛 · 机能风街头少年',
        asset: 'assets/samples/standees/standee_ren.jpg',
      ),
    ];

    final list = List<StandeeAsset>.from(validExisting);
    for (final s in samples) {
      if (list.any(
          (item) => item.id == s.id && blobStore.existsSync(item.cutoutPath))) {
        continue;
      }
      try {
        final rawData = await rootBundle.load(s.asset);
        final rawBytes = rawData.buffer.asUint8List(
          rawData.offsetInBytes,
          rawData.lengthInBytes,
        );

        final origPath =
            await blobStore.writeBytes('standees', '${s.id}_orig.jpg', rawBytes);

        final matte = await AutoMatteEngine.processBytes(
          inputBytes: rawBytes,
          config: const MatteConfig(
            mode: MatteMode.animeLineAware,
            tolerance: 28.0,
            softness: 16.0,
            featherRadius: 1.0,
            defringeStrength: 0.88,
            edgeShrink: 1,
            autoCrop: true,
          ),
          maxDimension: kIsWeb ? 960 : 1400,
        );

        final cutoutPath = await blobStore.writeBytes(
          'standees',
          '${s.id}_cutout.png',
          matte.pngBytes,
        );

        list.add(
          StandeeAsset(
            id: s.id,
            name: s.name,
            cutoutPath: cutoutPath,
            originalPath: origPath,
            width: matte.width,
            height: matte.height,
            createdAt: DateTime.now(),
            isBuiltIn: true,
            matteMethod: matte.methodUsed,
          ),
        );
      } catch (e) {
        debugPrint('Failed seeding built-in standee ${s.id}: $e');
      }
    }

    await saveStandees(list);
    await _prefs.setBool(_seededKey, true);
    return list;
  }

  Future<List<StandeeAsset>> loadStandees() async {
    final raw = _prefs.getString(_assetsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => StandeeAsset.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveStandees(List<StandeeAsset> items) async {
    final raw = jsonEncode(items.map((e) => e.toJson()).toList());
    await _prefs.setString(_assetsKey, raw);
  }

  Future<StandeeAsset> createStandeeFile({
    required String name,
    required Uint8List cutoutPngBytes,
    required Uint8List? originalBytes,
    required int width,
    required int height,
    required String matteMethod,
    String? overwriteId,
  }) async {
    final id = overwriteId ?? _uuid.v4();
    final cutoutPath = await blobStore.writeBytes(
      'standees',
      '${id}_cutout.png',
      cutoutPngBytes,
    );

    String? origPath;
    if (originalBytes != null) {
      origPath = await blobStore.writeBytes(
        'standees',
        '${id}_orig.bin',
        originalBytes,
      );
    }

    return StandeeAsset(
      id: id,
      name: name,
      cutoutPath: cutoutPath,
      originalPath: origPath,
      width: width,
      height: height,
      createdAt: DateTime.now(),
      isBuiltIn: false,
      matteMethod: matteMethod,
    );
  }

  Future<void> deleteStandeeFiles(StandeeAsset asset) async {
    await blobStore.deletePath(asset.cutoutPath);
    if (asset.originalPath != null) {
      await blobStore.deletePath(asset.originalPath!);
    }
  }

  Future<List<GalleryItem>> loadGallery() async {
    final raw = _prefs.getString(_galleryKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => GalleryItem.fromJson(e as Map<String, dynamic>))
          .where((item) => blobStore.existsSync(item.compositePath))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveGallery(List<GalleryItem> items) async {
    final raw = jsonEncode(items.map((e) => e.toJson()).toList());
    await _prefs.setString(_galleryKey, raw);
  }

  Future<String> writeGalleryFile(
    String prefix,
    Uint8List bytes, {
    String ext = 'jpg',
  }) async {
    final id = _uuid.v4();
    return blobStore.writeBytes('gallery', '${prefix}_$id.$ext', bytes);
  }

  Future<void> deleteGalleryFiles(GalleryItem item) async {
    for (final p in [
      item.compositePath,
      item.backgroundPath,
      item.aiEnhancedPath,
    ]) {
      if (p != null) {
        await blobStore.deletePath(p);
      }
    }
  }

  Future<AppSettings> loadSettings() async {
    final raw = _prefs.getString(_settingsKey);
    if (raw == null || raw.isEmpty) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    await _prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  Future<String> exportToSystemAlbum(String filePath) async {
    final bytes = await blobStore.readBytes(filePath);
    if (bytes == null) return '未找到待导出文件';
    final ext = filePath.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    return blobStore.exportToAlbumOrDownload(
      filePath,
      bytes,
      'lumen_blend_${DateTime.now().millisecondsSinceEpoch}.$ext',
    );
  }
}
