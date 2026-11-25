enum AiRelightProvider {
  gemini,
  openai,
  icLightCustom,
}

extension AiRelightProviderLabel on AiRelightProvider {
  String get displayName {
    switch (this) {
      case AiRelightProvider.gemini:
        return 'Google Gemini 图像重绘';
      case AiRelightProvider.openai:
        return 'OpenAI GPT-Image 编辑';
      case AiRelightProvider.icLightCustom:
        return 'IC-Light / ComfyUI 自定义接口';
    }
  }

  String get defaultEndpoint {
    switch (this) {
      case AiRelightProvider.gemini:
        return 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp-image-generation:generateContent';
      case AiRelightProvider.openai:
        return 'https://api.openai.com/v1/images/edits';
      case AiRelightProvider.icLightCustom:
        return 'http://127.0.0.1:8188/api/relight';
    }
  }

  String get defaultModel {
    switch (this) {
      case AiRelightProvider.gemini:
        return 'gemini-2.0-flash-exp-image-generation';
      case AiRelightProvider.openai:
        return 'gpt-image-1';
      case AiRelightProvider.icLightCustom:
        return 'ic-light-fbc-v1';
    }
  }
}

class AppSettings {
  final AiRelightProvider aiProvider;
  final String aiApiKey;
  final String aiEndpointUrl;
  final String aiModelName;
  final String customRelightPrompt;

  /// Local filesystem path to optional On-Device ONNX segmentation model (e.g. rmbg-1.4 / isnet-anime.onnx)
  final String onnxModelPath;

  /// Input resolution expected by ONNX model (320 for U2Net, 1024 for RMBG-1.4 / IS-Net)
  final int onnxInputSize;

  /// Default camera export JPEG/PNG high-res max edge
  final int maxExportDimension;

  const AppSettings({
    this.aiProvider = AiRelightProvider.gemini,
    this.aiApiKey = '',
    this.aiEndpointUrl = '',
    this.aiModelName = '',
    this.customRelightPrompt =
        'Seamlessly harmonize the anime character into the real-world photograph. Preserve the exact anime character design, face, pose, and outfit, while accurately matching the scene lighting direction, color temperature, atmospheric haze, soft shadows on the ground, ambient bounce light, and realistic camera lens grain so it looks naturally photographed in this environment.',
    this.onnxModelPath = '',
    this.onnxInputSize = 1024,
    this.maxExportDimension = 2560,
  });

  String get effectiveEndpoint =>
      aiEndpointUrl.trim().isNotEmpty ? aiEndpointUrl.trim() : aiProvider.defaultEndpoint;

  String get effectiveModel =>
      aiModelName.trim().isNotEmpty ? aiModelName.trim() : aiProvider.defaultModel;

  bool get isAiConfigured =>
      aiProvider == AiRelightProvider.icLightCustom
          ? effectiveEndpoint.isNotEmpty
          : aiApiKey.trim().isNotEmpty;

  AppSettings copyWith({
    AiRelightProvider? aiProvider,
    String? aiApiKey,
    String? aiEndpointUrl,
    String? aiModelName,
    String? customRelightPrompt,
    String? onnxModelPath,
    int? onnxInputSize,
    int? maxExportDimension,
  }) {
    return AppSettings(
      aiProvider: aiProvider ?? this.aiProvider,
      aiApiKey: aiApiKey ?? this.aiApiKey,
      aiEndpointUrl: aiEndpointUrl ?? this.aiEndpointUrl,
      aiModelName: aiModelName ?? this.aiModelName,
      customRelightPrompt: customRelightPrompt ?? this.customRelightPrompt,
      onnxModelPath: onnxModelPath ?? this.onnxModelPath,
      onnxInputSize: onnxInputSize ?? this.onnxInputSize,
      maxExportDimension: maxExportDimension ?? this.maxExportDimension,
    );
  }

  Map<String, dynamic> toJson() => {
        'aiProvider': aiProvider.name,
        'aiApiKey': aiApiKey,
        'aiEndpointUrl': aiEndpointUrl,
        'aiModelName': aiModelName,
        'customRelightPrompt': customRelightPrompt,
        'onnxModelPath': onnxModelPath,
        'onnxInputSize': onnxInputSize,
        'maxExportDimension': maxExportDimension,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final providerName = json['aiProvider'] as String? ?? 'gemini';
    final provider = AiRelightProvider.values.firstWhere(
      (e) => e.name == providerName,
      orElse: () => AiRelightProvider.gemini,
    );
    return AppSettings(
      aiProvider: provider,
      aiApiKey: json['aiApiKey'] as String? ?? '',
      aiEndpointUrl: json['aiEndpointUrl'] as String? ?? '',
      aiModelName: json['aiModelName'] as String? ?? '',
      customRelightPrompt: json['customRelightPrompt'] as String? ??
          const AppSettings().customRelightPrompt,
      onnxModelPath: json['onnxModelPath'] as String? ?? '',
      onnxInputSize: (json['onnxInputSize'] as num?)?.toInt() ?? 1024,
      maxExportDimension: (json['maxExportDimension'] as num?)?.toInt() ?? 1920,
    );
  }
}
