import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen_blend_camera/services/lighting_probe_service.dart';

void main() {
  group('LightingProbeService photometric analysis', () {
    test('distinguishes warm golden-hour scene from cool blue-hour scene', () {
      // Synthetic warm sunlit cafe photo (strong bright amber window on right)
      final warm = img.Image(width: 90, height: 160);
      for (int y = 0; y < warm.height; y++) {
        for (int x = 0; x < warm.width; x++) {
          final rightBoost = x > 65 ? 55 : 0;
          warm.setPixelRgba(
            x,
            y,
            (195 + rightBoost).clamp(0, 255),
            (138 + rightBoost).clamp(0, 255),
            (72 + rightBoost ~/ 2).clamp(0, 255),
            255,
          );
        }
      }

      // Synthetic cool twilight alley photo (dim cool blue ambient)
      final cool = img.Image(width: 90, height: 160);
      for (int y = 0; y < cool.height; y++) {
        for (int x = 0; x < cool.width; x++) {
          cool.setPixelRgba(x, y, 42, 68, 128, 255);
        }
      }

      final warmProfile = LightingProbeService.analyzeImage(warm);
      final coolProfile = LightingProbeService.analyzeImage(cool);

      expect(warmProfile.kelvin, lessThan(4500));
      expect(coolProfile.kelvin, greaterThan(6800));
      expect(warmProfile.exposureEv, greaterThan(coolProfile.exposureEv));
    });
  });
}
