import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

// ══════════════════════════════════════════
// 1. ASOSIY GLASS CONTAINER
// ══════════════════════════════════════════
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final double radius;
  final double opacity;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = 16,
    this.opacity = 0.55,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withValues(alpha: 0.35) : Colors.white.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════
// 2. GLASS JADVAL HEADER
// ══════════════════════════════════════════
class GlassTableHeader extends StatelessWidget {
  final List<GlassColumn> columns;

  const GlassTableHeader({super.key, required this.columns});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        border: Border(
          bottom: BorderSide(
            color: Colors.black.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: columns.map((col) => Expanded(
          flex: col.flex,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Text(
                  col.title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.sort_rounded, size: 12,
                  color: AppColors.primary.withValues(alpha: 0.5)),
              ],
            ),
          ),
        )).toList(),
      ),
    );
  }
}

// ══════════════════════════════════════════
// 3. GLASS JADVAL QATOR
// ══════════════════════════════════════════
class GlassTableRow extends StatefulWidget {
  final List<Widget> cells;
  final List<int>? flex;
  final VoidCallback? onTap;

  const GlassTableRow({
    super.key,
    required this.cells,
    this.flex,
    this.onTap,
  });

  @override
  State<GlassTableRow> createState() => _GlassTableRowState();
}

class _GlassTableRowState extends State<GlassTableRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: _hovered
              ? AppColors.primary.withValues(alpha: 0.04)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: Colors.black.withValues(alpha: 0.04),
              width: 0.5,
            ),
          ),
        ),
        child: InkWell(
          onTap: widget.onTap,
          child: Row(
            children: List.generate(widget.cells.length, (index) {
              return Expanded(
                flex: widget.flex?[index] ?? 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 13),
                  child: widget.cells[index],
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════
// 4. STATUS BADGE
// ══════════════════════════════════════════
class GlassBadge extends StatelessWidget {
  final String text;
  final BadgeType type;

  const GlassBadge({super.key, required this.text, required this.type});

  @override
  Widget build(BuildContext context) {
    final colors = switch (type) {
      BadgeType.success => (
          bg: AppColors.success.withValues(alpha: 0.12),
          text: AppColors.success,
        ),
      BadgeType.warning => (
          bg: AppColors.warning.withValues(alpha: 0.12),
          text: AppColors.warning,
        ),
      BadgeType.danger => (
          bg: AppColors.error.withValues(alpha: 0.12),
          text: AppColors.error,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: colors.text,
        ),
      ),
    );
  }
}

enum BadgeType { success, warning, danger }

// ══════════════════════════════════════════
// 5. GLASS TUGMA
// ══════════════════════════════════════════
class GlassButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final GlassButtonStyle style;
  final VoidCallback? onTap;

  const GlassButton({
    super.key,
    required this.label,
    this.icon,
    this.style = GlassButtonStyle.ghost,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = switch (style) {
      GlassButtonStyle.ghost => (
          bg: Colors.white.withValues(alpha: 0.6),
          border: Colors.black.withValues(alpha: 0.1),
          text: AppColors.textSecondary,
        ),
      GlassButtonStyle.excel => (
          bg: AppColors.success.withValues(alpha: 0.15),
          border: AppColors.success.withValues(alpha: 0.25),
          text: AppColors.success,
        ),
      GlassButtonStyle.primary => (
          bg: AppColors.primary.withValues(alpha: 0.9),
          border: Colors.transparent,
          text: Colors.white,
        ),
    };

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: cfg.bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cfg.border, width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: cfg.text),
                  const SizedBox(width: 6),
                ],
                Text(label, style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: cfg.text,
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum GlassButtonStyle { ghost, excel, primary }

// ══════════════════════════════════════════
// 6. GLASS TOP BAR
// ══════════════════════════════════════════
class GlassTopBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color titleColor;
  final List<Widget> actions;

  const GlassTopBar({
    super.key,
    required this.title,
    required this.subtitle,
    this.titleColor = AppColors.textPrimary,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.2), // Darker glass in dark mode
            border: Border(
              bottom: BorderSide(
                color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.5),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title, 
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 26, 
                        fontWeight: FontWeight.w700,
                        color: titleColor, 
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle, 
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12, 
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Row(children: actions
                  .map((w) => Padding(
                    padding: const EdgeInsets.only(left: 8), child: w))
                  .toList()),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════
// 7. ORQA FON — BARCHA SAHIFALAR UCHUN
// ══════════════════════════════════════════
class GlassBackground extends StatelessWidget {
  final Widget child;

  const GlassBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark 
            ? [
                const Color(0xFF0F172A), // Slate 900
                const Color(0xFF1E293B), // Slate 800
                const Color(0xFF0F172A),
              ]
            : [
                const Color(0xFFE0E8F8),
                const Color(0xFFF0F4FF),
                const Color(0xFFDDEEFF),
              ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: child,
    );
  }
}

// ══════════════════════════════════════════
// 8. UNIVERSAL GLASS CONTAINER (Backward Compatible)
// ══════════════════════════════════════════
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
    this.borderRadius = 16,
    this.blur = 20.0,
    this.opacity = 0.55,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.width,
    this.height,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: Container(
            width: width,
            height: height,
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              color: isDark 
                ? (color ?? Colors.black).withValues(alpha: opacity * 0.7) 
                : (color ?? Colors.white).withValues(alpha: opacity),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.2),
                width: 0.5,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════
// 9. YORDAMCHI CLASS
// ══════════════════════════════════════════
class GlassColumn {
  final String title;
  final int flex;
  const GlassColumn({required this.title, this.flex = 1});
}
