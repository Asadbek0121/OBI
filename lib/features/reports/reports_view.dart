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
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

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
        cells: {
          'date': PlutoCell(value: item['date_time'].toString().substring(0, 10)),
          'product': PlutoCell(value: item['product_name']),
          'quantity': PlutoCell(value: item['quantity']),
          'unit': PlutoCell(value: item['unit']),
          'price': PlutoCell(value: item['price_per_unit']),
          'total': PlutoCell(value: item['total_amount']),
          'party': PlutoCell(value: item['supplier_name']),
        }
      )).toList();

      // Load Stock Out Data
      final outData = await DatabaseHelper.instance.getStockOutReport(startDate: startStr, endDate: endStr);
      _outRows = outData.map((item) => PlutoRow(
        cells: {
          'date': PlutoCell(value: item['date_time'].toString().substring(0, 10)),
          'product': PlutoCell(value: item['product_name']),
          'quantity': PlutoCell(value: item['quantity']),
          'unit': PlutoCell(value: item['unit']),
          'party': PlutoCell(value: item['receiver_name']),
          'notes': PlutoCell(value: item['notes'] ?? ''),
        }
      )).toList();
    } catch (e) {
      debugPrint("Error loading reports: $e");
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
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

  Future<void> _exportToExcel() async {
    final t = Provider.of<AppTranslations>(context, listen: false);
    final stateManager = _tabController.index == 0 ? _inStateManager : _outStateManager;
    
    if (stateManager == null || stateManager.rows.isEmpty) {
      AppNotifications.showInfo(context, t.text('msg_no_data'));
      return;
    }

    try {
      var excel = Excel.createExcel();
      
      // 1. Setup Sheet
      // Rename default sheet
      String sheetName = _tabController.index == 0 ? "Kirim (Stock In)" : "Chiqim (Stock Out)";
      excel.rename('Sheet1', sheetName);
      Sheet sheet = excel[sheetName];

      // 2. Add Headers with Styling
      List<String> headers = stateManager.columns.map((c) => c.title).toList();
      
      for (var i = 0; i < headers.length; i++) {
        var cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = CellStyle(
          bold: true,
          horizontalAlign: HorizontalAlign.Center,
          backgroundColorHex: ExcelColor.fromHexString("#E0E0E0"),
          fontFamily: getFontFamily(FontFamily.Arial),
        );
        
        // Set Column Widths
        double width = 20.0;
        if (stateManager.columns[i].field == 'product') width = 40.0;
        else if (stateManager.columns[i].field == 'date') width = 15.0;
        else if (stateManager.columns[i].field == 'unit') width = 10.0;
        else if (stateManager.columns[i].field == 'quantity') width = 12.0;
        
        sheet.setColumnWidth(i, width);
      }

      // 3. Add Data with Correct Types
      int rowIndex = 1;
      for (var row in stateManager.rows) {
        int colIndex = 0;
        for (var col in stateManager.columns) {
          var val = row.cells[col.field]?.value;
          var cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: colIndex, rowIndex: rowIndex));
          
          if (val == null || val.toString().isEmpty) {
            cell.value = TextCellValue("");
          } else {
             // Check for numeric fields to store as Number
             if (['quantity', 'price', 'total', 'total_amount', 'tax_sum', 'surcharge_sum'].contains(col.field)) {
                 double? numVal = double.tryParse(val.toString());
                 if (numVal != null) {
                    cell.value = DoubleCellValue(numVal);
                    // Optional: Format currency if needed, but raw number is better for calculation
                 } else {
                    cell.value = TextCellValue(val.toString());
                 }
             } else {
                 cell.value = TextCellValue(val.toString());
             }
          }
          // Center align standard text columns
           if (!['product', 'notes', 'party'].contains(col.field)) {
              cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Center);
           }
          
          colIndex++;
        }
        rowIndex++;
      }

      // 3. Save File
      var fileBytes = excel.save();
      if (fileBytes == null) return;

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
                    columns: _getInColumns(t), 
                    rows: _inRows, 
                    onLoaded: (e) => _inStateManager = e.stateManager
                  ),
                  _buildGrid(
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

  Widget _buildGrid({required List<PlutoColumn> columns, required List<PlutoRow> rows, required Function(PlutoGridOnLoadedEvent) onLoaded}) {
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
      PlutoColumn(title: t.text('col_date'), field: 'date', type: PlutoColumnType.text(), width: 120),
      PlutoColumn(title: t.text('col_product'), field: 'product', type: PlutoColumnType.text(), width: 250),
      PlutoColumn(title: t.text('col_qty'), field: 'quantity', type: PlutoColumnType.number(), width: 100),
      PlutoColumn(title: t.text('col_unit'), field: 'unit', type: PlutoColumnType.text(), width: 80),
      PlutoColumn(title: t.text('col_price'), field: 'price', type: PlutoColumnType.currency(symbol: ''), width: 120),
      PlutoColumn(title: t.text('col_total_amount'), field: 'total', type: PlutoColumnType.currency(symbol: ''), width: 150),
      PlutoColumn(title: t.text('col_from'), field: 'party', type: PlutoColumnType.text(), width: 150),
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
    ];
  }
}
