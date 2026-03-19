import 'dart:async';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'core/services/update_service.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme/app_theme.dart';
import 'app_config.dart';
import 'core/database/database_helper.dart';
import 'core/services/telegram_service.dart';
import 'core/services/sync_service.dart';

import 'package:provider/provider.dart';
import 'core/localization/app_translations.dart';
import 'core/theme/theme_provider.dart';
import 'core/services/profile_provider.dart';

import 'features/splash/splash_screen.dart';
import 'core/services/auth_provider.dart';
import 'core/services/notification_provider.dart';
import 'features/setup/database_setup_screen.dart';
import 'dart:ui';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ☁️ INITIALIZE SUPABASE
  try {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
    debugPrint("✅ System: Supabase initialized.");
  } catch (e) {
    debugPrint("⚠️ System: Supabase init skipped or failed: $e");
  }

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
     debugPrint("⚠️ System: No DB configured. Showing Setup Screen.");
     startScreen = const DatabaseSetupScreen();
  } else {
     // Configured! Proceed with normal boot.
     startScreen = const SplashScreen();
     
    // 🛡️ SECURITY INIT: Open the Secure Vault
    try {
      await DatabaseHelper.instance.database;
      debugPrint("✅ System: Secure Database initialized successfully.");
    } catch (e) {
      debugPrint("❌ System: Failed to initialize Secure Database: $e");
    }

    // 🤖 TELEGRAM SCHEDULER
    try {
       debugPrint("🤖 System: Checking Telegram Backup Schedule...");
       final tgService = TelegramService();
       
       // Initial Check
       await tgService.checkWeeklyBackup(DatabaseHelper.instance);
       await tgService.checkDailyBackup(DatabaseHelper.instance);
       await tgService.checkHourlyExcelBackup(DatabaseHelper.instance);
       await tgService.checkDailyLowStockAlert(DatabaseHelper.instance);
       await tgService.checkDailyReportAuto(DatabaseHelper.instance);

       // Periodic Check (Every 30 minutes)
       // This ensures if app is left open, it still sends the report at 18:00
       Stream.periodic(const Duration(minutes: 30)).listen((_) async {
          await tgService.checkDailyReportAuto(DatabaseHelper.instance);
          await tgService.checkDailyBackup(DatabaseHelper.instance);
          await tgService.checkHourlyExcelBackup(DatabaseHelper.instance);
       });

       // 🎧 START INTERACTIVE BOT LISTENER
       tgService.startBotListener();

        // 🔄 SYNC SERVICE INIT
        final syncService = SyncService();
        await syncService.init();

    } catch (e) {
       debugPrint("❌ System: Service Initialization Error: $e");
    }
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appTranslations),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: profileProvider),
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ],
      child: ClinicalWarehouseApp(home: startScreen),
    )
  );
}
class ClinicalWarehouseApp extends StatefulWidget {
  final Widget home;
  const ClinicalWarehouseApp({super.key, required this.home});

  @override
  State<ClinicalWarehouseApp> createState() => _ClinicalWarehouseAppState();
}

class _ClinicalWarehouseAppState extends State<ClinicalWarehouseApp> {
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.checkUpdate(context);
    });
    
    // Check every 10 minutes for updates while app is open
    _updateTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      if (mounted) UpdateService.checkUpdate(context);
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      scrollBehavior: AppScrollBehavior(),
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
      home: widget.home,
    );
  }
}

