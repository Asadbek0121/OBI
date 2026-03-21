import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class GlassContainer extends StatelessWidget {
  final Widget child;
  final dynamic borderRadius;
  final double blur;
  final double opacity;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final double? width;
  final double? height;
  final VoidCallback? onTap;
  final bool showBorder;

  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = AppColors.borderRadius,
    this.blur = 14.0,
    this.opacity = 0.7,
    this.padding = const EdgeInsets.all(AppColors.cardPadding),
    this.color,
    this.borderColor,
    this.width,
    this.height,
    this.onTap,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius is num 
        ? BorderRadius.circular((borderRadius as num).toDouble()) 
        : (borderRadius as BorderRadius);
    
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: isDark 
                ? Colors.black.withValues(alpha: 0.3) 
                : Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            spreadRadius: -2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Material(
            color: (color ?? (isDark ? Colors.black : Colors.white)).withValues(alpha: isDark ? 0.3 : (color == null ? 0.4 : 1.0)),
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: Container(
                padding: padding,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: showBorder ? Border.all(
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? Colors.white.withValues(alpha: 0.2) 
                        : Colors.black.withValues(alpha: 0.12),
                    width: 1.2,
                  ) : null,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
