import 'dart:typed_data';
import 'package:flutter/widgets.dart';

abstract class PlatformBlobStore {
  Future<void> init();
  Future<String> writeBytes(String folder, String filename, Uint8List bytes);
  Future<Uint8List?> readBytes(String path);
  bool existsSync(String path);
  Future<void> deletePath(String path);
  void evictImageCache(String path);
  Widget buildImage(
    String path, {
    BoxFit fit = BoxFit.cover,
    Alignment alignment = Alignment.center,
    Key? imageKey,
    Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
  });
  Future<String> exportToAlbumOrDownload(
    String path,
    Uint8List bytes,
    String downloadFilename,
  );

  /// Samples a tiny 28x28 RGB buffer (length 28*28*3, values 0..255) from an active
  /// HTML5 <video> camera element on Web; returns null on native (which uses CameraImage stream).
  Uint8List? sampleWebVideoRgbGrid(int gridSize);

  /// Opens an external HTTP/HTTPS URL (e.g. Bilibili profile) in browser or copies if unsupported.
  Future<bool> openExternalUrl(String url);
}

PlatformBlobStore createPlatformBlobStore() =>
    throw UnsupportedError('Unsupported platform');
