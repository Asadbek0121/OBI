import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:clinical_warehouse/core/theme/app_colors.dart';
import 'package:clinical_warehouse/core/widgets/glass_container.dart';
import 'package:clinical_warehouse/core/localization/app_translations.dart';
import 'package:clinical_warehouse/core/database/database_helper.dart';
import 'package:clinical_warehouse/core/utils/app_notifications.dart';
import 'package:clinical_warehouse/core/theme/grid_theme.dart';
import 'package:clinical_warehouse/core/widgets/app_dialogs.dart';

class StockOutView extends StatefulWidget {
  const StockOutView({super.key});

  @override
  State<StockOutView> createState() => _StockOutViewState();
}

class _StockOutViewState extends State<StockOutView> {
  late final List<PlutoColumn> columns;
  late final List<PlutoRow> rows;
  late PlutoGridStateManager stateManager;
  List<String> receivers = [
    'ASADBEK DAVRONOV', 'ISHONCH (XURRAMOVA NOZIGUL)', 'BAK LABARATORIYA', 
    'XUSHIYVA SITORA', "JO'RAYEVA SABINA", 'KARIMOVA MOHINUR BOYSUN', 
    "JARQURG'ON TTB", "JARQURG'ON POLIKLINIKA", 'KARDIOLOGIYA', 'PRINATAL', 
    'ANGOR', 'SHEROBOD', 'XASANOVA SEVINCH', 'LABARATORIYA', 'SIL DISPANSER', 
    "MAXMADMO'MINOVA AZIZA", 'QON QUYISH MARKAZI', "ESHPO'LATOV SUNNATILLO", 
    "TURK GLOBAL CENTER AYSIN BISARO'G'LU"
  ];

  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadReceivers();
  }

  Future<void> _loadReceivers() async {
    try {
      final dbReceivers = await DatabaseHelper.instance.getReceivers();
      if (dbReceivers.isNotEmpty && mounted) {
        setState(() {
          receivers = dbReceivers;
        });
      }
    } catch (e) {
      debugPrint("Error loading receivers: $e");
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (isLoading) return;
    final t = Provider.of<AppTranslations>(context);
    
    columns = [
      PlutoColumn(
        title: t.text('col_no'),
        field: 'no',
        type: PlutoColumnType.text(),
        width: 50,
        enableEditingMode: false,
      ),
      PlutoColumn(
        title: t.text('col_date'),
        field: 'date',
        type: PlutoColumnType.date(format: 'yyyy-MM-dd'),
        width: 120,
      ),
      PlutoColumn(
        title: t.text('col_id'),
        field: 'product_id',
        type: PlutoColumnType.text(),
        width: 120,
      ),
      PlutoColumn(
        title: t.text('col_product'),
        field: 'product_name',
        type: PlutoColumnType.text(),
        width: 250,
        enableEditingMode: false, // Read-only, filled by ID
      ),
      PlutoColumn(
        title: t.text('col_unit'),
        field: 'unit',
        type: PlutoColumnType.text(),
        width: 150,
        enableEditingMode: false,
      ),
      PlutoColumn(
        title: t.text('col_qty'),
        field: 'quantity',
        type: PlutoColumnType.text(),
        width: 120,
      ),
      PlutoColumn(
        title: t.text('col_to_receiver'),
        field: 'receiver',
        type: PlutoColumnType.select(receivers.isNotEmpty ? receivers : [t.text('msg_loading')]), 
        width: 200,
      ),
      // Hidden column for validation
      PlutoColumn(
        title: t.text('col_stock'),
        field: 'current_stock',
        type: PlutoColumnType.number(),
        width: 0,
        hide: true,
      ),
    ];

    rows = List.generate(
      1,
      (index) => _createEmptyRow(index + 1),
    );
  }

  Future<void> _saveStockOut() async {
    final t = Provider.of<AppTranslations>(context, listen: false);
    int savedCount = 0;
    try {
      for (var row in stateManager.rows) {
        final productId = row.cells['product_id']?.value.toString() ?? '';
        if (productId.isEmpty) continue;

        final qty = double.tryParse(row.cells['quantity']?.value.toString() ?? '0') ?? 0;
        if (qty <= 0) continue;

        final receiver = row.cells['receiver']?.value.toString() ?? '';
        final dateStr = row.cells['date']?.value.toString() ?? DateTime.now().toIso8601String();
        
        // We can use the row date, but we need to ensure it's in a standard format for DB
        // PlutoGrid date column usually returns formatted string.
        
        await DatabaseHelper.instance.insertStockOut({
           'id': DateTime.now().millisecondsSinceEpoch.toString() + productId, // Unique ID
           'product_id': productId,
           'date_time': dateStr, // Use user selected date
           'quantity': qty,
           'receiver_name': receiver,
           'batch_reference': '', // Default empty for now as requested
           'notes': '', 
        });
        savedCount++;
      }

      if (savedCount > 0) {
        if (mounted) {
           AppNotifications.showSuccess(context, "$savedCount ${t.text('msg_saved')}");
           stateManager.removeAllRows();
           stateManager.appendRows(List.generate(1, (i) => _createEmptyRow(i + 1)));
        }
      } else {
         if (mounted) AppNotifications.showError(context, t.text('msg_no_data'));
      }
    } catch (e) {
      debugPrint("StockOut Error: $e");
      if (mounted) AppNotifications.showError(context, "${t.text('msg_error')}: $e");
    }
  }

  PlutoRow _createEmptyRow(int index) {
     return PlutoRow(
        cells: {
          'no': PlutoCell(value: index.toString()),
          'date': PlutoCell(value: DateTime.now().toString().substring(0, 10)),
          'product_id': PlutoCell(value: ''),
          'product_name': PlutoCell(value: ''),
          'unit': PlutoCell(value: ''),
          'quantity': PlutoCell(value: ''),
          'receiver': PlutoCell(value: receivers.isNotEmpty ? receivers.first : ''),
          'current_stock': PlutoCell(value: ''),
        },
      );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final t = Provider.of<AppTranslations>(context);

    final gridConfig = PlutoGridConfiguration(
      localeText: PlutoGridLocaleText(
        unfreezeColumn: t.text('grid_unfreeze'),
        freezeColumnToStart: t.text('grid_freeze_start'),
        freezeColumnToEnd: t.text('grid_freeze_end'),
        autoFitColumn: t.text('grid_auto_fit'),
        hideColumn: t.text('grid_hide_column'),
        setColumns: t.text('grid_set_columns'),
        setFilter: t.text('grid_set_filter'),
        resetFilter: t.text('grid_reset_filter'),
      ),
      columnSize: const PlutoGridColumnSizeConfig(
        autoSizeMode: PlutoAutoSizeMode.scale,
      ),
      style: GridTheme.getStyle(context),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.text('header_check_out'), style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(t.text('out_desc'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)),
              ],
            ),
            
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    if (mounted) {
                      stateManager.removeAllRows();
                      stateManager.appendRows(List.generate(1, (i) => _createEmptyRow(i + 1)));
                    }
                  }, 
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(t.text('btn_cancel')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.withValues(alpha: 0.2),
                    foregroundColor: AppColors.textPrimary,
                    elevation: 0,
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _saveStockOut, 
                  icon: const Icon(Icons.check_circle), 
                  label: Text(t.text('btn_create_out')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error, // Red for outflow
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),

        Expanded(
          child: GlassContainer(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: PlutoGrid(
                key: ValueKey(t.currentLocale),
                columns: columns,
                rows: rows,
                onLoaded: (PlutoGridOnLoadedEvent event) {
                  stateManager = event.stateManager;
                  stateManager.setShowColumnFilter(false);
                },
                onChanged: (PlutoGridOnChangedEvent event) async {
                   // Auto-append row if the last row is modified
                   if (event.rowIdx == stateManager.rows.length - 1) {
                     if (event.column.field == 'product_id' && event.value.toString().isNotEmpty) {
                        stateManager.appendRows([_createEmptyRow(stateManager.rows.length + 1)]);
                     }
                   }

                   // 1. ID Lookup Logic
                   if (event.column.field == 'product_id') {
                      final id = event.value.toString();
                      if (id.isNotEmpty) {
                         // Get Product Info
                         final product = await DatabaseHelper.instance.getProductById(id);
                         if (product != null) {
                            event.row.cells['product_name']?.value = product['name'];
                            event.row.cells['unit']?.value = product['unit'] ?? ''; // Populate Unit
                            
                            // Get Inventory Level
                            final inventory = await DatabaseHelper.instance.getInventorySummary();
                            // Find stock for this ID
                            final stockItem = inventory.firstWhere((e) => e['id'] == id, orElse: () => {'stock': 0.0});
                            event.row.cells['current_stock']?.value = stockItem['stock'] ?? 0;
                         } else {
                            event.row.cells['product_name']?.value = '❌ ${t.text('msg_not_found')}';
                            event.row.cells['unit']?.value = '';
                            event.row.cells['current_stock']?.value = 0;
                         }
                         setState((){});
                      }
                   }

                  // Validation Logic: Check if Quantity > Stock
                  if (event.column.field == 'quantity') {
                    final qty = double.tryParse(event.row.cells['quantity']?.value.toString() ?? '0') ?? 0;
                    final stock = double.tryParse(event.row.cells['current_stock']?.value.toString() ?? '0') ?? 0;
                    
                    if (qty > stock) {
                       event.row.cells['quantity']?.value = stock; // Auto-clamp
                       ScaffoldMessenger.of(context).showSnackBar(
                         SnackBar(content: Text("Omborda yetarli emas! Mavjud: $stock"), duration: const Duration(seconds: 1)),
                       );
                    }
                  }
                },
                configuration: gridConfig,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
