import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/blend_recipe.dart';
import '../services/perspective_engine.dart';
import '../theme/app_theme.dart';

/// Foreground interactive Horizon Gizmo rendered ABOVE the standee so handles are
/// never occluded by the character or right-side toolbar:
/// - Drag center `VP` handle: move horizon height (`horizonY`) & vanishing point (`vanishingX`)
/// - Drag Left or Right `⟳` wing handle: rotate horizon tilt (`rollDeg`, -38°..+38°)
/// - Double-tap: reset tilt to 0.0° level
class InteractiveHorizonOverlay extends StatefulWidget {
  final PerspectiveState perspective;
  final ValueChanged<PerspectiveState> onChanged;
  final ValueChanged<bool>? onActiveChanged;

  const InteractiveHorizonOverlay({
    super.key,
    required this.perspective,
    required this.onChanged,
    this.onActiveChanged,
  });

  @override
  State<InteractiveHorizonOverlay> createState() =>
      _InteractiveHorizonOverlayState();
}

class _InteractiveHorizonOverlayState extends State<InteractiveHorizonOverlay> {
  bool _isDragging = false;
  bool _isRotatingMode = false;
  double _startRollDeg = 0.0;
  double _startPointerAngleRad = 0.0;
  double _startHorizonY = 0.44;
  double _startVanishX = 0.50;
  Offset _startViewportPos = Offset.zero;

  Offset _globalToViewport(Offset globalPos) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return globalPos;
    return box.globalToLocal(globalPos);
  }

  void _onPanStart(DragStartDetails details, Size viewportSize) {
    final pos = _globalToViewport(details.globalPosition);
    final vp = Offset(
      widget.perspective.vanishingX.clamp(0.10, 0.90) * viewportSize.width,
      widget.perspective.horizonY.clamp(0.12, 0.82) * viewportSize.height,
    );

    final deltaFromVp = pos - vp;
    final rollRad = widget.perspective.rollDeg * math.pi / 180.0;
    final alongHorizon =
        deltaFromVp.dx * math.cos(rollRad) + deltaFromVp.dy * math.sin(rollRad);

    final rotateThreshold = (viewportSize.width * 0.16).clamp(52.0, 110.0);
    _isRotatingMode = alongHorizon.abs() > rotateThreshold;

    _startViewportPos = pos;
    _startHorizonY = widget.perspective.horizonY;
    _startVanishX = widget.perspective.vanishingX;
    _startRollDeg = widget.perspective.rollDeg;
    _startPointerAngleRad = math.atan2(deltaFromVp.dy, deltaFromVp.dx);

    setState(() => _isDragging = true);
    widget.onActiveChanged?.call(true);
  }

  void _onPanUpdate(DragUpdateDetails details, Size viewportSize) {
    final pos = _globalToViewport(details.globalPosition);

    if (_isRotatingMode) {
      final vp = Offset(
        widget.perspective.vanishingX.clamp(0.10, 0.90) * viewportSize.width,
        widget.perspective.horizonY.clamp(0.12, 0.82) * viewportSize.height,
      );
      final delta = pos - vp;
      if (delta.distance < 16.0) return;

      final currentAngle = math.atan2(delta.dy, delta.dx);
      double angleDiffRad = currentAngle - _startPointerAngleRad;
      while (angleDiffRad > math.pi) {
        angleDiffRad -= 2.0 * math.pi;
      }
      while (angleDiffRad < -math.pi) {
        angleDiffRad += 2.0 * math.pi;
      }

      final nextRoll =
          (_startRollDeg + angleDiffRad * 180.0 / math.pi).clamp(-38.0, 38.0);
      widget.onChanged(
        widget.perspective.copyWith(
          rollDeg: nextRoll,
          sensorSyncEnabled: false,
        ),
      );
    } else {
      final dragDelta = pos - _startViewportPos;
      final nextVx =
          (_startVanishX + dragDelta.dx / viewportSize.width).clamp(0.14, 0.82);
      final nextHy =
          (_startHorizonY + dragDelta.dy / viewportSize.height).clamp(0.14, 0.80);
      widget.onChanged(
        widget.perspective.copyWith(
          vanishingX: nextVx,
          horizonY: nextHy,
          pitchDeg: PerspectiveEngine.horizonYToPitchDeg(nextHy),
          sensorSyncEnabled: false,
        ),
      );
    }
  }

  void _onPanEnd() {
    if (mounted) setState(() => _isDragging = false);
    widget.onActiveChanged?.call(false);
  }

  void _onDoubleTap() {
    widget.onChanged(
      widget.perspective.copyWith(
        rollDeg: 0.0,
        vanishingX: 0.50,
        sensorSyncEnabled: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.perspective.showGrid) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final vx = widget.perspective.vanishingX.clamp(0.10, 0.90) * size.width;
        final hy = widget.perspective.horizonY.clamp(0.12, 0.82) * size.height;
        final stripWidth = size.width * 1.5;
        const stripHeight = 46.0;
        final rollRad = widget.perspective.rollDeg * math.pi / 180.0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Visual foreground handles painted cleanly above standee & left of right-rail
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _HorizonHandlesPainter(
                    perspective: widget.perspective,
                    active: _isDragging,
                  ),
                ),
              ),
            ),

            // Hit-test strip strictly along the rotated horizon line
            Positioned(
              left: vx - stripWidth * 0.5,
              top: hy - stripHeight * 0.5,
              width: stripWidth,
              height: stripHeight,
              child: Transform.rotate(
                angle: rollRad,
                alignment: Alignment.center,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onDoubleTap: _onDoubleTap,
                    onPanStart: (d) => _onPanStart(d, size),
                    onPanUpdate: (d) => _onPanUpdate(d, size),
                    onPanEnd: (_) => _onPanEnd(),
                    onPanCancel: _onPanEnd,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HorizonHandlesPainter extends CustomPainter {
  final PerspectiveState perspective;
  final bool active;

  const _HorizonHandlesPainter({
    required this.perspective,
    required this.active,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final vx = perspective.vanishingX.clamp(0.10, 0.90) * w;
    final hy = perspective.horizonY.clamp(0.12, 0.82) * h;

    final isLevel = perspective.rollDeg.abs() < 1.2;
    final vpColor = active
        ? AppTheme.accentAmber
        : isLevel
            ? AppTheme.accentMint
            : AppTheme.accentCyan;

    canvas.save();
    canvas.translate(vx, hy);
    canvas.rotate(perspective.rollDeg * math.pi / 180.0);
    canvas.translate(-vx, -hy);

    // Subtle connecting rail between left and right rotation handles
    final leftDist = (w * 0.30).clamp(78.0, 140.0);
    // Keep right wing clear of right-side quick toolbar (72px margin on right)
    final rightDist = math.min((w * 0.23).clamp(64.0, 112.0), math.max(58.0, w - 78.0 - vx));

    canvas.drawLine(
      Offset(vx - leftDist, hy),
      Offset(vx + rightDist, hy),
      Paint()
        ..color = vpColor.withValues(alpha: active ? 0.65 : 0.32)
        ..strokeWidth = 1.4,
    );

    // Center VP drag handle (moves horizon height & vanishing X)
    final vpCenter = Offset(vx, hy);
    canvas.drawCircle(vpCenter, 13, Paint()..color = const Color(0xDC0A0C10));
    canvas.drawCircle(
      vpCenter,
      11.5,
      Paint()
        ..color = vpColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
    // Up/down chevron arrows inside VP handle
    final iconPaint = Paint()
      ..color = vpColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(vx - 3.5, hy - 2.5), Offset(vx, hy - 6), iconPaint);
    canvas.drawLine(Offset(vx + 3.5, hy - 2.5), Offset(vx, hy - 6), iconPaint);
    canvas.drawLine(Offset(vx - 3.5, hy + 2.5), Offset(vx, hy + 6), iconPaint);
    canvas.drawLine(Offset(vx + 3.5, hy + 2.5), Offset(vx, hy + 6), iconPaint);

    // Left & Right Rotation Wing Handles (`⟳`)
    for (final gx in [vx - leftDist, vx + rightDist]) {
      if (gx < 18 || gx > w - 66) continue;
      final center = Offset(gx, hy);
      canvas.drawCircle(center, 12, Paint()..color = const Color(0xE00A0C10));
      canvas.drawCircle(
        center,
        10.5,
        Paint()
          ..color = AppTheme.accentAmber
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.7,
      );
      final arcRect = Rect.fromCircle(center: center, radius: 5.2);
      final arcPaint = Paint()
        ..color = AppTheme.accentAmber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(arcRect, -math.pi * 0.65, math.pi * 0.85, false, arcPaint);
      canvas.drawArc(arcRect, math.pi * 0.35, math.pi * 0.85, false, arcPaint);
    }

    // Compact pill badge right above center VP handle
    final rollSign = perspective.rollDeg >= 0 ? '+' : '';
    final tp = TextPainter(
      text: TextSpan(
        text: '地平线 ↕移动 · ⟳旋转 $rollSign${perspective.rollDeg.toStringAsFixed(1)}°',
        style: TextStyle(
          color: vpColor,
          fontSize: 9.8,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final pillRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(vx, hy - 24),
        width: tp.width + 12,
        height: tp.height + 5,
      ),
      const Radius.circular(8),
    );
    canvas.drawRRect(pillRect, Paint()..color = const Color(0xCC0A0C10));
    tp.paint(canvas, Offset(vx - tp.width * 0.5, hy - 24 - tp.height * 0.5));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HorizonHandlesPainter oldDelegate) =>
      oldDelegate.perspective != perspective || oldDelegate.active != active;
}
