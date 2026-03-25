import 'package:flutter/material.dart';

class AppColors {
  // Clinical Aura Premium Theme
  static const Color background = Color(0xFFF8F9FE); // ultra-clean light blue-white
  static const Color surface = Colors.white;
  
  // UI Constants
  static const double borderRadius = 20.0;
  static const double cardPadding = 24.0;

  // Text Colors
  static const Color textPrimary = Color(0xFF0F172A); // Slate 900
  static const Color textSecondary = Color(0xFF64748B); // Slate 500
  static const Color textTertiary = Color(0xFF94A3B8); // Slate 400
  
  // Accents (Electric Palette)
  static const Color primary = Color(0xFF2D5BFF); // Electric Blue
  static const Color secondary = Color(0xFF6366F1); // Indigo
  static const Color accent = Color(0xFF8B5CF6); // Violet
  
  static const Color success = Color(0xFF10B981); // Emerald
  static const Color warning = Color(0xFFF59E0B); // Amber
  static const Color error = Color(0xFFEF4444); // Rose
  
  // Translucency (Frosted Glass)
  static const Color glassBorder = Color(0x1F7A7A7A); // Neutral 12% 
  static const Color glassSurface = Color.fromRGBO(255, 255, 255, 0.7);

  // Premium Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF2D5BFF), Color(0xFF6366F1)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient auraGradient = LinearGradient(
    colors: [Color(0xFF2D5BFF), Color(0xFF64748B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient meshGradient = LinearGradient(
    colors: [
      Color(0xFF2D5BFF),
      Color(0xFF6366F1),
      Color(0xFF8B5CF6),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static List<BoxShadow> softShadow = [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.04),
      blurRadius: 20,
      offset: const Offset(0, 10),
    ),
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.02),
      blurRadius: 5,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> primaryGlow = [
    BoxShadow(
      color: primary.withValues(alpha: 0.25),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];
}
