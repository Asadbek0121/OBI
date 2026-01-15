import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:clinical_warehouse/core/theme/app_colors.dart';
import 'package:clinical_warehouse/core/theme/grid_theme.dart';
import 'package:clinical_warehouse/core/widgets/glass_container.dart';
import 'package:clinical_warehouse/core/widgets/app_dialogs.dart';
import 'package:clinical_warehouse/core/localization/app_translations.dart';
import 'package:clinical_warehouse/core/database/database_helper.dart';
import 'package:clinical_warehouse/core/utils/app_notifications.dart';

class ProductDatabaseView extends StatefulWidget {
  const ProductDatabaseView({super.key});

  @override
  State<ProductDatabaseView> createState() => _ProductDatabaseViewState();
}

class _ProductDatabaseViewState extends State<ProductDatabaseView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
            Text(t.text('db_title'), style: Theme.of(context).textTheme.headlineMedium),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: AppColors.primary,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppColors.primary,
              tabs: [
                Tab(text: t.text('db_products')),
                Tab(text: t.text('db_suppliers')),
                Tab(text: t.text('db_receivers')),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _ProductGrid(),
              _SimpleListGrid(type: 'supplier'),
              _SimpleListGrid(type: 'receiver'),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProductGrid extends StatefulWidget {
  const _ProductGrid();

  @override
  State<_ProductGrid> createState() => _ProductGridState();
}

class _ProductGridState extends State<_ProductGrid> {
  final List<PlutoRow> rows = [];
  late PlutoGridStateManager stateManager;
  List<String> validUnits = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadData();
  }

  Future<void> _loadData() async {
    validUnits = await DatabaseHelper.instance.getUnits();
    final products = await DatabaseHelper.instance.getAllProducts();
    
    if (mounted) {
      setState(() {
        rows.clear();
        for (var p in products) {
          rows.add(PlutoRow(
            cells: {
               'id': PlutoCell(value: p['id']),
               'name': PlutoCell(value: p['name']),
               'unit': PlutoCell(value: p['unit'] ?? (validUnits.isNotEmpty ? validUnits.first : '')),
            }
          ));
        }
        // Always add one empty row at the end for new entry
        rows.add(_createEmptyRow());
        isLoading = false;
      });
    }
  }

  PlutoRow _createEmptyRow() {
    return PlutoRow(cells: {
      'id': PlutoCell(value: ''),
      'name': PlutoCell(value: ''),
      'unit': PlutoCell(value: validUnits.isNotEmpty ? validUnits.first : 'DONA'),
    });
  }

  Future<void> _saveChanges() async {
    int savedCount = 0;
    for (var row in stateManager.rows) {
      final id = row.cells['id']?.value.toString() ?? '';
      final name = row.cells['name']?.value.toString() ?? '';
      final unit = row.cells['unit']?.value.toString() ?? '';

      if (id.isNotEmpty && name.isNotEmpty) {
        await DatabaseHelper.instance.insertProduct({
          'id': id,
          'name': name,
          'unit': unit,
          'created_at': DateTime.now().toIso8601String(),
        });
        savedCount++;
      }
    }
    if (mounted) {
      final t = Provider.of<AppTranslations>(context, listen: false);
      if (savedCount > 0) {
        AppNotifications.showSuccess(context, "${t.text('db_msg_saved')}: $savedCount");
      } else {
        AppNotifications.showError(context, t.text('msg_no_data'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    final t = Provider.of<AppTranslations>(context);
    final List<PlutoColumn> columns = [
      PlutoColumn(
        title: t.text('db_col_id_manual'),
        field: 'id',
        type: PlutoColumnType.text(),
        width: 150,
      ),
      PlutoColumn(
        title: t.text('col_product'),
        field: 'name',
        type: PlutoColumnType.text(),
        width: 300,
      ),
      PlutoColumn(
        title: t.text('col_unit'),
        field: 'unit',
        type: PlutoColumnType.select(validUnits),
        width: 150,
      ),
    ];

    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _saveChanges, 
            icon: const Icon(Icons.save), 
            label: Text(t.text('db_save_products')),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: GlassContainer(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: PlutoGrid(
                key: ValueKey(t.currentLocale),
                columns: columns,
                rows: rows,
                onLoaded: (e) {
                  stateManager = e.stateManager;
                  stateManager.setShowColumnFilter(false);
                },
                onChanged: (event) {
                  if (event.rowIdx == stateManager.rows.length - 1) {
                    if (event.value.toString().isNotEmpty) {
                      stateManager.appendRows([_createEmptyRow()]);
                    }
                  }
                },
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
          ),
        ),
      ],
    );
  }
}

class _SimpleListGrid extends StatefulWidget {
  final String type; // 'supplier' or 'receiver'
  const _SimpleListGrid({required this.type});

  @override
  State<_SimpleListGrid> createState() => _SimpleListGridState();
}

class _SimpleListGridState extends State<_SimpleListGrid> {
  final List<PlutoRow> rows = [];
  late PlutoGridStateManager stateManager;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadData();
  }

  Future<void> _loadData() async {
    List<String> data = [];
    if (widget.type == 'supplier') {
        data = await DatabaseHelper.instance.getSuppliers();
    } else {
        data = await DatabaseHelper.instance.getReceivers();
    }
    
    if (mounted) {
      setState(() {
        rows.clear();
        for (var name in data) {
          rows.add(PlutoRow(cells: {'name': PlutoCell(value: name)}));
        }
        // Always add one empty row at the end for new entry
        rows.add(PlutoRow(cells: {'name': PlutoCell(value: '')}));
        isLoading = false;
      });
    }
  }

  Future<void> _saveChanges() async {
    int savedCount = 0;
    for (var row in stateManager.rows) {
      final name = row.cells['name']?.value.toString() ?? '';
      if (name.isNotEmpty) {
        if (widget.type == 'supplier') {
          await DatabaseHelper.instance.insertSupplier(name);
        } else {
          await DatabaseHelper.instance.insertReceiver(name);
        }
        savedCount++;
      }
    }
    if (mounted) {
      final t = Provider.of<AppTranslations>(context, listen: false);
      if (savedCount > 0) {
        AppNotifications.showSuccess(context, "${t.text('db_msg_saved')}: $savedCount");
      } else {
        AppNotifications.showError(context, t.text('msg_no_data'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    final t = Provider.of<AppTranslations>(context);
    final List<PlutoColumn> columns = [
      PlutoColumn(
        title: widget.type == 'supplier' ? t.text('db_suppliers') : t.text('db_receivers'),
        field: 'name',
        type: PlutoColumnType.text(),
        width: 400,
      ),
    ];

    return Column(
      children: [
         Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _saveChanges, 
            icon: const Icon(Icons.save), 
            label: Text(t.text('btn_save')),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: GlassContainer(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: PlutoGrid(
                key: ValueKey(t.currentLocale),
                columns: columns,
                rows: rows,
                onLoaded: (e) {
                  stateManager = e.stateManager;
                  stateManager.setShowColumnFilter(false);
                },
                onChanged: (event) {
                  if (event.rowIdx == stateManager.rows.length - 1) {
                    if (event.value.toString().isNotEmpty) {
                      stateManager.appendRows([PlutoRow(cells: {'name': PlutoCell(value: '')})]);
                    }
                  }
                },
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
          ),
        ),
      ],
    );
  }
}
