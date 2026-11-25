import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_blend_camera/models/app_settings.dart';
import 'package:lumen_blend_camera/models/blend_recipe.dart';
import 'package:lumen_blend_camera/models/gallery_item.dart';

void main() {
  group('Serialization roundtrips', () {
    test('BlendRecipe and GalleryItem roundtrip cleanly through JSON', () {
      final original = GalleryItem(
        id: 'item-1',
        title: '米拉 · 咖啡馆',
        compositePath: '/tmp/comp.jpg',
        backgroundPath: '/tmp/bg.jpg',
        aiEnhancedPath: '/tmp/ai.png',
        aiProviderTag: 'Google Gemini 图像重绘',
        preferAiVersion: true,
        recipe: const BlendRecipe(
          standeeId: 'builtin_mira',
          placement: PlacementTransform(
            anchorX: 0.44,
            anchorY: 0.87,
            userScale: 1.15,
            flipX: true,
          ),
          perspective: PerspectiveState(horizonY: 0.43, pitchDeg: -10.5),
          lighting: LightingProfile(
            kelvin: 3650,
            exposureEv: -0.25,
            lightAzimuthDeg: 328,
            lightWrap: 0.55,
          ),
        ),
        createdAt: DateTime(2026, 11, 25, 13, 30),
        updatedAt: DateTime(2026, 11, 25, 13, 35),
      );

      final decoded = GalleryItem.fromJson(original.toJson());
      expect(decoded.id, equals(original.id));
      expect(decoded.preferAiVersion, isTrue);
      expect(decoded.recipe.standeeId, equals('builtin_mira'));
      expect(decoded.recipe.placement.flipX, isTrue);
      expect(decoded.recipe.lighting.kelvin, closeTo(3650, 0.01));
    });

    test('LightingProfile whiteBalanceRgb stays balanced and finite across Kelvin extremes', () {
      const warm = LightingProfile(kelvin: 2700);
      const cool = LightingProfile(kelvin: 9000);

      expect(warm.whiteBalanceRgb[0], greaterThan(warm.whiteBalanceRgb[2]));
      expect(cool.whiteBalanceRgb[2], greaterThan(cool.whiteBalanceRgb[0]));
    });

    test('AppSettings defaults and serialization work cleanly', () {
      const s = AppSettings(
        aiProvider: AiRelightProvider.openai,
        aiApiKey: 'sk-test',
        onnxInputSize: 320,
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.aiProvider, equals(AiRelightProvider.openai));
      expect(back.isAiConfigured, isTrue);
      expect(back.onnxInputSize, equals(320));
    });
  });
}
