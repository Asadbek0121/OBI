import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pluto_grid/pluto_grid.dart';
import '../../core/localization/app_translations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_container.dart';
import '../../core/database/database_helper.dart';
import '../../core/utils/app_notifications.dart';
import '../../core/theme/grid_theme.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter/services.dart';
import '../../core/widgets/liquid_glass.dart';

class InputView extends StatefulWidget {
  const InputView({super.key});

  @override
  State<InputView> createState() => _InputViewState();
}

class _InputViewState extends State<InputView> {
  late PlutoGridStateManager stateManager;
  List<PlutoRow> rows = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  void _initData() {
    rows = List.generate(100, (index) => _createEmptyRow());
    isLoading = false;
  }

  PlutoRow _createEmptyRow() {
    return PlutoRow(cells: {
      'no': PlutoCell(value: ''),
      'date': PlutoCell(value: DateTime.now().toString().substring(0, 16)), // Includes time
      'id': PlutoCell(value: ''),
      'product': PlutoCell(value: ''),
      'price': PlutoCell(value: 0.0),
      'unit': PlutoCell(value: 'dona'), // Added
      'qty': PlutoCell(value: 0.0),
      'tax_pct': PlutoCell(value: 0.0), // Added
      'tax_sum': PlutoCell(value: 0.0), // Added
      'surcharge_pct': PlutoCell(value: 0.0), // Added
      'surcharge_sum': PlutoCell(value: 0.0), // Added
      'supplier': PlutoCell(value: ''),
      'total': PlutoCell(value: 0.0), // Display only?
    });
  }

  Future<void> _saveData() async {
    final t = Provider.of<AppTranslations>(context, listen: false);
    stateManager.setShowLoading(true);
    try {
      int count = 0;
      for (var row in stateManager.rows) {
        String product = row.cells['product']?.value?.toString().trim() ?? '';
        if (product.isEmpty) continue;

        double qty = double.tryParse(row.cells['qty']?.value?.toString().replaceAll(RegExp(r'[^0-9.]'), '') ?? '0') ?? 0;
        if (qty <= 0) continue;

        double price = double.tryParse(row.cells['price']?.value?.toString().replaceAll(RegExp(r'[^0-9.]'), '') ?? '0') ?? 0;
        String supplier = row.cells['supplier']?.value?.toString() ?? '';
        String unit = row.cells['unit']?.value?.toString() ?? 'dona';
        String excelId = row.cells['id']?.value?.toString() ?? '';
        
        // Preserve Pasted Date
        String rawDate = row.cells['date']?.value?.toString() ?? '';
        String dateStr = _parseDate(rawDate);

        double taxPct = double.tryParse(row.cells['tax_pct']?.value?.toString().replaceAll(RegExp(r'[^0-9.]'), '') ?? '0') ?? 0;
        double taxSum = double.tryParse(row.cells['tax_sum']?.value?.toString().replaceAll(RegExp(r'[^0-9.]'), '') ?? '0') ?? 0;
        double surchargePct = double.tryParse(row.cells['surcharge_pct']?.value?.toString().replaceAll(RegExp(r'[^0-9.]'), '') ?? '0') ?? 0;
        double surchargeSum = double.tryParse(row.cells['surcharge_sum']?.value?.toString().replaceAll(RegExp(r'[^0-9.]'), '') ?? '0') ?? 0;

        String productId = await _resolveAndSyncProduct(excelId, product, unit);
        final txId = "MAN_${DateTime.now().microsecondsSinceEpoch}_${count}_$productId";

        await DatabaseHelper.instance.insertStockIn({
           'id': txId,
           'product_id': productId, 
           'date_time': dateStr,
           'quantity': qty,
           'price_per_unit': price,
           'total_amount': qty * price + taxSum + surchargeSum,
           'supplier_name': supplier,
           'tax_percent': taxPct,
           'tax_sum': taxSum,
           'surcharge_percent': surchargePct,
           'surcharge_sum': surchargeSum,
           'created_at': DateTime.now().toIso8601String(),
        });
        count++;
      }
      if (count > 0) {
        if (!mounted) return;
        AppNotifications.showSuccess(context, "$count ${t.text('msg_saved')}");
        // Refresh grid
        setState(() {
          rows = List.generate(100, (index) => _createEmptyRow());
        });
        stateManager.removeAllRows();
        stateManager.appendRows(rows);
      }
    } catch (e) {
      if (!mounted) return;
      AppNotifications.showError(context, "Xatolik: $e");
    } finally {
      stateManager.setShowLoading(false);
    }
  }

  String _parseDate(String raw) {
    if (raw.isEmpty) return DateTime.now().toIso8601String();
    
    // Check if it's already ISO
    final iso = DateTime.tryParse(raw);
    if (iso != null) return iso.toIso8601String();

    try {
      // 12/01/2026 format detection
      String clean = raw.trim().replaceAll('.', '/').replaceAll('-', '/');
      if (clean.contains('/')) {
        final pts = clean.split('/');
        if (pts.length == 3) {
          int p0 = int.parse(pts[0]);
          int p1 = int.parse(pts[1]);
          int p2 = int.parse(pts[2]);

          if (p2 > 2000) {
            // Assume dd/MM/yyyy (standard for UZ)
            // But if p0 > 12, it must be day. If p1 > 12, p0 must be month (US format)
            if (p0 > 12) {
               return DateTime(p2, p1, p0).toIso8601String();
            } else {
               // Standard dd/MM/yyyy
               return DateTime(p2, p1, p0).toIso8601String();
            }
          }
        }
      }
    } catch (_) {}
    
    return raw; // Result as is if failed, DB might handle it or it's already a string
  }

  Future<String> _resolveAndSyncProduct(String excelId, String name, String unit) async {
    final db = await DatabaseHelper.instance.database;
    
    // 1. Try Find by Name
    final res = await db.query('products', where: 'name = ?', whereArgs: [name], limit: 1);
    if (res.isNotEmpty) {
      final pid = res.first['id'] as String;
      // Update unit if needed
      if (unit.isNotEmpty && res.first['unit'] != unit) {
         await db.update('products', {'unit': unit}, where: 'id = ?', whereArgs: [pid]);
      }
      return pid;
    } 
    
    // 2. Create New
    final newId = excelId.isNotEmpty && excelId.length > 2 
        ? excelId 
        : 'P_${DateTime.now().microsecondsSinceEpoch}_${name.hashCode % 100}';
        
    await db.insert('products', {
      'id': newId,
      'name': name,
      'unit': unit.isEmpty ? 'dona' : unit,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    
    return newId;
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    
    if (text == null || text.isEmpty) {
      if (!mounted) return;
      AppNotifications.showError(context, "Clipboard bo'sh");
      return;
    }

    try {
      final lines = text.trim().split('\n');
      List<PlutoRow> newRows = [];
      
      for (var line in lines) {
        if (line.trim().isEmpty) continue;
        final cells = line.split('\t'); // Excel columns are tab-separated
        
        // Match columns order: #, Date, ID, Product, Price, Unit, Qty, Tax%, TaxSum, Surch%, SurchSum, From, Total
        // If pasted data has fewer cells, handle it
        Map<String, PlutoCell> rowCells = {
          'no': PlutoCell(value: cells.isNotEmpty ? cells[0] : ''),
          'date': PlutoCell(value: cells.length > 1 ? cells[1] : DateTime.now().toString().substring(0, 16)),
          'id': PlutoCell(value: cells.length > 2 ? cells[2] : ''),
          'product': PlutoCell(value: cells.length > 3 ? cells[3] : ''),
          'price': PlutoCell(value: cells.length > 4 ? double.tryParse(cells[4].replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0 : 0.0),
          'unit': PlutoCell(value: cells.length > 5 ? cells[5] : 'dona'),
          'qty': PlutoCell(value: cells.length > 6 ? double.tryParse(cells[6].replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0 : 0.0),
          'tax_pct': PlutoCell(value: cells.length > 7 ? double.tryParse(cells[7].replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0 : 0.0),
          'tax_sum': PlutoCell(value: cells.length > 8 ? double.tryParse(cells[8].replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0 : 0.0),
          'surcharge_pct': PlutoCell(value: cells.length > 9 ? double.tryParse(cells[9].replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0 : 0.0),
          'surcharge_sum': PlutoCell(value: cells.length > 10 ? double.tryParse(cells[10].replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0 : 0.0),
          'supplier': PlutoCell(value: cells.length > 11 ? cells[11] : ''),
          'total': PlutoCell(value: cells.length > 12 ? double.tryParse(cells[12].replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0 : 0.0),
        };
        
        newRows.add(PlutoRow(cells: rowCells));
      }

      if (newRows.isNotEmpty) {
        // If first row looks like header, remove it (optional but helpful)
        final firstRowVal = newRows.first.cells['product']?.value?.toString().toLowerCase();
        if (firstRowVal == 'product' || firstRowVal == 'mahsulot' || firstRowVal == 'product name') {
           newRows.removeAt(0);
        }

        stateManager.prependRows(newRows);
        if (!mounted) return;
        AppNotifications.showSuccess(context, "${newRows.length} qator nusxalandi");
      }
    } catch (e) {
      debugPrint("Paste error: $e");
      if (!mounted) return;
      AppNotifications.showError(context, "Nusxalashda xatolik: Ma'lumot formati mos emas");
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<AppTranslations>(context);
    
    final columns = [
      PlutoColumn(
        title: t.text('col_no'), 
        field: 'no', 
        type: PlutoColumnType.text(),
        width: 80,
      ),
      PlutoColumn(
        title: t.text('col_date'), 
        field: 'date', 
        type: PlutoColumnType.text(), // text type is better for pasting mixed formats
        width: 150,
      ),
      PlutoColumn(
        title: t.text('col_id'), 
        field: 'id', 
        type: PlutoColumnType.text(),
        width: 100,
      ),
      PlutoColumn(
        title: t.text('col_product'), 
        field: 'product', 
        type: PlutoColumnType.text(),
        width: 300,
      ),
      PlutoColumn(
        title: t.text('col_price'), 
        field: 'price', 
        type: PlutoColumnType.number(),
        width: 150,
      ),
      PlutoColumn(
        title: t.text('col_unit'), 
        field: 'unit', 
        type: PlutoColumnType.text(),
        width: 100,
      ),
      PlutoColumn(
        title: t.text('col_qty'), 
        field: 'qty', 
        type: PlutoColumnType.number(),
        width: 100,
      ),
      PlutoColumn(
        title: t.text('col_tax_percent'), 
        field: 'tax_pct', 
        type: PlutoColumnType.number(),
        width: 100,
      ),
      PlutoColumn(
        title: t.text('col_tax_sum'), 
        field: 'tax_sum', 
        type: PlutoColumnType.number(),
        width: 120,
      ),
      PlutoColumn(
        title: t.text('col_surcharge_percent'), 
        field: 'surcharge_pct', 
        type: PlutoColumnType.number(),
        width: 100,
      ),
      PlutoColumn(
        title: t.text('col_surcharge_sum'), 
        field: 'surcharge_sum', 
        type: PlutoColumnType.number(),
        width: 120,
      ),
      PlutoColumn(
        title: t.text('col_from'), 
        field: 'supplier', 
        type: PlutoColumnType.text(),
        width: 200,
      ),
      PlutoColumn(
        title: t.text('col_total_amount'), 
        field: 'total', 
        type: PlutoColumnType.number(),
        width: 150,
        readOnly: true,
      ),
    ];

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(t.text('inp_title'), style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: LiquidColors.of(context).title,
                  letterSpacing: -0.5,
                )),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _pasteFromClipboard,
                      icon: const Icon(Icons.content_paste),
                      label: const Text("Paste (Excel)"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _saveData,
                      icon: const Icon(Icons.save),
                      label: Text(t.text('btn_save')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: GlassContainer(
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: PlutoGrid(
                  columns: columns,
                  rows: rows,
                  onLoaded: (e) {
                     stateManager = e.stateManager;
                     stateManager.setSelectingMode(PlutoGridSelectingMode.cell);
                  },
                  configuration: GridTheme.getConfig(context).copyWith(
                    columnSize: const PlutoGridColumnSizeConfig(
                      autoSizeMode: PlutoAutoSizeMode.scale, // Automatically fits the screen
                    ),
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
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
