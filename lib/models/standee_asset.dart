class StandeeAsset {
  final String id;
  final String name;
  final String cutoutPath;
  final String? originalPath;
  final int width;
  final int height;
  final DateTime createdAt;
  final bool isBuiltIn;
  final String matteMethod;

  const StandeeAsset({
    required this.id,
    required this.name,
    required this.cutoutPath,
    this.originalPath,
    required this.width,
    required this.height,
    required this.createdAt,
    this.isBuiltIn = false,
    this.matteMethod = 'anime_line_aware',
  });

  double get aspectRatio => height > 0 ? width / height : 0.66;

  StandeeAsset copyWith({
    String? name,
    String? cutoutPath,
    String? originalPath,
    int? width,
    int? height,
    String? matteMethod,
  }) {
    return StandeeAsset(
      id: id,
      name: name ?? this.name,
      cutoutPath: cutoutPath ?? this.cutoutPath,
      originalPath: originalPath ?? this.originalPath,
      width: width ?? this.width,
      height: height ?? this.height,
      createdAt: createdAt,
      isBuiltIn: isBuiltIn,
      matteMethod: matteMethod ?? this.matteMethod,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cutoutPath': cutoutPath,
        'originalPath': originalPath,
        'width': width,
        'height': height,
        'createdAt': createdAt.toIso8601String(),
        'isBuiltIn': isBuiltIn,
        'matteMethod': matteMethod,
      };

  factory StandeeAsset.fromJson(Map<String, dynamic> json) {
    return StandeeAsset(
      id: json['id'] as String,
      name: json['name'] as String,
      cutoutPath: json['cutoutPath'] as String,
      originalPath: json['originalPath'] as String?,
      width: (json['width'] as num?)?.toInt() ?? 800,
      height: (json['height'] as num?)?.toInt() ?? 1200,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      matteMethod: json['matteMethod'] as String? ?? 'anime_line_aware',
    );
  }
}
