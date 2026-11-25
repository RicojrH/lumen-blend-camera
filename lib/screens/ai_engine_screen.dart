import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';

/// Dedicated AI Relighting Engine Integration Page (accessed exclusively inside Gallery / 图库).
class AiEngineScreen extends StatefulWidget {
  final AppController controller;

  const AiEngineScreen({super.key, required this.controller});

  static Future<void> push(BuildContext context, AppController controller) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AiEngineScreen(controller: controller),
      ),
    );
  }

  @override
  State<AiEngineScreen> createState() => _AiEngineScreenState();
}

class _AiEngineScreenState extends State<AiEngineScreen> {
  late AiRelightProvider _provider;
  late TextEditingController _apiKeyCtrl;
  late TextEditingController _endpointCtrl;
  late TextEditingController _modelCtrl;
  late TextEditingController _promptCtrl;
  late int _maxExportDim;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _provider = s.aiProvider;
    _apiKeyCtrl = TextEditingController(text: s.aiApiKey);
    _endpointCtrl = TextEditingController(text: s.aiEndpointUrl);
    _modelCtrl = TextEditingController(text: s.aiModelName);
    _promptCtrl = TextEditingController(text: s.customRelightPrompt);
    _maxExportDim = s.maxExportDimension;
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _endpointCtrl.dispose();
    _modelCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final prev = widget.controller.settings;
    final next = prev.copyWith(
      aiProvider: _provider,
      aiApiKey: _apiKeyCtrl.text.trim(),
      aiEndpointUrl: _endpointCtrl.text.trim(),
      aiModelName: _modelCtrl.text.trim(),
      customRelightPrompt: _promptCtrl.text.trim(),
      maxExportDimension: _maxExportDim,
    );
    await widget.controller.updateSettings(next);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('AI 溶图引擎配置已保存')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgObsidian,
      appBar: AppBar(
        title: const Text('AI 溶图引擎接入'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accentAmber,
                foregroundColor: Colors.black,
              ),
              child: const Text(
                '保存配置',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceDark,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.borderSubtle),
            ),
            child: const Text(
              '取景预览与默认出图均由端侧物理光影引擎实时完成。在此接入云端或本地 AI 视觉服务后，可在图库单张作品的「AI 精修」中一键进行全局重打光与环境材质融合。',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '选择 AI 引擎服务商',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AiRelightProvider.values.map((p) {
              return ChoiceChip(
                label: Text(p.displayName),
                selected: _provider == p,
                onSelected: (_) => setState(() => _provider = p),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apiKeyCtrl,
            obscureText: _obscureKey,
            decoration: InputDecoration(
              labelText: _provider == AiRelightProvider.icLightCustom
                  ? '鉴权 Token（可选）'
                  : 'API Key',
              hintText: _provider == AiRelightProvider.gemini
                  ? 'AIza...'
                  : _provider == AiRelightProvider.openai
                      ? 'sk-...'
                      : 'Bearer token（自建服务无需鉴权可留空）',
              filled: true,
              fillColor: AppTheme.surfaceElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.borderSubtle),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureKey ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                ),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _endpointCtrl,
            decoration: InputDecoration(
              labelText: '接口 Endpoint（留空使用默认地址）',
              hintText: _provider.defaultEndpoint,
              filled: true,
              fillColor: AppTheme.surfaceElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.borderSubtle),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _modelCtrl,
            decoration: InputDecoration(
              labelText: '模型名称（留空使用默认模型）',
              hintText: _provider.defaultModel,
              filled: true,
              fillColor: AppTheme.surfaceElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.borderSubtle),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _promptCtrl,
            maxLines: 4,
            style: const TextStyle(fontSize: 12.5),
            decoration: InputDecoration(
              labelText: 'AI 溶图提示词模板（自动注入场景色温与光照角度）',
              filled: true,
              fillColor: AppTheme.surfaceElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.borderSubtle),
              ),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            '图库重溶输出分辨率',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [1280, 1920, 2560].map((dim) {
              return ChoiceChip(
                label: Text('${dim}px'),
                selected: _maxExportDim == dim,
                onSelected: (_) => setState(() => _maxExportDim = dim),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
