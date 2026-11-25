import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/app_settings.dart';
import '../models/blend_recipe.dart';

class AiRelightingException implements Exception {
  final String message;
  const AiRelightingException(this.message);

  @override
  String toString() => message;
}

/// Optional AI Deep Relighting & Seamless Harmonization service.
/// Supports:
/// - Google Gemini Image Generation/Editing API
/// - OpenAI Images Edit API (gpt-image-1)
/// - IC-Light / ComfyUI / Custom REST Relighting Backend
class AiRelightingService {
  static String buildLightingAwarePrompt({
    required LightingProfile lighting,
    required String basePrompt,
  }) {
    final tempDesc = lighting.kelvin < 4300
        ? 'warm golden amber light (${lighting.kelvin.round()}K)'
        : lighting.kelvin > 6800
            ? 'cool twilight/blue-hour ambient light (${lighting.kelvin.round()}K)'
            : 'balanced natural daylight (${lighting.kelvin.round()}K)';

    final az = lighting.lightAzimuthDeg % 360;
    final dirDesc = (az >= 315 || az < 45)
        ? 'from the right'
        : (az >= 45 && az < 135)
            ? 'from the lower front'
            : (az >= 135 && az < 225)
                ? 'from the left'
                : 'from above';

    final shadowDesc = lighting.shadowSoftness > 0.65
        ? 'soft diffused contact and directional shadows'
        : 'crisp directional grounded shadows';

    return '$basePrompt '
        'Lighting constraints: $tempDesc coming mainly $dirDesc, '
        'matching scene exposure (${lighting.exposureEv.toStringAsFixed(2)} EV), '
        'casting $shadowDesc on the floor, with natural rim light wrap and subtle matching camera noise. '
        'Keep the background environment untouched and maintain the anime character identity accurately.';
  }

  /// Calls the configured AI relighting provider and returns the enhanced image bytes (PNG/JPEG).
  static Future<Uint8List> relightComposite({
    required AppSettings settings,
    required Uint8List compositeBytes,
    required Uint8List backgroundBytes,
    required Uint8List standeeBytes,
    required BlendRecipe recipe,
  }) async {
    if (!settings.isAiConfigured) {
      throw const AiRelightingException(
        '尚未配置 AI 溶图接口密钥。请点击右上角「设置」填写 Gemini / OpenAI API Key 或 IC-Light 服务地址。',
      );
    }

    final prompt = buildLightingAwarePrompt(
      lighting: recipe.lighting,
      basePrompt: settings.customRelightPrompt,
    );

    switch (settings.aiProvider) {
      case AiRelightProvider.gemini:
        return _callGemini(settings, compositeBytes, prompt);
      case AiRelightProvider.openai:
        return _callOpenAi(settings, compositeBytes, prompt);
      case AiRelightProvider.icLightCustom:
        return _callIcLightCustom(
          settings: settings,
          compositeBytes: compositeBytes,
          backgroundBytes: backgroundBytes,
          standeeBytes: standeeBytes,
          recipe: recipe,
          prompt: prompt,
        );
    }
  }

  static Future<Uint8List> _callGemini(
    AppSettings settings,
    Uint8List compositeBytes,
    String prompt,
  ) async {
    final endpoint = settings.effectiveEndpoint;
    final uri = Uri.parse(
      endpoint.contains('key=')
          ? endpoint
          : '$endpoint?key=${Uri.encodeQueryComponent(settings.aiApiKey.trim())}',
    );

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {
                'mime_type': 'image/jpeg',
                'data': base64Encode(compositeBytes),
              },
            },
          ],
        },
      ],
      'generationConfig': {
        'responseModalities': ['TEXT', 'IMAGE'],
      },
    });

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 90));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiRelightingException(
        'Gemini API 请求失败 (${response.statusCode}): ${_truncate(response.body)}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List<dynamic>?;
    if (candidates != null && candidates.isNotEmpty) {
      final parts =
          ((candidates.first as Map<String, dynamic>)['content']
              as Map<String, dynamic>?)?['parts'] as List<dynamic>?;
      if (parts != null) {
        for (final part in parts) {
          final map = part as Map<String, dynamic>;
          final inline =
              (map['inlineData'] ?? map['inline_data']) as Map<String, dynamic>?;
          if (inline != null && inline['data'] is String) {
            return base64Decode(inline['data'] as String);
          }
        }
      }
    }

    throw const AiRelightingException('Gemini 响应中未包含生成的图片数据，请检查模型是否支持图像输出。');
  }

  static Future<Uint8List> _callOpenAi(
    AppSettings settings,
    Uint8List compositeBytes,
    String prompt,
  ) async {
    final uri = Uri.parse(settings.effectiveEndpoint);
    final req = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer ${settings.aiApiKey.trim()}'
      ..fields['model'] = settings.effectiveModel
      ..fields['prompt'] = prompt
      ..files.add(
        http.MultipartFile.fromBytes(
          'image',
          compositeBytes,
          filename: 'composite.jpg',
        ),
      );

    final streamed = await req.send().timeout(const Duration(seconds: 90));
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiRelightingException(
        'OpenAI API 请求失败 (${response.statusCode}): ${_truncate(response.body)}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final items = json['data'] as List<dynamic>?;
    if (items != null && items.isNotEmpty) {
      final first = items.first as Map<String, dynamic>;
      if (first['b64_json'] is String) {
        return base64Decode(first['b64_json'] as String);
      }
      if (first['url'] is String) {
        final imgResp = await http
            .get(Uri.parse(first['url'] as String))
            .timeout(const Duration(seconds: 45));
        if (imgResp.statusCode == 200) return imgResp.bodyBytes;
      }
    }
    throw const AiRelightingException('OpenAI 响应中未找到有效图片结果。');
  }

  static Future<Uint8List> _callIcLightCustom({
    required AppSettings settings,
    required Uint8List compositeBytes,
    required Uint8List backgroundBytes,
    required Uint8List standeeBytes,
    required BlendRecipe recipe,
    required String prompt,
  }) async {
    final uri = Uri.parse(settings.effectiveEndpoint);
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (settings.aiApiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${settings.aiApiKey.trim()}';
    }

    final payload = jsonEncode({
      'model': settings.effectiveModel,
      'prompt': prompt,
      'composite_base64': base64Encode(compositeBytes),
      'background_base64': base64Encode(backgroundBytes),
      'foreground_base64': base64Encode(standeeBytes),
      'lighting': recipe.lighting.toJson(),
      'placement': recipe.placement.toJson(),
      'perspective': recipe.perspective.toJson(),
    });

    final response = await http
        .post(uri, headers: headers, body: payload)
        .timeout(const Duration(seconds: 120));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiRelightingException(
        'IC-Light 自定义服务请求失败 (${response.statusCode}): ${_truncate(response.body)}',
      );
    }

    final contentType = response.headers['content-type'] ?? '';
    if (contentType.startsWith('image/')) {
      return response.bodyBytes;
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final b64 = (json['image_base64'] ?? json['image'] ?? json['result']) as String?;
    if (b64 != null && b64.isNotEmpty) {
      final clean = b64.contains(',') ? b64.split(',').last : b64;
      return base64Decode(clean);
    }

    throw const AiRelightingException('自定义接口未返回 image_base64 或二进制图片。');
  }

  static String _truncate(String s) => s.length > 220 ? '${s.substring(0, 220)}...' : s;
}
