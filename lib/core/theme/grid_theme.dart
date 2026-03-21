import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'app_colors.dart';

class GridTheme {
  static PlutoGridStyleConfig getStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ?? (isDark ? Colors.white : Colors.black87);
    final surfaceColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return PlutoGridStyleConfig(
      // Backgrounds
      gridBackgroundColor: surfaceColor,
      rowColor: surfaceColor,
      oddRowColor: AppColors.primary.withValues(alpha: isDark ? 0.05 : 0.02),
      evenRowColor: surfaceColor,
      activatedColor: AppColors.primary.withValues(alpha: 0.08),
      
      // Borders
      gridBorderColor: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2),
      borderColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.05),
      enableColumnBorderHorizontal: false,
      enableColumnBorderVertical: true,
      enableRowColorAnimation: true,
      
      // Headers
      columnHeight: 60,
      columnTextStyle: TextStyle(
        color: AppColors.primary,
        fontWeight: FontWeight.w700,
        fontSize: 15,
        letterSpacing: 0.5,
      ),
      
      // Cells
      rowHeight: 52,
      cellTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
      
      // Icons and UI
      iconColor: AppColors.primary,
      menuBackgroundColor: surfaceColor,
      enableGridBorderShadow: !isDark,
    );
  }

  static PlutoGridConfiguration getConfig(BuildContext context) {
    return PlutoGridConfiguration(
      style: getStyle(context),
      columnSize: const PlutoGridColumnSizeConfig(
        autoSizeMode: PlutoAutoSizeMode.scale,
      ),
      scrollbar: const PlutoGridScrollbarConfig(
        isAlwaysShown: true,
        scrollbarThickness: 8,
        scrollbarRadius: Radius.circular(10),
        draggableScrollbar: true,
        hoverWidth: 12,
      ),
    );
  }
}
