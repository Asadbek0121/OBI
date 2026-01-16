import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:pluto_grid/pluto_grid.dart';
import '../../core/localization/app_translations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_container.dart';
import '../../core/database/database_helper.dart';
import '../../core/utils/app_notifications.dart';

class OutputView extends StatefulWidget {
  const OutputView({super.key});

  @override
  State<OutputView> createState() => _OutputViewState();
}

class _OutputViewState extends State<OutputView> {
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
      'date': PlutoCell(value: DateTime.now().toString().substring(0, 10)),
      'product': PlutoCell(value: ''),
      'qty': PlutoCell(value: 0),
      'receiver': PlutoCell(value: ''),
    });
  }

  Future<void> _saveData() async {
    final t = Provider.of<AppTranslations>(context, listen: false);
    stateManager.setShowLoading(true);
    try {
      int count = 0;
      for (var row in stateManager.rows) {
        String product = row.cells['product']?.value.toString() ?? '';
        double qty = double.tryParse(row.cells['qty']?.value.toString() ?? '0') ?? 0;
        String receiver = row.cells['receiver']?.value.toString() ?? '';
        String date = row.cells['date']?.value.toString() ?? DateTime.now().toIso8601String();

        if (product.isNotEmpty && qty > 0) {
          await DatabaseHelper.instance.insertStockOut({
             'id': DateTime.now().millisecondsSinceEpoch.toString() + count.toString(),
             'product_id': await _resolveProductId(product), 
             'date_time': date,
             'quantity': qty,
             'receiver_name': receiver,
             'created_at': DateTime.now().toIso8601String(),
          });
          count++;
        }
      }
      if (count > 0) {
        AppNotifications.showSuccess(context, "$count ${t.text('msg_saved')}");
      }
    } catch (e) {
      AppNotifications.showError(context, "Xatolik: $e");
    } finally {
      stateManager.setShowLoading(false);
    }
  }

  Future<String> _resolveProductId(String name) async {
    final db = await DatabaseHelper.instance.database;
    final res = await db.query('products', where: 'name = ?', whereArgs: [name], limit: 1);
    if (res.isNotEmpty) {
      return res.first['id'] as String;
    } else {
      final newId = DateTime.now().millisecondsSinceEpoch.toString() + (name.hashCode % 1000).toString();
      await db.insert('products', {
        'id': newId,
        'name': name,
        'unit': 'dona',
        'created_at': DateTime.now().toIso8601String(),
      });
      return newId;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<AppTranslations>(context);
    
    final columns = [
      PlutoColumn(
        title: t.text('col_date'), 
        field: 'date', 
        type: PlutoColumnType.date(format: 'yyyy-MM-dd'),
        width: 120,
      ),
      PlutoColumn(
        title: t.text('col_product'), 
        field: 'product', 
        type: PlutoColumnType.text(),
        width: 300,
      ),
      PlutoColumn(
        title: t.text('label_quantity'), 
        field: 'qty', 
        type: PlutoColumnType.number(),
        width: 100,
      ),
      PlutoColumn(
        title: t.text('col_to_receiver'), 
        field: 'receiver', 
        type: PlutoColumnType.text(),
        width: 200,
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(t.text('out_title'), style: Theme.of(context).textTheme.headlineMedium),
                ElevatedButton.icon(
                  onPressed: _saveData,
                  icon: const Icon(Icons.save),
                  label: Text(t.text('btn_save')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error, 
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
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
                  configuration: PlutoGridConfiguration(
                    style: PlutoGridStyleConfig(
                      gridBorderColor: Colors.transparent,
                      gridBackgroundColor: Colors.transparent,
                      rowColor: Colors.transparent, 
                      enableGridBorderShadow: false,
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
