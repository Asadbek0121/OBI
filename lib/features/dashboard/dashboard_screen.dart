import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/widgets/glass_container.dart';
import '../../core/theme/app_colors.dart';
import '../../core/localization/app_translations.dart';
import '../inventory/ui/inventory_view.dart';
// import '../transactions/transactions_view.dart'; // Keeping this for reference, but sidebar uses Input/Output
import '../settings/settings_view.dart';
import '../locations/locations_view.dart';
import '../stock_in/stock_in_view.dart';
import '../stock_out/stock_out_view.dart';
import '../database/product_database_view.dart'; // New Import
import '../input/input_view.dart';
import '../output/output_view.dart';
import '../assets/assets_view.dart';
import '../reports/reports_view.dart';
import '../../core/database/database_helper.dart';
import '../../core/services/auth_provider.dart';
import '../splash/splash_screen.dart';
import '../../core/utils/app_notifications.dart';
import '../../core/widgets/global_search_modal.dart';
import 'package:flutter/services.dart';
import '../telegram/telegram_orders_view.dart';
import 'dart:async';
import 'dart:io';
import 'package:window_manager/window_manager.dart';
import '../../core/widgets/window_buttons.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  bool _isLoadingDashboard = true;
  Map<String, dynamic> _stats = {'total_value': 0.0, 'low_stock': 0, 'finished': 0};
  List<Map<String, dynamic>> _activities = [];

  Map<String, dynamic> _todayStats = {}; 
  List<Map<String, dynamic>> _aiPredictions = []; 
  List<Map<String, dynamic>> _branchAnalytics = []; // New Analytics State
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
    });
    // Initial check
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
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    try {
      final stats = await DatabaseHelper.instance.getDashboardStats();
      final activities = await DatabaseHelper.instance.getRecentActivity();
      final today = await DatabaseHelper.instance.getDashboardStatusToday();
      final predictions = await DatabaseHelper.instance.getAiPredictions(); 
      final analytics = await DatabaseHelper.instance.getBranchAnalytics(); // Fetch Branch Stats

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

// ... (Inside _DashboardScreenState)

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<AppTranslations>(context);
    
    // Global Shortcut Listener
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
                  // Sidebar
                  SizedBox(
                    width: 250,
                    child: GlassContainer(
                      borderRadius: 0,
                      opacity: 0.8,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
                            child: Column(
                              children: [
                                Image.asset('assets/logo.png', width: 100, height: 100),
                                const SizedBox(height: 16),
                                Text(
                                  t.text('title_app'), 
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 18, 
                                    fontWeight: FontWeight.w900,
                                    height: 1.2,
                                     color: Theme.of(context).textTheme.headlineMedium?.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _SidebarItem(
                            icon: Icons.dashboard, 
                            label: t.text('menu_dashboard'), 
                            isActive: _selectedIndex == 0,
                            onTap: () {
                              setState(() => _selectedIndex = 0);
                              _loadDashboardData(); 
                            },
                          ),
                          _SidebarItem(
                            icon: Icons.inventory_2, 
                            label: t.text('menu_inventory'), 
                            isActive: _selectedIndex == 1,
                            onTap: () => setState(() => _selectedIndex = 1),
                          ),
                          _SidebarItem(
                            icon: Icons.storage, 
                            label: t.text('menu_database'), 
                            isActive: _selectedIndex == 2,
                            onTap: () => setState(() => _selectedIndex = 2),
                          ),
                          _SidebarItem(
                            icon: Icons.download, 
                            label: t.text('menu_in'), 
                            isActive: _selectedIndex == 3,
                            onTap: () => setState(() => _selectedIndex = 3),
                          ),
                          _SidebarItem(
                            icon: Icons.upload, 
                            label: t.text('menu_out'), 
                            isActive: _selectedIndex == 4,
                            onTap: () => setState(() => _selectedIndex = 4),
                          ),
                          _SidebarItem(
                            icon: Icons.devices_other, 
                            label: "Jihozlar", 
                            isActive: _selectedIndex == 5,
                            onTap: () => setState(() => _selectedIndex = 5),
                          ),
                          _SidebarItem(
                            icon: Icons.analytics, 
                            label: t.text('menu_reports'), 
                            isActive: _selectedIndex == 6,
                            onTap: () => setState(() => _selectedIndex = 6),
                          ),
                          const Spacer(),
                          
                          _SidebarItem(
                            icon: Icons.settings, 
                            label: t.text('menu_settings'), 
                            isActive: _selectedIndex == 7,
                            onTap: () => setState(() => _selectedIndex = 7),
                          ),
                          
                          _SidebarItem(
                            icon: Icons.smart_toy, 
                            label: "Telegram Bot", 
                            isActive: _selectedIndex == 8,
                            badgeCount: _pendingTelegramOrders,
                            onTap: () => setState(() => _selectedIndex = 8),
                          ),
                          
                          _SidebarItem(
                            icon: Icons.lock, 
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
                        ],
                      ),
                    ),
                  ),

                  // Main Content + Status Bar
                  Expanded(
                    child: Column(
                      children: [
                        // 🖥️ CUSTOM WINDOW TITLE BAR (Windows/Linux)
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
                        ? const Center(child: Text("Ma'lumot topilmadi"))
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: AppColors.glassBorder.withValues(alpha: 0.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Icon(Icons.circle, color: AppColors.success, size: 12),
          const SizedBox(width: 8),
          Text(Provider.of<AppTranslations>(context).text('system_active'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_selectedIndex) {
      case 0:
        return _buildDashboardView();
      case 1:
        return const InventoryView();
      case 2:
        return const ProductDatabaseView();
      case 3:
        return const StockInView();
      case 4:
        return const StockOutView();
      case 5:
        return const AssetsView();
      case 6:
        return const ReportsView();
      case 7:
        return const SettingsView();
      case 8:
        return const TelegramManagementView();
      default:
        return _buildDashboardView();
    }
  }

  // NOTE: I need to update _buildDashboardView to include the search button next to the Date.
  Widget _buildDashboardView() {
    final t = Provider.of<AppTranslations>(context);
    
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
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
                   // Search Button
                   GlassContainer(
                     onTap: () => GlobalSearchModal.show(context),
                     padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                     borderRadius: 30,
                     child: Row(
                       children: [
                         const Icon(Icons.search, size: 20, color: Colors.grey),
                         const SizedBox(width: 8),
                         Text("Qidirish (Cmd+K)", style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.bold)),
                       ],
                     ),
                   ),
                   const SizedBox(width: 16),
                   // Date Badge
                   GlassContainer(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    borderRadius: 30,
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 16, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text(
                          DateTime.now().toString().substring(0, 10), 
                          style: const TextStyle(fontWeight: FontWeight.bold)
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
           const SizedBox(height: 32),
          
          // 🤖 AI PREDICTION CARD (Only shows if there are risks)
          if (!_isLoadingDashboard && _aiPredictions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 24),
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF6A11CB), Color(0xFF2575FC)]), // Purple-Blue AI Theme
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF2575FC).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))
                ]
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                        child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        "AI BASHORATCHI", 
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                        child: Text("${_aiPredictions.length} ta xavf", style: const TextStyle(color: Colors.white, fontSize: 12)),
                      )
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                     "Ushbu mahsulotlar tez orada tugashi kutilmoqda:", 
                     style: TextStyle(color: Colors.white70, fontSize: 13)
                  ),
                  const SizedBox(height: 12),
                  // Horizontal List of Critical Items
                  SizedBox(
                    height: 90,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _aiPredictions.length,
                      separatorBuilder: (c,i) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                         final item = _aiPredictions[index];
                         return Container(
                           width: 160,
                           padding: const EdgeInsets.all(12),
                           decoration: BoxDecoration(
                             color: Colors.white.withOpacity(0.15),
                             borderRadius: BorderRadius.circular(12),
                             border: Border.all(color: Colors.white.withOpacity(0.2))
                           ),
                           child: Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             mainAxisAlignment: MainAxisAlignment.center,
                             children: [
                               Text(item['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                               const SizedBox(height: 4),
                               Row(
                                 children: [
                                   const Icon(Icons.timelapse, color: Colors.orangeAccent, size: 14),
                                   const SizedBox(width: 4),
                                   Text("${item['days_left']} kun qoldi", style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                                 ],
                               ),
                               Text("Zaxira: ${item['current_stock']} ${item['unit']}", style: const TextStyle(color: Colors.white70, fontSize: 11)),
                             ],
                           ),
                         );
                      },
                    ),
                  ),
                ],
              ),
            ),

          // TODAY'S LIVE MONITOR
          if (!_isLoadingDashboard && _todayStats.isNotEmpty)
             Container(
               margin: const EdgeInsets.only(bottom: 32),
               padding: const EdgeInsets.all(24),
               decoration: BoxDecoration(
                 color: AppColors.primary.withOpacity(0.05),
                 borderRadius: BorderRadius.circular(24),
                 border: Border.all(color: AppColors.primary.withOpacity(0.1)),
               ),
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                    Row(
                      children: [
                        const Icon(Icons.bolt, color: Colors.amber, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          "BUGUNGI HOLAT (${DateTime.now().toString().substring(0, 10)})", 
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey[700], letterSpacing: 1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _TodayStatItem(
                            label: "Kirim",
                            value: "${_todayStats['in_count']} ta",
                            subvalue: "${(_todayStats['in_sum'] as num).toDouble().toStringAsFixed(0)}",
                            icon: Icons.arrow_downward_rounded,
                            color: Colors.green,
                          ),
                        ),
                        Container(width: 1, height: 40, color: Colors.grey.withOpacity(0.3)),
                        Expanded(
                          child: _TodayStatItem(
                            label: "Chiqim",
                            value: "${_todayStats['out_count']} ta",
                            subvalue: "Tarqatildi",
                            icon: Icons.arrow_upward_rounded,
                            color: Colors.orange,
                          ),
                        ),
                        Container(width: 1, height: 40, color: Colors.grey.withOpacity(0.3)),
                         Expanded(
                          child: _TodayStatItem(
                            label: "Faollik",
                            value: "${_todayStats['in_count'] + _todayStats['out_count']}",
                            subvalue: "Jami operatsiyalar",
                            icon: Icons.timeline,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                 ],
               ),
             ),

          if (_isLoadingDashboard)
             const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
          else ...[
          // 🏢 BRANCH ANALYTICS SECTION (New)
          if (_branchAnalytics.isNotEmpty) ...[
            const SizedBox(height: 32),
            Row(
              children: [
                 const Icon(Icons.business_rounded, color: Colors.blueAccent, size: 20),
                 const SizedBox(width: 8),
                 Text(
                   "FILIALLAR ANALITIKASI", 
                   style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey[700], letterSpacing: 1),
                 ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _branchAnalytics.length,
                separatorBuilder: (c, i) => const SizedBox(width: 16),
                itemBuilder: (context, index) {
                  final branch = _branchAnalytics[index];
                  return SizedBox(
                    width: 260,
                    child: GlassContainer(
                      padding: const EdgeInsets.all(16),
                      borderRadius: 20,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: Colors.blue.withOpacity(0.1),
                                child: Text(branch['branch_name'][0].toUpperCase(), style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  branch['branch_name'], 
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  maxLines: 1, 
                                  overflow: TextOverflow.ellipsis
                                ),
                              ),
                            ],
                          ),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _BranchSmallStat(label: "Jami", value: "${branch['total_orders']}"),
                              _BranchSmallStat(label: "Kutilmoqda", value: "${branch['pending_count']}", color: Colors.orange),
                              _BranchSmallStat(label: "Yetkazildi", value: "${branch['delivered_count']}", color: Colors.green),
                            ],
                          ),
                          Text(
                            "Oxirgi: ${branch['last_order_date'].toString().substring(0, 10)}",
                            style: TextStyle(color: Colors.grey[500], fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          
          const SizedBox(height: 32),
          // KPIs Grid
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final isWide = width > 800;
              
              final totalVal = _stats['total_value'] as double;
              String totalValueStr;
              if (totalVal >= 1000000) {
                 totalValueStr = "${(totalVal / 1000000).toStringAsFixed(1)}M ${t.text('unit_currency')}";
              } else {
                 totalValueStr = "${totalVal.toStringAsFixed(0)} ${t.text('unit_currency')}";
              }

              return Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.start,
                children: [
                  _FancyStatCard(
                    title: t.text('dash_total_value'), 
                    value: totalValueStr,
                    icon: Icons.monetization_on_rounded,
                    color: Colors.blue,
                    gradient: AppColors.primaryGradient,
                    width: isWide ? (width - 48) / 3 : (width - 16) / 2,
                  ),
                  _FancyStatCard(
                    title: t.text('dash_low_stock'), 
                    value: _stats['low_stock'].toString(), 
                    subvalue: t.text('unit_items'),
                    icon: Icons.warning_rounded,
                    color: Colors.orange,
                    gradient: AppColors.orangeGradient,
                    width: isWide ? (width - 48) / 3 : (width - 16) / 2,
                    onTap: () async {
                      final items = await DatabaseHelper.instance.getLowStockProducts();
                      if (context.mounted) _showProductList(t.text('dash_low_stock'), items);
                    },
                  ),
                  _FancyStatCard(
                    title: t.text('dash_expiring'), 
                    value: _stats['finished'].toString(), 
                    subvalue: t.text('label_critical'),
                    icon: Icons.timer_off_rounded,
                    color: Colors.red,
                    gradient: AppColors.redGradient,
                    width: isWide ? (width - 48) / 3 : width, // Full width on small screens
                    onTap: () async {
                      final items = await DatabaseHelper.instance.getFinishedProducts();
                      if (context.mounted) _showProductList(t.text('dash_expiring'), items);
                    },
                  ),
                ],
              );
            },
          ),
          
          const SizedBox(height: 32),
          
          // Activity & Quick Actions
          // Text(t.text('dash_quick_actions'), style: Theme.of(context).textTheme.titleLarge), // Removed redundant header
          // const SizedBox(height: 16),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Recent Activity
              Expanded(
                flex: 2, 
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.text('dash_list_title'), style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    GlassContainer(
                      padding: const EdgeInsets.all(0),
                      child: _activities.isEmpty 
                        ? Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Center(child: Text(t.text('msg_no_data'), style: const TextStyle(color: Colors.grey))),
                          )
                        : Column(
                        children: [
                          for (int i = 0; i < _activities.length; i++) ...[
                             _ActivityItem(
                               title: _activities[i]['product_name'] ?? '', 
                               subtitle: "${_activities[i]['type'] == 'in' ? t.text('menu_in') : t.text('menu_out')}: ${_activities[i]['quantity']} (${_activities[i]['party']})", 
                               time: _activities[i]['date_time'].toString().length >= 16 
                                 ? _activities[i]['date_time'].toString().substring(5, 16)
                                 : _activities[i]['date_time'].toString(), 
                               icon: _activities[i]['type'] == 'in' ? Icons.download : Icons.upload, 
                               color: _activities[i]['type'] == 'in' ? Colors.green : Colors.orange
                             ),
                             if (i < _activities.length - 1)
                               const Divider(height: 1, color: AppColors.glassBorder),
                          ]
                        ],
                      ),
                    ),
                  ],
                )
              ),
              const SizedBox(width: 24),
              // Quick Actions
              Expanded(
                flex: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.text('dash_quick_actions'), style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    _QuickActionTile(
                      icon: Icons.add_shopping_cart, 
                      label: t.text('menu_in'), 
                      color: AppColors.success,
                      onTap: () => setState(() => _selectedIndex = 3),
                    ),
                    const SizedBox(height: 12),
                    _QuickActionTile(
                      icon: Icons.shopping_bag_outlined, 
                      label: t.text('menu_out'), 
                      color: AppColors.error,
                      onTap: () => setState(() => _selectedIndex = 4),
                    ),
                    const SizedBox(height: 12),
                    _QuickActionTile(
                      icon: Icons.bar_chart, 
                      label: t.text('menu_reports'), 
                      color: AppColors.primary,
                      onTap: () => setState(() => _selectedIndex = 5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          ],
        ],
      ),
    );
  }
}

class _FancyStatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subvalue;
  final IconData icon;
  final Color color;
  final LinearGradient? gradient;
  final double width;
  final VoidCallback? onTap;

  const _FancyStatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.width,
    this.gradient,
    this.subvalue,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: GlassContainer(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: gradient == null ? color.withOpacity(0.1) : null,
                      gradient: gradient,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: gradient != null ? [
                        BoxShadow(
                          color: color.withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        )
                      ] : null,
                    ),
                    child: Icon(icon, color: gradient != null ? Colors.white : color, size: 32),
                ),
                const SizedBox(height: 24),
                Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800, 
                  letterSpacing: -0.5,
                  fontSize: 28,
                )),
                if (subvalue != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(subvalue!, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final String time;
  final IconData icon;
  final Color color;

  const _ActivityItem({required this.title, required this.subtitle, required this.time, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Text(time, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
        ],
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionTile({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 16),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final int badgeCount;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon, 
    required this.label, 
    this.isActive = false,
    this.badgeCount = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: isActive ? BoxDecoration(
          gradient: LinearGradient(
              colors: [AppColors.primary.withOpacity(0.1), AppColors.primary.withOpacity(0.05)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withOpacity(0.2)),
        ) : null,
        child: Row(
          children: [
            Icon(icon, color: isActive ? AppColors.primary : AppColors.textSecondary, size: 20),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(
              color: isActive ? AppColors.primary : AppColors.textSecondary,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            )),
            if (badgeCount > 0) ...[
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badgeCount > 9 ? "9+" : badgeCount.toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
class _TodayStatItem extends StatelessWidget {
  final String label;
  final String value;
  final String subvalue;
  final IconData icon;
  final Color color;

  const _TodayStatItem({required this.label, required this.value, required this.subvalue, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text(subvalue, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ],
          ),
        ],
      ),
    );
  }
}

class _BranchSmallStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _BranchSmallStat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
      ],
    );
  }
}
