import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/blend_recipe.dart';
import '../services/perspective_engine.dart';

/// Real-time 60fps standee renderer inside the viewfinder & photo editor.
/// Retains a persistent `ui.FragmentShader` instance in State so CanvasKit/WebGL and Impeller
/// never garbage-collect the active shader across parent overlays or route transitions.
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

    final baseHeight = viewportSize.height * 0.56;
    final drawH = (baseHeight * perspScale * placement.userScale)
        .clamp(48.0, viewportSize.height * 1.9);
    final aspect = standeeImage.height > 0
        ? standeeImage.width / standeeImage.height
        : 0.66;
    final drawW = (drawH * aspect).clamp(32.0, viewportSize.width * 1.9);

    final anchorX = placement.anchorX * viewportSize.width;
    final anchorY = placement.anchorY * viewportSize.height;

    final left = anchorX - drawW * 0.5;
    final top = anchorY - drawH;

    final matrix = PerspectiveEngine.buildStandeeMatrix(
      placement: placement,
      perspective: perspective,
    );

    // Note: saveLayer inside _HarmonizedStandeePainter establishes a guaranteed local (0,0)
    // coordinate space on every frame without relying on delayed RepaintBoundary promotion!
    Widget standeeWidget = SizedBox(
      width: drawW,
      height: drawH,
      child: CustomPaint(
        painter: _HarmonizedStandeePainter(
          image: standeeImage,
          shader: _shader,
          lighting: lighting,
          timeSeed: widget.timeSeed,
        ),
      ),
    );

    if (lighting.dofBlur > 0.25 && lighting.blendStrength > 0.05) {
      final sigma =
          (lighting.dofBlur * lighting.blendStrength * 0.7).clamp(0.0, 5.0);
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
        Positioned(
          left: left,
          top: top,
          width: drawW,
          height: drawH,
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

    // Column-major 2D ground affine matrix mapping dstRect (-W/2..W/2, -H..0) onto 360° floor:
    // screenOffset = imgX * (flipSign * wAxis) + imgY * (-hAxis)
    final shadowMatrix = Matrix4.identity()
      ..setEntry(0, 0, flipSign * wAxis.dx)
      ..setEntry(1, 0, flipSign * wAxis.dy)
      ..setEntry(0, 1, -hAxis.dx)
      ..setEntry(1, 1, -hAxis.dy);
    canvas.transform(shadowMatrix.storage);

    final blurSigma = (3.5 + lighting.shadowSoftness * 13.0).clamp(2.0, 18.0);
    final castPaint = Paint()
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

    // Contact AO under feet rotated along horizon rollDeg
    final aoW = (drawSize.width * 0.44).clamp(28.0, 180.0);
    final aoH = (aoW * flatness * 0.62).clamp(6.0, 34.0);
    final aoPaint = Paint()
      ..color =
          shadowBaseColor.withValues(alpha: (opacity * 0.72).clamp(0.0, 0.75))
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        (4.0 + lighting.shadowSoftness * 6.5).clamp(3.0, 12.0),
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

      // Isolate into local (0,0,w,h) layer so FlutterFragCoord() ALWAYS starts at (0,0) on Frame 1!
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
