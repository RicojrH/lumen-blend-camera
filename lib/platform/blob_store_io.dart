import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import 'blob_store_stub.dart';

class IoBlobStore implements PlatformBlobStore {
  late Directory _rootDir;

  @override
  Future<void> init() async {
    final appDoc = await getApplicationDocumentsDirectory();
    _rootDir = Directory('${appDoc.path}${Platform.pathSeparator}lumen_blend');
    await Directory('${_rootDir.path}${Platform.pathSeparator}standees')
        .create(recursive: true);
    await Directory('${_rootDir.path}${Platform.pathSeparator}gallery')
        .create(recursive: true);
  }

  @override
  Future<String> writeBytes(
    String folder,
    String filename,
    Uint8List bytes,
  ) async {
    final dir = Directory('${_rootDir.path}${Platform.pathSeparator}$folder');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final path = '${dir.path}${Platform.pathSeparator}$filename';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  @override
  Future<Uint8List?> readBytes(String path) async {
    final f = File(path);
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  @override
  bool existsSync(String path) => File(path).existsSync();

  @override
  Future<void> deletePath(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  @override
  void evictImageCache(String path) {
    FileImage(File(path)).evict();
  }

  @override
  Widget buildImage(
    String path, {
    BoxFit fit = BoxFit.cover,
    Alignment alignment = Alignment.center,
    Key? imageKey,
    Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
  }) {
    return Image.file(
      File(path),
      key: imageKey,
      fit: fit,
      alignment: alignment,
      errorBuilder: errorBuilder,
    );
  }

  @override
  Future<String> exportToAlbumOrDownload(
    String path,
    Uint8List bytes,
    String downloadFilename,
  ) async {
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      try {
        final hasAccess = await Gal.hasAccess(toAlbum: true);
        if (!hasAccess) {
          await Gal.requestAccess(toAlbum: true);
        }
        await Gal.putImage(path, album: 'LumenBlend');
        return '已保存高清成品至系统相册「LumenBlend」';
      } catch (e) {
        debugPrint('Gal export fallback: $e');
      }
    }
    return '已保存高清成品：$path';
  }

  @override
  Uint8List? sampleWebVideoRgbGrid(int gridSize) => null;

  @override
  Future<bool> openExternalUrl(String url) async {
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
        return true;
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
        return true;
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
        return true;
      }
    } catch (_) {}
    return false;
  }
}

PlatformBlobStore createPlatformBlobStore() => IoBlobStore();
