import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:clinical_warehouse/core/theme/app_colors.dart';
import 'package:clinical_warehouse/core/theme/grid_theme.dart';
import 'package:clinical_warehouse/core/localization/app_translations.dart';
import 'package:clinical_warehouse/core/database/database_helper.dart';
import 'package:clinical_warehouse/core/utils/app_notifications.dart';
import 'package:clinical_warehouse/core/widgets/glass_container.dart';
import 'package:flutter/services.dart';

class ProductDatabaseView extends StatefulWidget {
  const ProductDatabaseView({super.key});

  @override
  State<ProductDatabaseView> createState() => _ProductDatabaseViewState();
}

class _ProductDatabaseViewState extends State<ProductDatabaseView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final t = Provider.of<AppTranslations>(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            bool isMobile = constraints.maxWidth < 800;
            return isMobile 
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(t),
                    const SizedBox(height: 20),
                    _buildTabs(t),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: _buildHeader(t)),
                    const SizedBox(width: 24),
                    Flexible(child: _buildTabs(t)),
                  ],
                );
          }
        ),
        const SizedBox(height: 40),
        Expanded(
          child: TabBarView(
            physics: const NeverScrollableScrollPhysics(),
            controller: _tabController,
            children: const [
              _ProductGrid(),
              _SimpleListGrid(type: 'supplier'),
              _SimpleListGrid(type: 'receiver'),
              _SimpleListGrid(type: 'payment_type'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(AppTranslations t) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 40,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(3),
            boxShadow: [
              BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))
            ],
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t.text('db_title'), style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
                letterSpacing: -0.5,
              )),
              Text(t.text('inventory_desc'), 
                style: const TextStyle(color: AppColors.textTertiary, fontSize: 13, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabs(AppTranslations t) {
    return GlassContainer(
      padding: const EdgeInsets.all(2),
      borderRadius: 16,
      blur: 20,
      opacity: 0.02,
      child: SizedBox(
        height: 48,
        width: 580, // Optimized for 4 tabs
        child: AnimatedBuilder(
          animation: _tabController.animation!,
          builder: (context, child) {
            return Stack(
              children: [
                // Sliding Indicator (Floating effect)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final tabWidth = constraints.maxWidth / 4;
                    return AnimatedPositioned(
                      duration: const Duration(milliseconds: 300), // Snappier
                      curve: Curves.easeOutCubic, 
                      left: _tabController.index * tabWidth,
                      top: 0,
                      bottom: 0,
                      width: tabWidth,
                      child: Container(
                        margin: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white, // Solid feel like in reference
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08), 
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          border: Border.all(color: Colors.black.withValues(alpha: 0.02)),
                        ),
                      ),
                    );
                  },
                ),
                // Tab Labels
                Row(
                  children: [
                    _buildTabItem(0, t.text('db_products')),
                    _buildTabItem(1, t.text('db_suppliers')),
                    _buildTabItem(2, t.text('db_receivers')),
                    _buildTabItem(3, t.text('db_payment_types')),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTabItem(int index, String label) {
    bool isActive = _tabController.index == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabController.animateTo(index)),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.w900 : FontWeight.w600,
              color: isActive ? AppColors.primary : Colors.black.withValues(alpha: 0.4),
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductGrid extends StatefulWidget {
  const _ProductGrid();

  @override
  State<_ProductGrid> createState() => _ProductGridState();
}

class _ProductGridState extends State<_ProductGrid> {
  final List<PlutoRow> rows = [];
  late PlutoGridStateManager stateManager;
  List<String> validUnits = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    validUnits = await DatabaseHelper.instance.getUnits();
    final products = await DatabaseHelper.instance.getAllProducts();
    
    if (mounted) {
      setState(() {
        rows.clear();
        for (var p in products) {
          rows.add(PlutoRow(
            cells: {
               'id': PlutoCell(value: p['id']),
               'name': PlutoCell(value: p['name']),
               'unit': PlutoCell(value: p['unit'] ?? (validUnits.isNotEmpty ? validUnits.first : '')),
               'min_stock_alert': PlutoCell(value: p['min_stock_alert']?.toString() ?? '10'),
               'action': PlutoCell(value: ''),
            }
          ));
        }
        // Always add one empty row at the end for new entry
        rows.add(_createEmptyRow());
        isLoading = false;
      });
    }
  }

  PlutoRow _createEmptyRow() {
    return PlutoRow(cells: {
      'id': PlutoCell(value: ''),
      'name': PlutoCell(value: ''),
      'unit': PlutoCell(value: validUnits.isNotEmpty ? validUnits.first : 'DONA'),
      'min_stock_alert': PlutoCell(value: '10'),
      'action': PlutoCell(value: ''),
    });
  }

  Future<void> _pasteFromClipboard() async {
    final t = Provider.of<AppTranslations>(context, listen: false);
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    
    if (text == null || text.isEmpty) {
      if (mounted) AppNotifications.showError(context, "Clipboard bo'sh");
      return;
    }

    try {
      stateManager.setShowLoading(true);
      final lines = text.trim().split('\n');
      List<PlutoRow> newRows = [];
      
      for (var line in lines) {
        if (line.trim().isEmpty) continue;
        final cells = line.split('\t'); 
        
        // Expected columns: ID, PRODUCT
        if (cells.length < 2) continue;

        String id = cells[0].trim();
        String name = cells[1].trim();
        
        if (id.isEmpty || name.isEmpty) continue;
        
        // Check if ID already exists in current rows
        bool exists = stateManager.rows.any((r) => r.cells['id']?.value.toString().toLowerCase() == id.toLowerCase());
        if (exists) continue;

        String minStock = '10';
        if (cells.length > 2) {
          // If 3 columns: ID, PRODUCT, MIN_STOCK. If only 2, use default 10.
          minStock = cells[2].trim().replaceAll(RegExp(r'[^0-9]'), '');
          if (minStock.isEmpty) minStock = '10';
        }

        newRows.add(PlutoRow(cells: {
          'id': PlutoCell(value: id),
          'name': PlutoCell(value: name),
          'unit': PlutoCell(value: validUnits.isNotEmpty ? validUnits.first : 'DONA'),
          'min_stock_alert': PlutoCell(value: minStock),
          'action': PlutoCell(value: ''),
        }));
      }

      if (newRows.isNotEmpty) {
        // Remove header if copied
        final firstRowVal = newRows.first.cells['name']?.value?.toString().toLowerCase() ?? '';
        if (firstRowVal.contains('product') || firstRowVal.contains('mahsulot')) {
           newRows.removeAt(0);
        }
        
        // Remove the very last empty row if present
        if (stateManager.rows.isNotEmpty) {
           final lastRow = stateManager.rows.last;
           final lastId = lastRow.cells['id']?.value?.toString() ?? '';
           if (lastId.isEmpty) {
              stateManager.removeRows([lastRow]);
           }
        }

        stateManager.appendRows(newRows);
        // Add back an empty row at the end
        stateManager.appendRows([_createEmptyRow()]);
        
        if (mounted) {
           AppNotifications.showSuccess(context, "${newRows.length} ${t.text('db_msg_saved')}");
        }
      }
    } catch (e) {
      debugPrint("Paste error: $e");
      if (mounted) AppNotifications.showError(context, "Nusxalashda xatolik");
    } finally {
      stateManager.setShowLoading(false);
    }
  }

  Future<void> _saveChanges() async {
    int savedCount = 0;
    for (var row in stateManager.rows) {
      final id = row.cells['id']?.value.toString() ?? '';
      final name = row.cells['name']?.value.toString() ?? '';
      final unit = row.cells['unit']?.value.toString() ?? '';
      final minStock = int.tryParse(row.cells['min_stock_alert']?.value.toString() ?? '10') ?? 10;

      if (id.isNotEmpty && name.isNotEmpty) {
        await DatabaseHelper.instance.insertProduct({
          'id': id,
          'name': name,
          'unit': unit,
          'min_stock_alert': minStock,
          'created_at': DateTime.now().toIso8601String(),
        });
        savedCount++;
      }
    }
    if (mounted) {
      final t = Provider.of<AppTranslations>(context, listen: false);
      if (savedCount > 0) {
        AppNotifications.showSuccess(context, "${t.text('db_msg_saved')}: $savedCount");
      } else {
        AppNotifications.showError(context, t.text('msg_no_data'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    final t = Provider.of<AppTranslations>(context);
    final List<PlutoColumn> columns = [
      PlutoColumn(
        title: t.text('db_col_id_manual'),
        field: 'id',
        type: PlutoColumnType.text(),
        width: 150,
      ),
      PlutoColumn(
        title: t.text('col_product'),
        field: 'name',
        type: PlutoColumnType.text(),
        width: 300,
      ),
      PlutoColumn(
        title: t.text('col_unit'),
        field: 'unit',
        type: PlutoColumnType.select(validUnits),
        width: 150,
      ),
      PlutoColumn(
        title: t.text('label_min_stock'),
        field: 'min_stock_alert',
        type: PlutoColumnType.number(),
        width: 180,
      ),
      PlutoColumn(
        title: "",
        field: "action",
        type: PlutoColumnType.text(),
        readOnly: true,
        enableFilterMenuItem: false,
        enableSorting: false,
        enableSetColumnsMenuItem: false,
        width: 80,
        renderer: (rendererContext) {
          return IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () {
               _confirmDelete(rendererContext.row);
            },
          );
        },
      ),
    ];

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            GlassContainer(
              onTap: _pasteFromClipboard,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              borderRadius: 12,
              opacity: 0.05,
              child: Row(
                children: [
                  Icon(Icons.content_paste_rounded, size: 18, color: AppColors.textPrimary.withValues(alpha: 0.7)),
                  const SizedBox(width: 10),
                  Text("Smart Paste", style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            GlassContainer(
              onTap: _saveChanges, 
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              borderRadius: 12,
              opacity: 0.1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.save_rounded, size: 18, color: AppColors.primary), 
                  const SizedBox(width: 10),
                  Text(t.text('db_save_products'), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: GlassContainer(
            borderRadius: 24,
            blur: 20,
            opacity: 0.05,
            padding: const EdgeInsets.all(2),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: PlutoGrid(
                key: ValueKey(t.currentLocale),
                columns: columns,
                rows: rows,
                onLoaded: (e) {
                  stateManager = e.stateManager;
                  stateManager.setShowColumnFilter(true);
                },
                onChanged: (event) {
                  if (event.rowIdx == stateManager.rows.length - 1) {
                    if (event.value.toString().isNotEmpty) {
                      stateManager.appendRows([_createEmptyRow()]);
                    }
                  }
                },
                configuration: GridTheme.getConfig(context).copyWith(
                  localeText: PlutoGridLocaleText(
                    unfreezeColumn: Provider.of<AppTranslations>(context, listen: false).text('grid_unfreeze'),
                    freezeColumnToStart: Provider.of<AppTranslations>(context, listen: false).text('grid_freeze_start'),
                    freezeColumnToEnd: Provider.of<AppTranslations>(context, listen: false).text('grid_freeze_end'),
                    autoFitColumn: Provider.of<AppTranslations>(context, listen: false).text('grid_auto_fit'),
                    hideColumn: Provider.of<AppTranslations>(context, listen: false).text('grid_hide_column'),
                    setColumns: Provider.of<AppTranslations>(context, listen: false).text('grid_set_columns'),
                    setFilter: Provider.of<AppTranslations>(context, listen: false).text('grid_set_filter'),
                    resetFilter: Provider.of<AppTranslations>(context, listen: false).text('grid_reset_filter'),
                    filterContains: Provider.of<AppTranslations>(context, listen: false).text('filter_contains'),
                    filterEquals: Provider.of<AppTranslations>(context, listen: false).text('filter_equals'),
                    filterStartsWith: Provider.of<AppTranslations>(context, listen: false).text('filter_starts_with'),
                    filterEndsWith: Provider.of<AppTranslations>(context, listen: false).text('filter_ends_with'),
                    filterGreaterThan: Provider.of<AppTranslations>(context, listen: false).text('filter_greater'),
                    filterGreaterThanOrEqualTo: Provider.of<AppTranslations>(context, listen: false).text('filter_greater_equal'),
                    filterLessThan: Provider.of<AppTranslations>(context, listen: false).text('filter_less'),
                    filterLessThanOrEqualTo: Provider.of<AppTranslations>(context, listen: false).text('filter_less_equal'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(PlutoRow row) async {
    final t = Provider.of<AppTranslations>(context, listen: false);
    final id = row.cells['id']?.value.toString() ?? '';
    final name = row.cells['name']?.value.toString() ?? '';
    
    if (id.isEmpty) {
        stateManager.removeRows([row]);
        return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${t.text('btn_delete')}?'),
        content: Text('$name\n\n${t.text('msg_confirm_delete')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.text('btn_cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true), 
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(t.text('btn_delete')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseHelper.instance.deleteProduct(id);
      stateManager.removeRows([row]);
      if (mounted) {
         AppNotifications.showSuccess(context, t.text('msg_deleted'));
      }
    }
  }
}

class _SimpleListGrid extends StatefulWidget {
  final String type; // 'supplier' or 'receiver'
  const _SimpleListGrid({required this.type});

  @override
  State<_SimpleListGrid> createState() => _SimpleListGridState();
}

class _SimpleListGridState extends State<_SimpleListGrid> {
  final List<PlutoRow> rows = [];
  late PlutoGridStateManager stateManager;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    List<String> data = [];
    if (widget.type == 'supplier') {
        data = await DatabaseHelper.instance.getSuppliers();
    } else if (widget.type == 'receiver') {
        data = await DatabaseHelper.instance.getReceivers();
    } else {
        data = await DatabaseHelper.instance.getPaymentTypes();
    }
    
    if (mounted) {
      setState(() {
        rows.clear();
        for (var name in data) {
          rows.add(PlutoRow(cells: {
             'name': PlutoCell(value: name),
             'action': PlutoCell(value: ''), // Initialize action cell
          }));
        }
        // Always add one empty row at the end for new entry
        rows.add(PlutoRow(cells: {
             'name': PlutoCell(value: ''),
             'action': PlutoCell(value: ''), // Initialize action cell
        }));
        isLoading = false;
      });
    }
  }

  Future<void> _saveChanges() async {
    int savedCount = 0;
    for (var row in stateManager.rows) {
      final name = row.cells['name']?.value.toString() ?? '';
      if (name.isNotEmpty) {
        if (widget.type == 'supplier') {
          await DatabaseHelper.instance.insertSupplier(name);
        } else if (widget.type == 'receiver') {
          await DatabaseHelper.instance.insertReceiver(name);
        } else {
          await DatabaseHelper.instance.insertPaymentType(name);
        }
        savedCount++;
      }
    }
    if (mounted) {
      final t = Provider.of<AppTranslations>(context, listen: false);
      if (savedCount > 0) {
        AppNotifications.showSuccess(context, "${t.text('db_msg_saved')}: $savedCount");
      } else {
        AppNotifications.showError(context, t.text('msg_no_data'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    final t = Provider.of<AppTranslations>(context);
    final List<PlutoColumn> columns = [
      PlutoColumn(
        title: widget.type == 'supplier' ? t.text('db_suppliers') : 
               (widget.type == 'receiver' ? t.text('db_receivers') : t.text('db_payment_types')),
        field: 'name',
        type: PlutoColumnType.text(),
        width: 400,
      ),
      PlutoColumn(
        title: "",
        field: "action",
        type: PlutoColumnType.text(),
        readOnly: true,
        enableFilterMenuItem: false,
        enableSorting: false,
        enableSetColumnsMenuItem: false,
        width: 80,
        renderer: (rendererContext) {
           // Don't show delete on the empty 'add new' row
           if (rendererContext.rowIdx == stateManager.rows.length - 1) return const SizedBox.shrink();
           return IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () {
               _confirmDelete(rendererContext.row);
            },
          );
        },
      ),
    ];

    return Column(
      children: [
         Align(
          alignment: Alignment.centerRight,
          child: Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: AppColors.success.withValues(alpha: 0.2),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: _saveChanges, 
              icon: const Icon(Icons.check_circle_outline_rounded, size: 20), 
              label: Text(t.text('btn_save')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: GlassContainer(
            borderRadius: 24,
            blur: 20,
            opacity: 0.05,
            padding: const EdgeInsets.all(2),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: PlutoGrid(
                key: ValueKey(t.currentLocale),
                columns: columns,
                rows: rows,
                onLoaded: (e) {
                  stateManager = e.stateManager;
                  stateManager.setShowColumnFilter(true);
                },
                onChanged: (event) {
                  if (event.rowIdx == stateManager.rows.length - 1) {
                    if (event.value.toString().isNotEmpty) {
                      stateManager.appendRows([PlutoRow(cells: {'name': PlutoCell(value: ''), 'action': PlutoCell(value: '')})]);
                    }
                  }
                },
                configuration: GridTheme.getConfig(context).copyWith(
                  localeText: PlutoGridLocaleText(
                    unfreezeColumn: Provider.of<AppTranslations>(context, listen: false).text('grid_unfreeze'),
                    freezeColumnToStart: Provider.of<AppTranslations>(context, listen: false).text('grid_freeze_start'),
                    freezeColumnToEnd: Provider.of<AppTranslations>(context, listen: false).text('grid_freeze_end'),
                    autoFitColumn: Provider.of<AppTranslations>(context, listen: false).text('grid_auto_fit'),
                    hideColumn: Provider.of<AppTranslations>(context, listen: false).text('grid_hide_column'),
                    setColumns: Provider.of<AppTranslations>(context, listen: false).text('grid_set_columns'),
                    setFilter: Provider.of<AppTranslations>(context, listen: false).text('grid_set_filter'),
                    resetFilter: Provider.of<AppTranslations>(context, listen: false).text('grid_reset_filter'),
                    filterContains: Provider.of<AppTranslations>(context, listen: false).text('filter_contains'),
                    filterEquals: Provider.of<AppTranslations>(context, listen: false).text('filter_equals'),
                    filterStartsWith: Provider.of<AppTranslations>(context, listen: false).text('filter_starts_with'),
                    filterEndsWith: Provider.of<AppTranslations>(context, listen: false).text('filter_ends_with'),
                    filterGreaterThan: Provider.of<AppTranslations>(context, listen: false).text('filter_greater'),
                    filterGreaterThanOrEqualTo: Provider.of<AppTranslations>(context, listen: false).text('filter_greater_equal'),
                    filterLessThan: Provider.of<AppTranslations>(context, listen: false).text('filter_less'),
                    filterLessThanOrEqualTo: Provider.of<AppTranslations>(context, listen: false).text('filter_less_equal'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(PlutoRow row) async {
    final t = Provider.of<AppTranslations>(context, listen: false);
    final name = row.cells['name']?.value.toString() ?? '';
    
    if (name.isEmpty) {
        stateManager.removeRows([row]);
        return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${t.text('btn_delete')}?'),
        content: Text('$name\n\n${t.text('msg_confirm_delete')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.text('btn_cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true), 
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(t.text('btn_delete')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (widget.type == 'supplier') {
          await DatabaseHelper.instance.deleteSupplier(name);
      } else if (widget.type == 'receiver') {
          await DatabaseHelper.instance.deleteReceiver(name);
      } else {
          await DatabaseHelper.instance.deletePaymentType(name);
      }
      stateManager.removeRows([row]);
      if (mounted) {
         AppNotifications.showSuccess(context, t.text('msg_deleted'));
      }
    }
  }
}


