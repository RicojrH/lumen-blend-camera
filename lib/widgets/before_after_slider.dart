import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Interactive Before/After split-curtain comparison widget for verifying
/// seamless lighting harmonization vs raw unblended photo or AI deep-relight output.
class BeforeAfterSlider extends StatefulWidget {
  final Widget beforeChild;
  final Widget afterChild;
  final String beforeLabel;
  final String afterLabel;

  const BeforeAfterSlider({
    super.key,
    required this.beforeChild,
    required this.afterChild,
    this.beforeLabel = '原始背景',
    this.afterLabel = '光影溶图',
  });

  @override
  State<BeforeAfterSlider> createState() => _BeforeAfterSliderState();
}

class _BeforeAfterSliderState extends State<BeforeAfterSlider> {
  double _split = 0.5;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final dividerX = (_split * w).clamp(16.0, w - 16.0);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) {
            setState(() {
              _split = ((details.localPosition.dx) / w).clamp(0.04, 0.96);
            });
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Right side (After)
              widget.afterChild,

              // Left clipped side (Before)
              ClipRect(
                clipper: _LeftSplitClipper(dividerX),
                child: widget.beforeChild,
              ),

              // Vertical divider line
              Positioned(
                left: dividerX - 1,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 2,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),

              // Draggable center handle
              Positioned(
                left: dividerX - 18,
                top: constraints.maxHeight * 0.5 - 18,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.bgObsidian.withValues(alpha: 0.85),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.8),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 8),
                    ],
                  ),
                  child: const Icon(
                    Icons.compare_arrows_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),

              // Floating corner labels
              Positioned(
                left: 12,
                top: 12,
                child: _Badge(label: widget.beforeLabel),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: _Badge(label: widget.afterLabel, accent: true),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final bool accent;

  const _Badge({required this.label, this.accent = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xB80A0C10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent
              ? AppTheme.accentAmber.withValues(alpha: 0.6)
              : Colors.white24,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent ? AppTheme.accentAmber : AppTheme.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _LeftSplitClipper extends CustomClipper<Rect> {
  final double splitX;
  const _LeftSplitClipper(this.splitX);

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, splitX, size.height);

  @override
  bool shouldReclip(covariant _LeftSplitClipper oldClipper) =>
      oldClipper.splitX != splitX;
}
