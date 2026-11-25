import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/blend_recipe.dart';
import '../services/perspective_engine.dart';
import '../theme/app_theme.dart';

/// Draws the real-time AR-style 3D perspective floor grid, rotated horizon line around
/// `(vanishingX, horizonY)`, interactive grip markers, and 360° shadow ray anchor ring.
class PerspectiveGridPainter extends CustomPainter {
  final PerspectiveState perspective;
  final PlacementTransform placement;
  final LightingProfile lighting;
  final bool highlightPlacement;
  final bool highlightHorizon;

  const PerspectiveGridPainter({
    required this.perspective,
    required this.placement,
    required this.lighting,
    this.highlightPlacement = false,
    this.highlightHorizon = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final horizonPxY = perspective.horizonY.clamp(0.12, 0.82) * h;
    final vanishPxX = perspective.vanishingX.clamp(0.10, 0.90) * w;
    final anchorX = placement.anchorX * w;
    final anchorY = placement.anchorY * h;

    if (perspective.showGrid) {
      canvas.save();
      // Pivot horizon & entire ground perspective grid around the vanishing point!
      canvas.translate(vanishPxX, horizonPxY);
      canvas.rotate(perspective.rollDeg * math.pi / 180.0);
      canvas.translate(-vanishPxX, -horizonPxY);

      _drawGroundPerspectiveGrid(canvas, w, h, vanishPxX, horizonPxY);
      _drawHorizonAndGrips(canvas, w, vanishPxX, horizonPxY);
      canvas.restore();
    }

    if (perspective.showGrid || highlightPlacement) {
      _drawPlacementAnchor(canvas, size, anchorX, anchorY);
    }
  }

  void _drawGroundPerspectiveGrid(
    Canvas canvas,
    double w,
    double h,
    double vx,
    double hy,
  ) {
    final diagPad = w * 0.55;
    final floorHeight = math.max(60.0, (h - hy) + diagPad * 0.5);

    final floorShader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        AppTheme.accentCyan.withValues(alpha: 0.0),
        AppTheme.accentCyan.withValues(alpha: 0.05),
        AppTheme.accentCyan.withValues(alpha: 0.11),
      ],
    ).createShader(Rect.fromLTRB(-diagPad, hy, w + diagPad, hy + floorHeight));

    canvas.drawRect(
      Rect.fromLTRB(-diagPad, hy, w + diagPad, hy + floorHeight),
      Paint()..shader = floorShader,
    );

    final gridPaint = Paint()
      ..strokeWidth = 0.85
      ..style = PaintingStyle.stroke;

    const rayCount = 9;
    final spread = w * (1.35 + perspective.depthStrength * 0.65);
    for (int i = -rayCount; i <= rayCount; i++) {
      final t = i / rayCount;
      final bottomX = vx + t * spread;
      final centerWeight = (1.0 - t.abs() * 0.72).clamp(0.15, 1.0);
      gridPaint.color = AppTheme.accentCyan.withValues(alpha: 0.22 * centerWeight);
      canvas.drawLine(Offset(vx, hy), Offset(bottomX, hy + floorHeight), gridPaint);
    }

    const rungCount = 8;
    for (int i = 1; i <= rungCount; i++) {
      final frac = i / rungCount;
      final yNorm = math.pow(frac, 2.05).toDouble();
      final y = hy + yNorm * floorHeight;
      gridPaint.color = AppTheme.accentCyan.withValues(alpha: 0.10 + frac * 0.22);
      canvas.drawLine(Offset(-diagPad, y), Offset(w + diagPad, y), gridPaint);
    }
  }

  void _drawHorizonAndGrips(Canvas canvas, double w, double vx, double hy) {
    final isLevel = perspective.rollDeg.abs() < 1.2;
    final baseColor = highlightHorizon
        ? AppTheme.accentAmber
        : isLevel
            ? AppTheme.accentMint
            : AppTheme.accentCyan;
    final lineColor = baseColor.withValues(alpha: highlightHorizon ? 0.95 : 0.78);

    final dashPaint = Paint()
      ..color = lineColor
      ..strokeWidth = highlightHorizon ? 1.8 : 1.25;

    // Dashed horizon reference line on the floor plane (interactive handles are rendered in foreground by InteractiveHorizonOverlay)
    const dashW = 9.0;
    const gapW = 5.0;
    double x = -w * 0.35;
    while (x < w * 1.35) {
      if ((x - vx).abs() > 18.0) {
        canvas.drawLine(Offset(x, hy), Offset(x + dashW, hy), dashPaint);
      }
      x += dashW + gapW;
    }
  }

  void _drawPlacementAnchor(
    Canvas canvas,
    Size size,
    double ax,
    double ay,
  ) {
    final flatness = PerspectiveEngine.contactEllipseFlatness(
      placement.anchorY,
      perspective.horizonY,
    );
    final perspScale = perspective.scaleFactorAtY(placement.anchorY);
    final rx = (44.0 * perspScale * placement.userScale).clamp(24.0, 96.0);
    final ry = (rx * flatness).clamp(6.0, 32.0);

    final ringColor = highlightPlacement
        ? AppTheme.accentAmber
        : AppTheme.accentCyan.withValues(alpha: 0.72);

    canvas.save();
    canvas.translate(ax, ay);
    canvas.rotate(perspective.rollDeg * math.pi / 180.0);

    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = highlightPlacement ? 1.8 : 1.2,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 10, height: 10 * flatness + 2),
      Paint()..color = ringColor.withValues(alpha: 0.85),
    );
    canvas.restore();

    // True 360° directional shadow preview ray matching computeShadowBasis
    final basis = PerspectiveEngine.computeShadowBasis(
      lighting: lighting,
      perspective: perspective,
      anchorYNorm: placement.anchorY,
    );
    final shadowTip = Offset(
      ax + basis.heightAxis.dx * rx * 1.4,
      ay + basis.heightAxis.dy * rx * 1.4,
    );
    canvas.drawLine(
      Offset(ax, ay),
      shadowTip,
      Paint()
        ..color = AppTheme.accentAmber.withValues(alpha: 0.65)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      shadowTip,
      2.8,
      Paint()..color = AppTheme.accentAmber.withValues(alpha: 0.85),
    );

    final distMeters = PerspectiveEngine.estimateDistanceMeters(
      placement.anchorY,
      perspective.horizonY,
    );
    final label = TextPainter(
      text: TextSpan(
        text: '站位 ≈ ${distMeters.toStringAsFixed(1)}m',
        style: TextStyle(
          color: ringColor,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    label.paint(
      canvas,
      Offset(
        (ax - label.width * 0.5).clamp(8.0, size.width - label.width - 8.0),
        (ay + ry + 4).clamp(8.0, size.height - 20.0),
      ),
    );
  }

  @override
  bool shouldRepaint(covariant PerspectiveGridPainter oldDelegate) {
    return oldDelegate.perspective != perspective ||
        oldDelegate.placement != placement ||
        oldDelegate.lighting != lighting ||
        oldDelegate.highlightPlacement != highlightPlacement ||
        oldDelegate.highlightHorizon != highlightHorizon;
  }
}
