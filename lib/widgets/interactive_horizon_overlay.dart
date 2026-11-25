import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/blend_recipe.dart';
import '../services/perspective_engine.dart';
import '../theme/app_theme.dart';

/// Direct on-canvas interactive perspective gizmo:
/// - In `onePointFloor` / `twoPointCorner` / `simpleHorizon`:
///   - Drag center `↕` VP handle to adjust horizon height & vanishing X
///   - Drag Left or Right orange `⟳` wing handles to rotate horizon tilt (`rollDeg`)
///   - One-tap 「恢复自动」 pill appears whenever user has manually adjusted the horizon!
/// - In `fourCornerPlane`:
///   - Renders 4 large tactile corner handles directly on the canvas so users can snap the
///     perspective plane onto any tabletop, tile floor, stair, or slanted wall!
class InteractiveHorizonOverlay extends StatefulWidget {
  final PerspectiveState perspective;
  final ValueChanged<PerspectiveState> onChanged;
  final ValueChanged<bool>? onActiveChanged;
  final VoidCallback? onRestoreAutoHorizon;

  const InteractiveHorizonOverlay({
    super.key,
    required this.perspective,
    required this.onChanged,
    this.onActiveChanged,
    this.onRestoreAutoHorizon,
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
    if (widget.onRestoreAutoHorizon != null) {
      widget.onRestoreAutoHorizon!();
    } else {
      widget.onChanged(
        widget.perspective.copyWith(
          rollDeg: 0.0,
          vanishingX: 0.50,
          sensorSyncEnabled: true,
        ),
      );
    }
  }

  void _updateQuadCorner(int idx, Offset globalPos, Size size) {
    final local = _globalToViewport(globalPos);
    final nx = (local.dx / size.width).clamp(0.03, 0.97);
    final ny = (local.dy / size.height).clamp(0.12, 0.96);
    final next = List<Offset>.from(widget.perspective.quadCorners);
    next[idx] = Offset(nx, ny);

    // Derive horizonY & rollDeg smoothly from the quad's far edge so shadows & tilt stay aligned
    final farY = ((next[0].dy + next[1].dy) * 0.5 - 0.14).clamp(0.12, 0.78);
    final bottomAngleRad = math.atan2(
      (next[2].dy - next[3].dy) * size.height,
      (next[2].dx - next[3].dx) * size.width,
    );
    final rollDeg = (bottomAngleRad * 180.0 / math.pi).clamp(-35.0, 35.0);

    widget.onChanged(
      widget.perspective.copyWith(
        quadCorners: next,
        horizonY: farY,
        pitchDeg: PerspectiveEngine.horizonYToPitchDeg(farY),
        rollDeg: rollDeg,
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

        if (widget.perspective.mode == PerspectiveMode.fourCornerPlane) {
          return _buildQuadCornerHandles(size);
        }

        final vx = widget.perspective.vanishingX.clamp(0.10, 0.90) * size.width;
        final hy = widget.perspective.horizonY.clamp(0.12, 0.82) * size.height;
        final stripWidth = size.width * 1.5;
        const stripHeight = 48.0;
        final rollRad = widget.perspective.rollDeg * math.pi / 180.0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
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

            // One-tap "恢复自动地平线" pill whenever user manually overrode horizon!
            if (!widget.perspective.sensorSyncEnabled)
              Positioned(
                left: (vx - 60).clamp(12.0, size.width - 134.0),
                top: (hy - 56).clamp(62.0, size.height - 160.0),
                child: GestureDetector(
                  onTap: _onDoubleTap,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xE60D121C),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppTheme.accentMint.withValues(alpha: 0.8),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.my_location_rounded,
                          size: 13,
                          color: AppTheme.accentMint,
                        ),
                        SizedBox(width: 4),
                        Text(
                          '恢复自动地平线',
                          style: TextStyle(
                            color: AppTheme.accentMint,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildQuadCornerHandles(Size size) {
    final corners = widget.perspective.quadCorners;
    const labels = ['远左', '远右', '近右', '近左'];

    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (int i = 0; i < 4; i++)
          Positioned(
            left: corners[i].dx * size.width - 22,
            top: corners[i].dy * size.height - 22,
            width: 44,
            height: 44,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => widget.onActiveChanged?.call(true),
              onPanUpdate: (d) => _updateQuadCorner(i, d.globalPosition, size),
              onPanEnd: (_) => widget.onActiveChanged?.call(false),
              child: Center(
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: const Color(0xE00A0C10),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.accentAmber, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    labels[i],
                    style: const TextStyle(
                      color: AppTheme.accentAmber,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
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

    final leftDist = (w * 0.30).clamp(78.0, 140.0);
    final rightDist = math.min(
      (w * 0.23).clamp(64.0, 112.0),
      math.max(58.0, w - 78.0 - vx),
    );

    canvas.drawLine(
      Offset(vx - leftDist, hy),
      Offset(vx + rightDist, hy),
      Paint()
        ..color = vpColor.withValues(alpha: active ? 0.65 : 0.32)
        ..strokeWidth = 1.4,
    );

    // Center VP drag handle
    final vpCenter = Offset(vx, hy);
    canvas.drawCircle(vpCenter, 14, Paint()..color = const Color(0xDC0A0C10));
    canvas.drawCircle(
      vpCenter,
      12.5,
      Paint()
        ..color = vpColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
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
      canvas.drawCircle(center, 13, Paint()..color = const Color(0xE00A0C10));
      canvas.drawCircle(
        center,
        11.5,
        Paint()
          ..color = AppTheme.accentAmber
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.7,
      );
      final arcRect = Rect.fromCircle(center: center, radius: 5.5);
      final arcPaint = Paint()
        ..color = AppTheme.accentAmber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(arcRect, -math.pi * 0.65, math.pi * 0.85, false, arcPaint);
      canvas.drawArc(arcRect, math.pi * 0.35, math.pi * 0.85, false, arcPaint);
    }

    final rollSign = perspective.rollDeg >= 0 ? '+' : '';
    final modeTag = perspective.sensorSyncEnabled ? '自动' : '手动';
    final tp = TextPainter(
      text: TextSpan(
        text: '拖动调高低 · 两侧转倾斜 ($modeTag $rollSign${perspective.rollDeg.toStringAsFixed(1)}°)',
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
