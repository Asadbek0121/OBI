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
import '../reports/reports_view.dart';
import '../../core/database/database_helper.dart';
import '../../core/services/auth_provider.dart';
import '../splash/splash_screen.dart';
import '../../core/utils/app_notifications.dart';

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

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    try {
      final stats = await DatabaseHelper.instance.getDashboardStats();
      final activities = await DatabaseHelper.instance.getRecentActivity();
      if (mounted) {
        setState(() {
          _stats = stats;
          _activities = activities;
          _isLoadingDashboard = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading dashboard data: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<AppTranslations>(context);
    
    return Scaffold(
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
                        child: Row(
                          children: [
                            Image.asset('assets/logo.png', width: 80, height: 80),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                t.text('title_app'), 
                                style: TextStyle(
                                  fontSize: 12, 
                                  fontWeight: FontWeight.bold,
                                  height: 1.1,
                                   color: Theme.of(context).textTheme.headlineMedium?.color,
                                ),
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
                          _loadDashboardData(); // Refresh on click
                        },
                      ),
                      _SidebarItem(
                        icon: Icons.inventory_2, 
                        label: t.text('menu_inventory'), 
                        isActive: _selectedIndex == 1,
                        onTap: () => setState(() => _selectedIndex = 1),
                      ),
                      _SidebarItem(
                        icon: Icons.storage, // Changed icon
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
                        icon: Icons.analytics, 
                        label: t.text('menu_reports'), 
                        isActive: _selectedIndex == 5,
                        onTap: () => setState(() => _selectedIndex = 5),
                      ),
                      const Spacer(),
                      
                      _SidebarItem(
                        icon: Icons.settings, 
                        label: t.text('menu_settings'), 
                        isActive: _selectedIndex == 6,
                        onTap: () => setState(() => _selectedIndex = 6),
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
                        ? Center(child: Text("Ma'lumot topilmadi"))
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

  Widget _buildContent() {
    switch (_selectedIndex) {
      case 0:
        return _buildDashboardView();
      case 1:
        return const InventoryView();
      case 2:
        return const ProductDatabaseView(); // Replaced Locations
      case 3:
        return const StockInView();
      case 4:
        return const StockOutView();
      case 5:
        return const ReportsView();
      case 6:
        return const SettingsView();
      default:
        return _buildDashboardView();
    }
  }

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
              GlassContainer(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          const SizedBox(height: 32),

          if (_isLoadingDashboard)
             const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
          else ...[
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
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon, 
    required this.label, 
    this.isActive = false,
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
          ],
        ),
      ),
    );
  }
}
