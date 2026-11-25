import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/camera_blend_screen.dart';
import 'state/app_controller.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.bgObsidian,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const LumenBlendApp());
}

class LumenBlendApp extends StatefulWidget {
  const LumenBlendApp({super.key});

  @override
  State<LumenBlendApp> createState() => _LumenBlendAppState();
}

class _LumenBlendAppState extends State<LumenBlendApp> {
  final AppController _controller = AppController();
  late final Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '自动溶图相机 · LumenBlend',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      builder: (context, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            // On mobile phones (iOS / Android), render full-bleed edge-to-edge.
            // On wide desktop / tablet displays, present inside a sleek smartphone camera frame
            // so portrait 9:16 camera perspective & composition stay true to mobile hardware.
            if (constraints.maxWidth <= 560) {
              return child ?? const SizedBox.shrink();
            }
            final targetH = (constraints.maxHeight - 32).clamp(560.0, 920.0);
            final targetW = (targetH * (9.0 / 19.2)).clamp(360.0, 440.0);
            return ColoredBox(
              color: const Color(0xFF05070B),
              child: Center(
                child: Container(
                  width: targetW,
                  height: targetH,
                  decoration: BoxDecoration(
                    color: AppTheme.bgObsidian,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: const Color(0xFF2B3448),
                      width: 2.5,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0xAA000000),
                        blurRadius: 42,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      size: Size(targetW, targetH),
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                    ),
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            );
          },
        );
      },
      home: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _BootstrapSplash();
          }
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '初始化失败：${snapshot.error}',
                    style: const TextStyle(color: AppTheme.accentRose),
                  ),
                ),
              ),
            );
          }
          return CameraBlendScreen(controller: _controller);
        },
      ),
    );
  }
}

class _BootstrapSplash extends StatelessWidget {
  const _BootstrapSplash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgObsidian,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.surfaceElevated,
                border: Border.all(
                  color: AppTheme.accentAmber.withValues(alpha: 0.7),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.camera_rounded,
                color: AppTheme.accentAmber,
                size: 34,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'LumenBlend · 自动溶图相机',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '正在加载光影着色器与内置二次元立绘抠图...',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5),
            ),
            const SizedBox(height: 20),
            const SizedBox(
              width: 140,
              child: LinearProgressIndicator(
                color: AppTheme.accentAmber,
                backgroundColor: AppTheme.surfaceElevated,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              '作者：@没品人类之一 · B站 space.bilibili.com/396896138',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}
