import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double blur;
  final double opacity;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double? width;
  final double? height;
  final VoidCallback? onTap;

  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = AppColors.borderRadius,
    this.blur = 14.0,
    this.opacity = 0.7,
    this.padding = const EdgeInsets.all(AppColors.cardPadding),
    this.color,
    this.width,
    this.height,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Advanced color palette for "Aura Glass"
    final surfaceColor = color ?? (isDark ? const Color(0xFF1E222A) : AppColors.glassSurface);
    final actualOpacity = opacity > 0.6 ? 0.05 : opacity; // Force ultra-glass look if not set specifically

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            color: surfaceColor.withValues(alpha: actualOpacity),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: isDark ? 0.08 : 0.12),
                Colors.white.withValues(alpha: 0.02),
                Colors.black.withValues(alpha: isDark ? 0.05 : 0.01),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.25),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
              // Simulating Inner Glow/Edge Highlight
              BoxShadow(
                color: Colors.white.withValues(alpha: isDark ? 0.05 : 0.15),
                blurRadius: 0,
                spreadRadius: 0,
                offset: const Offset(1, 1),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(borderRadius),
              child: Padding(
                padding: padding,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
