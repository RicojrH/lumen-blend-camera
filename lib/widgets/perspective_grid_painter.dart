import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/blend_recipe.dart';
import '../services/perspective_engine.dart';
import '../theme/app_theme.dart';

/// Multi-mode 3D perspective floor/surface guide painter:
/// - `onePointFloor`: 1-point perspective street/corridor floor grid
/// - `twoPointCorner`: 2-point architectural street-corner / indoor room floor grid
/// - `fourCornerPlane`: Free 4-corner quad mesh that snaps onto tabletops, tiles, or stairs
/// - `simpleHorizon`: Clean minimalist horizon & rule-of-thirds reference lines
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
      switch (perspective.mode) {
        case PerspectiveMode.onePointFloor:
          _paintRotated(canvas, vanishPxX, horizonPxY, () {
            _drawOnePointGrid(canvas, w, h, vanishPxX, horizonPxY);
            _drawHorizonLine(canvas, w, vanishPxX, horizonPxY);
          });
          break;
        case PerspectiveMode.twoPointCorner:
          _paintRotated(canvas, vanishPxX, horizonPxY, () {
            _drawTwoPointGrid(canvas, w, h, vanishPxX, horizonPxY);
            _drawHorizonLine(canvas, w, vanishPxX, horizonPxY);
          });
          break;
        case PerspectiveMode.fourCornerPlane:
          _drawFourCornerQuad(canvas, size);
          break;
        case PerspectiveMode.simpleHorizon:
          _paintRotated(canvas, vanishPxX, horizonPxY, () {
            _drawRuleOfThirds(canvas, w, h);
            _drawHorizonLine(canvas, w, vanishPxX, horizonPxY);
          });
          break;
      }
    }

    if (perspective.showGrid || highlightPlacement) {
      _drawPlacementAnchor(canvas, size, anchorX, anchorY);
    }
  }

  void _paintRotated(Canvas canvas, double vx, double hy, VoidCallback drawFn) {
    canvas.save();
    canvas.translate(vx, hy);
    canvas.rotate(perspective.rollDeg * math.pi / 180.0);
    canvas.translate(-vx, -hy);
    drawFn();
    canvas.restore();
  }

  void _drawOnePointGrid(
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

  /// Two-point architectural perspective (left VP1 & right VP2 on the horizon line),
  /// ideal for room corners, street intersections, and angled cafe floors.
  void _drawTwoPointGrid(
    Canvas canvas,
    double w,
    double h,
    double vx,
    double hy,
  ) {
    final spreadPx = w * perspective.twoPointSpread.clamp(0.22, 0.75);
    final vpLeft = Offset(vx - spreadPx, hy);
    final vpRight = Offset(vx + spreadPx, hy);
    final floorHeight = math.max(80.0, h - hy + w * 0.3);

    final paintL = Paint()
      ..color = AppTheme.accentCyan.withValues(alpha: 0.24)
      ..strokeWidth = 0.9;
    final paintR = Paint()
      ..color = AppTheme.accentMint.withValues(alpha: 0.22)
      ..strokeWidth = 0.9;

    const lineCount = 10;
    for (int i = 1; i <= lineCount; i++) {
      final frac = i / lineCount;
      final yTarget = hy + math.pow(frac, 1.65) * floorHeight;
      // Rays fanning downward from Left VP toward right floor edge
      canvas.drawLine(vpLeft, Offset(w * 1.35, yTarget), paintL);
      // Rays fanning downward from Right VP toward left floor edge
      canvas.drawLine(vpRight, Offset(-w * 0.35, yTarget), paintR);
    }

    // Subtle vertical corner plumb line at center vanishingX
    canvas.drawLine(
      Offset(vx, hy - h * 0.25),
      Offset(vx, h),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..strokeWidth = 0.9,
    );
  }

  /// Free 4-corner bilinear perspective quad for tabletops, floor tiles, or stairs.
  void _drawFourCornerQuad(Canvas canvas, Size size) {
    if (perspective.quadCorners.length != 4) return;
    final pts = perspective.quadCorners
        .map((c) => Offset(c.dx * size.width, c.dy * size.height))
        .toList();
    final tl = pts[0];
    final tr = pts[1];
    final br = pts[2];
    final bl = pts[3];

    final path = Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(bl.dx, bl.dy)
      ..close();

    canvas.drawPath(
      path,
      Paint()..color = AppTheme.accentCyan.withValues(alpha: 0.10),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = (highlightHorizon ? AppTheme.accentAmber : AppTheme.accentCyan)
            .withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    // Subdivide quad into 6x6 perspective surface grid
    final gridPaint = Paint()
      ..color = AppTheme.accentCyan.withValues(alpha: 0.30)
      ..strokeWidth = 0.85;
    const divs = 6;
    for (int i = 1; i < divs; i++) {
      final t = i / divs;
      final topPt = Offset.lerp(tl, tr, t)!;
      final botPt = Offset.lerp(bl, br, t)!;
      canvas.drawLine(topPt, botPt, gridPaint);

      final leftPt = Offset.lerp(tl, bl, t)!;
      final rightPt = Offset.lerp(tr, br, t)!;
      canvas.drawLine(leftPt, rightPt, gridPaint);
    }
  }

  void _drawRuleOfThirds(Canvas canvas, double w, double h) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(w / 3, 0), Offset(w / 3, h), p);
    canvas.drawLine(Offset(w * 2 / 3, 0), Offset(w * 2 / 3, h), p);
  }

  void _drawHorizonLine(Canvas canvas, double w, double vx, double hy) {
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
