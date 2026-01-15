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

class StockInView extends StatefulWidget {
  const StockInView({super.key});

  @override
  State<StockInView> createState() => _StockInViewState();
}

class _StockInViewState extends State<StockInView> {
  late final List<PlutoColumn> columns;
  late final List<PlutoRow> rows;
  late PlutoGridStateManager stateManager;

  List<String> suppliers = [
    'FOCUSMED', 
    'MEDTEXNIKA', 
    'ABDULLA PHARM'
  ];

  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    try {
      final dbSuppliers = await DatabaseHelper.instance.getSuppliers();
      if (dbSuppliers.isNotEmpty && mounted) {
        setState(() {
          suppliers = dbSuppliers;
        });
      }
    } catch (e) {
      debugPrint("Error loading suppliers: $e");
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
        width: 110,
      ),
      PlutoColumn(
        title: t.text('col_id'),
        field: 'product_id',
        type: PlutoColumnType.text(),
        width: 100,
      ),
      PlutoColumn(
        title: t.text('col_product'),
        field: 'product_name',
        type: PlutoColumnType.text(),
        width: 200,
        enableEditingMode: false,
      ),
      PlutoColumn(
        title: t.text('col_price'),
        field: 'price',
        type: PlutoColumnType.text(),
        width: 140,
      ),
      PlutoColumn(
        title: t.text('col_unit'),
        field: 'unit',
        type: PlutoColumnType.text(),
        width: 80,
        enableEditingMode: false,
      ),
      PlutoColumn(
        title: t.text('col_qty'),
        field: 'quantity',
        type: PlutoColumnType.text(),
        width: 100,
      ),
      PlutoColumn(
        title: t.text('col_tax_percent'),
        field: 'tax_percent',
        type: PlutoColumnType.text(),
        width: 80,
      ),
      PlutoColumn(
        title: t.text('col_tax_sum'),
        field: 'tax_sum',
        type: PlutoColumnType.text(),
        width: 120,
        enableEditingMode: false,
      ),
      PlutoColumn(
        title: t.text('col_surcharge_percent'),
        field: 'surcharge_percent',
        type: PlutoColumnType.text(),
        width: 110,
      ),
      PlutoColumn(
        title: t.text('col_surcharge_sum'),
        field: 'surcharge_sum',
        type: PlutoColumnType.text(),
        width: 140,
        enableEditingMode: false,
      ),
      PlutoColumn(
        title: t.text('col_from'),
        field: 'supplier',
        type: PlutoColumnType.select(suppliers.isNotEmpty ? suppliers : [t.text('msg_loading')]), 
        width: 150,
      ),
      PlutoColumn(
        title: t.text('col_total_amount'),
        field: 'total_amount',
        type: PlutoColumnType.text(),
        width: 160,
        enableEditingMode: false,
      ),
    ];

    rows = List.generate(
      1,
      (index) => _createEmptyRow(index + 1),
    );
  }

  PlutoRow _createEmptyRow(int index) {
     return PlutoRow(
        cells: {
          'no': PlutoCell(value: index.toString()),
          'date': PlutoCell(value: DateTime.now().toString().substring(0, 10)),
          'product_id': PlutoCell(value: ''),
          'product_name': PlutoCell(value: ''),
          'price': PlutoCell(value: ''),
          'unit': PlutoCell(value: ''),
          'quantity': PlutoCell(value: ''),
          'tax_percent': PlutoCell(value: ''),
          'tax_sum': PlutoCell(value: ''),
          'surcharge_percent': PlutoCell(value: ''),
          'surcharge_sum': PlutoCell(value: ''),
          'supplier': PlutoCell(value: suppliers.isNotEmpty ? suppliers.first : ''),
          'total_amount': PlutoCell(value: ''),
        },
      );
  }

  Future<void> _saveStockIn() async {
    final t = Provider.of<AppTranslations>(context, listen: false);
    int savedCount = 0;
    try {
      for (var row in stateManager.rows) {
        final productId = row.cells['product_id']?.value.toString() ?? '';
        if (productId.isEmpty) continue;

        final productName = row.cells['product_name']?.value.toString() ?? '';
        if (productName.isEmpty || productName.contains('❌')) continue;

        final qty = double.tryParse(row.cells['quantity']?.value.toString() ?? '0') ?? 0;
        if (qty <= 0) continue; 

        final supplier = row.cells['supplier']?.value.toString() ?? '';
        final price = double.tryParse(row.cells['price']?.value.toString() ?? '0') ?? 0;
        final dateStr = row.cells['date']?.value.toString() ?? DateTime.now().toIso8601String();
        
        // Calculated fields to save (mapping to existing DB schema where possible)
        final totalAmount = double.tryParse(row.cells['total_amount']?.value.toString() ?? '0') ?? 0;

        final txId = DateTime.now().millisecondsSinceEpoch.toString() + productId;

        await DatabaseHelper.instance.insertStockIn({
          'id': txId,
          'product_id': productId,
          'date_time': dateStr,
          'batch_number': '', // Removed from UI
          'expiry_date': '', // Removed from UI
          'quantity': qty,
          'price_per_unit': price,
          'total_amount': totalAmount,
          'supplier_name': supplier,
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
       debugPrint("Save Error: $e");
       if (mounted) AppNotifications.showError(context, "${t.text('msg_error')}: $e");
    }
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
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.text('header_check_in'), style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(t.text('inp_desc'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)),
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
                  onPressed: _saveStockIn, 
                  icon: const Icon(Icons.save), 
                  label: Text(t.text('btn_save')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
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
                    // Check if 'product_id' was entered, or generally if the row is being used
                    if (event.column.field == 'product_id' && event.value.toString().isNotEmpty) {
                       stateManager.appendRows([_createEmptyRow(stateManager.rows.length + 1)]);
                    }
                  }

                  // 1. ID Lookup
                  if (event.column.field == 'product_id') {
                    final id = event.value.toString();
                    if (id.isNotEmpty) {
                      final product = await DatabaseHelper.instance.getProductById(id);
                      if (product != null) {
                        event.row.cells['product_name']?.value = product['name'];
                        event.row.cells['unit']?.value = product['unit'] ?? '';
                      } else {
                        event.row.cells['product_name']?.value = '❌ ${t.text('msg_not_found')}';
                        event.row.cells['unit']?.value = '';
                      }
                      setState(() {});
                    }
                  }

                  // 2. Calculations
                  if (['quantity', 'price', 'tax_percent', 'surcharge_percent'].contains(event.column.field)) {
                    final row = event.row;
                    final qtyStr = row.cells['quantity']?.value?.toString() ?? '';
                    final priceStr = row.cells['price']?.value?.toString() ?? '';
                    
                    if (qtyStr.isEmpty && priceStr.isEmpty) {
                      row.cells['tax_sum']?.value = '';
                      row.cells['surcharge_sum']?.value = '';
                      row.cells['total_amount']?.value = '';
                    } else {
                      final qty = double.tryParse(qtyStr) ?? 0;
                      final price = double.tryParse(priceStr) ?? 0;
                      final taxPct = double.tryParse(row.cells['tax_percent']?.value?.toString() ?? '0') ?? 0;
                      final surPct = double.tryParse(row.cells['surcharge_percent']?.value?.toString() ?? '0') ?? 0;

                      final baseTotal = qty * price;
                      
                      // Tax is calculated on base amounts
                      final taxSum = baseTotal * (taxPct / 100);
                      
                      // Surcharge is calculated on (Base + Tax) as per user request definition
                      // Formula: ((PRICE * QTY) + TAXSUM) * SURCHARGE%
                      final surSum = (baseTotal + taxSum) * (surPct / 100);
                      
                      final finalTotal = baseTotal + taxSum + surSum;

                      row.cells['tax_sum']?.value = finalTotal > 0 ? taxSum.toStringAsFixed(0) : '';
                      row.cells['surcharge_sum']?.value = finalTotal > 0 ? surSum.toStringAsFixed(0) : '';
                      row.cells['total_amount']?.value = finalTotal > 0 ? finalTotal.toStringAsFixed(0) : '';
                    }
                    setState(() {});
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
