import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'blob_store_stub.dart';

@JS('document.createElement')
external JSObject _createElement(JSString tagName);

@JS('document.querySelector')
external JSObject? _querySelector(JSString selector);

@JS('window.open')
external JSObject? _windowOpen(JSString url, JSString target);

extension type _AnchorElement(JSObject _) implements JSObject {
  external set href(JSString value);
  external set download(JSString value);
  external void click();
}

extension type _VideoElement(JSObject _) implements JSObject {
  external int get videoWidth;
  external int get videoHeight;
  external int get readyState;
}

extension type _CanvasElement(JSObject _) implements JSObject {
  external set width(int value);
  external set height(int value);
  external JSObject? getContext(JSString contextType);
}

extension type _Canvas2DContext(JSObject _) implements JSObject {
  external void drawImage(JSObject image, num dx, num dy, num dWidth, num dHeight);
  external _ImageData getImageData(int sx, int sy, int sw, int sh);
}

extension type _ImageData(JSObject _) implements JSObject {
  external JSUint8ClampedArray get data;
}

class WebBlobStore implements PlatformBlobStore {
  final Map<String, Uint8List> _memoryFiles = {};
  _CanvasElement? _probeCanvas;

  @override
  Future<void> init() async {}

  @override
  Future<String> writeBytes(
    String folder,
    String filename,
    Uint8List bytes,
  ) async {
    final key = 'mem://$folder/$filename';
    _memoryFiles[key] = Uint8List.fromList(bytes);
    return key;
  }

  @override
  Future<Uint8List?> readBytes(String path) async => _memoryFiles[path];

  @override
  bool existsSync(String path) => _memoryFiles.containsKey(path);

  @override
  Future<void> deletePath(String path) async {
    _memoryFiles.remove(path);
  }

  @override
  void evictImageCache(String path) {
    final bytes = _memoryFiles[path];
    if (bytes != null) {
      MemoryImage(bytes).evict();
    }
  }

  @override
  Widget buildImage(
    String path, {
    BoxFit fit = BoxFit.cover,
    Alignment alignment = Alignment.center,
    Key? imageKey,
    Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
  }) {
    final bytes = _memoryFiles[path];
    if (bytes == null) {
      if (errorBuilder != null) {
        return Builder(
          builder: (ctx) =>
              errorBuilder(ctx, Exception('Missing blob $path'), null),
        );
      }
      return const SizedBox.shrink();
    }
    return Image.memory(
      bytes,
      key: imageKey,
      fit: fit,
      alignment: alignment,
      gaplessPlayback: true,
      errorBuilder: errorBuilder,
    );
  }

  @override
  Future<String> exportToAlbumOrDownload(
    String path,
    Uint8List bytes,
    String downloadFilename,
  ) async {
    try {
      final mime = downloadFilename.toLowerCase().endsWith('.png')
          ? 'image/png'
          : 'image/jpeg';
      final b64 = base64Encode(bytes);
      final dataUrl = 'data:$mime;base64,$b64';
      final anchor = _AnchorElement(_createElement('a'.toJS));
      anchor.href = dataUrl.toJS;
      anchor.download = downloadFilename.toJS;
      anchor.click();
      return '已触发浏览器下载：$downloadFilename';
    } catch (_) {
      return '浏览器导出完成';
    }
  }

  @override
  Uint8List? sampleWebVideoRgbGrid(int gridSize) {
    try {
      final videoObj = _querySelector('video'.toJS);
      if (videoObj == null) return null;
      final video = _VideoElement(videoObj);
      if (video.readyState < 2 || video.videoWidth <= 0 || video.videoHeight <= 0) {
        return null;
      }
      _probeCanvas ??= _CanvasElement(_createElement('canvas'.toJS));
      final canvas = _probeCanvas!;
      canvas.width = gridSize;
      canvas.height = gridSize;
      final ctxObj = canvas.getContext('2d'.toJS);
      if (ctxObj == null) return null;
      final ctx = _Canvas2DContext(ctxObj);
      ctx.drawImage(videoObj, 0, 0, gridSize, gridSize);
      final rgba = ctx.getImageData(0, 0, gridSize, gridSize).data.toDart;
      final rgb = Uint8List(gridSize * gridSize * 3);
      int src = 0;
      int dst = 0;
      final count = gridSize * gridSize;
      for (int i = 0; i < count; i++) {
        rgb[dst++] = rgba[src];
        rgb[dst++] = rgba[src + 1];
        rgb[dst++] = rgba[src + 2];
        src += 4;
      }
      return rgb;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> openExternalUrl(String url) async {
    try {
      _windowOpen(url.toJS, '_blank'.toJS);
      return true;
    } catch (_) {
      return false;
    }
  }
}

PlatformBlobStore createPlatformBlobStore() => WebBlobStore();
