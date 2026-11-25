import 'blend_recipe.dart';

class GalleryItem {
  final String id;
  final String title;

  /// Rendered composite PNG/JPG using our on-device physical lighting engine
  final String compositePath;

  /// Raw captured reality background photo (kept for non-destructive re-edit & re-blend!)
  final String backgroundPath;

  /// Optional AI deep-relit output image path (Gemini / OpenAI / IC-Light)
  final String? aiEnhancedPath;

  /// Name of the AI provider used if aiEnhancedPath != null
  final String? aiProviderTag;

  /// Whether user currently prefers displaying the AI enhanced version
  final bool preferAiVersion;

  /// Non-destructive blend parameters (placement + perspective + lighting + standeeId)
  final BlendRecipe recipe;

  final DateTime createdAt;
  final DateTime updatedAt;

  const GalleryItem({
    required this.id,
    required this.title,
    required this.compositePath,
    required this.backgroundPath,
    this.aiEnhancedPath,
    this.aiProviderTag,
    this.preferAiVersion = false,
    required this.recipe,
    required this.createdAt,
    required this.updatedAt,
  });

  String get displayPath =>
      (preferAiVersion && aiEnhancedPath != null) ? aiEnhancedPath! : compositePath;

  bool get hasAiEnhancement => aiEnhancedPath != null && aiEnhancedPath!.isNotEmpty;

  GalleryItem copyWith({
    String? title,
    String? compositePath,
    String? backgroundPath,
    String? aiEnhancedPath,
    String? aiProviderTag,
    bool? preferAiVersion,
    BlendRecipe? recipe,
    DateTime? updatedAt,
  }) {
    return GalleryItem(
      id: id,
      title: title ?? this.title,
      compositePath: compositePath ?? this.compositePath,
      backgroundPath: backgroundPath ?? this.backgroundPath,
      aiEnhancedPath: aiEnhancedPath ?? this.aiEnhancedPath,
      aiProviderTag: aiProviderTag ?? this.aiProviderTag,
      preferAiVersion: preferAiVersion ?? this.preferAiVersion,
      recipe: recipe ?? this.recipe,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'compositePath': compositePath,
        'backgroundPath': backgroundPath,
        'aiEnhancedPath': aiEnhancedPath,
        'aiProviderTag': aiProviderTag,
        'preferAiVersion': preferAiVersion,
        'recipe': recipe.toJson(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory GalleryItem.fromJson(Map<String, dynamic> json) {
    return GalleryItem(
      id: json['id'] as String,
      title: json['title'] as String? ?? '溶图作品',
      compositePath: json['compositePath'] as String,
      backgroundPath: json['backgroundPath'] as String,
      aiEnhancedPath: json['aiEnhancedPath'] as String?,
      aiProviderTag: json['aiProviderTag'] as String?,
      preferAiVersion: json['preferAiVersion'] as bool? ?? false,
      recipe: BlendRecipe.fromJson(
        (json['recipe'] as Map<String, dynamic>?) ?? const {},
      ),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
