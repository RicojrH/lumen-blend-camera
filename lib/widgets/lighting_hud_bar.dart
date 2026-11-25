import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/blend_recipe.dart';
import '../theme/app_theme.dart';

/// Compact viewfinder telemetry HUD displaying live detected Kelvin, EV, light direction,
/// and interactive Light Azimuth Compass dial for instant manual override.
class LightingHudBar extends StatelessWidget {
  final LightingProfile lighting;
  final PerspectiveState perspective;
  final VoidCallback onTapTelemetry;
  final VoidCallback onToggleAutoLight;

  const LightingHudBar({
    super.key,
    required this.lighting,
    required this.perspective,
    required this.onTapTelemetry,
    required this.onToggleAutoLight,
  });

  @override
  Widget build(BuildContext context) {
    final evSign = lighting.exposureEv >= 0 ? '+' : '';
    return GestureDetector(
      onTap: onTapTelemetry,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xCC0D1119),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: lighting.autoMatchEnabled
                ? AppTheme.accentAmber.withValues(alpha: 0.45)
                : AppTheme.borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ambient color probe swatch
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: lighting.ambientColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white54, width: 1),
              ),
            ),
            const SizedBox(width: 7),
            Text(
              '${lighting.kelvin.round()}K',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$evSign${lighting.exposureEv.toStringAsFixed(1)}EV',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            // Mini light direction arrow
            Transform.rotate(
              angle: lighting.lightAzimuthDeg * math.pi / 180.0,
              child: const Icon(
                Icons.arrow_forward_rounded,
                size: 13,
                color: AppTheme.accentAmber,
              ),
            ),
            const SizedBox(width: 3),
            Text(
              '${lighting.lightAzimuthDeg.round()}°',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onToggleAutoLight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: lighting.autoMatchEnabled
                      ? AppTheme.accentMint.withValues(alpha: 0.18)
                      : AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  lighting.autoMatchEnabled ? 'AUTO' : 'LOCK',
                  style: TextStyle(
                    color: lighting.autoMatchEnabled
                        ? AppTheme.accentMint
                        : AppTheme.textMuted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Spacious, ergonomic 360° circular Light Direction Compass with large thumb handle
/// so users can smoothly steer directional key/rim lighting and cast shadow angle without misclicks.
class LightCompassDial extends StatelessWidget {
  final double azimuthDeg;
  final double size;
  final ValueChanged<double> onChanged;

  const LightCompassDial({
    super.key,
    required this.azimuthDeg,
    required this.onChanged,
    this.size = 112,
  });

  void _updateFromLocal(Offset local) {
    final center = Offset(size * 0.5, size * 0.5);
    final delta = local - center;
    if (delta.distance < 6) return;
    final deg =
        (math.atan2(delta.dy, delta.dx) * 180.0 / math.pi + 360.0) % 360.0;
    onChanged(deg);
  }

  @override
  Widget build(BuildContext context) {
    final rad = azimuthDeg * math.pi / 180.0;
    final radius = size * 0.35;
    final sunX = size * 0.5 + math.cos(rad) * radius;
    final sunY = size * 0.5 + math.sin(rad) * radius;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) => _updateFromLocal(d.localPosition),
      onPanUpdate: (d) => _updateFromLocal(d.localPosition),
      onTapDown: (d) => _updateFromLocal(d.localPosition),
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _CompassPainter(
            sunPos: Offset(sunX, sunY),
            azimuthDeg: azimuthDeg,
          ),
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  final Offset sunPos;
  final double azimuthDeg;

  const _CompassPainter({
    required this.sunPos,
    required this.azimuthDeg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.5);
    final outerR = size.width * 0.47;
    final trackR = size.width * 0.35;

    // Dial base & subtle border
    canvas.drawCircle(center, outerR, Paint()..color = const Color(0xE00D1119));
    canvas.drawCircle(
      center,
      outerR,
      Paint()
        ..color = AppTheme.borderSubtle
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Track ring
    canvas.drawCircle(
      center,
      trackR,
      Paint()
        ..color = AppTheme.borderSubtle.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // Cardinal direction labels (上 / 下 / 左 / 右)
    final labelStyle = const TextStyle(
      color: AppTheme.textMuted,
      fontSize: 9.5,
      fontWeight: FontWeight.w600,
    );
    void drawDirLabel(String text, Offset pos) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(pos.dx - tp.width * 0.5, pos.dy - tp.height * 0.5));
    }

    drawDirLabel('上', Offset(center.dx, center.dy - outerR + 9));
    drawDirLabel('下', Offset(center.dx, center.dy + outerR - 9));
    drawDirLabel('左', Offset(center.dx - outerR + 9, center.dy));
    drawDirLabel('右', Offset(center.dx + outerR - 9, center.dy));

    // Shadow opposite ray (dashed / cool gray)
    final opposite = center - (sunPos - center) * 0.72;
    canvas.drawLine(
      center,
      opposite,
      Paint()
        ..color = AppTheme.accentCyan.withValues(alpha: 0.55)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      opposite,
      3.5,
      Paint()..color = AppTheme.accentCyan.withValues(alpha: 0.75),
    );

    // Sun incoming light ray
    canvas.drawLine(
      center,
      sunPos,
      Paint()
        ..color = AppTheme.accentAmber
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );

    // Center character marker
    canvas.drawCircle(center, 4.5, Paint()..color = Colors.white70);

    // Large ergonomic glowing sun handle
    canvas.drawCircle(
      sunPos,
      14.0,
      Paint()..color = AppTheme.accentAmber.withValues(alpha: 0.24),
    );
    canvas.drawCircle(sunPos, 9.0, Paint()..color = AppTheme.accentAmber);
    canvas.drawCircle(
      sunPos,
      9.0,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(covariant _CompassPainter oldDelegate) =>
      oldDelegate.sunPos != sunPos || oldDelegate.azimuthDeg != azimuthDeg;
}
