import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/blend_recipe.dart';
import '../services/perspective_engine.dart';

/// Ultra-smooth 60fps standee renderer:
/// - Renders the GPU-harmonized standee once at a stable base texture size inside a
///   `RepaintBoundary`, so dragging, pinching, and rotating ONLY updates a 0.1ms GPU
///   `Transform` matrix (ZERO shader/saveLayer re-execution per gesture frame!).
class HarmonizedStandeeView extends StatefulWidget {
  final ui.Image standeeImage;
  final ui.FragmentProgram? shaderProgram;
  final Size viewportSize;
  final PlacementTransform placement;
  final PerspectiveState perspective;
  final LightingProfile lighting;
  final double timeSeed;

  const HarmonizedStandeeView({
    super.key,
    required this.standeeImage,
    required this.shaderProgram,
    required this.viewportSize,
    required this.placement,
    required this.perspective,
    required this.lighting,
    this.timeSeed = 1.0,
  });

  @override
  State<HarmonizedStandeeView> createState() => _HarmonizedStandeeViewState();
}

class _HarmonizedStandeeViewState extends State<HarmonizedStandeeView> {
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    _shader = widget.shaderProgram?.fragmentShader();
  }

  @override
  void didUpdateWidget(covariant HarmonizedStandeeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shaderProgram != widget.shaderProgram) {
      _shader?.dispose();
      _shader = widget.shaderProgram?.fragmentShader();
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    _shader = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final placement = widget.placement;
    final perspective = widget.perspective;
    final lighting = widget.lighting;
    final viewportSize = widget.viewportSize;
    final standeeImage = widget.standeeImage;

    final perspScale = placement.lockToPerspectiveScale
        ? perspective.scaleFactorAtY(placement.anchorY)
        : 1.0;

    // Keep base shader canvas size constant across scale/rotate/drag gestures so the
    // RepaintBoundary caches the GPU-shaded standee texture at 60fps with zero re-shading!
    final baseH = (viewportSize.height * 0.56).clamp(180.0, 560.0);
    final aspect = standeeImage.height > 0
        ? standeeImage.width / standeeImage.height
        : 0.66;
    final baseW = (baseH * aspect).clamp(90.0, 560.0);

    final totalScale = (perspScale * placement.userScale).clamp(0.22, 3.0);
    final drawH = baseH * totalScale;
    final drawW = baseW * totalScale;

    final anchorX = placement.anchorX * viewportSize.width;
    final anchorY = placement.anchorY * viewportSize.height;

    final left = anchorX - baseW * 0.5;
    final top = anchorY - baseH;

    final matrix = PerspectiveEngine.buildStandeeMatrix(
      placement: placement,
      perspective: perspective,
    )..multiply(Matrix4.diagonal3Values(totalScale, totalScale, 1.0));

    Widget standeeWidget = RepaintBoundary(
      child: SizedBox(
        width: baseW,
        height: baseH,
        child: CustomPaint(
          isComplex: true,
          willChange: false,
          painter: _HarmonizedStandeePainter(
            image: standeeImage,
            shader: _shader,
            lighting: lighting,
            timeSeed: widget.timeSeed,
          ),
        ),
      ),
    );

    if (lighting.dofBlur > 0.25 && lighting.blendStrength > 0.05) {
      final sigma =
          (lighting.dofBlur * lighting.blendStrength * 0.7).clamp(0.0, 4.5);
      if (sigma > 0.1) {
        standeeWidget = ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.decal,
          ),
          child: standeeWidget,
        );
      }
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (lighting.shadowOpacity > 0.01 && lighting.blendStrength > 0.01)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _LiveShadowPainter(
                    standeeImage: standeeImage,
                    anchor: Offset(anchorX, anchorY),
                    drawSize: Size(drawW, drawH),
                    flipX: placement.flipX,
                    lighting: lighting,
                    perspective: perspective,
                    viewportSize: viewportSize,
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          left: left,
          top: top,
          width: baseW,
          height: baseH,
          child: Transform(
            alignment: Alignment.bottomCenter,
            transform: matrix,
            child: standeeWidget,
          ),
        ),
      ],
    );
  }
}

class _LiveShadowPainter extends CustomPainter {
  final ui.Image standeeImage;
  final Offset anchor;
  final Size drawSize;
  final bool flipX;
  final LightingProfile lighting;
  final PerspectiveState perspective;
  final Size viewportSize;

  const _LiveShadowPainter({
    required this.standeeImage,
    required this.anchor,
    required this.drawSize,
    required this.flipX,
    required this.lighting,
    required this.perspective,
    required this.viewportSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final opacity =
        (lighting.shadowOpacity * lighting.blendStrength).clamp(0.0, 0.9);
    if (opacity <= 0.01) return;

    final amb = lighting.ambientColor;
    final shadowBaseColor = Color.fromARGB(
      255,
      (amb.r * 255 * 0.16).round().clamp(4, 38),
      (amb.g * 255 * 0.18).round().clamp(5, 42),
      (amb.b * 255 * 0.24).round().clamp(8, 58),
    );

    final anchorNormY = anchor.dy / math.max(1.0, viewportSize.height);
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
    final flipSign = flipX ? -1.0 : 1.0;

    canvas.save();
    canvas.translate(anchor.dx, anchor.dy);

    final shadowMatrix = Matrix4.identity()
      ..setEntry(0, 0, flipSign * wAxis.dx)
      ..setEntry(1, 0, flipSign * wAxis.dy)
      ..setEntry(0, 1, -hAxis.dx)
      ..setEntry(1, 1, -hAxis.dy);
    canvas.transform(shadowMatrix.storage);

    // Keep live preview blur sigma fast on mobile GPUs while full-res export uses full blur
    final blurSigma = (2.5 + lighting.shadowSoftness * 7.5).clamp(2.0, 10.0);
    final castPaint = Paint()
      ..filterQuality = FilterQuality.low
      ..colorFilter = ColorFilter.mode(
        shadowBaseColor.withValues(alpha: (opacity * 0.55).clamp(0.0, 0.65)),
        BlendMode.srcIn,
      )
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma);

    final srcRect = Rect.fromLTWH(
      0,
      0,
      standeeImage.width.toDouble(),
      standeeImage.height.toDouble(),
    );
    final dstRect = Rect.fromLTWH(
      -drawSize.width * 0.5,
      -drawSize.height,
      drawSize.width,
      drawSize.height,
    );
    canvas.drawImageRect(standeeImage, srcRect, dstRect, castPaint);
    canvas.restore();

    final aoW = (drawSize.width * 0.44).clamp(28.0, 180.0);
    final aoH = (aoW * flatness * 0.62).clamp(6.0, 34.0);
    final aoPaint = Paint()
      ..color =
          shadowBaseColor.withValues(alpha: (opacity * 0.72).clamp(0.0, 0.75))
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        (3.5 + lighting.shadowSoftness * 5.0).clamp(2.5, 9.0),
      );
    canvas.save();
    canvas.translate(anchor.dx, anchor.dy + 1);
    canvas.rotate(perspective.rollDeg * math.pi / 180.0);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: aoW, height: aoH),
      aoPaint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LiveShadowPainter oldDelegate) {
    return oldDelegate.standeeImage != standeeImage ||
        oldDelegate.anchor != anchor ||
        oldDelegate.drawSize != drawSize ||
        oldDelegate.flipX != flipX ||
        oldDelegate.lighting != lighting ||
        oldDelegate.perspective != perspective;
  }
}

class _HarmonizedStandeePainter extends CustomPainter {
  final ui.Image image;
  final ui.FragmentShader? shader;
  final LightingProfile lighting;
  final double timeSeed;

  const _HarmonizedStandeePainter({
    required this.image,
    required this.shader,
    required this.lighting,
    required this.timeSeed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final activeShader = shader;

    if (activeShader != null) {
      final wb = lighting.whiteBalanceRgb;
      final lightVec = lighting.lightDirectionVector;
      final amb = lighting.ambientColor;

      activeShader.setFloat(0, size.width);
      activeShader.setFloat(1, size.height);
      activeShader.setFloat(2, wb[0]);
      activeShader.setFloat(3, wb[1]);
      activeShader.setFloat(4, wb[2]);
      activeShader.setFloat(5, lighting.exposureEv);
      activeShader.setFloat(6, lighting.contrast);
      activeShader.setFloat(7, lighting.blackLift);
      activeShader.setFloat(8, lighting.saturation);
      activeShader.setFloat(9, lightVec.dx);
      activeShader.setFloat(10, lightVec.dy);
      activeShader.setFloat(11, lighting.directionalStrength);
      activeShader.setFloat(12, amb.r);
      activeShader.setFloat(13, amb.g);
      activeShader.setFloat(14, amb.b);
      activeShader.setFloat(15, lighting.ambientStrength);
      activeShader.setFloat(16, lighting.lightWrap);
      activeShader.setFloat(17, lighting.filmGrain);
      activeShader.setFloat(18, lighting.blendStrength);
      activeShader.setFloat(19, timeSeed);
      activeShader.setImageSampler(0, image);

      canvas.saveLayer(rect, Paint());
      canvas.drawRect(rect, Paint()..shader = activeShader);
      canvas.restore();
      return;
    }

    final wb = lighting.whiteBalanceRgb;
    final ev =
        math.pow(2.0, lighting.exposureEv * lighting.blendStrength).toDouble();
    final rScale = 1.0 + (wb[0] * ev - 1.0) * lighting.blendStrength;
    final gScale = 1.0 + (wb[1] * ev - 1.0) * lighting.blendStrength;
    final bScale = 1.0 + (wb[2] * ev - 1.0) * lighting.blendStrength;
    final lift = lighting.blackLift * 255.0 * 0.45 * lighting.blendStrength;

    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..colorFilter = ColorFilter.matrix([
        rScale, 0, 0, 0, lift,
        0, gScale, 0, 0, lift,
        0, 0, bScale, 0, lift,
        0, 0, 0, 1, 0,
      ]);

    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _HarmonizedStandeePainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.shader != shader ||
        oldDelegate.lighting != lighting ||
        oldDelegate.timeSeed != timeSeed;
  }
}
