import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:clinical_warehouse/core/theme/app_colors.dart';
import 'package:clinical_warehouse/core/localization/app_translations.dart';
import 'package:clinical_warehouse/core/database/database_helper.dart';
import 'package:clinical_warehouse/core/utils/app_notifications.dart';
import 'package:clinical_warehouse/core/theme/grid_theme.dart';
import 'package:clinical_warehouse/core/widgets/glass_container.dart';
import 'package:flutter/services.dart';
import '../../core/widgets/liquid_glass.dart';

class StockInView extends StatefulWidget {
  const StockInView({super.key});

  @override
  State<StockInView> createState() => _StockInViewState();
}

class _StockInViewState extends State<StockInView> {
  late List<PlutoColumn> columns; // Removed final
  late final List<PlutoRow> rows;
  late PlutoGridStateManager stateManager;

  List<String> suppliers = [
    'FOCUSMED', 
    'MEDTEXNIKA', 
    'ABDULLA PHARM'
  ];
  List<String> paymentTypes = ['Naqd', 'Qarzga', 'O\'tkazma'];

  bool isLoading = false;
  bool isOCRLoading = false;
  bool isGridLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
    _loadPaymentTypes();
  }

  Future<void> _loadPaymentTypes() async {
    try {
      final dbTypes = await DatabaseHelper.instance.getPaymentTypes();
      if (mounted && dbTypes.isNotEmpty) {
        setState(() {
          paymentTypes = dbTypes;
          _updateColumns();
          if (isGridLoaded) {
             final col = stateManager.columns.firstWhere((c) => c.field == 'payment_status');
             col.type = PlutoColumnType.select(paymentTypes);
          }
        });
      }
    } catch (e) {
      debugPrint("Error loading payment types: $e");
    }
  }

  Future<void> _loadSuppliers() async {
    try {
      final dbSuppliers = await DatabaseHelper.instance.getSuppliers();
      if (mounted) {
        setState(() {
           if (dbSuppliers.isNotEmpty) {
             suppliers = dbSuppliers;
           }
           // Re-initialize columns with new data
           _updateColumns();
           
           // If grid is already loaded, we must update the stateManager's columns too
           if (isGridLoaded) {
             final col = stateManager.columns.firstWhere((c) => c.field == 'supplier');
             col.type = PlutoColumnType.select(suppliers);
           }
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
    _updateColumns();
    
    rows = List.generate(
      1,
      (index) => _createEmptyRow(index + 1),
    );
  }

  void _updateColumns() {
    final t = Provider.of<AppTranslations>(context, listen: false);
    columns = [
      PlutoColumn(
        title: t.text('col_no'),
        field: 'no',
        type: PlutoColumnType.text(),
        width: 80,
        enableEditingMode: false,
        textAlign: PlutoColumnTextAlign.center,
        titleTextAlign: PlutoColumnTextAlign.center,
      ),
      PlutoColumn(
        title: t.text('col_date'),
        field: 'date',
        type: PlutoColumnType.date(format: 'yyyy-MM-dd'),
        width: 140,
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
        enableEditingMode: false,
      ),
      PlutoColumn(
        title: t.text('col_price'),
        field: 'price',
        type: PlutoColumnType.text(),
        width: 160,
      ),
      PlutoColumn(
        title: t.text('col_unit'),
        field: 'unit',
        type: PlutoColumnType.text(),
        width: 100,
        enableEditingMode: false,
      ),
      PlutoColumn(
        title: t.text('col_qty'),
        field: 'quantity',
        type: PlutoColumnType.text(),
        width: 120,
      ),
      PlutoColumn(
        title: t.text('col_tax_percent'),
        field: 'tax_percent',
        type: PlutoColumnType.text(),
        width: 100,
      ),
      PlutoColumn(
        title: t.text('col_tax_sum'),
        field: 'tax_sum',
        type: PlutoColumnType.text(),
        width: 150,
        enableEditingMode: false,
      ),
      PlutoColumn(
        title: t.text('col_surcharge_percent'),
        field: 'surcharge_percent',
        type: PlutoColumnType.text(),
        width: 130,
      ),
      PlutoColumn(
        title: t.text('col_surcharge_sum'),
        field: 'surcharge_sum',
        type: PlutoColumnType.text(),
        width: 160,
        enableEditingMode: false,
      ),
      PlutoColumn(
        title: t.text('col_from'),
        field: 'supplier',
        type: PlutoColumnType.text(), 
        width: 180,
        enableEditingMode: false,
        renderer: (rendererContext) {
          return InkWell(
            onTap: () => _showChoiceDialog(
              title: t.text('col_from'), 
              options: suppliers, 
              onSelected: (val) {
                rendererContext.cell.value = val;
                stateManager.notifyListeners();
              }
            ),
            child: Row(
              children: [
                Expanded(child: Text(rendererContext.cell.value.toString(), style: const TextStyle(fontWeight: FontWeight.w600))),
                const Icon(Icons.arrow_drop_down, size: 20, color: AppColors.primary),
              ],
            ),
          );
        },
      ),
      PlutoColumn(
        title: t.text('col_payment_status'),
        field: 'payment_status',
        type: PlutoColumnType.text(), 
        width: 180,
        enableEditingMode: false,
        renderer: (rendererContext) {
          return InkWell(
            onTap: () => _showChoiceDialog(
              title: t.text('col_payment_status'), 
              options: paymentTypes, 
              onSelected: (val) {
                rendererContext.cell.value = val;
                stateManager.notifyListeners();
              }
            ),
            child: Row(
              children: [
                Expanded(child: Text(rendererContext.cell.value.toString(), style: const TextStyle(fontWeight: FontWeight.w600))),
                const Icon(Icons.arrow_drop_down, size: 20, color: AppColors.primary),
              ],
            ),
          );
        },
      ),
      PlutoColumn(
        title: t.text('col_total_amount'),
        field: 'total_amount',
        type: PlutoColumnType.text(),
        width: 180,
        enableEditingMode: false,
      ),
    ];
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
          'payment_status': PlutoCell(value: paymentTypes.isNotEmpty ? paymentTypes.first : 'Naqd'),
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

        final index = stateManager.rows.indexOf(row);
        final txId = "${DateTime.now().microsecondsSinceEpoch}_${index}_$productId";

        // Parse extra fields
        final taxPct = double.tryParse(row.cells['tax_percent']?.value.toString() ?? '0') ?? 0;
        final taxSum = double.tryParse(row.cells['tax_sum']?.value.toString() ?? '0') ?? 0;
        final surPct = double.tryParse(row.cells['surcharge_percent']?.value.toString() ?? '0') ?? 0;
        final surSum = double.tryParse(row.cells['surcharge_sum']?.value.toString() ?? '0') ?? 0;

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
          'tax_percent': taxPct,
          'tax_sum': taxSum,
          'surcharge_percent': surPct,
          'surcharge_sum': surSum,
          'payment_status': row.cells['payment_status']?.value.toString() ?? '',
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
        final cells = line.split('\t'); // Excel columns are tab-separated
        
        // Match columns order: #, Date, ID, Product, Price, Unit, Qty, Tax%, TaxSum, Surch%, SurchSum, From, P.Status, Total
        final row = _createEmptyRow(stateManager.rows.length + newRows.length + 1);
        
        if (cells.isNotEmpty) row.cells['no']?.value = cells[0];
        if (cells.length > 1) {
          String rawDate = cells[1];
          row.cells['date']?.value = _parseExcelDate(rawDate);
        }
        if (cells.length > 2) row.cells['product_id']?.value = cells[2];
        if (cells.length > 3) row.cells['product_name']?.value = cells[3];
        if (cells.length > 4) row.cells['price']?.value = cells[4].replaceAll(RegExp(r'[^0-9.]'), '');
        if (cells.length > 5) row.cells['unit']?.value = cells[5];
        if (cells.length > 6) row.cells['quantity']?.value = cells[6].replaceAll(RegExp(r'[^0-9.]'), '');
        if (cells.length > 7) row.cells['tax_percent']?.value = cells[7].replaceAll(RegExp(r'[^0-9.]'), '');
        if (cells.length > 8) row.cells['tax_sum']?.value = cells[8].replaceAll(RegExp(r'[^0-9.]'), '');
        if (cells.length > 9) row.cells['surcharge_percent']?.value = cells[9].replaceAll(RegExp(r'[^0-9.]'), '');
        if (cells.length > 10) row.cells['surcharge_sum']?.value = cells[10].replaceAll(RegExp(r'[^0-9.]'), '');
        if (cells.length > 11) row.cells['supplier']?.value = cells[11];
        if (cells.length > 12) row.cells['payment_status']?.value = cells[12];
        if (cells.length > 13) row.cells['total_amount']?.value = cells[13].replaceAll(RegExp(r'[^0-9.]'), '');

        // Verify product ID if missing but name exists
        final pIdVal = row.cells['product_id']?.value?.toString() ?? '';
        final pNameVal = row.cells['product_name']?.value?.toString() ?? '';

        if (pIdVal.isEmpty && pNameVal.isNotEmpty) {
           final p = await DatabaseHelper.instance.getProductByName(pNameVal);
           if (p != null) {
              row.cells['product_id']?.value = p['id'];
              row.cells['unit']?.value = p['unit'] ?? '';
              row.cells['product_name']?.value = p['name'];
           } else {
              row.cells['product_name']?.value = "❌ ${t.text('msg_not_found')}";
           }
        } else if (pIdVal.isNotEmpty) {
           final p = await DatabaseHelper.instance.getProductById(pIdVal);
           if (p != null) {
              row.cells['product_name']?.value = p['name'];
              row.cells['unit']?.value = p['unit'] ?? '';
           } else {
              row.cells['product_name']?.value = "❌ ${t.text('msg_not_found')}";
           }
        }
        
        // Re-calculate row total
        _calculateRow(row);
        newRows.add(row);
      }

      if (newRows.isNotEmpty) {
        // If first row looks like header, remove it
        final firstRowVal = newRows.first.cells['product_name']?.value?.toString().toLowerCase();
        if (firstRowVal == 'product' || firstRowVal == 'mahsulot' || firstRowVal == 'product name') {
           newRows.removeAt(0);
        }
        
        // Remove the default empty row if it's the only one and it's untouched
        if (stateManager.rows.length == 1) {
           final firstCell = stateManager.rows.first.cells['product_id']?.value?.toString() ?? '';
           if (firstCell.isEmpty) {
              stateManager.removeAllRows();
           }
        }

        stateManager.appendRows(newRows);
        if (mounted) AppNotifications.showSuccess(context, "${newRows.length} qator nusxalandi");
      }
    } catch (e) {
      debugPrint("Paste error: $e");
      if (mounted) AppNotifications.showError(context, "Nusxalashda xatolik: Ma'lumot formati mos emas");
    } finally {
      stateManager.setShowLoading(false);
    }
  }

  String _parseExcelDate(String raw) {
    if (raw.isEmpty) return DateTime.now().toString().substring(0, 10);
    try {
      String clean = raw.trim().replaceAll('.', '/').replaceAll('-', '/');
      if (clean.contains('/')) {
        final pts = clean.split('/');
        if (pts.length == 3) {
          int p0 = int.parse(pts[0]);
          int p1 = int.parse(pts[1]);
          int p2 = int.parse(pts[2]);
          if (p2 > 2000) return DateTime(p2, p1, p0).toString().substring(0, 10);
        }
      }
    } catch (_) {}
    return raw;
  }

  void _calculateRow(PlutoRow row) {
    final qty = double.tryParse(row.cells['quantity']?.value?.toString() ?? '0') ?? 0;
    final price = double.tryParse(row.cells['price']?.value?.toString() ?? '0') ?? 0;
    final taxPct = double.tryParse(row.cells['tax_percent']?.value?.toString() ?? '0') ?? 0;
    final surPct = double.tryParse(row.cells['surcharge_percent']?.value?.toString() ?? '0') ?? 0;

    final baseTotal = qty * price;
    final taxSum = baseTotal * (taxPct / 100);
    final surSum = (baseTotal + taxSum) * (surPct / 100);
    final finalTotal = baseTotal + taxSum + surSum;

    if (finalTotal > 0) {
      row.cells['tax_sum']?.value = taxSum.toStringAsFixed(0);
      row.cells['surcharge_sum']?.value = surSum.toStringAsFixed(0);
      row.cells['total_amount']?.value = finalTotal.toStringAsFixed(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(backgroundColor: Colors.transparent, body: Center(child: CircularProgressIndicator()));
    }
    
    final t = Provider.of<AppTranslations>(context);
    final gridConfig = GridTheme.getConfig(context).copyWith(
      localeText: PlutoGridLocaleText(
        unfreezeColumn: t.text('grid_unfreeze'),
        freezeColumnToStart: t.text('grid_freeze_start'),
        freezeColumnToEnd: t.text('grid_freeze_end'),
        autoFitColumn: t.text('grid_auto_fit'),
        hideColumn: t.text('grid_hide_column'),
        setColumns: t.text('grid_set_columns'),
        setFilter: t.text('grid_set_filter'),
        resetFilter: t.text('grid_reset_filter'),
        filterContains: t.text('filter_contains'),
        filterEquals: t.text('filter_equals'),
        filterStartsWith: t.text('filter_starts_with'),
        filterEndsWith: t.text('filter_ends_with'),
        filterGreaterThan: t.text('filter_greater'),
        filterGreaterThanOrEqualTo: t.text('filter_greater_equal'),
        filterLessThan: t.text('filter_less'),
        filterLessThanOrEqualTo: t.text('filter_less_equal'),
      ),
      columnSize: const PlutoGridColumnSizeConfig(
        autoSizeMode: PlutoAutoSizeMode.scale,
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(t.text('header_check_in'), style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: LiquidColors.of(context).title,
                    letterSpacing: -0.5,
                  )),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(width: 4, height: 16, decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 8),
                       Text(t.text('inp_desc'), style: TextStyle(color: LiquidColors.of(context).subtitle, fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ],
              ),
              
              Row(
                children: [
                  GlassContainer(
                    onTap: () {
                       if (mounted) {
                          stateManager.removeAllRows();
                          stateManager.appendRows(List.generate(1, (i) => _createEmptyRow(i + 1)));
                       }
                    }, 
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    borderRadius: 12,
                    opacity: 0.05,
                    child: Row(
                      children: [
                        Icon(Icons.refresh_rounded, size: 18, color: LiquidColors.of(context).body),
                        const SizedBox(width: 10),
                        Text(t.text('btn_cancel'), style: TextStyle(color: LiquidColors.of(context).body, fontWeight: FontWeight.w700, fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  GlassContainer(
                    onTap: _pasteFromClipboard, 
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    borderRadius: 12,
                    opacity: 0.05,
                    child: Row(
                      children: [
                         Icon(Icons.content_paste_rounded, size: 18, color: LiquidColors.of(context).body.withValues(alpha: 0.7)),
                        const SizedBox(width: 10),
                        Text("Smart Paste", style: TextStyle(color: LiquidColors.of(context).body, fontWeight: FontWeight.w700, fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  GlassContainer(
                    onTap: _saveStockIn, 
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    borderRadius: 12,
                    opacity: 0.1,
                    child: Row(
                      children: [
                        const Icon(Icons.save_rounded, size: 18, color: AppColors.primary),
                        const SizedBox(width: 10),
                        Text(t.text('btn_save'), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        Expanded(
          child: GlassContainer(
            borderRadius: 20,
            blur: 20,
            opacity: 0.03,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: PlutoGrid(
                key: ValueKey(t.currentLocale),
                columns: columns,
                rows: rows,
                onLoaded: (PlutoGridOnLoadedEvent event) {
                  stateManager = event.stateManager;
                  stateManager.setShowColumnFilter(false);
                  isGridLoaded = true;
                },
                onChanged: (PlutoGridOnChangedEvent event) async {
                  
                  // Auto-append row if the last row is modified
                  if (event.rowIdx == stateManager.rows.length - 1) {
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
                      final taxSum = baseTotal * (taxPct / 100);
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
        ),
      ),
    );
  }

  void _showChoiceDialog({
    required String title, 
    required List<String> options, 
    required Function(String) onSelected
  }) {
    showDialog(
      context: context,
      builder: (context) {
        String filter = "";
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredOptions = options.where((o) => o.toLowerCase().contains(filter.toLowerCase())).toList();
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 400,
                height: 500,
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: "Qidirish...",
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onChanged: (v) => setDialogState(() => filter = v),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Scrollbar(
                        thumbVisibility: true,
                        thickness: 8,
                        child: ListView.builder(
                          itemCount: filteredOptions.length,
                          itemBuilder: (context, i) {
                            return ListTile(
                              title: Text(filteredOptions[i]),
                              onTap: () {
                                onSelected(filteredOptions[i]);
                                Navigator.pop(context);
                              },
                              hoverColor: AppColors.primary.withValues(alpha: 0.1),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text(Provider.of<AppTranslations>(context, listen: false).text('btn_cancel'))),
              ],
            );
          }
        );
      }
    );
  }
}

