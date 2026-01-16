import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
// import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme/app_theme.dart';
// import 'app_config.dart';
import 'core/database/database_helper.dart';
import 'core/services/telegram_service.dart';

import 'package:provider/provider.dart';
import 'core/localization/app_translations.dart';
import 'core/theme/theme_provider.dart';
import 'core/services/profile_provider.dart';

import 'features/dashboard/dashboard_screen.dart'; 
import 'features/splash/splash_screen.dart';
import 'core/services/auth_provider.dart';
import 'features/setup/database_setup_screen.dart';

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
    titleBarStyle: TitleBarStyle.hidden, // Use hidden to allow custom window control behavior
  );
  
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // 🌍 LOCALIZATION & THEME INIT
  final appTranslations = AppTranslations();
  await appTranslations.init();
  
  final themeProvider = ThemeProvider();
  await themeProvider.init();
  
  final profileProvider = ProfileProvider();
  await profileProvider.init();

  final authProvider = AuthProvider();
  await authProvider.init();

  // 📂 DB CONFIGURATION CHECK
  final dbPath = await DatabaseHelper.instance.getConfiguredPath();
  Widget startScreen;
  
  if (dbPath == null) {
     // User hasn't picked a DB location yet
     print("⚠️ System: No DB configured. Showing Setup Screen.");
     startScreen = const DatabaseSetupScreen();
  } else {
     // Configured! Proceed with normal boot.
     startScreen = const SplashScreen();
     
    // 🛡️ SECURITY INIT: Open the Secure Vault
    try {
      await DatabaseHelper.instance.database;
      print("✅ System: Secure Database initialized successfully.");
    } catch (e) {
      print("❌ System: Failed to initialize Secure Database: $e");
    }

    // 🤖 TELEGRAM SCHEDULER
    try {
       print("🤖 System: Checking Telegram Backup Schedule...");
       final tgService = TelegramService();
       await tgService.checkWeeklyBackup(DatabaseHelper.instance);
       await tgService.checkDailyLowStockAlert(DatabaseHelper.instance);
    } catch (e) {
       print("❌ System: Telegram Scheduler Error: $e");
    }
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appTranslations),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: profileProvider),
        ChangeNotifierProvider.value(value: authProvider),
      ],
      child: ClinicalWarehouseApp(home: startScreen),
    )
  );
}

class ClinicalWarehouseApp extends StatelessWidget {
  final Widget home;
  const ClinicalWarehouseApp({super.key, required this.home});

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
      home: home,
    );
  }
}

