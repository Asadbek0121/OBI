import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:clinical_warehouse/core/theme/app_colors.dart';
import 'package:clinical_warehouse/core/localization/app_translations.dart';
import 'package:clinical_warehouse/core/database/database_helper.dart';
import 'package:clinical_warehouse/core/theme/grid_theme.dart';
import 'package:clinical_warehouse/core/utils/app_notifications.dart';
import 'package:clinical_warehouse/core/widgets/app_dialogs.dart';

class InventoryView extends StatefulWidget {
  const InventoryView({super.key});

  @override
  State<InventoryView> createState() => _InventoryViewState();
}

class _InventoryViewState extends State<InventoryView> {
  late final List<PlutoColumn> columns;
  late List<PlutoRow> rows = [];
  late PlutoGridStateManager stateManager;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  Future<void> _loadInventory() async {
    setState(() => isLoading = true);
    
    final t = Provider.of<AppTranslations>(context, listen: false);
    final data = await DatabaseHelper.instance.getInventorySummary();

    columns = [
      PlutoColumn(
        title: t.text('col_id'),
        field: 'id',
        type: PlutoColumnType.text(),
        width: 100,
        enableRowChecked: false,
      ),
      PlutoColumn(
        title: t.text('col_product'),
        field: 'name',
        type: PlutoColumnType.text(),
        width: 300,
      ),
      PlutoColumn(
        title: t.text('col_qty'),
        field: 'stock',
        type: PlutoColumnType.number(format: '#,###.##'),
        width: 150,
      ),
      PlutoColumn(
        title: t.text('col_unit'),
        field: 'unit',
        type: PlutoColumnType.text(),
        width: 100,
      ),
      PlutoColumn(
        title: t.text('col_status'),
        field: 'status',
        type: PlutoColumnType.text(),
        width: 150,
        renderer: (rendererContext) {
          final stock = double.tryParse(rendererContext.row.cells['stock']?.value.toString() ?? '0') ?? 0;
          String label = t.text('status_healthy');
          Color color = AppColors.success;

          if (stock <= 5) {
            label = t.text('status_critical');
            color = AppColors.error;
          } else if (stock <= 20) {
            label = t.text('status_low');
            color = AppColors.warning;
          }

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          );
        },
      ),
      PlutoColumn(
        title: "",
        field: 'actions',
        type: PlutoColumnType.text(),
        width: 80,
        enableSorting: false,
        enableFilterMenuItem: false,
        renderer: (rendererContext) {
          final id = rendererContext.row.cells['id']?.value.toString() ?? '';
          return IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
            onPressed: () => _deleteProduct(id),
            tooltip: "O'chirish",
          );
        },
      ),
    ];

    rows = data.map((item) {
      return PlutoRow(
        cells: {
          'id': PlutoCell(value: item['id'] ?? ''),
          'name': PlutoCell(value: item['name'] ?? ''),
          'stock': PlutoCell(value: item['stock'] ?? 0),
          'unit': PlutoCell(value: item['unit'] ?? ''),
          'status': PlutoCell(value: ''),
          'actions': PlutoCell(value: ''),
        },
      );
    }).toList();

    if (mounted) {
      setState(() => isLoading = false);
    }
  }

  Future<void> _deleteProduct(String id) async {
    final t = Provider.of<AppTranslations>(context, listen: false);
    
    AppDialogs.showBlurDialog(
      context: context,
      title: t.text('confirm'),
      content: const Text("Mahsulot va uning barcha tarixini o'chirib yubormoqchimisiz?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.text('btn_cancel'))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () async {
            Navigator.pop(context);
            await DatabaseHelper.instance.deleteProduct(id);
            if (mounted) {
              AppNotifications.showSuccess(context, t.text('msg_saved')); 
              _loadInventory();
            }
          },
          child: Text(t.text('btn_delete')),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
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
                Text(t.text('header_inventory'), style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                )),
                const SizedBox(height: 8),
                Text(t.text('inventory_desc'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                 _HeaderBtn(
                  onPressed: _loadInventory, 
                  icon: Icons.refresh_rounded, 
                  label: "Yangilash",
                  color: AppColors.primary.withValues(alpha: 0.1),
                  textColor: AppColors.primary,
                ),
                const SizedBox(width: 12),
                _HeaderBtn(
                  onPressed: _loadInventory, 
                  icon: Icons.download_rounded, 
                  label: "Excel",
                  color: AppColors.success,
                  textColor: Colors.white,
                  isPrimary: true,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        Expanded(
        child: Container(
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
            border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
          ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: PlutoGrid(
                key: ValueKey(t.currentLocale),
                columns: columns,
                rows: rows,
                onLoaded: (PlutoGridOnLoadedEvent event) {
                  stateManager = event.stateManager;
                  stateManager.setShowColumnFilter(true); 
                },
                mode: PlutoGridMode.readOnly,
                configuration: gridConfig,
              ),
            ),
          ),
        ),
      ],
    );
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
