import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'app_colors.dart';

class GridTheme {
  static PlutoGridStyleConfig getStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;
    final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ?? Colors.grey;
    final dividerColor = Theme.of(context).dividerColor;

    return PlutoGridStyleConfig(
      gridBackgroundColor: Colors.transparent,
      rowColor: Colors.transparent,
      oddRowColor: AppColors.primary.withValues(alpha: 0.05),
      evenRowColor: Colors.transparent,
      activatedColor: AppColors.primary.withValues(alpha: 0.1),
      gridBorderColor: dividerColor,
      borderColor: dividerColor,
      columnTextStyle: TextStyle(
        color: textPrimary,
        fontWeight: FontWeight.bold,
        fontSize: 13,
      ),
      cellTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 13,
      ),
      menuBackgroundColor: isDark ? const Color(0xFF1A1D23) : Colors.white,
      iconColor: textPrimary,
    );
  }
}
