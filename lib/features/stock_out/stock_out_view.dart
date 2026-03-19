import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:clinical_warehouse/core/theme/app_colors.dart';
import 'package:clinical_warehouse/core/localization/app_translations.dart';
import 'package:clinical_warehouse/core/database/database_helper.dart';
import 'package:clinical_warehouse/core/utils/app_notifications.dart';
import 'package:clinical_warehouse/core/theme/grid_theme.dart';
import 'package:flutter/services.dart';

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
        enableEditingMode: false,
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
        type: PlutoColumnType.text(), 
        width: 200,
        enableEditingMode: false,
        renderer: (rendererContext) {
          return InkWell(
            onTap: () => _showChoiceDialog(
              title: t.text('col_to_receiver'),
              options: receivers,
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
        final index = stateManager.rows.indexOf(row);
        final txId = "${DateTime.now().microsecondsSinceEpoch}_${index}_$productId";

        await DatabaseHelper.instance.insertStockOut({
           'id': txId,
           'product_id': productId,
           'date_time': dateStr,
           'quantity': qty,
           'receiver_name': receiver,
           'batch_reference': '',
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
      
      final inventory = await DatabaseHelper.instance.getInventorySummary();

      for (var line in lines) {
        if (line.trim().isEmpty) continue;
        final cells = line.split('\t'); 
        
        // Match columns order: #, Sana, ID, Mahsulot, Birlik, Miqdori, Kimga
        final row = _createEmptyRow(stateManager.rows.length + newRows.length + 1);
        
        if (cells.isNotEmpty) row.cells['no']?.value = cells[0];
        if (cells.length > 1) row.cells['date']?.value = _parseExcelDate(cells[1]);
        if (cells.length > 2) row.cells['product_id']?.value = cells[2];
        if (cells.length > 3) row.cells['product_name']?.value = cells[3];
        if (cells.length > 4) row.cells['unit']?.value = cells[4];
        if (cells.length > 5) row.cells['quantity']?.value = cells[5].replaceAll(RegExp(r'[^0-9.]'), '');
        if (cells.length > 6) row.cells['receiver']?.value = cells[6];

        // Verify product ID/Name
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
        
        // Check Stock
        final finalPid = row.cells['product_id']?.value?.toString() ?? '';
        if (finalPid.isNotEmpty) {
           final stockItem = inventory.firstWhere((e) => e['id'].toString().toLowerCase() == finalPid.toLowerCase(), orElse: () => {'stock': 0.0});
           row.cells['current_stock']?.value = stockItem['stock'] ?? 0.0;
        }

        newRows.add(row);
      }

      if (newRows.isNotEmpty) {
        // Remove header if copied
        final firstRowVal = newRows.first.cells['product_name']?.value?.toString().toLowerCase() ?? '';
        if (firstRowVal.contains('product') || firstRowVal.contains('mahsulot')) {
           newRows.removeAt(0);
        }
        
        // Remove default empty row
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
      if (mounted) AppNotifications.showError(context, "Nusxalashda xatolik");
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

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 16,
          runSpacing: 16,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.text('header_check_out'), style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                )),
                const SizedBox(height: 8),
                Text(t.text('out_desc'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
              ],
            ),
            
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _HeaderButton(
                  onPressed: () {
                    if (mounted) {
                      stateManager.removeAllRows();
                      stateManager.appendRows(List.generate(1, (i) => _createEmptyRow(i + 1)));
                    }
                  }, 
                  icon: Icons.refresh_rounded,
                  label: t.text('btn_cancel'),
                  color: Colors.grey[200]!,
                  textColor: AppColors.textPrimary,
                ),
                const SizedBox(width: 12),
                Row(
                  children: [
                    _HeaderButton(
                      onPressed: _pasteFromClipboard,
                      icon: Icons.content_paste_rounded,
                      label: "Smart Paste",
                      color: AppColors.primary.withValues(alpha: 0.1),
                      textColor: AppColors.primary,
                    ),
                    const SizedBox(width: 12),
                    _HeaderButton(
                      onPressed: _saveStockOut, 
                      icon: Icons.check_circle_rounded, 
                      label: t.text('btn_out'),
                      color: AppColors.primary, 
                      textColor: Colors.white,
                      isPrimary: true,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),

        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
              border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
            ),
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
                   if (event.rowIdx == stateManager.rows.length - 1) {
                     if (event.column.field == 'product_id' && event.value.toString().isNotEmpty) {
                        stateManager.appendRows([_createEmptyRow(stateManager.rows.length + 1)]);
                     }
                   }

                   if (event.column.field == 'product_id') {
                      final id = event.value.toString();
                      if (id.isNotEmpty) {
                         final product = await DatabaseHelper.instance.getProductById(id);
                         if (product != null) {
                            event.row.cells['product_name']?.value = product['name'];
                            event.row.cells['unit']?.value = product['unit'] ?? '';
                            
                            final inventory = await DatabaseHelper.instance.getInventorySummary();
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

                  if (event.column.field == 'quantity') {
                    final qty = double.tryParse(event.row.cells['quantity']?.value.toString() ?? '0') ?? 0;
                    final stock = double.tryParse(event.row.cells['current_stock']?.value.toString() ?? '0') ?? 0;
                    
                    if (qty > stock) {
                       event.row.cells['quantity']?.value = stock;
                       if (context.mounted) {
                         ScaffoldMessenger.of(context).showSnackBar(
                           SnackBar(content: Text("Omborda yetarli emas! Mavjud: $stock"), duration: const Duration(seconds: 1)),
                         );
                       }
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
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 400,
                height: 500,
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: "Qidirish...",
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (v) => setDialogState(() => filter = v),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
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
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context), 
                  child: Text(Provider.of<AppTranslations>(context, listen: false).text('btn_cancel'))
                ),
              ],
            );
          }
        );
      }
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;
  final bool isPrimary;

  const _HeaderButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.color,
    required this.textColor,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: isPrimary ? [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ] : null,
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
    );
  }
}
