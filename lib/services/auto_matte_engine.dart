import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../platform/onnx_bridge.dart';

enum MatteMode {
  animeLineAware,
  smartBorderFlood,
  chromaKey,
  onnxAi,
}

extension MatteModeInfo on MatteMode {
  String get label {
    switch (this) {
      case MatteMode.animeLineAware:
        return '白底/浅底(护白衣)';
      case MatteMode.smartBorderFlood:
        return '纯色/渐变背景';
      case MatteMode.chromaKey:
        return '点击吸色去背';
      case MatteMode.onnxAi:
        return 'AI 智能抠图';
    }
  }

  String get description {
    switch (this) {
      case MatteMode.animeLineAware:
        return '专为白底/浅色底二次元立绘优化，保护衣领/白袜/高光并去除白边';
      case MatteMode.smartBorderFlood:
        return '从四周边缘自动追踪纯色或渐变背景并羽化边缘';
      case MatteMode.chromaKey:
        return '全局移除指定色系背景（含手臂/腿间镂空区域）并抑制溢色';
      case MatteMode.onnxAi:
        return '调用端侧 ONNX 语义分割模型 (RMBG-1.4 / IS-Net-Anime) 处理复杂背景';
    }
  }
}

enum MatteBrushTool {
  none,
  erase,
  restore,
  magicWand,
  eyedropper,
}

class MatteStroke {
  final MatteBrushTool tool;
  final List<Offset> points;
  final double radiusNormalized;
  final double wandTolerance;

  const MatteStroke({
    required this.tool,
    required this.points,
    this.radiusNormalized = 0.035,
    this.wandTolerance = 32.0,
  });
}

class MatteConfig {
  final MatteMode mode;
  final double tolerance;
  final double softness;
  final double featherRadius;
  final double defringeStrength;
  final int edgeShrink;
  final int keyColorValue;
  final bool autoCrop;

  const MatteConfig({
    this.mode = MatteMode.animeLineAware,
    this.tolerance = 30.0,
    this.softness = 18.0,
    this.featherRadius = 1.0,
    this.defringeStrength = 0.85,
    this.edgeShrink = 1,
    this.keyColorValue = 0xFFFFFFFF,
    this.autoCrop = true,
  });

  MatteConfig copyWith({
    MatteMode? mode,
    double? tolerance,
    double? softness,
    double? featherRadius,
    double? defringeStrength,
    int? edgeShrink,
    int? keyColorValue,
    bool? autoCrop,
  }) {
    return MatteConfig(
      mode: mode ?? this.mode,
      tolerance: tolerance ?? this.tolerance,
      softness: softness ?? this.softness,
      featherRadius: featherRadius ?? this.featherRadius,
      defringeStrength: defringeStrength ?? this.defringeStrength,
      edgeShrink: edgeShrink ?? this.edgeShrink,
      keyColorValue: keyColorValue ?? this.keyColorValue,
      autoCrop: autoCrop ?? this.autoCrop,
    );
  }
}

class MatteResult {
  final Uint8List pngBytes;
  final int width;
  final int height;
  final String methodUsed;

  const MatteResult({
    required this.pngBytes,
    required this.width,
    required this.height,
    required this.methodUsed,
  });
}

class OnnxModelNotConfiguredException implements Exception {
  final String message;
  const OnnxModelNotConfiguredException(this.message);

  @override
  String toString() => message;
}

typedef _SerializedStroke = ({
  int toolIndex,
  List<(double, double)> points,
  double radius,
  double wandTol,
});

typedef _PureMatteJob = ({
  Uint8List inputBytes,
  int modeIndex,
  double tolerance,
  double softness,
  double featherRadius,
  double defringeStrength,
  int edgeShrink,
  int keyColorValue,
  bool autoCrop,
  int maxDimension,
  List<_SerializedStroke> strokes,
});

/// Hybrid Auto-Matting Engine supporting iOS, Android, Desktop, and Web seamlessly.
class AutoMatteEngine {
  static Future<MatteResult> processBytes({
    required Uint8List inputBytes,
    required MatteConfig config,
    List<MatteStroke> strokes = const [],
    String? onnxModelPath,
    int onnxInputSize = 1024,
    int maxDimension = 1600,
  }) async {
    final serializedStrokes = strokes
        .map<_SerializedStroke>((s) => (
              toolIndex: s.tool.index,
              points: s.points.map((p) => (p.dx, p.dy)).toList(),
              radius: s.radiusNormalized,
              wandTol: s.wandTolerance,
            ))
        .toList();

    if (config.mode == MatteMode.onnxAi) {
      return _processWithOnnx(
        inputBytes: inputBytes,
        config: config,
        strokes: serializedStrokes,
        onnxModelPath: onnxModelPath,
        onnxInputSize: onnxInputSize,
        maxDimension: maxDimension,
      );
    }

    final job = (
      inputBytes: inputBytes,
      modeIndex: config.mode.index,
      tolerance: config.tolerance,
      softness: config.softness,
      featherRadius: config.featherRadius,
      defringeStrength: config.defringeStrength,
      edgeShrink: config.edgeShrink,
      keyColorValue: config.keyColorValue,
      autoCrop: config.autoCrop,
      maxDimension: maxDimension,
      strokes: serializedStrokes,
    );
    return compute(_runPureDartMatteJob, job);
  }

  static Future<MatteResult> _processWithOnnx({
    required Uint8List inputBytes,
    required MatteConfig config,
    required List<_SerializedStroke> strokes,
    required String? onnxModelPath,
    required int onnxInputSize,
    required int maxDimension,
  }) async {
    final decoded = img.decodeImage(inputBytes);
    if (decoded == null) {
      throw Exception('无法解码输入图片');
    }

    final work = _resizeIfNeeded(decoded, maxDimension);
    final w = work.width;
    final h = work.height;

    final s = onnxInputSize.clamp(256, 1024);
    final resized = img.copyResize(
      work,
      width: s,
      height: s,
      interpolation: img.Interpolation.linear,
    );
    final tensorData = Float32List(1 * 3 * s * s);
    final planeSize = s * s;
    for (int y = 0; y < s; y++) {
      for (int x = 0; x < s; x++) {
        final p = resized.getPixel(x, y);
        final idx = y * s + x;
        tensorData[idx] = (p.r / 255.0) - 0.5;
        tensorData[planeSize + idx] = (p.g / 255.0) - 0.5;
        tensorData[planeSize * 2 + idx] = (p.b / 255.0) - 0.5;
      }
    }

    final maskSmall = await runOnnxSegmentationModel(
      onnxModelPath: onnxModelPath,
      inputNchw: tensorData,
      inputSize: s,
    );

    final alpha = Float32List(w * h);
    for (int y = 0; y < h; y++) {
      final fy = (y + 0.5) * s / h - 0.5;
      final y0 = fy.floor().clamp(0, s - 1);
      final y1 = (y0 + 1).clamp(0, s - 1);
      final ty = (fy - y0).clamp(0.0, 1.0);
      for (int x = 0; x < w; x++) {
        final fx = (x + 0.5) * s / w - 0.5;
        final x0 = fx.floor().clamp(0, s - 1);
        final x1 = (x0 + 1).clamp(0, s - 1);
        final tx = (fx - x0).clamp(0.0, 1.0);

        final v00 = maskSmall[y0 * s + x0];
        final v10 = maskSmall[y0 * s + x1];
        final v01 = maskSmall[y1 * s + x0];
        final v11 = maskSmall[y1 * s + x1];
        final top = v00 + (v10 - v00) * tx;
        final bot = v01 + (v11 - v01) * tx;
        alpha[y * w + x] = (top + (bot - top) * ty).clamp(0.0, 1.0);
      }
    }

    return _finalizeAlphaMask(
      work: work,
      alpha: alpha,
      bgClusters: _sampleBorderClusters(work),
      edgeShrink: config.edgeShrink,
      featherRadius: config.featherRadius,
      defringeStrength: config.defringeStrength,
      autoCrop: config.autoCrop,
      strokes: strokes,
      methodName: 'onnx_ai',
    );
  }

  static MatteResult _runPureDartMatteJob(_PureMatteJob job) {
    final decoded = img.decodeImage(job.inputBytes);
    if (decoded == null) {
      throw Exception('无法解码图像文件');
    }

    final work = _resizeIfNeeded(decoded, job.maxDimension);
    final w = work.width;
    final h = work.height;
    final mode =
        MatteMode.values[job.modeIndex.clamp(0, MatteMode.values.length - 1)];

    final hasExistingAlpha = _imageHasTransparency(work);
    final bgClusters = _sampleBorderClusters(work);
    final alpha = Float32List(w * h);

    if (hasExistingAlpha && mode != MatteMode.chromaKey) {
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          alpha[y * w + x] = work.getPixel(x, y).a / 255.0;
        }
      }
    } else if (mode == MatteMode.chromaKey) {
      final kr = ((job.keyColorValue >> 16) & 0xFF).toDouble();
      final kg = ((job.keyColorValue >> 8) & 0xFF).toDouble();
      final kb = (job.keyColorValue & 0xFF).toDouble();
      final softEnd = job.tolerance + math.max(job.softness, 1.0);

      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final p = work.getPixel(x, y);
          final d = _perceptualColorDist(
            p.r.toDouble(),
            p.g.toDouble(),
            p.b.toDouble(),
            kr,
            kg,
            kb,
          );
          if (d <= job.tolerance) {
            alpha[y * w + x] = 0.0;
          } else if (d < softEnd) {
            alpha[y * w + x] =
                ((d - job.tolerance) / (softEnd - job.tolerance)).clamp(0.0, 1.0);
          } else {
            alpha[y * w + x] = 1.0;
          }
        }
      }
    } else {
      for (int i = 0; i < alpha.length; i++) {
        alpha[i] = 1.0;
      }

      final isLineAware = mode == MatteMode.animeLineAware;
      final visited = Uint8List(w * h);
      final queue = Queue<int>();

      Float32List? gradMap;
      if (isLineAware) {
        gradMap = _computeGradientMagnitude(work);
      }

      final seedThreshold = job.tolerance * 1.18 + 8.0;
      void trySeed(int x, int y) {
        final idx = y * w + x;
        if (visited[idx] != 0) return;
        final p = work.getPixel(x, y);
        final dist = _minClusterDistance(
          p.r.toDouble(),
          p.g.toDouble(),
          p.b.toDouble(),
          bgClusters,
        );
        if (dist <= seedThreshold) {
          visited[idx] = 1;
          alpha[idx] = 0.0;
          queue.addLast(idx);
        }
      }

      for (int x = 0; x < w; x++) {
        trySeed(x, 0);
        trySeed(x, h - 1);
      }
      for (int y = 1; y < h - 1; y++) {
        trySeed(0, y);
        trySeed(w - 1, y);
      }

      final softBand = math.max(job.softness, 4.0);
      final maxDist = job.tolerance + softBand;
      const dx4 = [1, -1, 0, 0];
      const dy4 = [0, 0, 1, -1];

      while (queue.isNotEmpty) {
        final curr = queue.removeFirst();
        final cx = curr % w;
        final cy = curr ~/ w;
        final cp = work.getPixel(cx, cy);
        final cr = cp.r.toDouble();
        final cg = cp.g.toDouble();
        final cb = cp.b.toDouble();

        for (int dir = 0; dir < 4; dir++) {
          final nx = cx + dx4[dir];
          final ny = cy + dy4[dir];
          if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
          final nIdx = ny * w + nx;
          if (visited[nIdx] != 0) continue;

          final np = work.getPixel(nx, ny);
          final nr = np.r.toDouble();
          final ng = np.g.toDouble();
          final nb = np.b.toDouble();

          final clusterDist = _minClusterDistance(nr, ng, nb, bgClusters);
          final neighborDist = _perceptualColorDist(cr, cg, cb, nr, ng, nb);
          final gradPenalty = isLineAware ? (gradMap![nIdx] * 0.42) : 0.0;
          final effectiveDist =
              math.min(clusterDist, neighborDist * 1.45 + clusterDist * 0.45) +
                  gradPenalty;

          if (effectiveDist <= job.tolerance) {
            visited[nIdx] = 1;
            alpha[nIdx] = 0.0;
            queue.addLast(nIdx);
          } else if (effectiveDist < maxDist) {
            visited[nIdx] = 1;
            final softA =
                ((effectiveDist - job.tolerance) / softBand).clamp(0.0, 1.0);
            alpha[nIdx] = math.min(alpha[nIdx], softA);
            if (softA < 0.25 && (!isLineAware || gradMap![nIdx] < 38.0)) {
              queue.addLast(nIdx);
            }
          }
        }
      }

      if (!isLineAware) {
        final tightTol = job.tolerance * 0.48;
        for (int y = 1; y < h - 1; y++) {
          for (int x = 1; x < w - 1; x++) {
            final idx = y * w + x;
            if (alpha[idx] < 0.5) continue;
            final p = work.getPixel(x, y);
            final d = _minClusterDistance(
              p.r.toDouble(),
              p.g.toDouble(),
              p.b.toDouble(),
              bgClusters,
            );
            if (d < tightTol) {
              alpha[idx] = (d / tightTol * 0.25).clamp(0.0, 1.0);
            }
          }
        }
      }
    }

    return _finalizeAlphaMask(
      work: work,
      alpha: alpha,
      bgClusters: mode == MatteMode.chromaKey
          ? [
              [
                ((job.keyColorValue >> 16) & 0xFF).toDouble(),
                ((job.keyColorValue >> 8) & 0xFF).toDouble(),
                (job.keyColorValue & 0xFF).toDouble(),
              ]
            ]
          : bgClusters,
      edgeShrink: job.edgeShrink,
      featherRadius: job.featherRadius,
      defringeStrength: job.defringeStrength,
      autoCrop: job.autoCrop,
      strokes: job.strokes,
      methodName: mode.name,
    );
  }

  static MatteResult _finalizeAlphaMask({
    required img.Image work,
    required Float32List alpha,
    required List<List<double>> bgClusters,
    required int edgeShrink,
    required double featherRadius,
    required double defringeStrength,
    required bool autoCrop,
    required List<_SerializedStroke> strokes,
    required String methodName,
  }) {
    final w = work.width;
    final h = work.height;
    var mask = alpha;

    for (final stroke in strokes) {
      final tool = MatteBrushTool.values[
          stroke.toolIndex.clamp(0, MatteBrushTool.values.length - 1)];
      if (tool == MatteBrushTool.magicWand && stroke.points.isNotEmpty) {
        final pt = stroke.points.first;
        final sx = (pt.$1 * w).round().clamp(0, w - 1);
        final sy = (pt.$2 * h).round().clamp(0, h - 1);
        _applyMagicWandErase(work, mask, sx, sy, stroke.wandTol);
      } else if (tool == MatteBrushTool.erase || tool == MatteBrushTool.restore) {
        final targetVal = tool == MatteBrushTool.restore ? 1.0 : 0.0;
        final radiusPx = (stroke.radius * math.min(w, h)).clamp(4.0, 180.0);
        _applyBrushStroke(mask, w, h, stroke.points, radiusPx, targetVal);
      }
    }

    if (edgeShrink > 0) {
      mask = _erodeAlpha(mask, w, h, edgeShrink.clamp(1, 4));
    }

    if (featherRadius > 0.25) {
      mask = _boxBlurAlpha(mask, w, h, featherRadius.round().clamp(1, 5));
    }

    final out = img.Image(width: w, height: h, numChannels: 4);
    final bgR = bgClusters.isNotEmpty ? bgClusters[0][0] : 255.0;
    final bgG = bgClusters.isNotEmpty ? bgClusters[0][1] : 255.0;
    final bgB = bgClusters.isNotEmpty ? bgClusters[0][2] : 255.0;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final idx = y * w + x;
        final a = mask[idx].clamp(0.0, 1.0);
        if (a <= 0.015) {
          out.setPixelRgba(x, y, 0, 0, 0, 0);
          continue;
        }
        final p = work.getPixel(x, y);
        double r = p.r.toDouble();
        double g = p.g.toDouble();
        double b = p.b.toDouble();

        if (defringeStrength > 0.01 && a < 0.96) {
          final safeA = math.max(a, 0.22);
          final unmixedR = ((r - (1.0 - a) * bgR) / safeA).clamp(0.0, 255.0);
          final unmixedG = ((g - (1.0 - a) * bgG) / safeA).clamp(0.0, 255.0);
          final unmixedB = ((b - (1.0 - a) * bgB) / safeA).clamp(0.0, 255.0);

          final nearest = _sampleNearestOpaqueNeighbor(work, mask, w, h, x, y);
          final cleanR =
              nearest != null ? (unmixedR * 0.45 + nearest.$1 * 0.55) : unmixedR;
          final cleanG =
              nearest != null ? (unmixedG * 0.45 + nearest.$2 * 0.55) : unmixedG;
          final cleanB =
              nearest != null ? (unmixedB * 0.45 + nearest.$3 * 0.55) : unmixedB;

          final blend = defringeStrength * (1.0 - a).clamp(0.0, 1.0);
          r = r + (cleanR - r) * blend;
          g = g + (cleanG - g) * blend;
          b = b + (cleanB - b) * blend;
        }

        out.setPixelRgba(
          x,
          y,
          r.round().clamp(0, 255),
          g.round().clamp(0, 255),
          b.round().clamp(0, 255),
          (a * 255.0).round().clamp(0, 255),
        );
      }
    }

    img.Image finalImg = out;
    if (autoCrop) {
      finalImg = _trimTransparentBounds(out, padding: 8);
    }

    final pngBytes = Uint8List.fromList(img.encodePng(finalImg, level: 5));
    return MatteResult(
      pngBytes: pngBytes,
      width: finalImg.width,
      height: finalImg.height,
      methodUsed: methodName,
    );
  }

  static img.Image _resizeIfNeeded(img.Image src, int maxDim) {
    final longest = math.max(src.width, src.height);
    if (longest <= maxDim) return src;
    if (src.width >= src.height) {
      return img.copyResize(src,
          width: maxDim, interpolation: img.Interpolation.linear);
    } else {
      return img.copyResize(src,
          height: maxDim, interpolation: img.Interpolation.linear);
    }
  }

  static bool _imageHasTransparency(img.Image image) {
    if (image.numChannels < 4) return false;
    int transparentCount = 0;
    final stepX = math.max(1, image.width ~/ 32);
    final stepY = math.max(1, image.height ~/ 32);
    for (int y = 0; y < image.height; y += stepY) {
      for (int x = 0; x < image.width; x += stepX) {
        if (image.getPixel(x, y).a < 230) {
          transparentCount++;
          if (transparentCount > 12) return true;
        }
      }
    }
    return false;
  }

  static List<List<double>> _sampleBorderClusters(img.Image image) {
    final w = image.width;
    final h = image.height;
    final samples = <List<double>>[];

    final stepX = math.max(1, w ~/ 40);
    final stepY = math.max(1, h ~/ 40);
    for (int x = 0; x < w; x += stepX) {
      final pTop = image.getPixel(x, 0);
      final pBot = image.getPixel(x, h - 1);
      samples.add([pTop.r.toDouble(), pTop.g.toDouble(), pTop.b.toDouble()]);
      samples.add([pBot.r.toDouble(), pBot.g.toDouble(), pBot.b.toDouble()]);
    }
    for (int y = 0; y < h; y += stepY) {
      final pL = image.getPixel(0, y);
      final pR = image.getPixel(w - 1, y);
      samples.add([pL.r.toDouble(), pL.g.toDouble(), pL.b.toDouble()]);
      samples.add([pR.r.toDouble(), pR.g.toDouble(), pR.b.toDouble()]);
    }

    if (samples.isEmpty) {
      return [
        [255.0, 255.0, 255.0]
      ];
    }

    final clusters = <List<double>>[];
    final counts = <int>[];
    for (final s in samples) {
      int bestIdx = -1;
      double bestDist = 26.0;
      for (int i = 0; i < clusters.length; i++) {
        final d = _perceptualColorDist(
          s[0],
          s[1],
          s[2],
          clusters[i][0],
          clusters[i][1],
          clusters[i][2],
        );
        if (d < bestDist) {
          bestDist = d;
          bestIdx = i;
        }
      }
      if (bestIdx >= 0) {
        final c = counts[bestIdx];
        clusters[bestIdx][0] = (clusters[bestIdx][0] * c + s[0]) / (c + 1);
        clusters[bestIdx][1] = (clusters[bestIdx][1] * c + s[1]) / (c + 1);
        clusters[bestIdx][2] = (clusters[bestIdx][2] * c + s[2]) / (c + 1);
        counts[bestIdx] = c + 1;
      } else if (clusters.length < 6) {
        clusters.add([s[0], s[1], s[2]]);
        counts.add(1);
      }
    }

    final indices = List<int>.generate(clusters.length, (i) => i)
      ..sort((a, b) => counts[b].compareTo(counts[a]));
    final total = samples.length;
    final top = <List<double>>[];
    for (final i in indices.take(3)) {
      if (top.isEmpty || counts[i] >= total * 0.12) {
        top.add(clusters[i]);
      }
    }
    return top;
  }

  static double _perceptualColorDist(
    double r1,
    double g1,
    double b1,
    double r2,
    double g2,
    double b2,
  ) {
    final rMean = (r1 + r2) * 0.5;
    final dr = r1 - r2;
    final dg = g1 - g2;
    final db = b1 - b2;
    final wr = 2.0 + rMean / 256.0;
    const wg = 4.0;
    final wb = 2.0 + (255.0 - rMean) / 256.0;
    return math.sqrt(wr * dr * dr + wg * dg * dg + wb * db * db) * 0.45;
  }

  static double _minClusterDistance(
    double r,
    double g,
    double b,
    List<List<double>> clusters,
  ) {
    double best = double.infinity;
    for (final c in clusters) {
      final d = _perceptualColorDist(r, g, b, c[0], c[1], c[2]);
      if (d < best) best = d;
    }
    return best;
  }

  static Float32List _computeGradientMagnitude(img.Image image) {
    final w = image.width;
    final h = image.height;
    final luma = Float32List(w * h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        luma[y * w + x] = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      }
    }
    final grad = Float32List(w * h);
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final gx = luma[y * w + x + 1] - luma[y * w + x - 1];
        final gy = luma[(y + 1) * w + x] - luma[(y - 1) * w + x];
        grad[y * w + x] = math.sqrt(gx * gx + gy * gy);
      }
    }
    return grad;
  }

  static void _applyMagicWandErase(
    img.Image image,
    Float32List mask,
    int sx,
    int sy,
    double tolerance,
  ) {
    final w = image.width;
    final h = image.height;
    final sp = image.getPixel(sx, sy);
    final sr = sp.r.toDouble();
    final sg = sp.g.toDouble();
    final sb = sp.b.toDouble();

    final visited = Uint8List(w * h);
    final queue = Queue<int>();
    final startIdx = sy * w + sx;
    visited[startIdx] = 1;
    mask[startIdx] = 0.0;
    queue.addLast(startIdx);

    const dx4 = [1, -1, 0, 0];
    const dy4 = [0, 0, 1, -1];
    final softEnd = tolerance + 14.0;

    while (queue.isNotEmpty) {
      final curr = queue.removeFirst();
      final cx = curr % w;
      final cy = curr ~/ w;
      for (int dir = 0; dir < 4; dir++) {
        final nx = cx + dx4[dir];
        final ny = cy + dy4[dir];
        if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
        final nIdx = ny * w + nx;
        if (visited[nIdx] != 0) continue;
        final np = image.getPixel(nx, ny);
        final d = _perceptualColorDist(
          np.r.toDouble(),
          np.g.toDouble(),
          np.b.toDouble(),
          sr,
          sg,
          sb,
        );
        if (d <= tolerance) {
          visited[nIdx] = 1;
          mask[nIdx] = 0.0;
          queue.addLast(nIdx);
        } else if (d < softEnd) {
          visited[nIdx] = 1;
          final softA = ((d - tolerance) / (softEnd - tolerance)).clamp(0.0, 1.0);
          mask[nIdx] = math.min(mask[nIdx], softA);
        }
      }
    }
  }

  static void _applyBrushStroke(
    Float32List mask,
    int w,
    int h,
    List<(double, double)> points,
    double radiusPx,
    double targetAlpha,
  ) {
    if (points.isEmpty) return;

    void paintDisc(double cx, double cy) {
      final rCeil = radiusPx.ceil();
      final x0 = (cx - rCeil).floor().clamp(0, w - 1);
      final x1 = (cx + rCeil).ceil().clamp(0, w - 1);
      final y0 = (cy - rCeil).floor().clamp(0, h - 1);
      final y1 = (cy + rCeil).ceil().clamp(0, h - 1);
      for (int y = y0; y <= y1; y++) {
        for (int x = x0; x <= x1; x++) {
          final dist = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
          if (dist <= radiusPx) {
            final hardness = (1.0 - (dist / radiusPx)).clamp(0.0, 1.0);
            final strength = (hardness * 2.4).clamp(0.0, 1.0);
            final idx = y * w + x;
            mask[idx] = mask[idx] + (targetAlpha - mask[idx]) * strength;
          }
        }
      }
    }

    for (int i = 0; i < points.length; i++) {
      final px = points[i].$1 * w;
      final py = points[i].$2 * h;
      if (i == 0) {
        paintDisc(px, py);
      } else {
        final prevX = points[i - 1].$1 * w;
        final prevY = points[i - 1].$2 * h;
        final segLen =
            math.sqrt((px - prevX) * (px - prevX) + (py - prevY) * (py - prevY));
        final steps =
            math.max(1, (segLen / math.max(2.0, radiusPx * 0.35)).ceil());
        for (int s = 1; s <= steps; s++) {
          final t = s / steps;
          paintDisc(prevX + (px - prevX) * t, prevY + (py - prevY) * t);
        }
      }
    }
  }

  static Float32List _erodeAlpha(Float32List src, int w, int h, int iterations) {
    var current = src;
    for (int iter = 0; iter < iterations; iter++) {
      final next = Float32List.fromList(current);
      for (int y = 1; y < h - 1; y++) {
        for (int x = 1; x < w - 1; x++) {
          final idx = y * w + x;
          final c = current[idx];
          if (c <= 0.001) continue;
          double minN = c;
          final n1 = current[idx - 1];
          final n2 = current[idx + 1];
          final n3 = current[idx - w];
          final n4 = current[idx + w];
          if (n1 < minN) minN = n1;
          if (n2 < minN) minN = n2;
          if (n3 < minN) minN = n3;
          if (n4 < minN) minN = n4;
          next[idx] = c * 0.25 + minN * 0.75;
        }
      }
      current = next;
    }
    return current;
  }

  static Float32List _boxBlurAlpha(Float32List src, int w, int h, int radius) {
    final horiz = Float32List(w * h);
    final out = Float32List(w * h);
    final kernelSize = radius * 2 + 1;

    for (int y = 0; y < h; y++) {
      double acc = 0;
      for (int dx = -radius; dx <= radius; dx++) {
        acc += src[y * w + dx.clamp(0, w - 1)];
      }
      for (int x = 0; x < w; x++) {
        horiz[y * w + x] = acc / kernelSize;
        final removeX = (x - radius).clamp(0, w - 1);
        final addX = (x + radius + 1).clamp(0, w - 1);
        acc += src[y * w + addX] - src[y * w + removeX];
      }
    }

    for (int x = 0; x < w; x++) {
      double acc = 0;
      for (int dy = -radius; dy <= radius; dy++) {
        acc += horiz[dy.clamp(0, h - 1) * w + x];
      }
      for (int y = 0; y < h; y++) {
        final orig = src[y * w + x];
        final blurred = acc / kernelSize;
        out[y * w + x] = orig > 0.99 && blurred > 0.96 ? 1.0 : blurred;
        final removeY = (y - radius).clamp(0, h - 1);
        final addY = (y + radius + 1).clamp(0, h - 1);
        acc += horiz[addY * w + x] - horiz[removeY * w + x];
      }
    }
    return out;
  }

  static (double, double, double)? _sampleNearestOpaqueNeighbor(
    img.Image image,
    Float32List mask,
    int w,
    int h,
    int x,
    int y,
  ) {
    double sumR = 0, sumG = 0, sumB = 0;
    int count = 0;
    for (int dy = -2; dy <= 2; dy++) {
      final ny = y + dy;
      if (ny < 0 || ny >= h) continue;
      for (int dx = -2; dx <= 2; dx++) {
        final nx = x + dx;
        if (nx < 0 || nx >= w) continue;
        if (mask[ny * w + nx] > 0.92) {
          final p = image.getPixel(nx, ny);
          sumR += p.r;
          sumG += p.g;
          sumB += p.b;
          count++;
        }
      }
    }
    if (count == 0) return null;
    return (sumR / count, sumG / count, sumB / count);
  }

  static img.Image _trimTransparentBounds(img.Image src, {int padding = 8}) {
    int minX = src.width;
    int minY = src.height;
    int maxX = 0;
    int maxY = 0;

    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        if (src.getPixel(x, y).a > 12) {
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
        }
      }
    }

    if (minX >= maxX || minY >= maxY) return src;

    final cx = (minX - padding).clamp(0, src.width - 1);
    final cy = (minY - padding).clamp(0, src.height - 1);
    final cw = (maxX - minX + 1 + padding * 2).clamp(1, src.width - cx);
    final ch = (maxY - minY + 1 + padding * 2).clamp(1, src.height - cy);

    return img.copyCrop(src, x: cx, y: cy, width: cw, height: ch);
  }
}
