import 'package:flutter/material.dart';
import 'package:clinical_warehouse/core/database/database_helper.dart';
import 'package:clinical_warehouse/core/theme/app_colors.dart';
import 'package:clinical_warehouse/core/widgets/glass_container.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:clinical_warehouse/core/services/excel_service.dart';
import 'package:clinical_warehouse/core/services/print_service.dart';
import 'dart:math';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:clinical_warehouse/core/localization/app_translations.dart';

class AssetsView extends StatefulWidget {
  const AssetsView({super.key});

  @override
  State<AssetsView> createState() => _AssetsViewState();
}

class _AssetsViewState extends State<AssetsView> {
  List<Map<String, dynamic>> _allAssets = [];
  List<Map<String, dynamic>> _filteredAssets = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _buildings = [];
  
  bool _isLoading = true;
  final TextEditingController _searchCtrl = TextEditingController();
  
  int? _selectedBuildingId;
  int? _selectedFloorId;
  int? _selectedRoomId;
  int? _selectedCategoryId;
  String? _selectedStatus;

  // Sidebar hierarchy navigation
  int? _sidebarParentId;
  String _sidebarTitle = "Binolar";
  List<Map<String, dynamic>> _sidebarItems = [];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    await DatabaseHelper.instance.createAssetsTableIfNeeded();
    await _loadMetadata();
    await _loadAssets();
  }

  Future<void> _loadMetadata() async {
    final cats = await DatabaseHelper.instance.getAssetCategories();
    final items = await DatabaseHelper.instance.getLocations(parentId: _sidebarParentId);
    if (mounted) {
      setState(() {
        _categories = cats;
        _sidebarItems = items;
        if (_sidebarParentId == null) {
          _buildings = items; // Useful for dropdowns
        }
      });
    }
  }

  void _goBack() {
    setState(() {
      if (_selectedRoomId != null) {
        _selectedRoomId = null;
        // _sidebarParentId is already the floorId
        _sidebarTitle = "Xonalar";
      } else if (_selectedFloorId != null) {
        _selectedFloorId = null;
        _sidebarParentId = _selectedBuildingId;
        _sidebarTitle = "Qavatlar";
      } else if (_selectedBuildingId != null) {
        _selectedBuildingId = null;
        _sidebarParentId = null;
        _sidebarTitle = "Binolar";
      }
      _loadMetadata();
      _applyFilters();
    });
  }

  int _getCountForLocation(int locId, String type) {
    if (type == 'room') {
      return _allAssets.where((a) => a['location_id'] == locId).length;
    } else if (type == 'floor') {
       return _allAssets.where((a) => a['parent_id'] == locId).length;
    } else { // building
       return _allAssets.where((a) => a['grandparent_id'] == locId).length;
    }
  }

  Future<void> _loadAssets() async {
    try {
      setState(() => _isLoading = true);
      final data = await DatabaseHelper.instance.getAllAssetsDetailed();
      if (mounted) {
        setState(() {
          _allAssets = data;
          _applyFilters();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Load Assets Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    final query = _searchCtrl.text.toLowerCase();
    
    _filteredAssets = _allAssets.where((asset) {
      // Search text
      final nameMatches = asset['name'].toString().toLowerCase().contains(query) ||
                          (asset['model'] ?? '').toString().toLowerCase().contains(query) ||
                          (asset['barcode'] ?? '').toString().toLowerCase().contains(query) ||
                          (asset['serial_number'] ?? '').toString().toLowerCase().contains(query);
      
      // Category filter
      final catMatches = _selectedCategoryId == null || asset['category_id'] == _selectedCategoryId;
      
       // Location filter logic (Deep hierarchy check)
      bool locMatches = true;
      if (_selectedRoomId != null) {
        locMatches = asset['location_id'] == _selectedRoomId;
      } else if (_selectedFloorId != null) {
        locMatches = asset['location_id'] == _selectedFloorId || asset['parent_id'] == _selectedFloorId;
      } else if (_selectedBuildingId != null) {
        locMatches = asset['location_id'] == _selectedBuildingId || 
                     asset['parent_id'] == _selectedBuildingId || 
                     asset['grandparent_id'] == _selectedBuildingId;
      }

      // Status filter
      final statusMatches = _selectedStatus == null || asset['status'] == _selectedStatus;

      return nameMatches && catMatches && locMatches && statusMatches;
    }).toList();
    
    setState(() {});
  }

  void _showAddAssetModal({int? buildingId, int? floorId, int? roomId}) {
    showDialog(
      context: context,
      builder: (context) => _AddAssetDialog(
        initialBuildingId: buildingId, 
        initialFloorId: floorId,
        initialRoomId: roomId
      ),
    ).then((val) {
      if (val == true) _loadAssets();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<AppTranslations>(context);
    
    return Row(
      children: [
        // Sidebar Filters
        _buildFilterSidebar(t),
        const SizedBox(width: 24),
        
        // Main Content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(t),
              const SizedBox(height: 24),
              Expanded(
                child: _isLoading 
                  ? const Center(child: CircularProgressIndicator())
                  : _shouldShowLocationCards()
                    ? _buildHierarchyGrid(t)
                    : _filteredAssets.isEmpty 
                      ? _buildEmptyState(t)
                      : _buildGrid(t),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _shouldShowLocationCards() {
    // Show cards if we have sidebar items (sub-locations) 
    // AND either we are at the top level or we haven't selected a final room yet
    // AND the user hasn't typed in search (search should show results immediately)
    if (_searchCtrl.text.isNotEmpty) return false;
    if (_selectedRoomId != null) return false;
    return _sidebarItems.isNotEmpty;
  }

  Widget _buildHierarchyGrid(AppTranslations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (_selectedBuildingId != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: IconButton(
                  onPressed: _goBack, 
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
                  color: Colors.blue[200],
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
            Text(
              "${t.text('assets_select_label')} ${_sidebarTitle.toLowerCase()}:", 
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue[200])
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _showLocationManager(initialParentId: _sidebarParentId),
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: Text("${t.text('assets_add_new')} ${_sidebarTitle.substring(0, _sidebarTitle.length-1).toLowerCase()}"),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 300,
              mainAxisExtent: 220,
              crossAxisSpacing: 20,
              mainAxisSpacing: 20,
            ),
            itemCount: _sidebarItems.length,
            itemBuilder: (context, index) {
              final item = _sidebarItems[index];
              return _buildLocationCard(item, t);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLocationCard(Map<String, dynamic> item, AppTranslations t) {
    final type = item['type'] ?? 'building';
    final IconData icon = type == 'building' ? Icons.business_rounded :
                          type == 'floor' ? Icons.layers_rounded : Icons.meeting_room_rounded;
    final Color color = type == 'building' ? Colors.blue :
                        type == 'floor' ? Colors.purple : Colors.orange;

    return InkWell(
      onTap: () {
        setState(() {
          if (type == 'building') {
            _selectedBuildingId = item['id'];
            _selectedFloorId = null;
            _sidebarParentId = item['id'];
            _sidebarTitle = "Qavatlar";
          } else if (type == 'floor') {
            _selectedFloorId = item['id'];
            _sidebarParentId = item['id'];
            _sidebarTitle = "Xonalar";
          } else {
            _selectedRoomId = item['id'];
          }
          _loadMetadata();
          _applyFilters();
        });
      },
      borderRadius: BorderRadius.circular(24),
      child: GlassContainer(
        borderRadius: 24,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
                  child: Icon(icon, color: color, size: 24),
                ),
                Text(
                  "${_getCountForLocation(item['id'], type)} ${t.text('assets_count_unit')}",
                  style: TextStyle(color: color.withOpacity(0.8), fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'],
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  item['short_code'] ?? "ID kodi yo'q",
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
              ],
            ),
            const Divider(height: 16, color: AppColors.glassBorder),
            Row(
              children: [
                Icon(Icons.arrow_forward_ios_rounded, size: 12, color: color.withOpacity(0.5)),
                const SizedBox(width: 8),
                Text(
                  type == 'building' ? t.text('assets_view_floors') : (type == 'floor' ? t.text('assets_view_rooms') : t.text('assets_view_items')),
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.download_rounded, size: 18, color: Colors.grey),
                  onPressed: () => ExcelService.exportAssetsHierarchy(
                    buildingId: type == 'building' ? item['id'] : _selectedBuildingId,
                    floorId: type == 'floor' ? item['id'] : _selectedFloorId,
                    roomId: type == 'room' ? item['id'] : null,
                  ),
                  tooltip: "Excel yuklash",
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSidebar(AppTranslations t) {
    return GlassContainer(
      width: 260,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      borderRadius: 24,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.text('menu_location'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 12),
            Row(
              children: [
                _QuickAddBtn(icon: Icons.business_rounded, label: t.text('assets_building'), onTap: _showLocationManager),
                const SizedBox(width: 8),
                _QuickAddBtn(icon: Icons.layers_rounded, label: t.text('assets_floor'), onTap: _showLocationManager),
                const SizedBox(width: 8),
                _QuickAddBtn(icon: Icons.meeting_room_rounded, label: t.text('assets_room'), onTap: _showLocationManager),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (_sidebarParentId != null)
                  IconButton(
                    onPressed: () async {
                      final p = await DatabaseHelper.instance.getLocationById(_sidebarParentId!);
                      setState(() { 
                        _sidebarParentId = p?['parent_id'];
                        if (_sidebarParentId == null) {
                          _sidebarTitle = t.text('assets_building');
                          _selectedBuildingId = null;
                        } else {
                          if (p?['type'] == 'floor') _sidebarTitle = t.text('assets_floor');
                          else if (p?['type'] == 'building') _sidebarTitle = t.text('assets_building');
                        }
                      });
                      _loadMetadata();
                      _applyFilters();
                    }, 
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 14),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.only(right: 8),
                  ),
                Text(_sidebarTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blueAccent)),
              ],
            ),
            const SizedBox(height: 8),
            _FilterItem(
              label: _sidebarParentId == null ? t.text('filter_all_places') : t.text('filter_all_here'),
              icon: Icons.grid_view_rounded,
              isSelected: _selectedBuildingId == null && _selectedFloorId == null && _selectedRoomId == null,
              onTap: () => setState(() { 
                _selectedBuildingId = _selectedFloorId = _selectedRoomId = null;
                _applyFilters(); 
              }),
            ),
            const Divider(height: 16, color: Colors.white10),
            
            // Location List Items
            ..._sidebarItems.map((item) {
              final type = item['type'] ?? 'building';
              bool isSelected = (type == 'building' && _selectedBuildingId == item['id']) ||
                               (type == 'floor' && _selectedFloorId == item['id']) ||
                               (type == 'room' && _selectedRoomId == item['id']);

              return _FilterItem(
                label: item['name'],
                icon: type == 'building' ? Icons.business_rounded :
                      type == 'floor' ? Icons.layers_rounded : Icons.meeting_room_rounded,
                isSelected: isSelected,
                onTap: () {
                  setState(() {
                    if (type == 'building') {
                      _selectedBuildingId = item['id']; _selectedFloorId = _selectedRoomId = null;
                      _sidebarParentId = item['id']; _sidebarTitle = "Qavatlar";
                    } else if (type == 'floor') {
                      _selectedFloorId = item['id']; _selectedRoomId = null;
                      _sidebarParentId = item['id']; _sidebarTitle = "Xonalar";
                    } else {
                      _selectedRoomId = item['id'];
                    }
                    _loadMetadata();
                    _applyFilters();
                  });
                },
                onExport: () => ExcelService.exportAssetsHierarchy(
                  buildingId: type == 'building' ? item['id'] : null,
                  floorId: type == 'floor' ? item['id'] : null,
                  roomId: type == 'room' ? item['id'] : null,
                ),
              );
            }),

            const Divider(height: 24, color: Colors.white10),
            Text(t.text('col_status'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            ...['status_new', 'status_used', 'status_repair', 'status_old'].map((key) => 
              _FilterItem(
                label: t.text(key),
                icon: Icons.circle,
                iconSize: 8,
                iconColor: _getStatusColor(t.text(key)),
                isSelected: _selectedStatus == t.text(key),
                onTap: () => setState(() { 
                  final val = t.text(key);
                  _selectedStatus = (_selectedStatus == val) ? null : val; 
                  _applyFilters(); 
                }),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showLocationManager,
              icon: const Icon(Icons.settings_suggest_rounded, size: 18),
              onPressed: _showLocationManager,
              icon: const Icon(Icons.settings_suggest_rounded, size: 18),
              label: Text(t.text('assets_manage_loc'), style: const TextStyle(fontSize: 11)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.05),
                foregroundColor: Colors.white70,
                minimumSize: const Size(double.infinity, 45),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppTranslations t) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isSmall = constraints.maxWidth < 900;
        
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_selectedBuildingId != null) 
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: IconButton.filled(
                      onPressed: _goBack,
                      icon: const Icon(Icons.arrow_back_rounded, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.primary.withOpacity(0.1),
                        foregroundColor: AppColors.primary,
                      ),
                    ),
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t.text('assets_title'), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: -1)),
                    Text(t.text('assets_subtitle'), style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                  ],
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: isSmall ? 300 : 600,
                  child: GlassContainer(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    borderRadius: 16,
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => _applyFilters(),
                      decoration: InputDecoration(
                        hintText: t.text('assets_search'),
                        border: InputBorder.none,
                        icon: Icon(Icons.search_rounded, color: AppColors.primary.withOpacity(0.7), size: 22),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)]),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: () => _showAddAssetModal(),
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: Text(t.text('btn_add_new'), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      }
    );
  }

  Widget _buildCategoryBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _CategoryChip(
            label: t.text('filter_all'),
            isSelected: _selectedCategoryId == null,
            onTap: () => setState(() { _selectedCategoryId = null; _applyFilters(); }),
          ),
          ..._categories.map((c) =>  _CategoryChip(
            label: c['name'],
            isSelected: _selectedCategoryId == c['id'],
            onTap: () => setState(() { _selectedCategoryId = c['id']; _applyFilters(); }),
          )),
          IconButton(
            onPressed: _showCategoryManager, 
            icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.grey),
            tooltip: "Kategoriya qo'shish",
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(AppTranslations t) {
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 350,
        childAspectRatio: 0.85,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: _filteredAssets.length,
      itemBuilder: (context, index) {
        final asset = _filteredAssets[index];
        return _AnimatedAssetCard(
          index: index,
          asset: asset, 
          onTap: () => _showAssetPassport(asset),
          onDelete: () => _confirmDelete(asset),
        );
      },
    );
  }

  Widget _buildEmptyState(AppTranslations t) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(t.text('msg_no_data'), style: const TextStyle(fontSize: 18, color: Colors.grey)),
        ],
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'Yangi': return Colors.green;
      case 'Ishlatilgan': return Colors.blue;
      case 'Tamirtalab': return Colors.orange;
      case 'Eskirgan': return Colors.red;
      default: return Colors.grey;
    }
  }

  // Dialogs & Screens
  void _showCategoryManager() {
     showDialog(
       context: context,
       builder: (context) => const _CategoryManagerDialog(),
     ).then((_)=> _loadMetadata());
  }

  void _showLocationManager({int? initialParentId}) {
    showDialog(
      context: context,
      builder: (context) => _LocationManagerDialog(initialParentId: initialParentId),
    ).then((result) {
      if (result is Map && result['action'] == 'add_asset') {
        _showAddAssetModal(
          buildingId: result['buildingId'],
          floorId: result['floorId'],
          roomId: result['roomId']
        );
      } else {
        _loadMetadata();
      }
    });
  }

  void _showAssetPassport(Map<String, dynamic> asset) {
     showDialog(
       context: context,
       builder: (context) => _AssetPassportDialog(asset: asset),
     ).then((val) {
       if (val == true) {
         _loadAssets();
       }
     });
  }

  void _confirmDelete(Map<String, dynamic> asset) {
    final t = Provider.of<AppTranslations>(context, listen: false);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.text('asset_delete_title')),
        content: Text("${asset['name']} ${t.text('asset_delete_confirm')}"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t.text('btn_cancel'))),
          ElevatedButton(
            onPressed: () async {
              await DatabaseHelper.instance.deleteAsset(asset['id']);
              if (mounted) {
                Navigator.pop(context);
                _loadAssets();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(t.text('btn_delete')),
          ),
        ],
      ),
    );
  }
}

// Sub-widgets
class _FilterItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onExport;
  final double iconSize;
  final Color? iconColor;

  const _FilterItem({
    required this.label, 
    required this.icon, 
    required this.isSelected, 
    required this.onTap,
    this.onExport,
    this.iconSize = 20,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<AppTranslations>(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: iconSize, color: isSelected ? AppColors.primary : (iconColor ?? Colors.grey[600])),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label, 
                style: TextStyle(
                  color: isSelected ? AppColors.primary : Colors.grey[300],
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (onExport != null)
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.download_rounded, size: 16, color: Colors.grey),
                onPressed: onExport,
                tooltip: t.text('btn_export_excel'),
              ),
          ],
        ),
      ),
    );
  }
}

class _QuickAddBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAddBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.primary,
        backgroundColor: Colors.white.withOpacity(0.05),
        labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.grey[400]),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: isSelected ? AppColors.primary : Colors.grey.withOpacity(0.2)),
      ),
    );
  }
}

class _AnimatedAssetCard extends StatefulWidget {
  final int index;
  final Map<String, dynamic> asset;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _AnimatedAssetCard({required this.index, required this.asset, required this.onTap, required this.onDelete});

  @override
  State<_AnimatedAssetCard> createState() => _AnimatedAssetCardState();
}

class _AnimatedAssetCardState extends State<_AnimatedAssetCard> {
  bool _isHovered = false;
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 50 * (widget.index % 10)), () {
      if (mounted) setState(() => _isVisible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(widget.asset['status']);
    final hasImage = widget.asset['photo_path'] != null;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 500),
      opacity: _isVisible ? 1.0 : 0.0,
      curve: Curves.easeOut,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 500),
        padding: _isVisible ? EdgeInsets.zero : const EdgeInsets.only(top: 50),
        curve: Curves.easeOut,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              transform: Matrix4.identity()..scale(_isHovered ? 1.02 : 1.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: Colors.white.withOpacity(0.03), // Subtle glass 
                border: Border.all(color: Colors.white.withOpacity(_isHovered ? 0.2 : 0.05), width: 1.5),
                boxShadow: _isHovered ? [
                  BoxShadow(color: AppColors.primary.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10))
                ] : [],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // TOP HALF: COVER IMAGE OR GRADIENT
                    Expanded(
                      flex: 6,
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: hasImage ? Colors.black : AppColors.primary.withOpacity(0.05),
                          image: hasImage 
                            ? DecorationImage(image: FileImage(File(widget.asset['photo_path'])), fit: BoxFit.cover) 
                            : null,
                          gradient: hasImage ? null : LinearGradient(
                              colors: [AppColors.primary.withOpacity(0.05), AppColors.primary.withOpacity(0.15)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                        ),
                        child: Stack(
                          children: [
                            if (!hasImage)
                              Center(child: _buildBigIcon()),
                            
                            // Delete Button (Top Right)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Material(
                                color: Colors.black26, 
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: widget.onDelete,
                                  child: const Padding(
                                    padding: EdgeInsets.all(6),
                                    child: Icon(Icons.delete_outline_rounded, color: Colors.white, size: 18),
                                  ),
                                ),
                              ),
                            ),

                            // Tag (Top Left)
                            Positioned(
                              top: 10,
                              left: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black38,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white12)
                                ),
                                child: Text(
                                  widget.asset['category_name'] ?? 'Jihoz',
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // BOTTOM HALF: INFO
                    Expanded(
                      flex: 4,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        color: Colors.white.withOpacity(0.02), // Slight contrast
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.asset['name'],
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.asset['model'] ?? 'Rusum yo\'q',
                                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                                  maxLines: 1,
                                ),
                              ],
                            ),
                            
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Location
                                Expanded(
                                  child: Row(
                                    children: [
                                      Icon(Icons.room_rounded, size: 14, color: Colors.grey[600]),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          widget.asset['location_name'] ?? 'Noma\'lum',
                                          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                
                                // Status Dot
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: statusColor.withOpacity(0.3))
                                  ),
                                  child: Row(
                                    children: [
                                      Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor)),
                                      const SizedBox(width: 6),
                                      Text(
                                        widget.asset['status'] ?? 'Yangi',
                                        style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                )
                              ],
                            )
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBigIcon() {
    IconData icon;
    final n = widget.asset['name'].toString().toLowerCase();
    if (n.contains('komp') || n.contains('laptop')) icon = Icons.laptop_mac_rounded;
    else if (n.contains('stol') || n.contains('mebel')) icon = Icons.table_restaurant_rounded;
    else if (n.contains('printer')) icon = Icons.print_rounded;
    else if (n.contains('monitor')) icon = Icons.desktop_windows_rounded;
    else icon = Icons.inventory_2_rounded;

    return Icon(icon, size: 56, color: AppColors.primary.withOpacity(0.3));
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'Yangi': return Colors.green;
      case 'Ishlatilgan': return Colors.blue;
      case 'Tamirtalab': return Colors.orange;
      case 'Eskirgan': return Colors.red;
      default: return Colors.grey;
    }
  }
}

// MANAGEMENT DIALOGS
class _CategoryManagerDialog extends StatefulWidget {
  const _CategoryManagerDialog();
  @override
  State<_CategoryManagerDialog> createState() => _CategoryManagerDialogState();
}

class _CategoryManagerDialogState extends State<_CategoryManagerDialog> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _list = [];

  @override
  void initState() { super.initState(); _load(); }
  
  void _load() async {
    final data = await DatabaseHelper.instance.getAssetCategories();
    setState(() => _list = data);
  }

  @override
  @override
  Widget build(BuildContext context) {
    final t = Provider.of<AppTranslations>(context);
    return _buildBaseManager(t.text('col_category'), _ctrl, _list, (name) async {
       await DatabaseHelper.instance.insertAssetCategory(name);
       _load();
    }, (id) async {
       await DatabaseHelper.instance.deleteAssetCategory(id);
       _load();
    }, t);
  }
}

class _LocationManagerDialog extends StatefulWidget {
  final int? initialParentId;
  const _LocationManagerDialog({this.initialParentId});
  @override
  State<_LocationManagerDialog> createState() => _LocationManagerDialogState();
}

class _LocationManagerDialogState extends State<_LocationManagerDialog> {
  final _ctrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  List<Map<String, dynamic>> _list = [];
  int? _selectedParentId;
  String? _parentName;

  @override
  void initState() { 
    super.initState(); 
    _selectedParentId = widget.initialParentId;
    _load(); 
  }
  
  void _load() async {
    final data = await DatabaseHelper.instance.getLocations(parentId: _selectedParentId);
    if (_selectedParentId != null) {
       final p = await DatabaseHelper.instance.getLocationById(_selectedParentId!);
       if (p != null) _parentName = p['name'];
    } else {
       _parentName = null;
    }
    setState(() => _list = data);
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<AppTranslations>(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassContainer(
        width: 500,
        height: 600,
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Row(
              children: [
                if (_selectedParentId != null) 
                  IconButton(
                    onPressed: () async {
                      final p = await DatabaseHelper.instance.getLocationById(_selectedParentId!);
                      setState(() { 
                        _selectedParentId = p?['parent_id']; 
                        _load(); 
                      });
                    }, 
                    icon: const Icon(Icons.arrow_back)
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedParentId == null ? "${t.text('assets_building')} (${t.text('assets_select_label')})" : 
                        (_parentName != null ? "$_parentName" : t.text('loc_title')), 
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)
                      ),
                      Text(
                        _selectedParentId == null ? t.text('assets_add_new') : 
                        t.text('assets_manage_loc'), 
                        style: const TextStyle(fontSize: 12, color: Colors.grey)
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl, 
                    decoration: InputDecoration(
                      hintText: t.text('col_name')
                    )
                  )
                ),
                const SizedBox(width: 8),
                SizedBox(width: 80, child: TextField(controller: _codeCtrl, decoration: const InputDecoration(hintText: "Code"))),
                const SizedBox(width: 10),
                ElevatedButton(onPressed: () async {
                  if (_ctrl.text.isNotEmpty) {
                    String type = 'room';
                    int? grandParentId;
                    if (_selectedParentId == null) {
                      type = 'building';
                    } else {
                       final p = await DatabaseHelper.instance.getLocationById(_selectedParentId!);
                       if (p?['type'] == 'building') type = 'floor';
                       grandParentId = p?['parent_id'];
                    }

                    await DatabaseHelper.instance.insertLocation({
                      'name': _ctrl.text,
                      'short_code': _codeCtrl.text.toUpperCase(),
                      'parent_id': _selectedParentId,
                      'type': type
                    });
                    _ctrl.clear();
                    _codeCtrl.clear();
                    _load();
                  }
                }, child: const Icon(Icons.add)),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.separated(
                itemCount: _list.length,
                separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                itemBuilder: (context, index) {
                  final item = _list[index];
                  final bool isRoom = item['type'] == 'room';
                  
                  return ListTile(
                    leading: Icon(
                      item['type'] == 'building' ? Icons.business_rounded :
                      item['type'] == 'floor' ? Icons.layers_rounded : Icons.meeting_room_rounded,
                      color: isRoom ? Colors.orangeAccent : Colors.blueAccent,
                    ),
                    title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(item['short_code'] ?? '-', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    onTap: isRoom ? null : () => setState(() { _selectedParentId = item['id']; _load(); }),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isRoom) 
                          IconButton(
                            onPressed: () async {
                               // Find floor and building ID for this room to pre-fill
                               final floor = await DatabaseHelper.instance.getLocationById(item['parent_id']);
                               int? bid;
                               if (floor != null) {
                                 bid = floor['type'] == 'building' ? (floor['id'] as int?) : (floor['parent_id'] as int?);
                               }
                               if (mounted) {
                                 Navigator.pop(context, {
                                   'action': 'add_asset',
                                   'buildingId': bid,
                                   'floorId': item['parent_id'],
                                   'roomId': item['id']
                                 });
                               }
                            }, 
                            icon: const Icon(Icons.add_box_rounded, color: Colors.greenAccent)
                          )
                        else
                          const Icon(Icons.chevron_right, color: Colors.grey),
                        
                        const SizedBox(width: 8),
                        IconButton(onPressed: () async {
                           await DatabaseHelper.instance.deleteLocation(item['id']);
                           _load();
                        }, icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 20)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildBaseManager(String title, TextEditingController ctrl, List<Map<String, dynamic>> list, Function(String) onAdd, Function(int) onDel, AppTranslations t) {
  return Dialog(
    backgroundColor: Colors.transparent,
    child: GlassContainer(
      width: 400,
      height: 500,
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: TextField(controller: ctrl, decoration: InputDecoration(hintText: t.text('col_name')))),
              const SizedBox(width: 10),
              ElevatedButton(onPressed: () { if(ctrl.text.isNotEmpty) { onAdd(ctrl.text); ctrl.clear(); } }, child: const Icon(Icons.add)),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) => ListTile(
                title: Text(list[index]['name']),
                trailing: IconButton(onPressed: () => onDel(list[index]['id']), icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20)),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ASSET ADD DIALOG (NEW)
class _AddAssetDialog extends StatefulWidget {
  final int? initialBuildingId;
  final int? initialFloorId;
  final int? initialRoomId;
  final Map<String, dynamic>? asset;
  const _AddAssetDialog({super.key, this.initialBuildingId, this.initialFloorId, this.initialRoomId, this.asset});
  @override
  State<_AddAssetDialog> createState() => _AddAssetDialogState();
}

class _AddAssetDialogState extends State<_AddAssetDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _serialCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _catCtrl = TextEditingController();
  
  int? _selectedBuildId;
  int? _selectedFloorId;
  int? _selectedRoomId;
  String? _selectedStatus = 'Yangi';
  String? _photoPath;

  List<Map<String, dynamic>> _cats = [];
  List<Map<String, dynamic>> _buildings = [];
  List<Map<String, dynamic>> _floors = [];
  List<Map<String, dynamic>> _rooms = [];

  @override
  void initState() { 
    super.initState(); 
    if (widget.asset != null) {
      final a = widget.asset!;
      _nameCtrl.text = a['name'];
      _modelCtrl.text = a['model'] ?? '';
      _serialCtrl.text = a['serial_number'] ?? '';
      _colorCtrl.text = a['color'] ?? '';
      _catCtrl.text = a['category_name'] ?? '';
      _selectedStatus = a['status'];
      _photoPath = a['photo_path'];
      
      _selectedBuildId = a['grandparent_id'];
      _selectedFloorId = a['parent_id'];
      _selectedRoomId = a['location_id'];
    } else {
      _selectedBuildId = widget.initialBuildingId;
      _selectedFloorId = widget.initialFloorId;
      _selectedRoomId = widget.initialRoomId;
    }
    _load(); 
  }

  void _load() async {
    final c = await DatabaseHelper.instance.getAssetCategories();
    final b = await DatabaseHelper.instance.getLocations(parentId: null);
    setState(() { _cats = c; _buildings = b; });
    
    // Proper cascading load for initial values
    if (_selectedBuildId != null) {
      final f = await DatabaseHelper.instance.getLocations(parentId: _selectedBuildId!);
      setState(() => _floors = f);
      
      if (_selectedFloorId != null) {
        final r = await DatabaseHelper.instance.getLocations(parentId: _selectedFloorId!);
        setState(() => _rooms = r);
      }
    }
  }

  void _loadFloors(int bid) async {
    final f = await DatabaseHelper.instance.getLocations(parentId: bid);
    setState(() { 
      _floors = f; 
      // Only reset if the new building doesn't contain the current floor
      if (_selectedFloorId != null && !f.any((e) => e['id'] == _selectedFloorId)) {
        _selectedFloorId = null;
        _rooms = [];
        _selectedRoomId = null;
      }
    });
    
    // If we have an initial floor, load its rooms
    if (widget.initialFloorId != null && _selectedFloorId == widget.initialFloorId) {
      _loadRooms(widget.initialFloorId!);
    }
  }

  void _loadRooms(int fid) async {
    final r = await DatabaseHelper.instance.getLocations(parentId: fid);
    setState(() { 
      _rooms = r; 
      // Only reset if the new floor doesn't contain the current room
      if (_selectedRoomId != null && !r.any((e) => e['id'] == _selectedRoomId)) {
        _selectedRoomId = null; 
      }
    });
  }

  Future<void> _save() async {
    if (_selectedRoomId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Iltimos, xonani tanlang")));
      return;
    }

    if (_formKey.currentState!.validate()) {
      try {
        // 1. Generate Smart Barcode
        final barcode = await DatabaseHelper.instance.generateSmartSKU(
          buildingId: _selectedBuildId!, 
          floorId: _selectedFloorId,
          roomId: _selectedRoomId!
        );

      // 2. Get or Create Category ID
      int? catId;
      if (_catCtrl.text.trim().isNotEmpty) {
        catId = await DatabaseHelper.instance.getOrCreateAssetCategory(_catCtrl.text.trim());
      }

      // 3. Insert or Update Asset
      final data = {
        'name': _nameCtrl.text,
        'model': _modelCtrl.text,
        'serial_number': _serialCtrl.text,
        'color': _colorCtrl.text,
        'category_id': catId,
        'location_id': _selectedRoomId,
        'status': _selectedStatus,
        'photo_path': _photoPath,
      };

      if (widget.asset == null) {
        data['barcode'] = barcode;
        data['created_at'] = DateTime.now().toIso8601String();
        await DatabaseHelper.instance.insertAsset(data);
      } else {
        await DatabaseHelper.instance.updateAsset(widget.asset!['id'], data);
      }
        if (mounted) Navigator.pop(context, true);
      } catch (e) {
        debugPrint("❌ Save Asset Error: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Xatolik: $e")));
        }
      }
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    final t = Provider.of<AppTranslations>(context);
    
    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassContainer(
        width: 700,
        height: 700,
        padding: const EdgeInsets.all(40),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.asset == null ? t.text('asset_add_title') : t.text('btn_edit'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 32),

                // Photo Selection
                Center(
                  child: InkWell(
                    onTap: () async {
                      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.image);
                      if (result != null) setState(() => _photoPath = result.files.single.path);
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                        image: _photoPath != null ? DecorationImage(image: FileImage(File(_photoPath!)), fit: BoxFit.cover) : null,
                      ),
                      child: _photoPath == null ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_a_photo_outlined, size: 32, color: Colors.white24),
                          const SizedBox(height: 8),
                          Text(t.text('btn_upload_photo'), style: const TextStyle(fontSize: 10, color: Colors.white24))
                        ],
                      ) : null,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                
                TextFormField(controller: _nameCtrl, decoration: _deco(t.text('asset_inp_name')), validator: (v)=>v!.isEmpty ? "?":null),
                const SizedBox(height: 20),
                
                Row(
                  children: [
                    Expanded(child: TextFormField(controller: _modelCtrl, decoration: _deco("Model"))),
                    const SizedBox(width: 16),
                    Expanded(child: TextFormField(controller: _serialCtrl, decoration: _deco("Seriya raqami"))),
                  ],
                ),
                const SizedBox(height: 20),
                
                Row(
                  children: [
                    Expanded(child: TextFormField(controller: _catCtrl, decoration: _deco("Kategoriya (Mebel, Texnika...)"))),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedStatus,
                        isExpanded: true,
                        decoration: _deco("Holati"),
                        items: ['Yangi', 'Ishlatilgan', 'Tamirtalab', 'Eskirgan'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                        onChanged: (v) => setState(() => _selectedStatus = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextFormField(controller: _colorCtrl, decoration: _deco("Rangi")),
                
                const SizedBox(height: 32),
                const Text("Joylashuv", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 195,
                      child: DropdownButtonFormField<int>(
                        value: _selectedBuildId,
                        isExpanded: true,
                        decoration: _deco("Bino"),
                        items: _buildings.map((b) => DropdownMenuItem<int>(value: b['id'], child: Text(b['name']))).toList(),
                        onChanged: (v) { setState(() => _selectedBuildId = v); if(v!=null) _loadFloors(v); },
                      ),
                    ),
                    SizedBox(
                      width: 195,
                      child: DropdownButtonFormField<int>(
                        value: _selectedFloorId,
                        isExpanded: true,
                        decoration: _deco("Qavat"),
                        items: _floors.map((f) => DropdownMenuItem<int>(value: f['id'], child: Text(f['name']))).toList(),
                        onChanged: (v) { setState(() => _selectedFloorId = v); if(v!=null) _loadRooms(v); },
                      ),
                    ),
                    SizedBox(
                      width: 195,
                      child: DropdownButtonFormField<int>(
                        value: _selectedRoomId,
                        isExpanded: true,
                        decoration: _deco("Xona"),
                        items: _rooms.map((r) => DropdownMenuItem<int>(value: r['id'], child: Text(r['name']))).toList(),
                        onChanged: (v) => setState(() => _selectedRoomId = v),
                        validator: (v) => v == null ? "?" : null,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 48),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: Text(t.text('btn_cancel'))),
                    const SizedBox(width: 20),
                    ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20)),
                      child: Text(t.text('btn_save').toUpperCase()),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _deco(String l) => InputDecoration(labelText: l, filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)));
}

// ASSET PASSPORT DIALOG (Stateful to load history)
class _AssetPassportDialog extends StatefulWidget {
  final Map<String, dynamic> asset;
  const _AssetPassportDialog({required this.asset});

  @override
  State<_AssetPassportDialog> createState() => _AssetPassportDialogState();
}

class _AssetPassportDialogState extends State<_AssetPassportDialog> {
  late Map<String, dynamic> _asset;
  List<Map<String, dynamic>> _history = [];
  bool _isLoadingHistory = true;
  bool _didUpdate = false;

  @override
  void initState() {
    super.initState();
    _asset = widget.asset;
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final data = await DatabaseHelper.instance.getAssetHistory(_asset['id']);
    if (mounted) {
      setState(() {
        _history = data;
        _isLoadingHistory = false;
      });
    }
  }

  void _showTransferDialog() {
    showDialog(
      context: context,
      builder: (context) => _TransferAssetDialog(asset: widget.asset),
    ).then((val) {
      if (val == true) {
        _reloadAsset();
      }
    });
  }

  void _showEditDialog() {
    showDialog(
      context: context,
      builder: (context) => _AddAssetDialog(asset: _asset),
    ).then((val) {
      if (val == true) {
         _reloadAsset();
      }
    });
  }

  Future<void> _reloadAsset() async {
    final barcode = _asset['barcode'];
    final refreshed = await DatabaseHelper.instance.getAssetByBarcode(barcode); // Using barcode lookup or we need getById
    // Actually we need getAssetById logic, but we only have getAssetByBarcode public or getAll. 
    // Let's assume barcode is stable. Or I should add getAssetById
    
    // Fallback: reload history and just set didUpdate = true. 
    // Ideally we want to see the new Name/Model immediately.
    // Let's implement fresh fetch.
    if (refreshed != null) {
      setState(() {
         _asset = refreshed;
         _didUpdate = true;
      });
      _loadHistory();
    } else {
      // If refreshed is null (barcode changed?), just close?
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<AppTranslations>(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassContainer(
        width: 600,
        height: 800,
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                     Text(t.text('asset_passport_title'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                     const SizedBox(width: 16),
                     IconButton(
                       onPressed: _showEditDialog, 
                       icon: const Icon(Icons.edit_rounded, color: Colors.blue),
                       tooltip: t.text('btn_edit'),
                     ),
                  ],
                ),
                IconButton(onPressed: () => Navigator.pop(context, _didUpdate), icon: const Icon(Icons.close)),
              ],
            ),
            const Divider(height: 30),
            
            if (_asset['photo_path'] != null) ...[
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white10),
                  image: DecorationImage(image: FileImage(File(_asset['photo_path'])), fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 24),
            ],
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow(t.text('col_name')+":", _asset['name']),
                    _infoRow("${t.text('asset_inp_model')}/Marka:", _asset['model'] ?? '-'),
                    _infoRow("${t.text('asset_inp_serial')}:", _asset['serial_number'] ?? '-'),
                    _infoRow("${t.text('col_category')}:", _asset['category_name'] ?? '-'),
                    _infoRow("${t.text('col_status')}:", _asset['status'] ?? t.text('status_new')),
                    _infoRow("${t.text('asset_inp_color')}:", _asset['color'] ?? '-'),
                    
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 24),
                    
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("JOYI:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                            Text("${_asset['grandparent_location_name'] != null ? _asset['grandparent_location_name'] + ' > ' : ''}${_asset['parent_location_name'] ?? ''} > ${_asset['location_name'] ?? 'Noma\'lum'}", 
                                 style: const TextStyle(fontSize: 18, color: Colors.blue)),
                          ],
                        ),
                        ElevatedButton.icon(
                          onPressed: _showTransferDialog,
                          icon: const Icon(Icons.move_up_rounded, size: 18),
                          label: Text(t.text('btn_transfer').toUpperCase()),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.withOpacity(0.1), foregroundColor: Colors.orange),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),
                    Text(t.text('asset_history').toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 12),
                    _isLoadingHistory 
                      ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                      : _history.isEmpty 
                         ? Text(t.text('msg_no_data'), style: const TextStyle(color: Colors.grey, fontSize: 13))
                         : _buildHistoryTimeline(),

                    const SizedBox(height: 40),
                    Center(
                      child: GlassContainer(
                        padding: const EdgeInsets.all(16),
                        color: Colors.white,
                        child: BarcodeWidget(
                          barcode: Barcode.code128(),
                          data: _asset['barcode'] ?? 'N/A',
                          width: 300,
                          height: 80,
                          drawText: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => PrintService.printAssetPassport(_asset), 
                icon: const Icon(Icons.print_rounded),
                label: const Text("PASPORTNI CHOP ETISH"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(20),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTimeline() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final move = _history[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  const Icon(Icons.circle, size: 10, color: Colors.blue),
                  if (index != _history.length - 1) 
                    Container(width: 2, height: 30, color: Colors.grey.withOpacity(0.3)),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      index == 0 ? "Hozirgi joyiga ko'chirildi" : "Ko'chirilgan", 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)
                    ),
                    Text(
                      "${move['from_location_name'] ?? 'Boshlang\'ich'} -> ${move['to_location_name']}",
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                    Text(
                      move['moved_at'].toString().substring(0, 16).replaceAll('T', ' '),
                      style: TextStyle(color: Colors.grey[600], fontSize: 11),
                    ),
                    if (move['notes'] != null && move['notes'].toString().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Text(
                          "Izoh: ${move['notes']}",
                          style: const TextStyle(fontSize: 11, color: Colors.orangeAccent, fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoRow(String l, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(l, style: const TextStyle(color: Colors.grey)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }
}

// TRANSFER DIALOG
class _TransferAssetDialog extends StatefulWidget {
  final Map<String, dynamic> asset;
  const _TransferAssetDialog({required this.asset});

  @override
  State<_TransferAssetDialog> createState() => _TransferAssetDialogState();
}

class _TransferAssetDialogState extends State<_TransferAssetDialog> {
  int? _selectedBuildId;
  int? _selectedFloorId;
  int? _selectedRoomId;
  final _notesCtrl = TextEditingController();

  List<Map<String, dynamic>> _buildings = [];
  List<Map<String, dynamic>> _floors = [];
  List<Map<String, dynamic>> _rooms = [];

  @override
  void initState() { super.initState(); _load(); }

  void _load() async {
    final b = await DatabaseHelper.instance.getLocations(parentId: null);
    setState(() => _buildings = b);
  }

  void _loadFloors(int bid) async {
    final f = await DatabaseHelper.instance.getLocations(parentId: bid);
    setState(() { 
      _floors = f; 
      _selectedFloorId = null; 
      _rooms = []; 
      _selectedRoomId = null; 
    });
  }

  void _loadRooms(int fid) async {
    final r = await DatabaseHelper.instance.getLocations(parentId: fid);
    setState(() { 
      _rooms = r; 
      _selectedRoomId = null; 
    });
  }

  Future<void> _transfer() async {
    if (_selectedRoomId == null) return;
    try {
      await DatabaseHelper.instance.transferAsset(widget.asset['id'], _selectedRoomId!, notes: _notesCtrl.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Xatolik: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<AppTranslations>(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassContainer(
        width: 450,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.move_up_rounded, color: Colors.blueAccent, size: 24),
                const SizedBox(width: 12),
                Text(t.text('asset_transfer_title'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "${t.text('asset_transfer_curr')}: ${widget.asset['parent_location_name'] ?? ''} > ${widget.asset['location_name'] ?? ''}",
              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const Divider(height: 32),
            
            // 1. Building
            DropdownButtonFormField<int>(
              value: _selectedBuildId,
              dropdownColor: const Color(0xFF1E1E1E),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: t.text('asset_transfer_dest_build'),
                labelStyle: const TextStyle(color: Colors.white70),
                prefixIcon: const Icon(Icons.business_rounded, size: 20, color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.08),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.2))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
              ),
              items: _buildings.map((b) => DropdownMenuItem(value: b['id'] as int, child: Text(b['name']))).toList(),
              onChanged: (v) { 
                setState(() => _selectedBuildId = v); 
                if(v!=null) _loadFloors(v); 
              },
            ),
            const SizedBox(height: 16),

            // 2. Floor
            DropdownButtonFormField<int>(
              value: _selectedFloorId,
              dropdownColor: const Color(0xFF1E1E1E),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: t.text('asset_transfer_dest_floor'),
                labelStyle: const TextStyle(color: Colors.white70),
                prefixIcon: const Icon(Icons.layers_rounded, size: 20, color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.08),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.2))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
              ),
              items: _floors.map((f) => DropdownMenuItem(value: f['id'] as int, child: Text(f['name']))).toList(),
              onChanged: (v) { 
                setState(() => _selectedFloorId = v); 
                if(v!=null) _loadRooms(v); 
              },
            ),
            const SizedBox(height: 16),

            // 3. Room
            DropdownButtonFormField<int>(
              value: _selectedRoomId,
              dropdownColor: const Color(0xFF1E1E1E),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: t.text('asset_transfer_dest_room'),
                labelStyle: const TextStyle(color: Colors.white70),
                prefixIcon: const Icon(Icons.room_rounded, size: 20, color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.08),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.2))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
              ),
              items: _rooms.map((r) => DropdownMenuItem(value: r['id'] as int, child: Text(r['name']))).toList(),
              onChanged: (v) => setState(() => _selectedRoomId = v),
            ),
            const SizedBox(height: 24),
            
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: t.text('asset_transfer_reason'),
                filled: true,
                fillColor: Colors.white.withOpacity(0.08),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.2))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                labelStyle: const TextStyle(color: Colors.white70),
                alignLabelWithHint: true,
              ),
              style: const TextStyle(color: Colors.white),
            ),

            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context), 
                  child: Text(t.text('btn_cancel'), style: const TextStyle(color: Colors.white60))
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _transfer,
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(t.text('btn_confirm').toUpperCase()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
