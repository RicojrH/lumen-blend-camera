import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen_blend_camera/services/auto_matte_engine.dart';

void main() {
  group('AutoMatteEngine anime line-aware matting', () {
    test('removes exterior pure white background while preserving interior white enclosed by dark outline', () async {
      // Create a 120x120 synthetic anime sprite on pure white (#FFFFFF):
      // Outer dark lineart box (30..90, 20..100), colored body, and an interior pure-white collar patch (48..72, 42..62)
      final src = img.Image(width: 120, height: 120, numChannels: 4);
      img.fill(src, color: img.ColorRgba8(255, 255, 255, 255));

      for (int y = 20; y <= 100; y++) {
        for (int x = 30; x <= 90; x++) {
          final onBorder = x <= 32 || x >= 88 || y <= 22 || y >= 98;
          if (onBorder) {
            src.setPixelRgba(x, y, 25, 25, 32, 255); // Dark anime lineart
          } else if (x >= 48 && x <= 72 && y >= 42 && y <= 62) {
            src.setPixelRgba(x, y, 255, 255, 255, 255); // Interior white shirt/collar
          } else {
            src.setPixelRgba(x, y, 70, 110, 190, 255); // Navy outfit
          }
        }
      }

      final jpgBytes = Uint8List.fromList(img.encodeJpg(src, quality: 96));
      final result = await AutoMatteEngine.processBytes(
        inputBytes: jpgBytes,
        config: const MatteConfig(
          mode: MatteMode.animeLineAware,
          tolerance: 28.0,
          softness: 14.0,
          edgeShrink: 0,
          featherRadius: 0.0,
          autoCrop: false,
        ),
      );

      final out = img.decodeImage(result.pngBytes);
      expect(out, isNotNull);
      // Exterior corner must be fully transparent
      expect(out!.getPixel(5, 5).a, equals(0));
      // Colored outfit interior must be opaque
      expect(out.getPixel(40, 80).a, greaterThan(240));
      // Interior pure white shirt enclosed by dark lineart MUST remain opaque!
      expect(out.getPixel(60, 52).a, greaterThan(240));
    });
  });
}
