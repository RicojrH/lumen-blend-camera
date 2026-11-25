import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_blend_camera/models/blend_recipe.dart';
import 'package:lumen_blend_camera/services/perspective_engine.dart';

void main() {
  group('PerspectiveEngine math', () {
    test('upright level phone yields ~0 pitch and 0.50 horizon', () {
      final orient = PerspectiveEngine.computeOrientationFromGravity(0.0, 9.81, 0.0);
      expect(orient.pitchDeg, closeTo(0.0, 0.5));
      expect(orient.rollDeg, closeTo(0.0, 0.5));

      final horizon = PerspectiveEngine.pitchToHorizonY(orient.pitchDeg);
      expect(horizon, closeTo(0.50, 0.01));
    });

    test('tilting camera downward moves horizon upward toward top of frame', () {
      // Looking downward makes +z positive in portrait accelerometer coordinates
      final orient = PerspectiveEngine.computeOrientationFromGravity(0.0, 8.5, 4.9);
      expect(orient.pitchDeg, lessThan(-20.0));
      final horizon = PerspectiveEngine.pitchToHorizonY(orient.pitchDeg);
      expect(horizon, lessThan(0.35));
    });

    test('horizonY <-> pitchDeg roundtrip is consistent', () {
      const targetHorizon = 0.38;
      final pitch = PerspectiveEngine.horizonYToPitchDeg(targetHorizon);
      final recovered = PerspectiveEngine.pitchToHorizonY(pitch);
      expect(recovered, closeTo(targetHorizon, 0.005));
    });

    test('perspective scale grows monotonically as standee approaches foreground', () {
      const p = PerspectiveState(horizonY: 0.42);
      final farScale = p.scaleFactorAtY(0.52);
      final midScale = p.scaleFactorAtY(0.72);
      final nearScale = p.scaleFactorAtY(0.92);
      expect(midScale, greaterThan(farScale));
      expect(nearScale, greaterThan(midScale));
    });

    test('360-degree shadow basis covers all quadrants smoothly without collapsing', () {
      const p = PerspectiveState(horizonY: 0.44, rollDeg: 0.0);

      // 0 deg (light on right) -> shadow casts left (-X)
      final b0 = PerspectiveEngine.computeShadowBasis(
        lighting: const LightingProfile(lightAzimuthDeg: 0),
        perspective: p,
        anchorYNorm: 0.85,
      );
      expect(b0.heightAxis.dx, lessThan(-0.2));

      // 90 deg (light in front/below) -> shadow casts upward/behind (-Y)
      final b90 = PerspectiveEngine.computeShadowBasis(
        lighting: const LightingProfile(lightAzimuthDeg: 90),
        perspective: p,
        anchorYNorm: 0.85,
      );
      expect(b90.heightAxis.dy, lessThan(-0.1));

      // 180 deg (light on left) -> shadow casts right (+X)
      final b180 = PerspectiveEngine.computeShadowBasis(
        lighting: const LightingProfile(lightAzimuthDeg: 180),
        perspective: p,
        anchorYNorm: 0.85,
      );
      expect(b180.heightAxis.dx, greaterThan(0.2));

      // 270 deg (light overhead/behind) -> shadow casts downward/forward (+Y)
      final b270 = PerspectiveEngine.computeShadowBasis(
        lighting: const LightingProfile(lightAzimuthDeg: 270),
        perspective: p,
        anchorYNorm: 0.85,
      );
      expect(b270.heightAxis.dy, greaterThan(0.1));

      // Determinant is strictly non-zero across all 360 degrees (never collapses to 1px line)
      for (int deg = 0; deg < 360; deg += 15) {
        final basis = PerspectiveEngine.computeShadowBasis(
          lighting: LightingProfile(lightAzimuthDeg: deg.toDouble()),
          perspective: p,
          anchorYNorm: 0.85,
        );
        final det = (basis.widthAxis.dx * basis.heightAxis.dy -
                basis.widthAxis.dy * basis.heightAxis.dx)
            .abs();
        expect(det, greaterThan(0.05), reason: 'Shadow collapsed at $deg deg');
      }
    });
  });
}
