import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _startBackgroundRefresh();
  }

  void _startBackgroundRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
       final count = await DatabaseHelper.instance.getPendingBranchOrdersCount();
       if (mounted && count != _pendingTelegramOrders) {
         if (count > _pendingTelegramOrders) {
           _playVoiceAlert("Yangi buyurtma keldi");
           AppNotifications.showInfo(context, "Yangi Telegram buyurtmasi qabul qilindi!");
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
          body: Stack(
            children: [
              Container(color: Theme.of(context).scaffoldBackgroundColor),
              Row(
                children: [
                  SizedBox(
                    width: 260,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        border: const Border(right: BorderSide(color: AppColors.glassBorder)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 10,
                            offset: const Offset(4, 0),
                          )
                        ],
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              children: [
                                Image.asset('assets/logo.png', width: 100, height: 100),
                                const SizedBox(height: 12),
                                Text(
                                  t.text('title_app'), 
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
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
                            padding: const EdgeInsets.all(16.0),
                            child: _SidebarItem(
                              icon: Icons.logout_rounded, 
                              label: t.text('menu_logout'), 
                              isActive: false,
                              onTap: () {
                                Provider.of<AuthProvider>(context, listen: false).logout();
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(builder: (c) => const SplashScreen()),
                                  (route) => false,
                                );
                              },
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
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, myscrollController) {
             final t = Provider.of<AppTranslations>(context);
             return GlassContainer(
               padding: const EdgeInsets.all(20),
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                    Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 16),
                    Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Expanded(
                      child: items.isEmpty 
                      ? Center(child: Text(t.text('msg_no_data')))
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: const Border(top: BorderSide(color: AppColors.glassBorder)),
      ),
      child: Row(
        children: [
          StatusIndicator(label: t.text('menu_database').toUpperCase(), status: "SQLite", icon: Icons.storage_rounded, color: Colors.blue),
          const SizedBox(width: 24),
          GestureDetector(
            onTap: () {
              SyncService().startSync();
              AppNotifications.showInfo(context, t.text('msg_loading'));
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
          Text(t.text('system_active'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
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
                     padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                     borderRadius: 30,
                     child: Row(
                       children: [
                         const Icon(Icons.search, size: 20, color: Colors.grey),
                         const SizedBox(width: 8),
                         Text(t.text('search_hint'), style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.bold)),
                       ],
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
              margin: const EdgeInsets.only(bottom: 24),
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: Theme.of(context).brightness == Brightness.dark 
                    ? [const Color(0xFF2C3E50), const Color(0xFF000000)]
                    : [const Color(0xFF6A11CB), const Color(0xFF2575FC)]
                ), 
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: AppColors.primary.withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, 10))
                ]
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: Colors.white, size: 20), 
                      const SizedBox(width: 12), 
                      Text(t.text('ai_predictor_title'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), 
                      const Spacer(), 
                      Text("${_aiPredictions.length} ${t.text('ai_risk_count')}", style: const TextStyle(color: Colors.white70, fontSize: 12))
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 100,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _aiPredictions.length,
                      separatorBuilder: (c,i) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                         final item = _aiPredictions[index];
                         final isStatic = item['reason'] == 'low_stock_static';
                         final color = isStatic ? Colors.orangeAccent : Colors.redAccent;

                         return Container(
                           width: 180, 
                           padding: const EdgeInsets.all(12), 
                           decoration: BoxDecoration(
                             color: Colors.white.withValues(alpha: 0.1), 
                             borderRadius: BorderRadius.circular(16),
                             border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                           ), 
                           child: Column(
                             crossAxisAlignment: CrossAxisAlignment.start, 
                             mainAxisAlignment: MainAxisAlignment.center, 
                             children: [
                               Text(item['name'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis), 
                               const SizedBox(height: 4),
                               Row(
                                 children: [
                                   Icon(isStatic ? Icons.warning_amber_rounded : Icons.trending_down_rounded, size: 14, color: color),
                                   const SizedBox(width: 6),
                                   Text(
                                     isStatic ? "${item['current_stock']} ${item['unit']}" : "${item['days_left']} ${t.text('ai_days_left')}", 
                                     style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)
                                   ),
                                 ],
                               ),
                               Text(
                                 isStatic ? t.text('status_critical') : t.text('ai_daily_use').replaceAll('{}', item['daily_use']), 
                                 style: const TextStyle(color: Colors.white60, fontSize: 10)
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
             Container(
               margin: const EdgeInsets.only(bottom: 32),
               padding: const EdgeInsets.all(24),
               decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.primary.withValues(alpha: 0.1))),
               child: Row(children: [
                 Expanded(child: _TodayStatItem(
                   label: t.text('dash_income'), 
                   value: "${_formatNum(_todayStats['in_count'])} ${t.text('unit_items')}", 
                   subvalue: "${_formatNum(_todayStats['in_sum'])} ${t.text('unit_currency')}", 
                   icon: Icons.arrow_downward_rounded, 
                   color: Colors.green
                 )),
                 Expanded(child: _TodayStatItem(
                   label: t.text('dash_outcome'), 
                   value: "${_formatNum(_todayStats['out_count'])} ${t.text('unit_items')}", 
                   subvalue: t.text('dash_distributed'), 
                   icon: Icons.arrow_upward_rounded, 
                   color: Colors.orange
                 )),
                 Expanded(child: _TodayStatItem(
                   label: t.text('dash_activity'), 
                   value: _formatNum((_todayStats['in_count'] ?? 0) + (_todayStats['out_count'] ?? 0)), 
                   subvalue: t.text('dash_total_ops'), 
                   icon: Icons.timeline, 
                   color: Colors.blue
                 )),
               ]),
             ),
          if (_isLoadingDashboard) const Center(child: CircularProgressIndicator())
          else ...[
            if (_branchAnalytics.isNotEmpty) ...[
              const SizedBox(height: 32),
              SizedBox(height: 150, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: _branchAnalytics.length, separatorBuilder: (c,i)=>const SizedBox(width: 16), itemBuilder: (context, index) {
                final b = _branchAnalytics[index];
                return SizedBox(width: 260, child: GlassContainer(padding: const EdgeInsets.all(16), borderRadius: 20, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(b['branch_name'] ?? 'Filial', style: const TextStyle(fontWeight: FontWeight.bold)), const Divider(), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_BranchSmallStat(label: "Jami", value: "${b['total_orders'] ?? 0}"), _BranchSmallStat(label: "Kutilmoqda", value: "${b['pending_count'] ?? 0}", color: Colors.orange)])])));
              })),
            ],
            const SizedBox(height: 32),
            LayoutBuilder(builder: (context, constraints) {
              final width = constraints.maxWidth;
              return Wrap(spacing: 16, runSpacing: 16, children: [
                _FancyStatCard(
                  title: t.text('dash_total_value'), 
                  value: "${_formatNum(_stats['total_value'])} ${t.text('unit_currency')}", 
                  icon: Icons.monetization_on_rounded, 
                  color: Colors.blue, 
                  width: (width - 48)/3
                ),
                _FancyStatCard(
                  title: t.text('dash_low_stock'), 
                  value: _formatNum(_stats['low_stock']), 
                  icon: Icons.warning_rounded, 
                  color: Colors.orange, 
                  width: (width - 48)/3, 
                  onTap: () async { 
                    final items = await DatabaseHelper.instance.getLowStockProducts(); 
                    _showProductList(t.text('dash_low_stock'), items); 
                  }
                ),
                _FancyStatCard(
                  title: t.text('dash_expiring'), 
                  value: _formatNum(_stats['finished']), 
                  icon: Icons.timer_off_rounded, 
                  color: Colors.red, 
                  width: (width - 48)/3, 
                  onTap: () async { 
                    final items = await DatabaseHelper.instance.getFinishedProducts(); 
                    _showProductList(t.text('dash_expiring'), items); 
                  }
                ),
              ]);
            }),
            const SizedBox(height: 32),
            Text(t.text('dash_list_title'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            GlassContainer(padding: const EdgeInsets.all(0), child: Column(children: List.generate(_activities.length, (index) {
                final activity = _activities[index];
                return _ActivityItem(
                  title: activity['product_name'] ?? '', 
                  subtitle: "${activity['quantity'] ?? 0} ${activity['unit'] ?? ''}", 
                  time: activity['date'] ?? '', 
                  icon: activity['type'] == 'IN' ? Icons.arrow_downward : Icons.arrow_upward, 
                  color: activity['type'] == 'IN' ? Colors.green : Colors.orange
                );
            }))),
          ],
        ],
      ),
    );
  }
}

class _FancyStatCard extends StatelessWidget {
  final String title, value; final IconData icon; final Color color; final double width; final VoidCallback? onTap;
  const _FancyStatCard({required this.title, required this.value, required this.icon, required this.color, required this.width, this.onTap});
  @override Widget build(BuildContext context) {
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(24), child: GlassContainer(width: width, padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(icon, color: color)),
        const SizedBox(height: 20),
        Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
    ])));
  }
}

class _ActivityItem extends StatelessWidget {
  final String title, subtitle, time; final IconData icon; final Color color;
  const _ActivityItem({required this.title, required this.subtitle, required this.time, required this.icon, required this.color});
  @override Widget build(BuildContext context) {
    return ListTile(leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.1), child: Icon(icon, color: color, size: 20)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(subtitle), trailing: Text(time, style: TextStyle(color: Colors.grey[500], fontSize: 12)));
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon; final String label; final bool isActive; final VoidCallback onTap; final int badgeCount;
  const _SidebarItem({required this.icon, required this.label, required this.isActive, required this.onTap, this.badgeCount = 0});
  @override Widget build(BuildContext context) {
    final color = isActive ? AppColors.primary : Colors.grey[600];
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: isActive ? AppColors.primary.withValues(alpha: 0.1) : Colors.transparent, borderRadius: BorderRadius.circular(12)), child: Row(children: [Icon(icon, color: color, size: 22), const SizedBox(width: 16), Expanded(child: Text(label, style: TextStyle(color: color, fontWeight: isActive ? FontWeight.bold : FontWeight.w500))), if (badgeCount > 0) Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), child: Text("$badgeCount", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))]))));
  }
}

class _TodayStatItem extends StatelessWidget {
  final String label, value, subvalue; final IconData icon; final Color color;
  const _TodayStatItem({required this.label, required this.value, required this.subvalue, required this.icon, required this.color});
  @override Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(icon, color: color, size: 16), const SizedBox(width: 8), Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12))]), const SizedBox(height: 8), Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text(subvalue, style: TextStyle(color: Colors.grey[400], fontSize: 11))]);
  }
}

class _BranchSmallStat extends StatelessWidget {
  final String label, value; final Color color;
  const _BranchSmallStat({required this.label, required this.value, this.color = Colors.blue});
  @override Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 10)), Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14))]);
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
  final String label, status; final IconData icon; final Color color;
  const StatusIndicator({super.key, required this.label, required this.status, required this.icon, required this.color});
  @override Widget build(BuildContext context) {
    return Row(children: [Icon(icon, color: color, size: 14), const SizedBox(width: 8), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(fontSize: 9, color: Colors.grey[500], fontWeight: FontWeight.bold)), Text(status, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))])]);
  }
}
