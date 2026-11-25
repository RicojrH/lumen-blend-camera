import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/standee_asset.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/checkerboard_painter.dart';
import 'matte_studio_screen.dart';

/// Feature 3a: Anime Standee Asset Library.
/// Allows users to import JPG/PNG/WebP character illustrations, automatically remove
/// backgrounds in MatteStudioScreen, manage saved transparent standees, and send
/// any standee straight into the Camera viewfinder.
class AssetLibraryScreen extends StatefulWidget {
  final AppController controller;

  const AssetLibraryScreen({super.key, required this.controller});

  @override
  State<AssetLibraryScreen> createState() => _AssetLibraryScreenState();
}

class _AssetLibraryScreenState extends State<AssetLibraryScreen> {
  final ImagePicker _picker = ImagePicker();

  AppController get _ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_refresh);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _importAndAutoMatte() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final nextIndex = _ctrl.standees.length + 1;
      final rawName = picked.name.replaceAll(RegExp(r'\.[^.]+$'), '').trim();
      final looksAutoHash = rawName.isEmpty ||
          rawName.length > 8 ||
          RegExp(r'^[a-zA-Z0-9_\-]{8,}$').hasMatch(rawName) ||
          rawName.toLowerCase().contains('image_picker') ||
          rawName.toLowerCase().startsWith('img_');
      final shortName = looksAutoHash ? '立绘 #$nextIndex' : rawName;
      if (!mounted) return;

      final saved = await Navigator.of(context).push<StandeeAsset>(
        MaterialPageRoute<StandeeAsset>(
          builder: (_) => MatteStudioScreen(
            controller: _ctrl,
            sourceBytes: bytes,
            initialName: shortName,
          ),
        ),
      );
      if (saved != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已抠图并保存素材「${saved.name}」')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择立绘图片失败：$e')),
      );
    }
  }

  Future<void> _reMatteStandee(StandeeAsset asset) async {
    final srcPath = asset.originalPath ?? asset.cutoutPath;
    final bytes = await _ctrl.storage.blobStore.readBytes(srcPath);
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到该立绘的原始文件')),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push<StandeeAsset>(
      MaterialPageRoute<StandeeAsset>(
        builder: (_) => MatteStudioScreen(
          controller: _ctrl,
          sourceBytes: bytes,
          initialName: asset.name,
          overwriteAssetId: asset.id,
        ),
      ),
    );
  }

  Future<void> _renameStandee(StandeeAsset asset) async {
    final textCtrl = TextEditingController(text: asset.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        title: const Text('重命名立绘素材'),
        content: TextField(
          controller: textCtrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入角色或立绘名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, textCtrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    textCtrl.dispose();
    if (result != null && result.isNotEmpty) {
      await _ctrl.renameStandee(asset, result);
    }
  }

  Future<void> _confirmDelete(StandeeAsset asset) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        title: const Text('删除立绘素材'),
        content: Text('确定删除「${asset.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accentRose),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _ctrl.deleteStandee(asset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final standees = _ctrl.standees;
    final activeId = _ctrl.activeStandee?.id;

    return Scaffold(
      appBar: AppBar(
        title: Text('立绘素材库 (${standees.length})'),
      ),
      body: Column(
        children: [
          // Prominent Auto-Matting Import Banner
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: GestureDetector(
              onTap: _importAndAutoMatte,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.accentAmber.withValues(alpha: 0.22),
                      AppTheme.accentCyan.withValues(alpha: 0.14),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.accentAmber.withValues(alpha: 0.55),
                  ),
                ),
                child: const Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: AppTheme.accentAmber,
                      child: Icon(
                        Icons.auto_fix_high_rounded,
                        color: Colors.black,
                        size: 22,
                      ),
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '导入立绘并自动抠图去背景',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            '支持 JPG / PNG / WebP · 内置二次元护线去白边 + 手动精修画笔 + 端侧 ONNX AI',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: AppTheme.accentAmber),
                  ],
                ),
              ),
            ),
          ),

          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.68,
              ),
              itemCount: standees.length,
              itemBuilder: (context, index) {
                final asset = standees[index];
                final isSelected = asset.id == activeId;
                return _buildAssetCard(asset, isSelected);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetCard(StandeeAsset asset, bool isSelected) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? AppTheme.accentAmber : AppTheme.borderSubtle,
          width: isSelected ? 1.8 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Transparent Cutout Checkerboard Preview
          Expanded(
            child: GestureDetector(
              onTap: () {
                _ctrl.selectStandee(asset.id);
                Navigator.of(context).pop();
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const CustomPaint(painter: CheckerboardPainter(cellSize: 10)),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: _ctrl.storage.blobStore.buildImage(
                      asset.cutoutPath,
                      fit: BoxFit.contain,
                      imageKey: ValueKey('${asset.cutoutPath}_${asset.width}x${asset.height}'),
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image_outlined,
                            color: AppTheme.textMuted),
                      ),
                    ),
                  ),
                  if (isSelected)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.accentAmber,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '当前取景中',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  if (asset.isBuiltIn)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xB80A0C10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '示例',
                          style: TextStyle(
                            color: AppTheme.accentCyan,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Asset Metadata & Actions
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
            color: AppTheme.surfaceDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${asset.width}×${asset.height} · PNG 透明通道',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 28,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            side: const BorderSide(color: AppTheme.borderSubtle),
                          ),
                          onPressed: () => _reMatteStandee(asset),
                          child: const Text(
                            '抠图精修',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.more_horiz_rounded,
                            size: 18, color: AppTheme.textSecondary),
                        color: AppTheme.surfaceElevated,
                        onSelected: (v) {
                          if (v == 'use') {
                            _ctrl.selectStandee(asset.id);
                            Navigator.of(context).pop();
                          } else if (v == 'rename') {
                            _renameStandee(asset);
                          } else if (v == 'delete') {
                            _confirmDelete(asset);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'use', child: Text('立即溶图使用')),
                          PopupMenuItem(value: 'rename', child: Text('重命名')),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('删除素材',
                                style: TextStyle(color: AppTheme.accentRose)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
