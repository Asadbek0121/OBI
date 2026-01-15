import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
// import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme/app_theme.dart';
// import 'app_config.dart';
import 'core/services/database_helper.dart';

import 'package:provider/provider.dart';
import 'core/localization/app_translations.dart';
import 'core/theme/theme_provider.dart';
import 'core/services/profile_provider.dart';

// Placeholder for now
import 'features/dashboard/dashboard_screen.dart'; 
import 'features/splash/splash_screen.dart';
import 'core/services/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Window Manager for Desktop
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(1024, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden, // Hides native title bar for custom one
  );
  
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // 🛡️ SECURITY INIT: Open the Secure Vault
  try {
    await DatabaseHelper.instance.database;
    print("✅ System: Secure Database initialized successfully.");
  } catch (e) {
    print("❌ System: Failed to initialize Secure Database: $e");
    // In a real app, show a "Fatal Error" dialog here.
  }

  // 🌍 LOCALIZATION & THEME INIT
  final appTranslations = AppTranslations();
  await appTranslations.init();
  
  final themeProvider = ThemeProvider();
  await themeProvider.init();
  
  final profileProvider = ProfileProvider();
  await profileProvider.init();

  final authProvider = AuthProvider();
  await authProvider.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appTranslations),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: profileProvider),
        ChangeNotifierProvider.value(value: authProvider),
      ],
      child: const ClinicalWarehouseApp(),
    )
  );
}

class ClinicalWarehouseApp extends StatelessWidget {
  const ClinicalWarehouseApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Omborxona Boshqaruv Tizimi',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      builder: (context, child) {
        return AnimatedTheme(
          data: themeProvider.isDarkMode ? AppTheme.darkTheme : AppTheme.lightTheme,
          duration: const Duration(milliseconds: 500),
          child: child!,
        );
      },
      home: const SplashScreen(),
    );
  }
}
