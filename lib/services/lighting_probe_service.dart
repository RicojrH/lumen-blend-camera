import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/blend_recipe.dart';

/// Analyzes real-world scenes (live camera frames or decoded photos) to infer:
/// - Color Temperature (Kelvin) & Tint
/// - Exposure EV, Contrast, Saturation & Atmospheric Black-Level Lift
/// - Dominant Light Source Azimuth & Elevation
/// - Local Ground / Ambient Bounce Color around the standee's feet
/// - Camera Sensor Noise (Film Grain) level
class LightingProbeService {
  static const int gridSize = 28;
  static const int _gridSize = 28;

  /// Analyzes a pre-downsampled `gridSize x gridSize` RGB byte buffer (length = gridSize*gridSize*3).
  static LightingProfile analyzeRgbBytesGrid(
    Uint8List rgbBytes, {
    int size = gridSize,
    double anchorX = 0.50,
    double anchorY = 0.85,
    LightingProfile? base,
  }) {
    if (rgbBytes.length < size * size * 3) {
      return base ?? const LightingProfile();
    }
    final grid = Float32List(size * size * 3);
    for (int i = 0; i < grid.length; i++) {
      grid[i] = rgbBytes[i] / 255.0;
    }
    return _estimateFromRgbGrid(
      grid,
      size,
      size,
      anchorX: anchorX,
      anchorY: anchorY,
      base: base,
    );
  }

  /// Analyzes a decoded `img.Image` (for mock scenes, captured photos, or gallery re-blend).
  static LightingProfile analyzeImage(
    img.Image image, {
    double anchorX = 0.50,
    double anchorY = 0.85,
    LightingProfile? base,
  }) {
    final grid = Float32List(_gridSize * _gridSize * 3);
    final w = image.width;
    final h = image.height;
    if (w <= 0 || h <= 0) return base ?? const LightingProfile();

    for (int gy = 0; gy < _gridSize; gy++) {
      final sy = ((gy + 0.5) * h / _gridSize).floor().clamp(0, h - 1);
      for (int gx = 0; gx < _gridSize; gx++) {
        final sx = ((gx + 0.5) * w / _gridSize).floor().clamp(0, w - 1);
        final p = image.getPixel(sx, sy);
        final idx = (gy * _gridSize + gx) * 3;
        grid[idx] = p.r / 255.0;
        grid[idx + 1] = p.g / 255.0;
        grid[idx + 2] = p.b / 255.0;
      }
    }

    return _estimateFromRgbGrid(
      grid,
      _gridSize,
      _gridSize,
      anchorX: anchorX,
      anchorY: anchorY,
      base: base,
    );
  }

  /// Fast zero-allocation-friendly lighting estimation directly from a live `CameraImage`.
  /// Supports Android YUV420 (`ImageFormatGroup.yuv420`) and iOS BGRA8888 (`ImageFormatGroup.bgra8888`).
  static LightingProfile analyzeCameraImage(
    CameraImage frame, {
    double anchorX = 0.50,
    double anchorY = 0.85,
    LightingProfile? base,
  }) {
    final w = frame.width;
    final h = frame.height;
    if (w <= 0 || h <= 0 || frame.planes.isEmpty) {
      return base ?? const LightingProfile();
    }

    final grid = Float32List(_gridSize * _gridSize * 3);

    if (frame.format.group == ImageFormatGroup.bgra8888) {
      final plane = frame.planes[0];
      final bytes = plane.bytes;
      final stride = plane.bytesPerRow;

      for (int gy = 0; gy < _gridSize; gy++) {
        final sy = ((gy + 0.5) * h / _gridSize).floor().clamp(0, h - 1);
        for (int gx = 0; gx < _gridSize; gx++) {
          final sx = ((gx + 0.5) * w / _gridSize).floor().clamp(0, w - 1);
          final offset = sy * stride + sx * 4;
          if (offset + 2 >= bytes.length) continue;
          final b = bytes[offset] / 255.0;
          final g = bytes[offset + 1] / 255.0;
          final r = bytes[offset + 2] / 255.0;
          final idx = (gy * _gridSize + gx) * 3;
          grid[idx] = r;
          grid[idx + 1] = g;
          grid[idx + 2] = b;
        }
      }
    } else if (frame.planes.length >= 3) {
      // Android YUV420
      final yPlane = frame.planes[0];
      final uPlane = frame.planes[1];
      final vPlane = frame.planes[2];
      final yBytes = yPlane.bytes;
      final uBytes = uPlane.bytes;
      final vBytes = vPlane.bytes;
      final uvPixelStride = uPlane.bytesPerPixel ?? 1;

      for (int gy = 0; gy < _gridSize; gy++) {
        final sy = ((gy + 0.5) * h / _gridSize).floor().clamp(0, h - 1);
        for (int gx = 0; gx < _gridSize; gx++) {
          final sx = ((gx + 0.5) * w / _gridSize).floor().clamp(0, w - 1);
          final yIdx = sy * yPlane.bytesPerRow + sx;
          final uvIdx = (sy ~/ 2) * uPlane.bytesPerRow + (sx ~/ 2) * uvPixelStride;
          if (yIdx >= yBytes.length ||
              uvIdx >= uBytes.length ||
              uvIdx >= vBytes.length) {
            continue;
          }
          final yVal = yBytes[yIdx].toDouble();
          final uVal = uBytes[uvIdx].toDouble() - 128.0;
          final vVal = vBytes[uvIdx].toDouble() - 128.0;

          final r = ((yVal + 1.402 * vVal) / 255.0).clamp(0.0, 1.0);
          final g = ((yVal - 0.344136 * uVal - 0.714136 * vVal) / 255.0)
              .clamp(0.0, 1.0);
          final b = ((yVal + 1.772 * uVal) / 255.0).clamp(0.0, 1.0);

          final idx = (gy * _gridSize + gx) * 3;
          grid[idx] = r;
          grid[idx + 1] = g;
          grid[idx + 2] = b;
        }
      }
    } else {
      return base ?? const LightingProfile();
    }

    return _estimateFromRgbGrid(
      grid,
      _gridSize,
      _gridSize,
      anchorX: anchorX,
      anchorY: anchorY,
      base: base,
    );
  }

  /// Core photometric estimation from a normalized RGB sample grid.
  static LightingProfile _estimateFromRgbGrid(
    Float32List grid,
    int gw,
    int gh, {
    required double anchorX,
    required double anchorY,
    LightingProfile? base,
  }) {
    final total = gw * gh;
    final lumas = Float32List(total);

    double wbR = 0, wbG = 0, wbB = 0, wbWeight = 0;
    double satSum = 0;

    // Ground/local ambient bounce accumulators near the standee placement
    double ambR = 0, ambG = 0, ambB = 0, ambWeight = 0;

    // Light centroid accumulators (bright regions determine key light direction)
    double brightSumX = 0, brightSumY = 0, brightWeight = 0;

    for (int gy = 0; gy < gh; gy++) {
      final ny = (gy + 0.5) / gh;
      for (int gx = 0; gx < gw; gx++) {
        final nx = (gx + 0.5) / gw;
        final idx = (gy * gw + gx) * 3;
        final r = grid[idx];
        final g = grid[idx + 1];
        final b = grid[idx + 2];

        final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        lumas[gy * gw + gx] = luma;

        final maxC = math.max(r, math.max(g, b));
        final minC = math.min(r, math.min(g, b));
        final sat = maxC > 0.001 ? (maxC - minC) / maxC : 0.0;
        satSum += sat;

        // White-balance weighting: favor mid-to-bright pixels, avoid clipped whites and pitch blacks
        if (luma > 0.06 && luma < 0.96) {
          final upperBias = ny < 0.65 ? 1.25 : 0.85;
          final w = (0.35 + luma) * upperBias;
          wbR += r * w;
          wbG += g * w;
          wbB += b * w;
          wbWeight += w;
        }

        // Local ambient bounce color around standee body & feet
        final dx = nx - anchorX;
        final dy = ny - (anchorY - 0.08);
        final distSq = dx * dx + dy * dy;
        final localW = math.exp(-distSq / 0.09);
        ambR += r * localW;
        ambG += g * localW;
        ambB += b * localW;
        ambWeight += localW;
      }
    }

    // Percentile luminance distribution
    final sortedLuma = List<double>.from(lumas)..sort();
    final p05 = sortedLuma[(total * 0.05).floor().clamp(0, total - 1)];
    final p50 = sortedLuma[(total * 0.50).floor().clamp(0, total - 1)];
    final p82 = sortedLuma[(total * 0.82).floor().clamp(0, total - 1)];
    final p95 = sortedLuma[(total * 0.95).floor().clamp(0, total - 1)];

    // Bright-region centroid for dominant light source azimuth & elevation
    final threshold = math.max(p82, 0.28);
    for (int gy = 0; gy < gh; gy++) {
      final ny = (gy + 0.5) / gh;
      // Upper 80% contributes most strongly to sky/lamp/window key direction
      final skyBias = ny < 0.78 ? 1.0 : 0.25;
      for (int gx = 0; gx < gw; gx++) {
        final nx = (gx + 0.5) / gw;
        final luma = lumas[gy * gw + gx];
        if (luma >= threshold) {
          final excess = (luma - threshold + 0.05) * skyBias;
          brightSumX += nx * excess;
          brightSumY += ny * excess;
          brightWeight += excess;
        }
      }
    }

    double azimuthDeg = base?.lightAzimuthDeg ?? 315.0;
    double elevationDeg = base?.lightElevationDeg ?? 42.0;
    if (brightWeight > 0.001) {
      final cx = brightSumX / brightWeight;
      final cy = brightSumY / brightWeight;
      // Vector from character torso center toward dominant bright zone
      final vx = cx - anchorX;
      final vy = cy - (anchorY - 0.28).clamp(0.15, 0.85);
      if (vx * vx + vy * vy > 0.0015) {
        azimuthDeg = (math.atan2(vy, vx) * 180.0 / math.pi + 360.0) % 360.0;
      }
      // Higher bright centroid (smaller cy) => steeper elevation angle
      elevationDeg = (68.0 - cy * 52.0).clamp(16.0, 74.0);
    }

    // Color temperature estimation from weighted average R/B ratio
    double kelvin = 5600.0;
    double tint = 0.0;
    if (wbWeight > 0.001) {
      final avgR = (wbR / wbWeight).clamp(0.02, 1.0);
      final avgG = (wbG / wbWeight).clamp(0.02, 1.0);
      final avgB = (wbB / wbWeight).clamp(0.02, 1.0);

      // log(R/B): positive = warm scene (lower Kelvin), negative = cool scene (higher Kelvin)
      final rbLog = math.log(avgR / avgB);
      kelvin = (5600.0 * math.exp(-rbLog * 0.72)).clamp(2700.0, 9200.0);

      // Green vs magenta shift
      final rbAvg = (avgR + avgB) * 0.5;
      tint = ((rbAvg - avgG) / (rbAvg + 0.12) * 1.4).clamp(-0.65, 0.65);
    }

    // Local ambient bounce color
    Color ambientColor = const Color(0xFF8C94A0);
    if (ambWeight > 0.001) {
      final ar = (ambR / ambWeight).clamp(0.0, 1.0);
      final ag = (ambG / ambWeight).clamp(0.0, 1.0);
      final ab = (ambB / ambWeight).clamp(0.0, 1.0);
      ambientColor = Color.fromARGB(
        255,
        (ar * 255).round().clamp(0, 255),
        (ag * 255).round().clamp(0, 255),
        (ab * 255).round().clamp(0, 255),
      );
    }

    // Estimate high-frequency texture/noise via 4-neighbor Laplacian on luma grid
    double lapSum = 0;
    int lapCount = 0;
    for (int gy = 1; gy < gh - 1; gy++) {
      for (int gx = 1; gx < gw - 1; gx++) {
        final c = lumas[gy * gw + gx];
        final avgN = (lumas[gy * gw + gx - 1] +
                lumas[gy * gw + gx + 1] +
                lumas[(gy - 1) * gw + gx] +
                lumas[(gy + 1) * gw + gx]) *
            0.25;
        lapSum += (c - avgN).abs();
        lapCount++;
      }
    }
    final avgLap = lapCount > 0 ? lapSum / lapCount : 0.03;
    // Darker scenes naturally exhibit higher smartphone ISO grain
    final darkIsoBoost = (1.0 - p50).clamp(0.0, 0.7) * 0.10;
    final filmGrain = (avgLap * 0.45 + darkIsoBoost).clamp(0.03, 0.22);

    // Exposure, contrast, saturation, and black-level match
    final exposureEv = ((p50 - 0.50) * 1.35).clamp(-1.05, 0.75);
    final dynamicRange = (p95 - p05).clamp(0.15, 1.0);
    final contrast = (0.80 + dynamicRange * 0.36).clamp(0.78, 1.22);
    final blackLift = (p05 * 0.85 + 0.015).clamp(0.015, 0.20);
    final avgSat = (satSum / total).clamp(0.0, 1.0);
    final saturation = (0.72 + avgSat * 0.52).clamp(0.68, 1.18);

    // Directional contrast (how strongly directional vs flat overcast the light is)
    final dirStrength = (0.38 + (p95 - p50) * 0.85).clamp(0.35, 0.90);

    final template = base ?? const LightingProfile();
    return template.copyWith(
      kelvin: kelvin,
      tint: tint,
      exposureEv: exposureEv,
      contrast: contrast,
      saturation: saturation,
      blackLift: blackLift,
      lightAzimuthDeg: azimuthDeg,
      lightElevationDeg: elevationDeg,
      directionalStrength: dirStrength,
      ambientColorValue: ambientColor.toARGB32(),
      filmGrain: filmGrain,
    );
  }
}
