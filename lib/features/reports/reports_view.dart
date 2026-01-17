import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:clinical_warehouse/core/localization/app_translations.dart';
import 'package:clinical_warehouse/core/theme/app_colors.dart';
import 'package:clinical_warehouse/core/widgets/glass_container.dart';
import 'package:clinical_warehouse/core/database/database_helper.dart';
import '../../core/utils/app_notifications.dart';
import '../../core/theme/grid_theme.dart';
import '../../core/widgets/app_dialogs.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:file_picker/file_picker.dart';
import '../../core/services/telegram_service.dart';

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
          'date': PlutoCell(value: item['date_time'].toString().substring(0, 10)),
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
          'date': PlutoCell(value: item['date_time'].toString().substring(0, 10)),
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

  void _onDeleteRow(PlutoColumnRendererContext context, bool isIn) {
    if (context.row.key is! ValueKey) return;
    final int id = (context.row.key as ValueKey).value;

    AppDialogs.showConfirmDialog(
      context: this.context,
      title: "O'chirishni tasdiqlang",
      message: "Ushbu yozuvni o'chirib yubormoqchimisiz? Bu ombor qoldig'iga ta'sir qilishi mumkin.",
      onConfirm: () async {
        try {
          if (isIn) {
            await DatabaseHelper.instance.deleteStockIn(id);
          } else {
             await DatabaseHelper.instance.deleteStockOut(id);
          }
          if (mounted) {
            context.stateManager.removeRows([context.row]);
            AppNotifications.showSuccess(this.context, "Muvaffaqiyatli o'chirildi");
          }
        } catch (e) {
          if (mounted) AppNotifications.showError(this.context, "Xatolik: $e");
        }
      }
    );
  }

  void _onEditRow(PlutoColumnRendererContext context, bool isIn) {
    // Basic editing for now: Quantity, Price/Notes
    if (context.row.key is! ValueKey) return;
    final int id = (context.row.key as ValueKey).value;
    final cells = context.row.cells;

    final nameController = TextEditingController(text: cells['product']?.value.toString());
    final qtyController = TextEditingController(text: cells['quantity']?.value?.toString());
    
    // For IN: Price
    final priceController = isIn ? TextEditingController(text: cells['price']?.value?.toString()) : null;
    // For OUT: Notes
    final notesController = !isIn ? TextEditingController(text: cells['notes']?.value?.toString()) : null;

    showDialog(
      context: this.context,
      builder: (c) => AlertDialog(
        title: const Text("Tahrirlash"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Mahsulot (O\'zgartirib bo\'lmaydi)'), enabled: false),
            TextField(controller: qtyController, decoration: const InputDecoration(labelText: 'Miqdor'), keyboardType: TextInputType.number),
            if (isIn)
               TextField(controller: priceController, decoration: const InputDecoration(labelText: 'Narx'), keyboardType: TextInputType.number),
            if (!isIn)
               TextField(controller: notesController, decoration: const InputDecoration(labelText: 'Izoh')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("Bekor qilish")),
          ElevatedButton(
            onPressed: () async {
              try {
                final qty = double.tryParse(qtyController.text) ?? 0;
                if (qty <= 0) {
                  AppNotifications.showError(this.context, "Miqdor noto'g'ri");
                  return;
                }
                
                final updateData = {'quantity': qty};
                
                if (isIn && priceController != null) {
                   final price = double.tryParse(priceController.text) ?? 0;
                   updateData['price_per_unit'] = price;
                   // Recalculate total if possible, but simplified for now
                   // In a real scenario, we should recount taxes/surcharges.
                   // As a quick fix, update total roughly:
                   updateData['total_amount'] = price * qty;
                }

                if (!isIn && notesController != null) {
                  updateData['notes'] = notesController.text;
                }

                if (isIn) {
                  await DatabaseHelper.instance.updateStockIn(id, updateData);
                } else {
                  await DatabaseHelper.instance.updateStockOut(id, updateData);
                }

                if (mounted) {
                   Navigator.pop(c);
                   _loadData(); // Reload to refresh grid
                   AppNotifications.showSuccess(this.context, "Yangilandi");
                }
              } catch (e) {
                if (mounted) AppNotifications.showError(this.context, "Xatolik: $e");
              }
            }, 
            child: const Text("Saqlash")
          ),
        ],
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
      excel_pkg.Sheet sheetIn = excel['Kirim'];
      addHeader(sheetIn, ['Sana', 'ID', 'Mahsulot', 'Narxi', 'Birlik', 'Miqdori', 'QQS %', 'QQS Summa', 'Ustama %', 'Ustama Summa', 'Kimdan', 'To\'lov Holati', 'Jami Summa']);

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
      excel_pkg.Sheet sheetOut = excel['Chiqim'];
      addHeader(sheetOut, ['Sana', 'Mahsulot', 'Miqdori', 'Birlik', 'Kimga (Qabul qiluvchi)', 'Izoh']);

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
      excel_pkg.Sheet sheetStock = excel['Qoldiq'];
      addHeader(sheetStock, ['Mahsulot Nomi', 'Birlik', 'Qoldiq Miqdori']);

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
    final allUsers = await _telegramService.getUsers();
    final users = allUsers.where((u) => u['role'] == 'admin').toList();
    
    if (!mounted) return;
    
    if (users.isEmpty) {
      AppNotifications.showError(context, "Oldin sozlamalardan Telegram userni qo'shing");
      return;
    }

    final fileBytes = await _generateComprehensiveExcel();
    if (fileBytes == null) {
      AppNotifications.showInfo(context, "Ma'lumot topilmadi");
      return;
    }

    // Select User
    final selectedUser = await showDialog<Map<String, dynamic>>(
      context: context, 
      builder: (c) => SimpleDialog(
        title: const Text("Kimga yuborilsin?"),
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
    AppDialogs.showBlurDialog(context: context, title: "Yuborilmoqda...", content: const CircularProgressIndicator());
    
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
        caption: "📊 ${selectedUser['name']} uchun hisobot.\nSana: ${_startDate.toString().substring(0,10)} - ${_endDate.toString().substring(0,10)}"
      ).timeout(const Duration(seconds: 30)); // 30s timeout

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (error == null) {
        AppNotifications.showSuccess(context, "Yuborildi!");
      } else {
        AppNotifications.showError(context, "Xatolik: $error");
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog on error
        AppNotifications.showError(context, "Kutilmagan xatolik: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<AppTranslations>(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.text('rep_title'), style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  "${_startDate.toString().substring(0,10)} - ${_endDate.toString().substring(0,10)}",
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _selectDateRange,
                  icon: const Icon(Icons.date_range),
                  label: Text(t.text('rep_select_date')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                    foregroundColor: AppColors.primary,
                    elevation: 0,
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _exportToExcel, 
                  icon: const Icon(Icons.download), 
                  label: Text(t.text('btn_export_excel')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _sendToTelegram,
                  icon: const Icon(Icons.send, color: Colors.white, size: 20),
                  label: const Text("Telegram"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppColors.primary,
          tabs: [
            Tab(text: "📦 ${t.text('rep_in_report')}"),
            Tab(text: "📤 ${t.text('rep_out_report')}"),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildGrid(
                    context,
                    columns: _getInColumns(t), 
                    rows: _inRows, 
                    onLoaded: (e) => _inStateManager = e.stateManager
                  ),
                  _buildGrid(
                    context,
                    columns: _getOutColumns(t), 
                    rows: _outRows, 
                    onLoaded: (e) => _outStateManager = e.stateManager
                  ),
                ],
              ),
        ),
      ],
    );
  }

  Widget _buildGrid(BuildContext context, {required List<PlutoColumn> columns, required List<PlutoRow> rows, required Function(PlutoGridOnLoadedEvent) onLoaded}) {
    return GlassContainer(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: PlutoGrid(
          key: ValueKey(Provider.of<AppTranslations>(context).currentLocale),
          columns: columns,
          rows: rows,
          onLoaded: onLoaded,
          mode: PlutoGridMode.readOnly,
          configuration: PlutoGridConfiguration(
            localeText: PlutoGridLocaleText(
              unfreezeColumn: Provider.of<AppTranslations>(context, listen: false).text('grid_unfreeze'),
              freezeColumnToStart: Provider.of<AppTranslations>(context, listen: false).text('grid_freeze_start'),
              freezeColumnToEnd: Provider.of<AppTranslations>(context, listen: false).text('grid_freeze_end'),
              autoFitColumn: Provider.of<AppTranslations>(context, listen: false).text('grid_auto_fit'),
              hideColumn: Provider.of<AppTranslations>(context, listen: false).text('grid_hide_column'),
              setColumns: Provider.of<AppTranslations>(context, listen: false).text('grid_set_columns'),
              setFilter: Provider.of<AppTranslations>(context, listen: false).text('grid_set_filter'),
              resetFilter: Provider.of<AppTranslations>(context, listen: false).text('grid_reset_filter'),
            ),
            style: GridTheme.getStyle(context),
          ),
        ),
      ),
    );
  }

  List<PlutoColumn> _getInColumns(AppTranslations t) {
    return [
      PlutoColumn(title: t.text('col_date'), field: 'date', type: PlutoColumnType.text(), width: 110),
      PlutoColumn(title: t.text('col_id') ?? 'ID', field: 'product_id', type: PlutoColumnType.text(), width: 80),
      PlutoColumn(title: t.text('col_product'), field: 'product', type: PlutoColumnType.text(), width: 200),
      PlutoColumn(title: t.text('col_price'), field: 'price', type: PlutoColumnType.currency(symbol: ''), width: 100),
      PlutoColumn(title: t.text('col_unit'), field: 'unit', type: PlutoColumnType.text(), width: 70),
      PlutoColumn(title: t.text('col_qty'), field: 'quantity', type: PlutoColumnType.number(), width: 80),
      PlutoColumn(title: t.text('col_tax_percent') ?? 'QQS %', field: 'tax_percent', type: PlutoColumnType.number(), width: 80),
      PlutoColumn(title: t.text('col_tax_sum') ?? 'QQS Sum', field: 'tax_sum', type: PlutoColumnType.number(), width: 100),
      PlutoColumn(title: t.text('col_surcharge_percent') ?? 'Ustama %', field: 'surcharge_percent', type: PlutoColumnType.number(), width: 80),
      PlutoColumn(title: t.text('col_surcharge_sum') ?? 'Ustama Sum', field: 'surcharge_sum', type: PlutoColumnType.number(), width: 100),
      PlutoColumn(title: t.text('col_from'), field: 'party', type: PlutoColumnType.text(), width: 120),
      PlutoColumn(title: t.text('col_payment_status'), field: 'payment_status', type: PlutoColumnType.text(), width: 120),
      PlutoColumn(title: t.text('col_total_amount'), field: 'total', type: PlutoColumnType.currency(symbol: ''), width: 120),
      PlutoColumn(
        title: t.text('actions') ?? 'Amallar',
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
      PlutoColumn(title: t.text('col_to') ?? 'Kimga', field: 'party', type: PlutoColumnType.text(), width: 200),
      PlutoColumn(title: t.text('col_notes') ?? 'Izoh', field: 'notes', type: PlutoColumnType.text(), width: 150),
      PlutoColumn(
        title: t.text('actions') ?? 'Amallar',
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
