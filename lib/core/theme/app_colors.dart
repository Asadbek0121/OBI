import 'package:flutter/material.dart';

class AppColors {
  // Clinical White Theme
  static const Color background = Color(0xFFF5F5F7); // Apple-like off-white
  static const Color surface = Colors.white;
  
  // Text Colors
  static const Color textPrimary = Color(0xFF1D1D1F); // Apple System Black
  static const Color textSecondary = Color(0xFF86868B); // Apple System Gray
  
  // Accents
  static const Color primary = Color(0xFF007AFF); // Apple Blue
  static const Color success = Color(0xFF34C759); // Apple Green
  static const Color warning = Color(0xFFFF9500); // Apple Orange
  static const Color error = Color(0xFFFF3B30); // Apple Red
  
  // Translucency (Frosted Glass)
  static const Color glassBorder = Color(0xFFE5E5EA); // Light border
  static const Color glassSurface = Color.fromRGBO(255, 255, 255, 0.65);
  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF007AFF), Color(0xFF5AC8FA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient orangeGradient = LinearGradient(
    colors: [Color(0xFFFF9500), Color(0xFFFFD60A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient redGradient = LinearGradient(
    colors: [Color(0xFFFF3B30), Color(0xFFFF2D55)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
