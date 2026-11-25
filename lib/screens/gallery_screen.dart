import 'package:flutter/material.dart';

import '../models/gallery_item.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/author_info_sheet.dart';
import 'ai_engine_screen.dart';
import 'photo_editor_screen.dart';

/// Feature 2a: Gallery screen displaying all finished composites with non-destructive
/// recipes, AI-relight badges, quick system-album export, and entry to PhotoEditorScreen.
class GalleryScreen extends StatefulWidget {
  final AppController controller;

  const GalleryScreen({super.key, required this.controller});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  bool _onlyAiEnhanced = false;

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

  Future<void> _exportItem(GalleryItem item) async {
    final msg = await _ctrl.storage.exportToSystemAlbum(item.displayPath);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _confirmDelete(GalleryItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        title: const Text('删除成品图'),
        content: Text('确定删除「${item.title}」及其溶图工程数据吗？此操作无法撤销。'),
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
      await _ctrl.deleteGalleryItem(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _onlyAiEnhanced
        ? _ctrl.gallery.where((e) => e.hasAiEnhancement).toList()
        : _ctrl.gallery;

    return Scaffold(
      appBar: AppBar(
        title: Text('溶图图库 (${_ctrl.gallery.length})'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: _ctrl.settings.isAiConfigured
                      ? AppTheme.accentMint
                      : AppTheme.accentAmber.withValues(alpha: 0.75),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              onPressed: () => AiEngineScreen.push(context, _ctrl),
              icon: Icon(
                Icons.auto_awesome_rounded,
                size: 15,
                color: _ctrl.settings.isAiConfigured
                    ? AppTheme.accentMint
                    : AppTheme.accentAmber,
              ),
              label: Text(
                'AI 引擎接入',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _ctrl.settings.isAiConfigured
                      ? AppTheme.accentMint
                      : AppTheme.accentAmber,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Strip
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: Row(
              children: [
                ChoiceChip(
                  label: Text('全部成品 (${_ctrl.gallery.length})'),
                  selected: !_onlyAiEnhanced,
                  onSelected: (_) => setState(() => _onlyAiEnhanced = false),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(
                    'AI 精修 (${_ctrl.gallery.where((e) => e.hasAiEnhancement).length})',
                  ),
                  selected: _onlyAiEnhanced,
                  onSelected: (_) => setState(() => _onlyAiEnhanced = true),
                ),
              ],
            ),
          ),

          Expanded(
            child: items.isEmpty
                ? _buildEmptyState()
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.66,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, idx) => _buildCard(items[idx]),
                  ),
          ),
          SafeArea(
            top: false,
            child: GestureDetector(
              onTap: () => AuthorInfoSheet.show(context, _ctrl),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '作者：@没品人类之一 · B站：https://space.bilibili.com/396896138',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_filter_rounded,
                size: 54, color: AppTheme.textMuted),
            const SizedBox(height: 14),
            Text(
              _onlyAiEnhanced ? '还没有经过 AI 深度精修的成品' : '图库里还没有溶图成品',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '回到取景相机按下快门，即可生成光影匹配的成品图，并在图库中随时无损微调光影、换立绘或再次溶图。',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accentAmber,
                foregroundColor: Colors.black,
              ),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.camera_alt_rounded, size: 18),
              label: const Text('回到取景相机拍摄'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(GalleryItem item) {
    final lighting = item.recipe.lighting;
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PhotoEditorScreen(
              controller: _ctrl,
              initialItem: item,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.borderSubtle),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _ctrl.storage.blobStore.buildImage(
              item.displayPath,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image_outlined,
                    color: AppTheme.textMuted),
              ),
            ),

            // Top badges (AI enhanced & Kelvin)
            Positioned(
              left: 8,
              top: 8,
              right: 8,
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xB80A0C10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${lighting.kelvin.round()}K',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (item.hasAiEnhancement)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.accentMint.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'AI 精修',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Bottom gradient info & quick menu
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 26, 6, 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xE80A0C10)],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            '点击调光 / 再次溶图',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded,
                          color: Colors.white70, size: 18),
                      color: AppTheme.surfaceElevated,
                      onSelected: (action) async {
                        if (action == 'export') {
                          await _exportItem(item);
                        } else if (action == 'reblend_cam') {
                          await _ctrl.loadGalleryItemIntoCamera(item);
                          if (mounted) Navigator.of(context).pop();
                        } else if (action == 'delete') {
                          await _confirmDelete(item);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'export', child: Text('导出至系统相册')),
                        PopupMenuItem(
                            value: 'reblend_cam', child: Text('带入相机再次溶图')),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('删除作品',
                              style: TextStyle(color: AppTheme.accentRose)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
