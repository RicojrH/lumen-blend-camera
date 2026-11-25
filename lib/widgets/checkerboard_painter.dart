import 'package:flutter/material.dart';

/// Dark transparency checkerboard for cleanly inspecting cutout edges & alpha masks.
class CheckerboardPainter extends CustomPainter {
  final double cellSize;
  final Color lightColor;
  final Color darkColor;

  const CheckerboardPainter({
    this.cellSize = 12.0,
    this.lightColor = const Color(0xFF232A38),
    this.darkColor = const Color(0xFF161B24),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pLight = Paint()..color = lightColor;
    final pDark = Paint()..color = darkColor;

    canvas.drawRect(Offset.zero & size, pDark);
    final cols = (size.width / cellSize).ceil();
    final rows = (size.height / cellSize).ceil();

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if ((r + c).isEven) {
          canvas.drawRect(
            Rect.fromLTWH(c * cellSize, r * cellSize, cellSize, cellSize),
            pLight,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CheckerboardPainter oldDelegate) =>
      oldDelegate.cellSize != cellSize ||
      oldDelegate.lightColor != lightColor ||
      oldDelegate.darkColor != darkColor;
}
