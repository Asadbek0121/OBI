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
    
    final surfaceColor = color ?? (isDark ? const Color(0xFF1E222A) : AppColors.glassSurface);
    final borderColor = isDark 
        ? Colors.white.withValues(alpha: 0.08) 
        : AppColors.glassBorder.withValues(alpha: 0.6);

    Widget content = Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: surfaceColor.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: borderColor,
          width: 1.5,
        ),
        boxShadow: isDark ? [] : AppColors.softShadow,
      ),
      child: child,
    );

    if (onTap != null) {
      content = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: content,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: content,
      ),
    );
  }
}
