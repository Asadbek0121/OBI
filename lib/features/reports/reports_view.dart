import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:clinical_warehouse/core/localization/app_translations.dart';
import 'package:clinical_warehouse/core/theme/app_colors.dart';
import 'package:clinical_warehouse/core/database/database_helper.dart';
import '../../core/utils/app_notifications.dart';
import '../../core/theme/grid_theme.dart';
import '../../core/widgets/app_dialogs.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:file_picker/file_picker.dart';
import '../../core/services/telegram_service.dart';
import '../../core/widgets/liquid_glass.dart';
import 'reports_dashboard_view.dart';

class ReportsView extends StatefulWidget {
  const ReportsView({super.key});

  @override
  State<ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<ReportsView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();
  
  List<PlutoRow> _inRows = [];
  List<PlutoRow> _outRows = [];
  bool _isLoading = true;
  
  PlutoGridStateManager? _inStateManager;
  PlutoGridStateManager? _outStateManager;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
       if (_tabController.indexIsChanging) {
         _loadData();
       }
    });
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final startStr = _startDate.toIso8601String().substring(0, 10);
    final endStr = _endDate.toIso8601String().substring(0, 10);

    try {
      // Load Stock In Data
      final inData = await DatabaseHelper.instance.getStockInReport(startDate: startStr, endDate: endStr);
      _inRows = inData.map((item) => PlutoRow(
        key: ValueKey(item['id']),
        cells: {
          'date': PlutoCell(value: item['date_time'].toString().length >= 16 ? item['date_time'].toString().substring(0, 16) : item['date_time'].toString()),
          'product_id': PlutoCell(value: item['product_id']),
          'product': PlutoCell(value: item['product_name']),
          'price': PlutoCell(value: item['price_per_unit']),
          'unit': PlutoCell(value: item['unit']),
          'quantity': PlutoCell(value: item['quantity']),
          'tax_percent': PlutoCell(value: item['tax_percent'] ?? 0),
          'tax_sum': PlutoCell(value: item['tax_sum'] ?? 0),
          'surcharge_percent': PlutoCell(value: item['surcharge_percent'] ?? 0),
          'surcharge_sum': PlutoCell(value: item['surcharge_sum'] ?? 0),
          'party': PlutoCell(value: item['supplier_name']),
          'payment_status': PlutoCell(value: item['payment_status'] ?? '-'),
          'total': PlutoCell(value: item['total_amount']),
          'actions': PlutoCell(value: ''),
        }
      )).toList();

      // Load Stock Out Data
      final outData = await DatabaseHelper.instance.getStockOutReport(startDate: startStr, endDate: endStr);
      _outRows = outData.map((item) => PlutoRow(
        key: ValueKey(item['id']),
        cells: {
          'date': PlutoCell(value: item['date_time'].toString().length >= 16 ? item['date_time'].toString().substring(0, 16) : item['date_time'].toString()),
          'product': PlutoCell(value: item['product_name']),
          'quantity': PlutoCell(value: item['quantity']),
          'unit': PlutoCell(value: item['unit']),
          'party': PlutoCell(value: item['receiver_name']),
          'notes': PlutoCell(value: item['notes'] ?? ''),
          'actions': PlutoCell(value: ''),
        }
      )).toList();
    } catch (e) {
      debugPrint("Error loading reports: $e");
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _onDeleteRow(PlutoColumnRendererContext rendererContext, bool isIn) async {
    final t = Provider.of<AppTranslations>(context, listen: false);
    if (rendererContext.row.key is! ValueKey) return;
    final dynamic id = (rendererContext.row.key as ValueKey).value;

    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: t.text('btn_delete'),
      content: t.text('rep_delete_confirm'),
    );

    if (confirmed == true) {
      try {
        if (isIn) {
          await DatabaseHelper.instance.deleteStockIn(id);
        } else {
           await DatabaseHelper.instance.deleteStockOut(id);
        }
        if (mounted) {
          rendererContext.stateManager.removeRows([rendererContext.row]);
          AppNotifications.showSuccess(context, t.text('msg_deleted'));
        }
      } catch (e) {
        if (mounted) AppNotifications.showError(context, "${t.text('msg_error')}: $e");
      }
    }
  }

  void _onEditRow(PlutoColumnRendererContext rendererContext, bool isIn) {
    final t = Provider.of<AppTranslations>(context, listen: false);
    if (rendererContext.row.key is! ValueKey) return;
    final dynamic id = (rendererContext.row.key as ValueKey).value;
    final cells = rendererContext.row.cells;

    // Controllers
    final nameController = TextEditingController(text: cells['product']?.value.toString());
    final qtyController = TextEditingController(text: cells['quantity']?.value?.toString());
    final partyController = TextEditingController(text: cells['party']?.value?.toString());
    
    // Date Handling
    DateTime currentDt;
    try {
      currentDt = DateTime.parse(cells['date']?.value.toString() ?? DateTime.now().toString());
    } catch (_) {
      currentDt = DateTime.now();
    }
    DateTime tempDate = currentDt;
    TimeOfDay tempTime = TimeOfDay.fromDateTime(currentDt);

    // Specific Fields
    final priceController = isIn ? TextEditingController(text: cells['price']?.value?.toString()) : null;
    final notesController = !isIn ? TextEditingController(text: cells['notes']?.value?.toString()) : null;
    
    String? paymentStatus = isIn ? (cells['payment_status']?.value?.toString()) : null;
    if (paymentStatus == '-') paymentStatus = null;
    final paymentOptions = [t.text('pay_cash'), t.text('pay_debt'), t.text('pay_transfer')];

    // Helper for styled input
    InputDecoration fieldDecor(String label, IconData icon) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.grey[600]),
        prefixIcon: Icon(icon, size: 20, color: isDark ? Colors.white70 : Colors.grey[600]),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey[300]!)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey[300]!)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
        filled: true,
        fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[50], 
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );
    }

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text("${t.text('rep_edit_title')} (${isIn ? t.text('menu_in') : t.text('menu_out')})", style: const TextStyle(fontWeight: FontWeight.bold)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            scrollable: true,
            contentPadding: const EdgeInsets.all(24),
            content: SizedBox(
              width: 400, // Fixed width for better look on desktop
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                    TextField(
                      controller: nameController, 
                      decoration: fieldDecor(t.text('label_reagent'), Icons.inventory_2),
                      enabled: false,
                      style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color),
                    ),
                   const SizedBox(height: 16),
                  
                  // Date & Time Picker Row
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final d = await showDatePicker(context: context, initialDate: tempDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
                            if (d != null) setStateDialog(() => tempDate = d);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.grey[50],
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today, size: 18, color: AppColors.primary),
                                const SizedBox(width: 8),
                                Text("${tempDate.year}-${tempDate.month.toString().padLeft(2,'0')}-${tempDate.day.toString().padLeft(2,'0')}", style: const TextStyle(fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final t = await showTimePicker(context: context, initialTime: tempTime);
                            if (t != null) setStateDialog(() => tempTime = t);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.grey[50],
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.schedule, size: 18, color: AppColors.primary),
                                const SizedBox(width: 8),
                                Text("${tempTime.hour.toString().padLeft(2,'0')}:${tempTime.minute.toString().padLeft(2,'0')}", style: const TextStyle(fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  TextField(controller: qtyController, decoration: fieldDecor(t.text('col_qty'), Icons.numbers), keyboardType: TextInputType.number),
                  const SizedBox(height: 16),
                  
                  TextField(
                    controller: partyController, 
                    decoration: fieldDecor(isIn ? t.text('col_from') : t.text('col_to'), isIn ? Icons.business : Icons.person)
                  ),
                  
                  if (isIn) ...[
                    const SizedBox(height: 16),
                    TextField(controller: priceController, decoration: fieldDecor(t.text('col_price'), Icons.attach_money), keyboardType: TextInputType.number),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: paymentOptions.contains(paymentStatus) ? paymentStatus : null,
                      decoration: fieldDecor(t.text('col_payment_status'), Icons.payment),
                      dropdownColor: Theme.of(context).cardColor,
                      items: paymentOptions.map<DropdownMenuItem<String>>((e) => DropdownMenuItem<String>(value: e, child: Text(e))).toList(),
                      onChanged: (v) => paymentStatus = v,
                    ),
                  ],

                  if (!isIn) ...[
                     const SizedBox(height: 16),
                     TextField(controller: notesController, decoration: fieldDecor(t.text('col_notes'), Icons.edit_note), maxLines: 2),
                  ],
                ],
              ),
            ),
            actionsPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c), 
                style: TextButton.styleFrom(foregroundColor: Colors.grey[600]),
                child: Text(t.text('btn_cancel'))
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    final qty = double.tryParse(qtyController.text) ?? 0;
                    if (qty <= 0) {
                      AppNotifications.showError(this.context, t.text('msg_error'));
                      return;
                    }
                    
                    // Reconstruct DateTime
                    final finalDt = DateTime(tempDate.year, tempDate.month, tempDate.day, tempTime.hour, tempTime.minute);

                    final Map<String, dynamic> updateData = {
                      'quantity': qty,
                      'date_time': finalDt.toString(), // Save full string
                    };

                    if (isIn) {
                       updateData['supplier_name'] = partyController.text;
                       if (priceController != null) {
                         final price = double.tryParse(priceController.text) ?? 0;
                         updateData['price_per_unit'] = price;
                         updateData['total_amount'] = price * qty;
                       }
                       if (paymentStatus != null) {
                         updateData['payment_status'] = paymentStatus;
                       }
                    } else {
                       updateData['receiver_name'] = partyController.text;
                       if (notesController != null) {
                         updateData['notes'] = notesController.text;
                       }
                    }

                    if (isIn) {
                      await DatabaseHelper.instance.updateStockIn(id, updateData);
                    } else {
                      await DatabaseHelper.instance.updateStockOut(id, updateData);
                    }

                    if (!context.mounted) return;
                    Navigator.pop(c);
                    _loadData(); // Reload to refresh grid
                    AppNotifications.showSuccess(context, t.text('msg_updated'));
                  } catch (e) {
                    if (!context.mounted) return;
                    AppNotifications.showError(context, "${t.text('msg_error')}: $e");
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white, 
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ), 
                child: Text(t.text('btn_save'))
              ),
            ],
          );
        }
      )
    );
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadData();
    }
  }



  Future<List<int>?> _generateComprehensiveExcel() async {
    final t = Provider.of<AppTranslations>(context, listen: false);
    try {
      var excel = excel_pkg.Excel.createExcel();
      
      // Define Styles
      final border = excel_pkg.Border(
        borderStyle: excel_pkg.BorderStyle.Thin,
        borderColorHex: excel_pkg.ExcelColor.fromHexString("#000000"),
      );

      final headerStyle = excel_pkg.CellStyle(
        backgroundColorHex: excel_pkg.ExcelColor.fromHexString("#1976D2"), // Blue
        fontColorHex: excel_pkg.ExcelColor.fromHexString("#FFFFFF"), // White
        fontFamily: excel_pkg.getFontFamily(excel_pkg.FontFamily.Arial),
        bold: true,
        horizontalAlign: excel_pkg.HorizontalAlign.Center,
        verticalAlign: excel_pkg.VerticalAlign.Center,
        topBorder: border,
        bottomBorder: border,
        leftBorder: border,
        rightBorder: border,
      );

      final dataStyle = excel_pkg.CellStyle(
        fontFamily: excel_pkg.getFontFamily(excel_pkg.FontFamily.Arial),
        verticalAlign: excel_pkg.VerticalAlign.Center,
        topBorder: border,
        bottomBorder: border,
        leftBorder: border,
        rightBorder: border,
      );

      final totalStyle = excel_pkg.CellStyle(
        backgroundColorHex: excel_pkg.ExcelColor.fromHexString("#FFFF00"), // Yellow
        fontFamily: excel_pkg.getFontFamily(excel_pkg.FontFamily.Arial),
        bold: true,
        verticalAlign: excel_pkg.VerticalAlign.Center,
        topBorder: border,
        bottomBorder: border,
        leftBorder: border,
        rightBorder: border,
      );

      // Helper to add header
      void addHeader(excel_pkg.Sheet sheet, List<String> titles) {
        for (var i = 0; i < titles.length; i++) {
          var cell = sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
          cell.value = excel_pkg.TextCellValue(titles[i]);
          cell.cellStyle = headerStyle;
        }
      }

      // Helper to append row with style
      void appendRowWithStyle(excel_pkg.Sheet sheet, List<excel_pkg.CellValue> cells) {
        sheet.appendRow(cells);
        final rowIndex = sheet.maxRows - 1;
        for (var i = 0; i < cells.length; i++) {
          var cell = sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: rowIndex));
          cell.cellStyle = dataStyle;
        }
      }

      // 1. KIRIM (IN)
      excel_pkg.Sheet sheetIn = excel[t.text('menu_in')];
      addHeader(sheetIn, [
        t.text('col_date'), 
        t.text('col_id'), 
        t.text('col_product'), 
        t.text('col_price'), 
        t.text('col_unit'), 
        t.text('col_qty'), 
        t.text('col_tax_percent'), 
        t.text('col_tax_sum'), 
        t.text('col_surcharge_percent'), 
        t.text('col_surcharge_sum'), 
        t.text('col_from'), 
        t.text('col_payment_status'), 
        t.text('col_total_amount')
      ]);

      double grandTotal = 0.0;
      for (var row in _inRows) {
        final total = double.tryParse(row.cells['total']?.value.toString() ?? '0') ?? 0;
        grandTotal += total;

        appendRowWithStyle(sheetIn, [
          excel_pkg.TextCellValue(row.cells['date']?.value.toString() ?? ''),
          excel_pkg.TextCellValue(row.cells['product_id']?.value.toString() ?? ''),
          excel_pkg.TextCellValue(row.cells['product']?.value.toString() ?? ''),
          excel_pkg.DoubleCellValue(double.tryParse(row.cells['price']?.value.toString() ?? '0') ?? 0),
          excel_pkg.TextCellValue(row.cells['unit']?.value.toString() ?? ''),
          excel_pkg.DoubleCellValue(double.tryParse(row.cells['quantity']?.value.toString() ?? '0') ?? 0),
          excel_pkg.DoubleCellValue(double.tryParse(row.cells['tax_percent']?.value.toString() ?? '0') ?? 0),
          excel_pkg.DoubleCellValue(double.tryParse(row.cells['tax_sum']?.value.toString() ?? '0') ?? 0),
          excel_pkg.DoubleCellValue(double.tryParse(row.cells['surcharge_percent']?.value.toString() ?? '0') ?? 0),
          excel_pkg.DoubleCellValue(double.tryParse(row.cells['surcharge_sum']?.value.toString() ?? '0') ?? 0),
          excel_pkg.TextCellValue(row.cells['party']?.value.toString() ?? ''),
          excel_pkg.TextCellValue(row.cells['payment_status']?.value.toString() ?? ''),
          excel_pkg.DoubleCellValue(total),
        ]);
      }

      // Add Total Row
      sheetIn.appendRow([
        excel_pkg.TextCellValue(''),
        excel_pkg.TextCellValue(''),
        excel_pkg.TextCellValue(''),
        excel_pkg.TextCellValue(''),
        excel_pkg.TextCellValue(''),
        excel_pkg.TextCellValue(''),
        excel_pkg.TextCellValue(''),
        excel_pkg.TextCellValue(''),
        excel_pkg.TextCellValue(''),
        excel_pkg.TextCellValue(''),
        excel_pkg.TextCellValue(''),
        excel_pkg.TextCellValue(''),
        excel_pkg.DoubleCellValue(grandTotal),
      ]);
      
      // Style only the last cell (Total)
      var totalRowIndex = sheetIn.maxRows - 1;
      var totalCell = sheetIn.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: totalRowIndex));
      totalCell.cellStyle = totalStyle;

      // 2. CHIQIM (OUT)
      excel_pkg.Sheet sheetOut = excel[t.text('menu_out')];
      addHeader(sheetOut, [
        t.text('col_date'), 
        t.text('col_product'), 
        t.text('col_qty'), 
        t.text('col_unit'), 
        t.text('col_to'), 
        t.text('col_notes')
      ]);

      for (var row in _outRows) {
        appendRowWithStyle(sheetOut, [
          excel_pkg.TextCellValue(row.cells['date']?.value.toString() ?? ''),
          excel_pkg.TextCellValue(row.cells['product']?.value.toString() ?? ''),
          excel_pkg.DoubleCellValue(double.tryParse(row.cells['quantity']?.value.toString() ?? '0') ?? 0),
          excel_pkg.TextCellValue(row.cells['unit']?.value.toString() ?? ''),
          excel_pkg.TextCellValue(row.cells['party']?.value.toString() ?? ''),
          excel_pkg.TextCellValue(row.cells['notes']?.value.toString() ?? ''),
        ]);
      }

      // 3. QOLDIQ (STOCK)
      excel_pkg.Sheet sheetStock = excel[t.text('menu_inventory')];
      addHeader(sheetStock, [t.text('col_product'), t.text('col_unit'), t.text('col_stock')]);

      final stockData = await DatabaseHelper.instance.getInventorySummary();
      for (var item in stockData) {
          appendRowWithStyle(sheetStock, [
             excel_pkg.TextCellValue(item['name'].toString()),
             excel_pkg.TextCellValue(item['unit'].toString()),
             excel_pkg.DoubleCellValue((item['stock'] as num).toDouble()),
          ]);
      }

      // Clean up default sheet
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      return excel.save();
    } catch (e) {
      debugPrint("Comprehensive Excel Error: $e");
      return null;
    }
  }

  Future<List<int>?> _generateExcel() async {
    final stateManager = _tabController.index == 0 ? _inStateManager : _outStateManager;
    
    if (stateManager == null || stateManager.rows.isEmpty) {
      return null;
    }

    try {
      var excel = excel_pkg.Excel.createExcel();
      excel_pkg.Sheet sheet = excel['Sheet1'];
      
      // Headers
      List<excel_pkg.CellValue> headers = [];
      for (var col in stateManager.columns) {
        headers.add(excel_pkg.TextCellValue(col.title));
      }
      sheet.appendRow(headers);
      
      // Rows
      for (var row in stateManager.rows) {
        List<excel_pkg.CellValue> rowData = [];
        for (var col in stateManager.columns) {
          var val = row.cells[col.field]?.value;
          if (val == null) {
            rowData.add(excel_pkg.TextCellValue(''));
          } else if (val is num || double.tryParse(val.toString()) != null) {
            rowData.add(excel_pkg.DoubleCellValue(double.tryParse(val.toString()) ?? 0));
          } else {
            rowData.add(excel_pkg.TextCellValue(val.toString()));
          }
        }
        sheet.appendRow(rowData);
      }
      return excel.save();
    } catch (e) {
      debugPrint("Excel Error: $e");
      return null;
    }
  }

  Future<void> _exportToExcel() async {
    final t = Provider.of<AppTranslations>(context, listen: false);
    final fileBytes = await _generateExcel();
    if (fileBytes == null) {
       if (!mounted) return;
       AppNotifications.showInfo(context, t.text('msg_no_data'));
       return;
    }
    
    try {
      // 3. Save File


      final type = _tabController.index == 0 ? "In" : "Out";
      final fileName = "Report_${type}_${DateTime.now().toString().substring(0,10)}.xlsx";

      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: t.text('btn_export_excel'),
          fileName: fileName,
          allowedExtensions: ['xlsx'],
          type: FileType.custom,
        );

        if (outputFile != null) {
          File(outputFile)
            ..createSync(recursive: true)
            ..writeAsBytesSync(fileBytes);
            
          if (mounted) {
            AppNotifications.showSuccess(context, t.text('msg_saved'));
          }
        }
      } else {
        // Mobile fallback (save to docs)
        final directory = await getApplicationDocumentsDirectory();
        final path = "${directory.path}/$fileName";
        File(path)
          ..createSync(recursive: true)
          ..writeAsBytesSync(fileBytes);
          
         if (mounted) {
            AppNotifications.showSuccess(context, "${t.text('msg_saved')}: $path");
         }
      }

    } catch (e) {
      if (mounted) {
        AppNotifications.showError(context, "${t.text('msg_error')}: $e");
      }
    }
  }

  final _telegramService = TelegramService();

  Future<void> _sendToTelegram() async {
    final t = Provider.of<AppTranslations>(context, listen: false);
    final allUsers = await _telegramService.getUsers();
    final users = allUsers.where((u) => u['role'] == 'admin').toList();
    
    if (!mounted) return;
    
    if (users.isEmpty) {
      AppNotifications.showError(context, t.text('rep_msg_add_telegram'));
      return;
    }

    final fileBytes = await _generateComprehensiveExcel();
    if (fileBytes == null) {
      if (!mounted) return;
      AppNotifications.showInfo(context, t.text('msg_no_data'));
      return;
    }

    if (!mounted) return;
    // Select User
    final selectedUser = await showDialog<Map<String, dynamic>>(
      context: context, 
      builder: (c) => SimpleDialog(
        title: Text(t.text('rep_transfer_to')),
        children: users.map((u) => SimpleDialogOption(
          child: ListTile(
            leading: const Icon(Icons.person),
            title: Text(u['name']),
            subtitle: Text(u['role'] ?? ''),
          ),
          onPressed: () => Navigator.pop(c, u),
        )).toList(),
      )
    );

    if (selectedUser == null) return;
    
    if (!mounted) return;
    
    // Show Loading Dialog
    AppDialogs.showBlurDialog(context: context, title: t.text('rep_sending'), content: const CircularProgressIndicator());
    
    try {
      // Save Temp File
      final tempDir = await getTemporaryDirectory();
      final fileName = "Hisobot_${DateTime.now().toIso8601String().substring(0,19).replaceAll(':','-')}.xlsx";
      final file = File('${tempDir.path}/$fileName');
      
      // Ensure file and directory exist
      await file.create(recursive: true);
      await file.writeAsBytes(fileBytes);

      // Send
      final error = await _telegramService.sendDocument(
        selectedUser['chatId'], 
        file, 
        caption: "📊 ${selectedUser['name']} ${t.text('rep_in_report').toLowerCase()}.\n${t.text('col_date')}: ${_startDate.toString().substring(0,10)} - ${_endDate.toString().substring(0,10)}"
      ).timeout(const Duration(seconds: 30)); // 30s timeout

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (mounted) {
        Navigator.pop(context); // Close loading dialog on error
        AppNotifications.showError(context, "${t.text('msg_error')}: $error");
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog on error
        AppNotifications.showError(context, "${t.text('msg_error')}: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
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
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 16,
              runSpacing: 16,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.text('rep_title'), style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: LiquidColors.of(context).title,
                      letterSpacing: -0.5,
                    )),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_month_rounded, size: 14, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            "${_startDate.toString().substring(0,10)} — ${_endDate.toString().substring(0,10)}",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _HeaderBtn(
                      onPressed: _selectDateRange,
                      icon: Icons.date_range_rounded,
                      label: t.text('rep_select_date'),
                      color: AppColors.primary.withValues(alpha: 0.1),
                      textColor: AppColors.primary,
                    ),
                    _HeaderBtn(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsDashboardView())),
                      icon: Icons.analytics_rounded,
                      label: "Analytics",
                      color: AppColors.primary,
                      textColor: Colors.white,
                      isPrimary: true,
                    ),
                    const SizedBox(width: 12),
                    _HeaderBtn(
                      onPressed: _exportToExcel,
                      icon: Icons.download_rounded,
                      label: "Excel",
                      color: AppColors.success,
                      textColor: Colors.white,
                      isPrimary: true,
                    ),
                    const SizedBox(width: 12),
                    _HeaderBtn(
                      onPressed: _sendToTelegram,
                      icon: Icons.send_rounded,
                      label: "Telegram",
                      color: const Color(0xFF229ED9), // Telegram Blue
                      textColor: Colors.white,
                      isPrimary: true,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              height: 50,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(4),
              child: TabBar(
                controller: _tabController,
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                labelColor: AppColors.primary,
                unselectedLabelColor: Colors.grey[600],
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                tabs: [
                  Tab(text: t.text('rep_in_report')),
                  Tab(text: t.text('rep_out_report')),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildGridContainer(
                    context,
                    columns: _getInColumns(t), 
                    rows: _inRows, 
                    onLoaded: (e) => _inStateManager = e.stateManager,
                    config: gridConfig,
                  ),
                  _buildGridContainer(
                    context,
                    columns: _getOutColumns(t), 
                    rows: _outRows, 
                    onLoaded: (e) => _outStateManager = e.stateManager,
                    config: gridConfig,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridContainer(BuildContext context, {
    required List<PlutoColumn> columns, 
    required List<PlutoRow> rows, 
    required Function(PlutoGridOnLoadedEvent) onLoaded,
    required PlutoGridConfiguration config,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
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
          columns: columns,
          rows: rows,
          onLoaded: onLoaded,
          mode: PlutoGridMode.readOnly,
          configuration: config,
        ),
      ),
    );
  }

  List<PlutoColumn> _getInColumns(AppTranslations t) {
    return [
      PlutoColumn(title: t.text('col_date'), field: 'date', type: PlutoColumnType.text(), width: 110),
      PlutoColumn(title: t.text('col_id'), field: 'product_id', type: PlutoColumnType.text(), width: 80),
      PlutoColumn(title: t.text('col_product'), field: 'product', type: PlutoColumnType.text(), width: 200),
      PlutoColumn(title: t.text('col_price'), field: 'price', type: PlutoColumnType.currency(symbol: ''), width: 100),
      PlutoColumn(title: t.text('col_unit'), field: 'unit', type: PlutoColumnType.text(), width: 70),
      PlutoColumn(title: t.text('col_qty'), field: 'quantity', type: PlutoColumnType.number(), width: 80),
      PlutoColumn(title: t.text('col_tax_percent'), field: 'tax_percent', type: PlutoColumnType.number(), width: 80),
      PlutoColumn(title: t.text('col_tax_sum'), field: 'tax_sum', type: PlutoColumnType.number(), width: 100),
      PlutoColumn(title: t.text('col_surcharge_percent'), field: 'surcharge_percent', type: PlutoColumnType.number(), width: 80),
      PlutoColumn(title: t.text('col_surcharge_sum'), field: 'surcharge_sum', type: PlutoColumnType.number(), width: 100),
      PlutoColumn(title: t.text('col_from'), field: 'party', type: PlutoColumnType.text(), width: 120),
      PlutoColumn(title: t.text('col_payment_status'), field: 'payment_status', type: PlutoColumnType.text(), width: 120),
      PlutoColumn(title: t.text('col_total_amount'), field: 'total', type: PlutoColumnType.currency(symbol: ''), width: 120),
      PlutoColumn(
        title: t.text('actions'),
        field: 'actions',
        type: PlutoColumnType.text(),
        width: 100,
        enableSorting: false,
        enableFilterMenuItem: false,
        renderer: (rendererContext) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.blue, size: 18),
                onPressed: () => _onEditRow(rendererContext, true),
                tooltip: "Tahrirlash",
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                onPressed: () => _onDeleteRow(rendererContext, true),
                tooltip: "O'chirish",
              ),
            ],
          );
        },
      ),
    ];
  }

  List<PlutoColumn> _getOutColumns(AppTranslations t) {
    return [
      PlutoColumn(title: t.text('col_date'), field: 'date', type: PlutoColumnType.text(), width: 120),
      PlutoColumn(title: t.text('col_product'), field: 'product', type: PlutoColumnType.text(), width: 250),
      PlutoColumn(title: t.text('col_qty'), field: 'quantity', type: PlutoColumnType.number(), width: 100),
      PlutoColumn(title: t.text('col_unit'), field: 'unit', type: PlutoColumnType.text(), width: 80),
      PlutoColumn(title: t.text('col_to'), field: 'party', type: PlutoColumnType.text(), width: 200),
      PlutoColumn(title: t.text('col_notes'), field: 'notes', type: PlutoColumnType.text(), width: 150),
      PlutoColumn(
        title: t.text('actions'),
        field: 'actions',
        type: PlutoColumnType.text(),
        width: 100,
        enableSorting: false,
        enableFilterMenuItem: false,
        renderer: (rendererContext) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.blue, size: 18),
                onPressed: () => _onEditRow(rendererContext, false),
                tooltip: "Tahrirlash",
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                onPressed: () => _onDeleteRow(rendererContext, false),
                tooltip: "O'chirish",
              ),
            ],
          );
        },
      ),
    ];
  }
}

class _HeaderBtn extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;
  final bool isPrimary;

  const _HeaderBtn({
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
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ] : null,
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
    );
  }
}
