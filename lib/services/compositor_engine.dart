import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/blend_recipe.dart';
import 'perspective_engine.dart';

typedef _CompositeJob = ({
  Uint8List backgroundBytes,
  Uint8List standeePngBytes,
  Map<String, dynamic> recipeJson,
  int maxDimension,
  bool encodeAsPng,
});

/// High-resolution physical optical compositor running in a background Isolate (and Web-safe via compute).
/// Reproduces our GLSL harmonization shader physics at full resolution PLUS:
/// - True pixel-accurate Contact Ambient Occlusion under actual character feet
/// - Perspective-projected Directional Cast Shadow with distance-based penumbra falloff
/// - Real background-sampled Optical Light Wrap along the silhouette border
/// - Lens depth-of-field blur & camera CMOS grain matching
class CompositorEngine {
  static Future<Uint8List> renderComposite({
    required Uint8List backgroundBytes,
    required Uint8List standeePngBytes,
    required BlendRecipe recipe,
    int maxDimension = 1920,
    bool encodeAsPng = false,
  }) async {
    final job = (
      backgroundBytes: backgroundBytes,
      standeePngBytes: standeePngBytes,
      recipeJson: recipe.toJson(),
      maxDimension: maxDimension,
      encodeAsPng: encodeAsPng,
    );
    return compute(_renderJob, job);
  }

  static Uint8List _renderJob(_CompositeJob job) {
    return _renderSync(
      backgroundBytes: job.backgroundBytes,
      standeePngBytes: job.standeePngBytes,
      recipe: BlendRecipe.fromJson(job.recipeJson),
      maxDimension: job.maxDimension,
      encodeAsPng: job.encodeAsPng,
    );
  }

  static Uint8List _renderSync({
    required Uint8List backgroundBytes,
    required Uint8List standeePngBytes,
    required BlendRecipe recipe,
    required int maxDimension,
    required bool encodeAsPng,
  }) {
    final bgDecoded = img.decodeImage(backgroundBytes);
    final fgDecoded = img.decodeImage(standeePngBytes);
    if (bgDecoded == null || fgDecoded == null) {
      throw Exception('无法解码背景图或立绘素材');
    }

    // Normalize background resolution
    img.Image canvas = _resizeLongest(bgDecoded, maxDimension);
    // Ensure 4 channels RGBA for clean blending
    if (canvas.numChannels < 4) {
      canvas = canvas.convert(numChannels: 4);
    }

    final bgW = canvas.width;
    final bgH = canvas.height;

    final placement = recipe.placement;
    final perspective = recipe.perspective;
    final lighting = recipe.lighting;

    // 1. Compute target standee dimensions anchored at feet
    final perspScale = placement.lockToPerspectiveScale
        ? perspective.scaleFactorAtY(placement.anchorY)
        : 1.0;
    final baseHeight = bgH * 0.56;
    final targetH =
        (baseHeight * perspScale * placement.userScale).round().clamp(48, bgH * 2);
    final fgAspect = fgDecoded.height > 0 ? fgDecoded.width / fgDecoded.height : 0.66;
    final targetW = (targetH * fgAspect).round().clamp(32, bgW * 2);

    img.Image fg = img.copyResize(
      fgDecoded,
      width: targetW,
      height: targetH,
      interpolation: img.Interpolation.cubic,
    );

    if (placement.flipX) {
      fg = img.flipHorizontal(fg);
    }

    // Optional lens Depth-of-Field blur on standee
    if (lighting.dofBlur > 0.35) {
      final blurRad = lighting.dofBlur.round().clamp(1, 6);
      fg = img.gaussianBlur(fg, radius: blurRad);
    }

    // Foot anchor pixel coordinates on canvas
    final anchorPxX = (placement.anchorX * bgW).round();
    final anchorPxY = (placement.anchorY * bgH).round();

    // Standee top-left position on canvas (before rotation)
    final fgLeft = anchorPxX - (targetW ~/ 2);
    final fgTop = anchorPxY - targetH;

    // 2. Render Grounded Shadows directly onto background BEFORE character
    if (lighting.shadowOpacity > 0.01 && lighting.blendStrength > 0.01) {
      _drawGroundedShadows(
        canvas: canvas,
        standee: fg,
        fgLeft: fgLeft,
        fgTop: fgTop,
        anchorPxX: anchorPxX,
        anchorPxY: anchorPxY,
        lighting: lighting,
        perspective: perspective,
      );
    }

    // 3. Harmonize & Composite Standee over Background with exact optical physics
    _compositeHarmonizedStandee(
      canvas: canvas,
      standee: fg,
      fgLeft: fgLeft,
      fgTop: fgTop,
      anchorPxX: anchorPxX,
      anchorPxY: anchorPxY,
      placement: placement,
      perspective: perspective,
      lighting: lighting,
    );

    if (encodeAsPng) {
      return Uint8List.fromList(img.encodePng(canvas, level: 4));
    }
    return Uint8List.fromList(img.encodeJpg(canvas, quality: 94));
  }

  /// Draws both:
  /// (A) Tight Contact Ambient Occlusion right beneath the character's shoes
  /// (B) Perspective-skewed Directional Cast Shadow projected along the opposite light direction
  static void _drawGroundedShadows({
    required img.Image canvas,
    required img.Image standee,
    required int fgLeft,
    required int fgTop,
    required int anchorPxX,
    required int anchorPxY,
    required LightingProfile lighting,
    required PerspectiveState perspective,
  }) {
    final bgW = canvas.width;
    final bgH = canvas.height;
    final fgW = standee.width;
    final fgH = standee.height;

    final masterOpacity =
        (lighting.shadowOpacity * lighting.blendStrength).clamp(0.0, 0.95);

    // Shadow tint: deep darkened ambient hue (realistic shadows carry sky/ambient color, never flat black)
    final amb = lighting.ambientColor;
    final shR = (amb.r * 255 * 0.16).clamp(4.0, 38.0);
    final shG = (amb.g * 255 * 0.18).clamp(5.0, 42.0);
    final shB = (amb.b * 255 * 0.24).clamp(8.0, 56.0);

    // Continuous 360-degree ground shadow projection basis matching live preview
    final anchorNormY = anchorPxY / math.max(1, bgH);
    final flatness = PerspectiveEngine.contactEllipseFlatness(
      anchorNormY,
      perspective.horizonY,
    );
    final basis = PerspectiveEngine.computeShadowBasis(
      lighting: lighting,
      perspective: perspective,
      anchorYNorm: anchorNormY,
    );
    final wAxis = basis.widthAxis;
    final hAxis = basis.heightAxis;

    // Generous 360° ROI around feet so long shadows in ANY direction (front/back/left/right) never clip
    final padX = (fgW * 1.9 + fgH * hAxis.dx.abs() + 36).round();
    final padY = (fgH * hAxis.dy.abs() + fgW * wAxis.dy.abs() + 48).round();
    final roiL = (anchorPxX - padX).clamp(0, bgW - 1);
    final roiT = (anchorPxY - padY).clamp(0, bgH - 1);
    final roiR = (anchorPxX + padX).clamp(0, bgW - 1);
    final roiB = (anchorPxY + padY).clamp(0, bgH - 1);
    final roiW = roiR - roiL + 1;
    final roiH = roiB - roiT + 1;
    if (roiW <= 2 || roiH <= 2) return;

    final castBuf = Float32List(roiW * roiH);

    final step = fgH > 650 ? 2 : 1;
    for (int y = 0; y < fgH; y += step) {
      final hPx = (fgH - 1 - y).toDouble();
      final heightRatio = hPx / math.max(1, fgH);
      final distFade = (1.0 - heightRatio * 0.68).clamp(0.18, 1.0);

      for (int x = 0; x < fgW; x += step) {
        final a = standee.getPixel(x, y).a / 255.0;
        if (a < 0.15) continue;

        final dxFoot = (x - fgW * 0.5);
        final projX = anchorPxX + dxFoot * wAxis.dx + hPx * hAxis.dx;
        final projY = anchorPxY + dxFoot * wAxis.dy + hPx * hAxis.dy;

        final rx = (projX - roiL).round();
        final ry = (projY - roiT).round();
        if (rx >= 0 && rx < roiW && ry >= 0 && ry < roiH) {
          final v = a * distFade * 0.65;
          final idx = ry * roiW + rx;
          if (v > castBuf[idx]) castBuf[idx] = v;
          if (step == 2 && rx + 1 < roiW && ry + 1 < roiH) {
            if (v > castBuf[idx + 1]) castBuf[idx + 1] = v;
            if (v > castBuf[idx + roiW]) castBuf[idx + roiW] = v;
          }
        }
      }
    }

    // Blur cast shadow buffer according to shadowSoftness
    final blurRadius = (3 + lighting.shadowSoftness * 14).round().clamp(2, 18);
    final softCast = _boxBlurFloat(castBuf, roiW, roiH, blurRadius);

    // Detect actual foot contact span in bottom 7% of standee for precise Contact AO
    final footContacts = <int>[];
    final bottomBandStart = (fgH * 0.93).floor().clamp(0, fgH - 1);
    for (int x = 0; x < fgW; x += 2) {
      for (int y = bottomBandStart; y < fgH; y++) {
        if (standee.getPixel(x, y).a > 90) {
          footContacts.add(fgLeft + x);
          break;
        }
      }
    }

    // Multiply cast shadow onto background canvas
    for (int ry = 0; ry < roiH; ry++) {
      final cy = roiT + ry;
      for (int rx = 0; rx < roiW; rx++) {
        final density = (softCast[ry * roiW + rx] * masterOpacity).clamp(0.0, 0.80);
        if (density <= 0.004) continue;
        final cx = roiL + rx;
        final bgP = canvas.getPixel(cx, cy);
        final nr = bgP.r * (1.0 - density) + shR * density;
        final ng = bgP.g * (1.0 - density) + shG * density;
        final nb = bgP.b * (1.0 - density) + shB * density;
        canvas.setPixelRgba(
          cx,
          cy,
          nr.round().clamp(0, 255),
          ng.round().clamp(0, 255),
          nb.round().clamp(0, 255),
          255,
        );
      }
    }

    // Layer A: High-density Contact Ambient Occlusion hugging the character's shoes
    if (footContacts.isNotEmpty) {
      final aoRadX = (fgW * 0.09).clamp(10.0, 48.0);
      final aoRadY = (aoRadX * flatness * 0.72).clamp(4.0, 20.0);
      final aoStrength = (masterOpacity * 0.72).clamp(0.0, 0.78);

      // Cluster contiguous foot contact x positions (typically left & right shoe)
      final centers = <double>[];
      int segStart = footContacts.first;
      int segPrev = footContacts.first;
      for (int i = 1; i < footContacts.length; i++) {
        if (footContacts[i] - segPrev > (fgW * 0.06).clamp(8, 32)) {
          centers.add((segStart + segPrev) * 0.5);
          segStart = footContacts[i];
        }
        segPrev = footContacts[i];
      }
      centers.add((segStart + segPrev) * 0.5);

      for (final cxFoot in centers) {
        final x0 = (cxFoot - aoRadX * 1.5).floor().clamp(0, bgW - 1);
        final x1 = (cxFoot + aoRadX * 1.5).ceil().clamp(0, bgW - 1);
        final y0 = (anchorPxY - aoRadY * 1.2).floor().clamp(0, bgH - 1);
        final y1 = (anchorPxY + aoRadY * 1.5).ceil().clamp(0, bgH - 1);

        for (int y = y0; y <= y1; y++) {
          for (int x = x0; x <= x1; x++) {
            final ndx = (x - cxFoot) / aoRadX;
            final ndy = (y - anchorPxY) / aoRadY;
            final r2 = ndx * ndx + ndy * ndy;
            if (r2 > 2.2) continue;
            final falloff = math.exp(-r2 * 1.45) * aoStrength;
            final bgP = canvas.getPixel(x, y);
            final nr = bgP.r * (1.0 - falloff) + shR * 0.5 * falloff;
            final ng = bgP.g * (1.0 - falloff) + shG * 0.5 * falloff;
            final nb = bgP.b * (1.0 - falloff) + shB * 0.5 * falloff;
            canvas.setPixelRgba(
              x,
              y,
              nr.round().clamp(0, 255),
              ng.round().clamp(0, 255),
              nb.round().clamp(0, 255),
              255,
            );
          }
        }
      }
    }
  }

  /// Applies full physical lighting harmonization + real background-sampled Light Wrap + grain.
  static void _compositeHarmonizedStandee({
    required img.Image canvas,
    required img.Image standee,
    required int fgLeft,
    required int fgTop,
    required int anchorPxX,
    required int anchorPxY,
    required PlacementTransform placement,
    required PerspectiveState perspective,
    required LightingProfile lighting,
  }) {
    final bgW = canvas.width;
    final bgH = canvas.height;
    final fgW = standee.width;
    final fgH = standee.height;

    final wb = lighting.whiteBalanceRgb;
    final evGain = math.pow(2.0, lighting.exposureEv).toDouble();
    final lightVec = lighting.lightDirectionVector;
    final amb = lighting.ambientColor;
    final ambR = amb.r;
    final ambG = amb.g;
    final ambB = amb.b;

    final totalRotRad =
        placement.rotationRad + (perspective.rollDeg * math.pi / 180.0);
    final cosRot = math.cos(totalRotRad);
    final sinRot = math.sin(totalRotRad);
    final hasRotation = totalRotRad.abs() > 0.004;

    final blend = lighting.blendStrength.clamp(0.0, 1.0);
    final dirStr = lighting.directionalStrength;
    final ambStr = lighting.ambientStrength;
    final wrapStr = lighting.lightWrap;
    final contrast = lighting.contrast;
    final saturation = lighting.saturation;
    final blackLift = lighting.blackLift;
    final grain = lighting.filmGrain;

    // Precompute alpha buffer for fast rim normal & edge mask detection
    final alphaBuf = Float32List(fgW * fgH);
    for (int y = 0; y < fgH; y++) {
      for (int x = 0; x < fgW; x++) {
        alphaBuf[y * fgW + x] = standee.getPixel(x, y).a / 255.0;
      }
    }

    final stepProbe = math.max(2, (math.min(fgW, fgH) / 90).round());

    // Compute rotated bounding box on canvas
    final diag = math.sqrt(fgW * fgW + fgH * fgH);
    final minX = hasRotation
        ? (anchorPxX - diag).floor().clamp(0, bgW - 1)
        : fgLeft.clamp(0, bgW - 1);
    final maxX = hasRotation
        ? (anchorPxX + diag).ceil().clamp(0, bgW - 1)
        : (fgLeft + fgW - 1).clamp(0, bgW - 1);
    final minY = hasRotation
        ? (anchorPxY - diag).floor().clamp(0, bgH - 1)
        : fgTop.clamp(0, bgH - 1);
    final maxY = hasRotation
        ? (anchorPxY + diag * 0.4).ceil().clamp(0, bgH - 1)
        : (fgTop + fgH - 1).clamp(0, bgH - 1);

    for (int cy = minY; cy <= maxY; cy++) {
      for (int cx = minX; cx <= maxX; cx++) {
        int fx, fy;
        if (!hasRotation) {
          fx = cx - fgLeft;
          fy = cy - fgTop;
        } else {
          // Rotate around foot anchor (anchorPxX, anchorPxY)
          final dx = cx - anchorPxX;
          final dy = cy - anchorPxY;
          final rx = dx * cosRot + dy * sinRot;
          final ry = -dx * sinRot + dy * cosRot;
          fx = (rx + fgW * 0.5).round();
          fy = (ry + fgH).round();
        }

        if (fx < 0 || fx >= fgW || fy < 0 || fy >= fgH) continue;

        final a = alphaBuf[fy * fgW + fx];
        if (a <= 0.008) continue;

        final fp = standee.getPixel(fx, fy);
        final rawR = fp.r / 255.0;
        final rawG = fp.g / 255.0;
        final rawB = fp.b / 255.0;

        double r = rawR * evGain * wb[0];
        double g = rawG * evGain * wb[1];
        double b = rawB * evGain * wb[2];

        // Silhouette pseudo-normal & edge mask
        final xR = (fx + stepProbe).clamp(0, fgW - 1);
        final xL = (fx - stepProbe).clamp(0, fgW - 1);
        final yD = (fy + stepProbe).clamp(0, fgH - 1);
        final yU = (fy - stepProbe).clamp(0, fgH - 1);

        final aR = alphaBuf[fy * fgW + xR];
        final aL = alphaBuf[fy * fgW + xL];
        final aD = alphaBuf[yD * fgW + fx];
        final aU = alphaBuf[yU * fgW + fx];

        final gx = aL - aR;
        final gy = aU - aD;
        final gLen = math.sqrt(gx * gx + gy * gy);
        final rimNx = gLen > 0.01 ? gx / gLen : 0.0;
        final rimNy = gLen > 0.01 ? gy / gLen : 0.0;

        final avgA = (aR + aL + aD + aU) * 0.25;
        final edgeMask = ((1.0 - avgA) * 2.1).clamp(0.0, 1.0);

        // Directional body shading & sunlit rim highlight
        final u = fx / math.max(1, fgW);
        final v = fy / math.max(1, fgH);
        final bodyDot = (u - 0.5) * 2.0 * lightVec.dx + (v - 0.5) * 2.0 * lightVec.dy;
        final keyShade = 1.0 + bodyDot * 0.18 * dirStr;
        r *= keyShade;
        g *= keyShade;
        b *= keyShade;

        final rimDot = rimNx * lightVec.dx + rimNy * lightVec.dy;
        if (rimDot > 0) {
          final rimLight = rimDot * edgeMask * dirStr * 0.28;
          r += (0.35 + 0.65 * wb[0]) * rimLight;
          g += (0.35 + 0.65 * wb[1]) * rimLight;
          b += (0.35 + 0.65 * wb[2]) * rimLight;
        } else {
          final backShade = 1.0 - (-rimDot * edgeMask * dirStr * 0.16);
          r *= backShade;
          g *= backShade;
          b *= backShade;
        }

        // Ground bounce & ambient tint
        final groundFactor = ((v - 0.55) / 0.45).clamp(0.0, 1.0);
        final ambTintR = 1.0 + ((ambR * 1.35 + 0.18) - 1.0) * ambStr * 0.55;
        final ambTintG = 1.0 + ((ambG * 1.35 + 0.18) - 1.0) * ambStr * 0.55;
        final ambTintB = 1.0 + ((ambB * 1.35 + 0.18) - 1.0) * ambStr * 0.55;
        r *= ambTintR;
        g *= ambTintG;
        b *= ambTintB;

        final gBounce = groundFactor * ambStr * 0.35;
        r = r * (1.0 - gBounce) + (r * 0.65 + ambR * 0.45) * gBounce;
        g = g * (1.0 - gBounce) + (g * 0.65 + ambG * 0.45) * gBounce;
        b = b * (1.0 - gBounce) + (b * 0.65 + ambB * 0.45) * gBounce;

        // Real background-sampled Optical Light Wrap!
        final bgP = canvas.getPixel(cx, cy);
        final bgR = bgP.r / 255.0;
        final bgG = bgP.g / 255.0;
        final bgB = bgP.b / 255.0;

        if (wrapStr > 0.01 && edgeMask > 0.01) {
          final wrapAmt = edgeMask * wrapStr * 0.45;
          final wrapR = math.max(bgR * 1.15, ambR * 0.9);
          final wrapG = math.max(bgG * 1.15, ambG * 0.9);
          final wrapB = math.max(bgB * 1.15, ambB * 0.9);
          r = r + (math.max(r, wrapR) - r) * wrapAmt;
          g = g + (math.max(g, wrapG) - g) * wrapAmt;
          b = b + (math.max(b, wrapB) - b) * wrapAmt;
        }

        // Saturation & Contrast
        final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        r = luma + (r - luma) * saturation;
        g = luma + (g - luma) * saturation;
        b = luma + (b - luma) * saturation;

        r = (r - 0.5) * contrast + 0.5;
        g = (g - 0.5) * contrast + 0.5;
        b = (b - 0.5) * contrast + 0.5;

        // Atmospheric Black-Level Lift
        final blackFloorR = (0.02 + ambR * 0.27) * blackLift;
        final blackFloorG = (0.02 + ambG * 0.27) * blackLift;
        final blackFloorB = (0.02 + ambB * 0.27) * blackLift;
        r = r * (1.0 - blackLift * 0.75) + blackFloorR;
        g = g * (1.0 - blackLift * 0.75) + blackFloorG;
        b = b * (1.0 - blackLift * 0.75) + blackFloorB;

        // Deterministic Camera CMOS Grain
        if (grain > 0.001) {
          final n = _hashNoise(cx, cy) - 0.5;
          final midW = 1.0 - (luma - 0.5).abs() * 0.8;
          final delta = n * grain * 0.28 * midW;
          r += delta;
          g += delta;
          b += delta;
        }

        // Master blend between raw cutout and physically harmonized standee
        final finalR = (rawR + (r.clamp(0.0, 1.0) - rawR) * blend);
        final finalG = (rawG + (g.clamp(0.0, 1.0) - rawG) * blend);
        final finalB = (rawB + (b.clamp(0.0, 1.0) - rawB) * blend);

        // Alpha composite over background
        final outR = (finalR * a + bgR * (1.0 - a)) * 255.0;
        final outG = (finalG * a + bgG * (1.0 - a)) * 255.0;
        final outB = (finalB * a + bgB * (1.0 - a)) * 255.0;

        canvas.setPixelRgba(
          cx,
          cy,
          outR.round().clamp(0, 255),
          outG.round().clamp(0, 255),
          outB.round().clamp(0, 255),
          255,
        );
      }
    }
  }

  static double _hashNoise(int x, int y) {
    int n = (x * 374761393 + y * 668265263) ^ 0x5bf03635;
    n = (n ^ (n >> 13)) * 1274126177;
    return ((n ^ (n >> 16)) & 0x7fffffff) / 2147483647.0;
  }

  static img.Image _resizeLongest(img.Image src, int maxDim) {
    final longest = math.max(src.width, src.height);
    if (longest <= maxDim) return src.clone();
    if (src.width >= src.height) {
      return img.copyResize(src, width: maxDim, interpolation: img.Interpolation.linear);
    } else {
      return img.copyResize(src, height: maxDim, interpolation: img.Interpolation.linear);
    }
  }

  static Float32List _boxBlurFloat(Float32List src, int w, int h, int radius) {
    final horiz = Float32List(w * h);
    final out = Float32List(w * h);
    final kSize = radius * 2 + 1;

    for (int y = 0; y < h; y++) {
      double acc = 0;
      for (int dx = -radius; dx <= radius; dx++) {
        acc += src[y * w + dx.clamp(0, w - 1)];
      }
      for (int x = 0; x < w; x++) {
        horiz[y * w + x] = acc / kSize;
        acc += src[y * w + (x + radius + 1).clamp(0, w - 1)] -
            src[y * w + (x - radius).clamp(0, w - 1)];
      }
    }

    for (int x = 0; x < w; x++) {
      double acc = 0;
      for (int dy = -radius; dy <= radius; dy++) {
        acc += horiz[dy.clamp(0, h - 1) * w + x];
      }
      for (int y = 0; y < h; y++) {
        out[y * w + x] = acc / kSize;
        acc += horiz[(y + radius + 1).clamp(0, h - 1) * w + x] -
            horiz[(y - radius).clamp(0, h - 1) * w + x];
      }
    }
    return out;
  }
}
