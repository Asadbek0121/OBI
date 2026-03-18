import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:clinical_warehouse/core/theme/app_colors.dart';
import 'package:clinical_warehouse/core/widgets/glass_container.dart';
import 'package:clinical_warehouse/core/localization/app_translations.dart';
import 'package:clinical_warehouse/core/database/database_helper.dart';
import 'package:clinical_warehouse/core/utils/app_notifications.dart';
import 'package:clinical_warehouse/core/theme/grid_theme.dart';
import 'package:clinical_warehouse/core/services/local_ocr_service.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

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
        textAlign: PlutoColumnTextAlign.right,
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
        textAlign: PlutoColumnTextAlign.right,
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
        textAlign: PlutoColumnTextAlign.right,
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
        textAlign: PlutoColumnTextAlign.right,
      ),
      PlutoColumn(
        title: t.text('col_from'),
        field: 'supplier',
        type: PlutoColumnType.text(), 
        width: 150,
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
                Expanded(child: Text(rendererContext.cell.value.toString())),
                const Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey),
              ],
            ),
          );
        },
      ),
      PlutoColumn(
        title: t.text('col_payment_status'),
        field: 'payment_status',
        type: PlutoColumnType.text(), 
        width: 150,
        enableEditingMode: false,
        renderer: (rendererContext) {
          final val = rendererContext.cell.value.toString();
          final isNaqd = val.toLowerCase().contains('naqd');
          return InkWell(
            onTap: () => _showChoiceDialog(
              title: t.text('col_payment_status'), 
              options: paymentTypes, 
              onSelected: (val) {
                rendererContext.cell.value = val;
                stateManager.notifyListeners();
              }
            ),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: isNaqd ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isNaqd ? Colors.green.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2)),
                ),
                child: Text(
                  val,
                  style: TextStyle(
                    color: isNaqd ? Colors.green : Colors.orange,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
        },
      ),
      PlutoColumn(
        title: t.text('col_total_amount'),
        field: 'total_amount',
        type: PlutoColumnType.text(),
        width: 160,
        enableEditingMode: false,
        textAlign: PlutoColumnTextAlign.right,
        renderer: (rendererContext) {
          return Text(
            rendererContext.cell.value.toString(),
            style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
          );
        },
      ),
      PlutoColumn(
        title: "",
        field: "action",
        type: PlutoColumnType.text(),
        readOnly: true,
        enableFilterMenuItem: false,
        enableSorting: false,
        enableSetColumnsMenuItem: false,
        width: 60,
        renderer: (rendererContext) {
          return IconButton(
            icon: Icon(Icons.delete_outline_rounded, color: Colors.red.withValues(alpha: 0.7), size: 18),
            onPressed: () {
               stateManager.removeRows([rendererContext.row]);
            },
          );
        },
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
          'action': PlutoCell(value: ''),
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

  Future<void> _handleOCR() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() => isOCRLoading = true);
        stateManager.setShowLoading(true);
        final file = File(result.files.single.path!);
        
        // 🚀 Using Our NEW Personal Local AI Model (MacOS Native Vision)
        final localOCR = LocalOCRService();
        final List<Map<String, dynamic>>? extractedItems = await localOCR.processImageLocally(file);

        if (extractedItems != null && extractedItems.isNotEmpty) {
          final List<PlutoRow> newRows = [];
          
          for (var item in extractedItems) {
            final row = _createEmptyRow(newRows.length + 1);
            row.cells['product_name']?.value = item['name'];
            row.cells['product_id']?.value = item['id'];
            row.cells['unit']?.value = item['unit'];
            row.cells['quantity']?.value = item['quantity'].toString();
            row.cells['price']?.value = item['price'].toString();
            
            // Auto Calculation
            final q = double.tryParse(row.cells['quantity']?.value ?? '0') ?? 0;
            final p = double.tryParse(row.cells['price']?.value ?? '0') ?? 0;
            row.cells['total_amount']?.value = (q * p).toStringAsFixed(0);
            
            newRows.add(row);
          }

          stateManager.appendRows(newRows);
          stateManager.setShowLoading(false);
          
          if (mounted) {
            final newCount = extractedItems.where((i) => i['is_new'] == true).length;
            
            if (newCount > 0) {
              AppNotifications.showWarning(context, "Local AI: ${extractedItems.length} ta mahsulot topildi, lekin ulardan $newCount tasi bazangizda yo'q. Iltimos tekshirib chiqing!");
            } else {
              AppNotifications.showSuccess(context, "Local AI: ${extractedItems.length} ta mahsulot tanib olindi!");
            }
          }
        } else {
          if (mounted) AppNotifications.showError(context, "Rasmdan birorta mahsulot topilmadi.");
          stateManager.setShowLoading(false);
        }
      }
    } catch (e) {
      debugPrint("OCR Handler Error: $e");
      if (mounted) AppNotifications.showError(context, "OCR Xatosi: $e");
      stateManager.setShowLoading(false);
    } finally {
      if (mounted) setState(() => isOCRLoading = false);
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
        scrollbar: const PlutoGridScrollbarConfig(
          isAlwaysShown: true,
          scrollbarThickness: 10,
          scrollbarRadius: Radius.circular(5),
        ),
        style: GridTheme.getStyle(context),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 16,
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
              mainAxisSize: MainAxisSize.min,
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
                  onPressed: isOCRLoading ? null : _handleOCR, 
                  icon: isOCRLoading 
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) 
                    : const Icon(Icons.document_scanner, size: 18), 
                  label: Text(isOCRLoading ? t.text('msg_ocr_reading') : t.text('btn_ocr')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                    foregroundColor: AppColors.primary,
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
                  isGridLoaded = true;
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
