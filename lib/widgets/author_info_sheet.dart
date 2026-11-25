import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_controller.dart';
import '../theme/app_theme.dart';

class AuthorInfo {
  static const String authorHandle = '@没品人类之一';
  static const String bilibiliUrl = 'https://space.bilibili.com/396896138';
}

/// Modal card showcasing creator credit & clickable Bilibili space link.
class AuthorInfoSheet extends StatelessWidget {
  final AppController controller;

  const AuthorInfoSheet({super.key, required this.controller});

  static Future<void> show(BuildContext context, AppController controller) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => AuthorInfoSheet(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.borderSubtle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.accentAmber.withValues(alpha: 0.16),
                    border: Border.all(color: AppTheme.accentAmber, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.camera_enhance_rounded,
                    color: AppTheme.accentAmber,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '自动溶图相机 · LumenBlend',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        '实时 3D 透视 · 物理光影匹配 · 二次元无损溶图',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.verified_user_rounded,
                          size: 16, color: AppTheme.accentCyan),
                      SizedBox(width: 6),
                      Text(
                        '作者信息',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    AuthorInfo.authorHandle,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const SelectableText(
                    'B站：${AuthorInfo.bilibiliUrl}',
                    style: TextStyle(
                      color: AppTheme.accentCyan,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFB7299),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () async {
                            final opened = await controller.storage.blobStore
                                .openExternalUrl(AuthorInfo.bilibiliUrl);
                            if (!opened && context.mounted) {
                              await Clipboard.setData(
                                const ClipboardData(text: AuthorInfo.bilibiliUrl),
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('已复制 B站主页链接到剪贴板'),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.open_in_new_rounded, size: 16),
                          label: const Text(
                            '访问 B站主页',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            const ClipboardData(text: AuthorInfo.bilibiliUrl),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('已复制：@没品人类之一 B站主页链接'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 15),
                        label: const Text('复制链接'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
