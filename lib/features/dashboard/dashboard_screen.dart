import 'package:flutter/material.dart';
import '../../main.dart';
import 'package:provider/provider.dart';
import '../../core/widgets/liquid_glass.dart';
import '../../core/widgets/glass_container.dart';
import '../../core/theme/app_colors.dart';
import '../../core/localization/app_translations.dart';
import '../inventory/ui/inventory_view.dart';
import '../settings/settings_view.dart';
import '../stock_in/stock_in_view.dart';
import '../stock_out/stock_out_view.dart';
import '../database/product_database_view.dart';
import '../assets/assets_view.dart';
import '../reports/reports_view.dart';
import '../contracts/contracts_view.dart';
import '../../core/database/database_helper.dart';
import '../../core/services/auth_provider.dart';
import 'package:intl/intl.dart';
import '../splash/splash_screen.dart';
import '../../core/utils/app_notifications.dart';
import '../../core/widgets/global_search_modal.dart';
import 'package:flutter/services.dart';
import '../telegram/telegram_orders_view.dart';
import 'dart:async';
import 'dart:io';
import 'package:window_manager/window_manager.dart';
import '../../core/widgets/window_buttons.dart';
import '../../core/services/sync_service.dart';
import '../../core/services/notification_provider.dart';
import '../../core/services/profile_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as p;
import '../../core/services/telegram_service.dart';
import '../../core/widgets/app_dialogs.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ScrollController _sidebarController = ScrollController();
  int _selectedIndex = 0;
  bool _isLoadingDashboard = true;
  Map<String, dynamic> _stats = {'total_value': 0.0, 'low_stock': 0, 'finished': 0};
  List<Map<String, dynamic>> _activities = [];

  Map<String, dynamic> _todayStats = {}; 
  List<Map<String, dynamic>> _aiPredictions = []; 
  List<Map<String, dynamic>> _branchAnalytics = [];
  int _pendingTelegramOrders = 0;
  Timer? _refreshTimer;

  void _openDatabaseFolder() async {
    final path = await DatabaseHelper.instance.getConfiguredPath();
    if (path == null) return;
    
    final directory = p.dirname(path);
    final uri = Uri.file(directory);
    
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
         AppNotifications.showError(context, "Papkani ochib bo'lmadi: $directory");
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _startBackgroundRefresh();
    // 🛡️ SECURITY/UX FIX: Auto-start cloud sync if configured
    SyncService().init(autoStart: true);
    // 🤖 Heartbeat for Telegram Bot (Device Separation)
    TelegramService().startHeartbeat();
  }

  void _startBackgroundRefresh() {
    final t = Provider.of<AppTranslations>(context, listen: false);
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
       final count = await DatabaseHelper.instance.getPendingBranchOrdersCount();
       if (mounted && count != _pendingTelegramOrders) {
         if (count > _pendingTelegramOrders) {
           _playVoiceAlert(t.text('notif_new_order'));
           AppNotifications.showInfo(context, t.text('msg_new_order_telegram'));
         }
         setState(() => _pendingTelegramOrders = count);
       }
       if (_selectedIndex == 0) _loadDashboardData(); 
    });
    DatabaseHelper.instance.getPendingBranchOrdersCount().then((count) {
       if (mounted) setState(() => _pendingTelegramOrders = count);
    });
  }

  void _playVoiceAlert(String text) {
    if (Platform.isMacOS) {
      Process.run('say', [text]);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _sidebarController.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    final t = Provider.of<AppTranslations>(context, listen: false);
    if (mounted) setState(() => _isLoadingDashboard = true);
    try {
      await _loadDashboardData();
      await SyncService().startSync();
      if (mounted) {
        AppNotifications.showInfo(context, t.text('msg_saved'));
      }
    } catch (e) {
      if (mounted) {
        AppNotifications.showError(context, "${t.text('msg_error')}: $e");
      }
    } finally {
      if (mounted) setState(() => _isLoadingDashboard = false);
    }
  }

  Future<void> _loadDashboardData() async {
    try {
      final stats = await DatabaseHelper.instance.getDashboardStats();
      final activities = await DatabaseHelper.instance.getRecentActivity();
      final today = await DatabaseHelper.instance.getDashboardStatusToday();
      final predictions = await DatabaseHelper.instance.getAiPredictions(); 
      final analytics = await DatabaseHelper.instance.getBranchAnalytics();

      if (mounted) {
        setState(() {
          _stats = stats;
          _activities = activities;
          _todayStats = today;
          _aiPredictions = predictions;
          _branchAnalytics = analytics;
          _isLoadingDashboard = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading dashboard data: $e");
    }
  }

  String _formatNum(dynamic value) {
    if (value == null) return "0";
    final formatter = NumberFormat.decimalPattern('en_US');
    return formatter.format(value).replaceAll(',', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<AppTranslations>(context);
    
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () => GlobalSearchModal.show(context),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => GlobalSearchModal.show(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: LiquidBackground(
            child: Stack(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 260,
                      child: Container(
                        decoration: const BoxDecoration(
                          border: Border(right: BorderSide(color: AppColors.glassBorder, width: 0.5)),
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                              child: Column(
                                children: [
                                Image.asset('assets/logo.png', width: 120, height: 120, fit: BoxFit.contain),
                                const SizedBox(height: 16),
                                Text(
                                  t.text('title_app'), 
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Scrollbar(
                              controller: _sidebarController,
                              child: ListView(
                                controller: _sidebarController,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                children: [
                                  _SidebarItem(
                                    icon: Icons.dashboard_rounded, 
                                    label: t.text('menu_dashboard'), 
                                    isActive: _selectedIndex == 0,
                                    onTap: () {
                                      setState(() => _selectedIndex = 0);
                                      _loadDashboardData(); 
                                    },
                                  ),
                                  _SidebarItem(
                                    icon: Icons.inventory_2_rounded, 
                                    label: t.text('menu_inventory'), 
                                    isActive: _selectedIndex == 1,
                                    onTap: () => setState(() => _selectedIndex = 1),
                                  ),
                                  _SidebarItem(
                                    icon: Icons.storage_rounded, 
                                    label: t.text('menu_database'), 
                                    isActive: _selectedIndex == 2,
                                    onTap: () => setState(() => _selectedIndex = 2),
                                  ),
                                  _SidebarItem(
                                    icon: Icons.add_circle_outline_rounded, 
                                    label: t.text('menu_in'), 
                                    isActive: _selectedIndex == 3,
                                    onTap: () => setState(() => _selectedIndex = 3),
                                  ),
                                  _SidebarItem(
                                    icon: Icons.remove_circle_outline_rounded, 
                                    label: t.text('menu_out'), 
                                    isActive: _selectedIndex == 4,
                                    onTap: () => setState(() => _selectedIndex = 4),
                                  ),
                                  _SidebarItem(
                                    icon: Icons.devices_other_rounded, 
                                    label: t.text('menu_assets'), 
                                    isActive: _selectedIndex == 5,
                                    onTap: () => setState(() => _selectedIndex = 5),
                                  ),
                                  _SidebarItem(
                                    icon: Icons.analytics_rounded, 
                                    label: t.text('menu_reports'), 
                                    isActive: _selectedIndex == 6,
                                    onTap: () => setState(() => _selectedIndex = 6),
                                  ),
                                  _SidebarItem(
                                    icon: Icons.smart_toy_rounded, 
                                    label: t.text('menu_telegram'),
                                    isActive: _selectedIndex == 8,
                                    badgeCount: _pendingTelegramOrders,
                                    onTap: () => setState(() => _selectedIndex = 8),
                                  ),
                                   _SidebarItem(
                                    icon: Icons.description_rounded, 
                                    label: t.text('menu_contracts'), 
                                    isActive: _selectedIndex == 9,
                                    onTap: () => setState(() => _selectedIndex = 9),
                                  ),
                                  _SidebarItem(
                                    icon: Icons.settings_rounded, 
                                    label: t.text('menu_settings'), 
                                    isActive: _selectedIndex == 7,
                                    onTap: () => setState(() => _selectedIndex = 7),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Consumer<ProfileProvider>(
                              builder: (context, profile, _) => InkWell(
                                onTap: () => setState(() => _selectedIndex = 7),
                                borderRadius: BorderRadius.circular(24),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(alpha: 0.1),
                                          shape: BoxShape.circle,
                                          image: profile.imagePath != null
                                              ? DecorationImage(
                                                  image: profile.imagePath!.contains('http')
                                                      ? NetworkImage(profile.imagePath!) as ImageProvider
                                                      : FileImage(File(profile.imagePath!)),
                                                  fit: BoxFit.cover,
                                                  onError: (exception, stackTrace) {
                                                    debugPrint("❌ Dashboard: Image load error: $exception");
                                                  },
                                                )
                                              : null,
                                        ),
                                        child: profile.imagePath == null
                                            ? Icon(Icons.person_rounded, color: AppColors.primary, size: 20)
                                            : null,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              profile.name,
                                              style: const TextStyle(
                                                fontSize: 12.5, 
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: -0.3,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Text(
                                              profile.email,
                                              style: TextStyle(
                                                fontSize: 10, 
                                                color: AppColors.textSecondary.withValues(alpha: 0.6),
                                                fontWeight: FontWeight.w500,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                            child: InkWell(
                              onTap: () async {
                                final confirmed = await AppDialogs.showConfirmDialog(
                                  context: context,
                                  title: t.text("confirm_exit"),
                                  content: t.text("msg_confirm_logout"), // We might need to add this key too, or use the string if it's fine.
                                  confirmText: t.text("btn_confirm"),
                                  cancelText: t.text("btn_cancel"),
                                );
                                if (confirmed != true) return;
                                if (!context.mounted) return;
                                
                                await context.read<AuthProvider>().logout();
                                if (!context.mounted) return;
                                
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(builder: (c) => const SplashScreen()),
                                  (route) => false,
                                );
                              },
                              borderRadius: BorderRadius.circular(50),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(50),
                                  border: Border.all(color: Colors.grey.shade300, width: 1),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.logout_rounded, color: Color(0xFF475569), size: 22),
                                    const SizedBox(width: 12),
                                    Text(
                                      t.text('menu_logout'), 
                                      style: const TextStyle(
                                        color: Color(0xFF475569), 
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        if (!Platform.isMacOS)
                          SizedBox(
                            height: 40,
                            child: Row(
                              children: [
                                Expanded(
                                  child: DragToMoveArea(
                                    child: Container(color: Colors.transparent),
                                  ),
                                ),
                                const WindowButtons(),
                                const SizedBox(width: 8),
                              ],
                            ),
                          ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: _buildContent(),
                          ),
                        ),
                        _buildStatusBar(),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  void _showNotificationCenter(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.1),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final provider = Provider.of<NotificationProvider>(context);
            final t = Provider.of<AppTranslations>(context, listen: false);

            return Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 80, right: 24),
                child: Material(
                  color: Colors.transparent,
                  child: GlassContainer(
                    width: 400,
                    height: 500,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(t.text('notif_title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            if (provider.unreadCount > 0)
                              TextButton(
                                onPressed: () => provider.markAllAsRead(),
                                child: Text(t.text('notif_mark_all'), style: const TextStyle(fontSize: 12)),
                              ),
                          ],
                        ),
                        const Divider(),
                        Expanded(
                          child: provider.notifications.isEmpty
                              ? Center(child: Text(t.text('notif_no_data'), style: const TextStyle(color: Colors.grey)))
                              : ListView.separated(
                                  itemCount: provider.notifications.length,
                                  separatorBuilder: (c, i) => const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final n = provider.notifications[index];
                                    return InkWell(
                                      onTap: () {
                                        if (!n.isRead) provider.markAsRead(n.id!);
                                      },
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: n.isRead ? Colors.transparent : Colors.blue.withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: n.isRead ? Colors.grey.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.2)),
                                        ),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: _getNotifColor(n.type).withValues(alpha: 0.1),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(_getNotifIcon(n.type), color: _getNotifColor(n.type), size: 16),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(n.title, style: TextStyle(fontWeight: n.isRead ? FontWeight.normal : FontWeight.bold, fontSize: 13)),
                                                  const SizedBox(height: 2),
                                                  Text(n.message, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    DateFormat('dd.MM.yyyy HH:mm').format(n.createdAt),
                                                    style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (!n.isRead)
                                              const CircleAvatar(radius: 4, backgroundColor: Colors.blue),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Color _getNotifColor(String type) {
    switch (type) {
      case 'success': return Colors.green;
      case 'error': return Colors.red;
      case 'warning': return Colors.orange;
      default: return Colors.blue;
    }
  }

  IconData _getNotifIcon(String type) {
    switch (type) {
      case 'success': return Icons.check_circle_rounded;
      case 'error': return Icons.error_rounded;
      case 'warning': return Icons.warning_rounded;
      default: return Icons.info_rounded;
    }
  }

  void _showProductList(String title, List<Map<String, dynamic>> items) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: items.isEmpty ? 0.3 : 0.6,
          minChildSize: 0.2,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, myscrollController) {
             final t = Provider.of<AppTranslations>(context);
             return GlassContainer(
               padding: const EdgeInsets.all(24),
               opacity: 0.5,
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 mainAxisSize: MainAxisSize.max,
                 children: [
                    Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 16),
                    Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Flexible(
                      child: items.isEmpty 
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.withValues(alpha: 0.3)),
                              const SizedBox(height: 12),
                              Text(t.text('msg_no_data'), style: const TextStyle(color: Colors.grey)),
                            ],
                          )
                        )
                        : ListView.separated(
                            controller: myscrollController,
                            itemCount: items.length,
                            separatorBuilder: (c, i) => const Divider(),
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(item['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(item['unit'] ?? ''),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: (item['stock'] == 0) ? AppColors.error : AppColors.warning,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    "${item['stock']} ${item['unit']}",
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              );
                            },
                        ),
                    ),
                 ],
               ),
             );
          },
        );
      },
    );
  }

  Widget _buildStatusBar() {
    final t = Provider.of<AppTranslations>(context);
    return GlassContainer(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      borderRadius: 0,
      opacity: 0.02,
      child: Row(
        children: [
          StatusIndicator(
            label: t.text('menu_database').toUpperCase(), 
            status: "SQLite", 
            icon: Icons.storage_rounded, 
            color: Colors.blue,
            onTap: _openDatabaseFolder,
          ),
          const SizedBox(width: 24),
          GestureDetector(
            onTap: () {
              if (SyncService().currentStatus == "Error") {
                 scaffoldMessengerKey.currentState?.showSnackBar(
                   SnackBar(
                    content: Text("Sync Error: ${SyncService().lastError}"),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 10),
                   )
                 );
              } else {
                 SyncService().startSync();
                 AppNotifications.showInfo(context, t.text('msg_loading'));
              }
            },
            child: StreamBuilder<String>(
              stream: SyncService().syncStatusStream,
              initialData: SyncService().currentStatus,
              builder: (context, snapshot) {
                final status = snapshot.data ?? "Disconnected";
                Color color = Colors.grey;
                IconData icon = Icons.cloud_off_rounded;
                if (status == "Synced") { color = Colors.green; icon = Icons.cloud_done_rounded; }
                else if (status == "Syncing...") { color = Colors.orange; icon = Icons.sync; }
                else if (status == "Error") { color = Colors.red; icon = Icons.cloud_off_rounded; }
                return StatusIndicator(label: "CLOUD", status: status == "Synced" ? "Supabase Synced" : status, icon: icon, color: color);
              },
            ),
          ),
          const Spacer(),
          const Icon(Icons.circle, color: AppColors.success, size: 8),
          const SizedBox(width: 8),
          Text(t.text('system_active'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_selectedIndex) {
      case 0: return _buildDashboardView();
      case 1: return const InventoryView();
      case 2: return const ProductDatabaseView();
      case 3: return const StockInView();
      case 4: return const StockOutView();
      case 5: return const AssetsView();
      case 6: return const ReportsView();
      case 7: return const SettingsView();
      case 8: return const TelegramManagementView();
      case 9: return const ContractsView();
      default: return _buildDashboardView();
    }
  }

  Widget _buildDashboardView() {
    final t = Provider.of<AppTranslations>(context);
    final notifProvider = Provider.of<NotificationProvider>(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.text('text_welcome'), style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                  Text(t.text('menu_dashboard'), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                ],
              ),
              Row(
                children: [
                   GlassContainer(
                     onTap: () => GlobalSearchModal.show(context),
                     padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                     borderRadius: 30,
                     child: IntrinsicWidth(
                       child: Row(
                         children: [
                           const Icon(Icons.search_rounded, size: 20, color: AppColors.primary),
                           const SizedBox(width: 12),
                           Text(
                             t.text('search_hint').replaceAll('(Cmd+K)', '').trim(),
                             style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w700),
                           ),
                           const SizedBox(width: 20),
                           Container(
                             padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                             decoration: BoxDecoration(
                               color: AppColors.primary.withValues(alpha: 0.1),
                               borderRadius: BorderRadius.circular(20),
                             ),
                             child: const Text(
                               "CMD+K",
                               style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.primary, letterSpacing: 0.5),
                             ),
                           ),
                         ],
                       ),
                     ),
                   ),
                   const SizedBox(width: 12),
                   Stack(
                     children: [
                       GlassContainer(
                         onTap: () => _showNotificationCenter(context),
                         padding: const EdgeInsets.all(10),
                         borderRadius: 30,
                         child: Icon(notifProvider.unreadCount > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded, size: 20, color: notifProvider.unreadCount > 0 ? Colors.orange : Colors.grey),
                       ),
                       if (notifProvider.unreadCount > 0)
                         Positioned(
                           right: 0, top: 0,
                           child: Container(
                             padding: const EdgeInsets.all(4),
                             decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                             constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                             child: Text("${notifProvider.unreadCount}", style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                           ),
                         ),
                     ],
                   ),
                   const SizedBox(width: 12),
                   GlassContainer(onTap: _refreshAll, padding: const EdgeInsets.all(10), borderRadius: 30, child: const Icon(Icons.refresh_rounded, size: 20, color: AppColors.primary)),
                   const SizedBox(width: 12),
                   GlassContainer(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), borderRadius: 30, child: const _HeaderClock()),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          if (!_isLoadingDashboard && _aiPredictions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 32),
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: AppColors.auraGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 30, offset: const Offset(0, 15))
                ]
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 16),
                      Text(t.text('ai_predictor_title'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: 0.5)),
                      const Spacer(),
                      GlassContainer(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        borderRadius: 12,
                        opacity: 0.2,
                        child: Text("${_aiPredictions.length} ${t.text('ai_risk_count')}", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 120,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _aiPredictions.length,
                      separatorBuilder: (c,i) => const SizedBox(width: 16),
                      itemBuilder: (context, index) {
                         final item = _aiPredictions[index];
                         final isStatic = item['reason'] == 'low_stock_static';
                         final color = isStatic ? const Color(0xFFFFD60A) : const Color(0xFFFF375F);

                         return Container(
                           width: 220,
                           padding: const EdgeInsets.all(16),
                           decoration: BoxDecoration(
                             color: Colors.white.withValues(alpha: 0.1),
                             borderRadius: BorderRadius.circular(20),
                             border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                           ),
                           child: Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             mainAxisAlignment: MainAxisAlignment.center,
                             children: [
                               Text(item['name'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                               const Spacer(),
                               Row(
                                 children: [
                                   Container(
                                     padding: const EdgeInsets.all(4),
                                     decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle),
                                     child: Icon(isStatic ? Icons.warning_amber_rounded : Icons.trending_down_rounded, size: 14, color: color),
                                   ),
                                   const SizedBox(width: 8),
                                   Text(
                                     isStatic ? "${item['current_stock']} ${item['unit']}" : "${item['days_left']} ${t.text('ai_days_left')}",
                                     style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900)
                                   ),
                                 ],
                               ),
                               const SizedBox(height: 4),
                               Text(
                                 isStatic ? t.text('status_critical') : t.text('ai_daily_use').replaceAll('{}', item['daily_use']),
                                 style: const TextStyle(color: Colors.white70, fontSize: 11)
                               ),
                             ],
                           ),
                         );
                      },
                    ),
                  ),
                ],
              ),
            ),
          if (!_isLoadingDashboard && _todayStats.isNotEmpty)
             GlassContainer(
               padding: const EdgeInsets.all(24),
               borderRadius: 24,
               opacity: 0.03,
               child: Row(children: [
                 Expanded(child: _TodayStatItem(
                   label: t.text('dash_income'),
                   value: _formatNum(_todayStats['in_count']),
                   subvalue: "${_formatNum(_todayStats['in_sum'])} ${t.text('unit_currency')}",
                   icon: Icons.south_west_rounded,
                   color: AppColors.success
                 )),
                 _StatDivider(),
                 Expanded(child: _TodayStatItem(
                   label: t.text('dash_outcome'),
                   value: _formatNum(_todayStats['out_count']),
                   subvalue: t.text('dash_distributed'),
                   icon: Icons.north_east_rounded,
                   color: AppColors.warning
                 )),
                 _StatDivider(),
                 Expanded(child: _TodayStatItem(
                   label: t.text('dash_activity'),
                   value: _formatNum((_todayStats['in_count'] ?? 0) + (_todayStats['out_count'] ?? 0)),
                   subvalue: t.text('dash_total_ops'),
                   icon: Icons.bolt_rounded,
                   color: AppColors.primary
                 )),
               ]),
             ),
          if (_isLoadingDashboard) const Center(child: CircularProgressIndicator())
          else ...[
            if (_branchAnalytics.isNotEmpty) ...[
              const SizedBox(height: 32),
              SizedBox(height: 160, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: _branchAnalytics.length, separatorBuilder: (c,i)=>const SizedBox(width: 20), itemBuilder: (context, index) {
                final b = _branchAnalytics[index];
                return SizedBox(width: 280, child: GlassContainer(padding: const EdgeInsets.all(20), borderRadius: 24, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(b['branch_name'] ?? 'Filial', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), const Spacer(), const Divider(height: 32), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_BranchSmallStat(label: "Jami", value: "${b['total_orders'] ?? 0}"), _BranchSmallStat(label: "Kutilmoqda", value: "${b['pending_count'] ?? 0}", color: AppColors.warning)])])));
              })),
            ],
            const SizedBox(height: 40),
            LayoutBuilder(builder: (context, constraints) {
              final width = constraints.maxWidth;
              return Wrap(spacing: 20, runSpacing: 20, children: [
                _FancyStatCard(
                  title: t.text('dash_total_value'),
                  value: "${_formatNum(_stats['total_value'])} ${t.text('unit_currency')}",
                  icon: Icons.account_balance_wallet_rounded,
                  color: AppColors.primary,
                  width: (width - 40)/3
                ),
                _FancyStatCard(
                  title: t.text('dash_low_stock'),
                  value: _formatNum(_stats['low_stock']),
                  icon: Icons.analytics_rounded,
                  color: AppColors.warning,
                  width: (width - 40)/3,
                  onTap: () async {
                    final items = await DatabaseHelper.instance.getLowStockProducts();
                    _showProductList(t.text('dash_low_stock'), items);
                  }
                ),
                _FancyStatCard(
                  title: t.text('dash_expiring'),
                  value: _formatNum(_stats['finished']),
                  icon: Icons.timer_off_rounded,
                  color: AppColors.error,
                  width: (width - 40)/3,
                  onTap: () async {
                    final items = await DatabaseHelper.instance.getFinishedProducts();
                    _showProductList(t.text('dash_expiring'), items);
                  }
                ),
              ]);
            }),
            const SizedBox(height: 48),
            Row(
              children: [
                Container(width: 4, height: 24, decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 12),
                Text(t.text('dash_list_title'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 24),
            GlassContainer(
              padding: const EdgeInsets.all(0),
              child: Column(children: List.generate(_activities.length, (index) {
                final activity = _activities[index];
                return Column(
                  children: [
                    _ActivityItem(
                      title: activity['product_name'] ?? '',
                      subtitle: "${activity['quantity'] ?? 0} ${activity['unit'] ?? ''}",
                      time: activity['date'] ?? '',
                      icon: activity['type'] == 'IN' ? Icons.add_rounded : Icons.remove_rounded,
                      color: activity['type'] == 'IN' ? AppColors.success : AppColors.warning
                    ),
                    if (index < _activities.length - 1)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Divider(color: AppColors.glassBorder.withValues(alpha: 0.1), height: 1),
                      ),
                  ],
                );
            }))),
          ],
        ],
      ),
    );
  }
}

class _FancyStatCard extends StatefulWidget {
  final String title, value; final IconData icon; final Color color; final double width; final VoidCallback? onTap;
  const _FancyStatCard({required this.title, required this.value, required this.icon, required this.color, required this.width, this.onTap});

  @override
  State<_FancyStatCard> createState() => _FancyStatCardState();
}

class _FancyStatCardState extends State<_FancyStatCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(24),
          child: GlassContainer(
            width: widget.width,
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                      child: Icon(widget.icon, color: widget.color, size: 24)
                    ),
                    if (widget.onTap != null)
                      Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textTertiary.withValues(alpha: 0.5)),
                  ],
                ),
                const SizedBox(height: 32),
                Text(widget.title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(widget.value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -1)),
              ]
            )
          )
        ),
      ),
    );
  }
}

class _ActivityItem extends StatelessWidget {
  final String title, subtitle, time; final IconData icon; final Color color;
  const _ActivityItem({required this.title, required this.subtitle, required this.time, required this.icon, required this.color});
  @override Widget build(BuildContext context) {
    return ListTile(leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.1), child: Icon(icon, color: color, size: 20)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(subtitle), trailing: Text(time, style: TextStyle(color: Colors.grey[500], fontSize: 12)));
  }
}

class _SidebarItem extends StatefulWidget {
  final IconData icon; final String label; final bool isActive; final VoidCallback onTap; final int badgeCount;
  const _SidebarItem({required this.icon, required this.label, required this.isActive, required this.onTap, this.badgeCount = 0});

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.isActive ? AppColors.primary : AppColors.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(28),
            bottomRight: Radius.circular(28),
            bottomLeft: Radius.circular(8),
          ),
          child: GlassContainer(
            showBorder: true,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
              bottomRight: Radius.circular(28),
              bottomLeft: Radius.circular(8),
            ),
            opacity: widget.isActive ? 0.35 : 0.15,
            blur: 25,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                AnimatedScale(
                  scale: widget.isActive || _isHovered ? 1.1 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(widget.icon, color: color, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: widget.isActive ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ),
                if (widget.badgeCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(color: AppColors.error.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 2))
                      ],
                    ),
                    child: Text(
                      "${widget.badgeCount}",
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                    ),
                  ),
                if (widget.isActive)
                  Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(color: AppColors.primary.withValues(alpha: 0.5), blurRadius: 4)
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            AppColors.glassBorder.withValues(alpha: 0.1),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

class _TodayStatItem extends StatelessWidget {
  final String label, value, subvalue; final IconData icon; final Color color;
  const _TodayStatItem({required this.label, required this.value, required this.subvalue, required this.icon, required this.color});
  @override Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, 
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 14),
            ),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 12),
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        Text(subvalue, style: const TextStyle(color: AppColors.textTertiary, fontSize: 12, fontWeight: FontWeight.w400)),
      ],
    );
  }
}

class _BranchSmallStat extends StatelessWidget {
  final String label, value; final Color color;
  const _BranchSmallStat({required this.label, required this.value, this.color = AppColors.primary});
  @override Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: AppColors.textTertiary, fontSize: 10)), Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 15))]);
  }
}

class _HeaderClock extends StatefulWidget {
  const _HeaderClock();
  @override State<_HeaderClock> createState() => _HeaderClockState();
}

class _HeaderClockState extends State<_HeaderClock> {
  late Timer _timer;
  @override void initState() { super.initState(); _timer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() {})); }
  @override void dispose() { _timer.cancel(); super.dispose(); }
  @override Widget build(BuildContext context) {
    return Text(DateFormat('dd.MM.yyyy HH:mm:ss').format(DateTime.now()), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary));
  }
}

class StatusIndicator extends StatelessWidget {
  final String label, status; 
  final IconData icon; 
  final Color color;
  final VoidCallback? onTap;

  const StatusIndicator({
    super.key, 
    required this.label, 
    required this.status, 
    required this.icon, 
    required this.color,
    this.onTap,
  });

  @override 
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Row(
          children: [
            Icon(icon, color: color, size: 14), 
            const SizedBox(width: 8), 
            Column(
              crossAxisAlignment: CrossAxisAlignment.start, 
              children: [
                Text(label, style: TextStyle(fontSize: 9, color: Colors.grey[500], fontWeight: FontWeight.bold)), 
                Text(status, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))
              ]
            )
          ]
        ),
      ),
    );
  }
}
