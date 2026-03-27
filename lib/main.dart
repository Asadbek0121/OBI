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
import 'core/services/session_timer_service.dart';
import 'features/setup/database_setup_screen.dart';
import 'features/auth/pin_entry_screen.dart';
import 'dart:ui';
import 'package:app_links/app_links.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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
        await syncService.init(autoStart: false);

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
        ChangeNotifierProvider(create: (_) => SessionTimerService()),
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

class _ClinicalWarehouseAppState extends State<ClinicalWarehouseApp> with WindowListener {
  Timer? _updateTimer;
  bool _isClosing = false;
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.setPreventClose(true); // Don't close immediately

    _initDeepLinkListener();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.checkUpdate();
    });
    
    // Check every 5 minutes for updates while app is open
    _updateTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (mounted) UpdateService.checkUpdate();
    });
  }

  void _initDeepLinkListener() {
    _appLinks = AppLinks();
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) async {
       debugPrint("🔗 System: Incoming Deep Link Received: $uri");
       // On Windows, manually handle the link fragments for Supabase to parse session
       if (uri.scheme == 'com.obi.clinicalwarehouse') {
          // Allow Supabase to handle the link (it will trigger onAuthStateChange)
       }
    });
  }

  @override
  void onWindowClose() async {
    if (_isClosing) return;
    _isClosing = true;
    
    // Skip transferring to Cloud (Local bot only)
    try {
      // await TelegramService().setWebhookToCloud();
    } catch (_) {}
    
    await windowManager.destroy(); // Now perform actual exit
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _updateTimer?.cancel();
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final sessionTimer = Provider.of<SessionTimerService>(context);
    final auth = Provider.of<AuthProvider>(context, listen: false);

    // Sync Timer enable status with Auth pin status
    WidgetsBinding.instance.addPostFrameCallback((_) {
       if (auth.isPinEnabled && auth.isLoggedIn) {
          sessionTimer.enable(true);
       } else {
          sessionTimer.enable(false);
       }
    });
    
    return Listener(
      onPointerDown: (_) => sessionTimer.resetTimer(),
      onPointerMove: (_) => sessionTimer.resetTimer(),
      child: MaterialApp(
        scaffoldMessengerKey: scaffoldMessengerKey,
        navigatorKey: navigatorKey,
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
            child: Stack(
              children: [
                child!,
                if (sessionTimer.isLocked && auth.isLoggedIn)
                  Positioned.fill(
                    child: PinEntryScreen(
                       onSuccess: () => sessionTimer.unlock(),
                       onCancel: () {
                         auth.logout();
                         sessionTimer.unlock(); // Dismiss overlay
                         // Force head back to login
                         navigatorKey.currentState?.pushAndRemoveUntil(
                           MaterialPageRoute(builder: (_) => const SplashScreen()),
                           (route) => false,
                         );
                       },
                    ),
                  ),
              ],
            ),
          );
        },
        home: widget.home,
      ),
    );
  }
}

