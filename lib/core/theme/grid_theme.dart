import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'app_colors.dart';

class GridTheme {
  static PlutoGridStyleConfig getStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textPrimary;
    
    return PlutoGridStyleConfig(
      // --- Backgrounds & Colors ---
      gridBackgroundColor: isDark ? const Color(0xFF1E1E2D) : Colors.white,
      rowColor: isDark ? Colors.transparent : Colors.white,
      oddRowColor: isDark ? Colors.white.withValues(alpha: 0.02) : AppColors.primary.withValues(alpha: 0.03),
      evenRowColor: isDark ? Colors.transparent : Colors.white,
      activatedColor: AppColors.primary.withValues(alpha: 0.12),
      
      // --- Borders ---
      gridBorderColor: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
      borderColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.05),
      
      // --- Header Styling ---
      columnTextStyle: TextStyle(
        color: textPrimary.withValues(alpha: 0.8),
        fontWeight: FontWeight.w700,
        fontSize: 12,
        letterSpacing: 0.5,
      ),
      
      // --- Cell Styling ---
      cellTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      
      // --- Functional Colors ---
      menuBackgroundColor: isDark ? const Color(0xFF2B2B40) : Colors.white,
      iconColor: AppColors.primary,
      
      // --- Row Heights ---
      rowHeight: 52,
      columnHeight: 48,
    );
  }
}
