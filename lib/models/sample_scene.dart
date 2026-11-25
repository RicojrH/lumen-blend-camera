import 'blend_recipe.dart';

class SampleScene {
  final String id;
  final String name;
  final String subtitle;
  final String assetPath;
  final PerspectiveState defaultPerspective;
  final double defaultAnchorX;
  final double defaultAnchorY;

  const SampleScene({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.assetPath,
    required this.defaultPerspective,
    this.defaultAnchorX = 0.50,
    this.defaultAnchorY = 0.86,
  });

  static const List<SampleScene> builtInScenes = [
    SampleScene(
      id: 'cafe_golden',
      name: '午后暖阳咖啡馆',
      subtitle: '右侧夕阳斜射 · 3600K 暖色温',
      assetPath: 'assets/samples/scenes/scene_cafe_golden.jpg',
      defaultPerspective: PerspectiveState(
        horizonY: 0.44,
        vanishingX: 0.46,
        pitchDeg: -10.0,
        rollDeg: 0.0,
        depthStrength: 0.90,
      ),
      defaultAnchorX: 0.43,
      defaultAnchorY: 0.88,
    ),
    SampleScene(
      id: 'tokyo_night',
      name: '雨夜东京霓虹巷',
      subtitle: '蓝调夜色 + 左侧暖霓虹 · 7800K 冷调',
      assetPath: 'assets/samples/scenes/scene_tokyo_night.jpg',
      defaultPerspective: PerspectiveState(
        horizonY: 0.51,
        vanishingX: 0.55,
        pitchDeg: -5.0,
        rollDeg: 0.0,
        depthStrength: 1.05,
      ),
      defaultAnchorX: 0.50,
      defaultAnchorY: 0.87,
    ),
    SampleScene(
      id: 'park_daylight',
      name: '樱花林荫步道',
      subtitle: '清透日光漫射 · 5800K 自然白',
      assetPath: 'assets/samples/scenes/scene_park_daylight.jpg',
      defaultPerspective: PerspectiveState(
        horizonY: 0.53,
        vanishingX: 0.49,
        pitchDeg: -4.0,
        rollDeg: 0.0,
        depthStrength: 0.95,
      ),
      defaultAnchorX: 0.50,
      defaultAnchorY: 0.86,
    ),
  ];
}
