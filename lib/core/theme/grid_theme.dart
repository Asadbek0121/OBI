import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'app_colors.dart';

class GridTheme {
  static PlutoGridStyleConfig getStyle(BuildContext context) {
    // final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black87;

    return PlutoGridStyleConfig(
      // Backgrounds
      gridBackgroundColor: Colors.white,
      rowColor: Colors.white,
      oddRowColor: AppColors.primary.withValues(alpha: 0.02),
      evenRowColor: Colors.white,
      activatedColor: AppColors.primary.withValues(alpha: 0.08),
      
      // Borders - subtle
      gridBorderColor: Colors.grey.withValues(alpha: 0.2),
      borderColor: Colors.grey.withValues(alpha: 0.05),
      enableColumnBorderHorizontal: false,
      enableColumnBorderVertical: true,
      enableRowColorAnimation: true,
      
      // Headers
      columnHeight: 52,
      columnTextStyle: TextStyle(
        color: AppColors.primary,
        fontWeight: FontWeight.w600,
        fontSize: 14,
        letterSpacing: 0.5,
      ),
      
      // Cells
      rowHeight: 50,
      cellTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      
      // Icons and UI
      iconColor: AppColors.primary,
      menuBackgroundColor: Colors.white,
      enableGridBorderShadow: true,
    );
  }

  static PlutoGridConfiguration getConfig(BuildContext context) {
    return PlutoGridConfiguration(
      style: getStyle(context),
      columnSize: const PlutoGridColumnSizeConfig(
        autoSizeMode: PlutoAutoSizeMode.equal,
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
