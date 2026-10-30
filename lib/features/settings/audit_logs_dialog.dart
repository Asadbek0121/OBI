import 'package:flutter/material.dart';
import '../../core/database/database_helper.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_container.dart';
import '../../core/widgets/liquid_glass.dart';

class AuditLogsDialog extends StatefulWidget {
  const AuditLogsDialog({super.key});

  static Future<void> show(BuildContext context) async {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (c) => const AuditLogsDialog(),
    );
  }

  @override
  State<AuditLogsDialog> createState() => _AuditLogsDialogState();
}

class _AuditLogsDialogState extends State<AuditLogsDialog> {
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    final logs = await DatabaseHelper.instance.getAuditLogs(limit: 100);
    if (mounted) {
      setState(() {
        _logs = logs;
        _isLoading = false;
      });
    }
  }

  Color _getActionColor(String action) {
    switch (action.toUpperCase()) {
      case 'INSERT':
        return Colors.green;
      case 'UPDATE':
        return Colors.blue;
      case 'DELETE':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  String _formatAction(String action) {
    switch (action.toUpperCase()) {
      case 'INSERT':
        return "Qo'shildi";
      case 'UPDATE':
        return "Tahrirlandi";
      case 'DELETE':
        return "O'chirildi";
      default:
        return action;
    }
  }

  String _formatTable(String table) {
    switch (table) {
      case 'products':
        return "Mahsulotlar";
      case 'stock_in':
        return "Kirim";
      case 'stock_out':
        return "Chiqim";
      case 'assets':
        return "Jihozlar";
      default:
        return table;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    return Center(
      child: GlassContainer(
        width: size.width > 800 ? 760 : size.width * 0.92,
        height: size.height * 0.8,
        padding: const EdgeInsets.all(24),
        borderRadius: 24,
        child: Material(
          color: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.history_rounded, color: AppColors.primary, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "O'zgarishlar tarixi va Audit",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: isDark ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            "Kim, qachon va qaysi ma'lumotni o'zgartirganligi jurnali",
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white.withValues(alpha: 0.6) : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Content
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _logs.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inbox_rounded, size: 48, color: Colors.grey.shade400),
                                const SizedBox(height: 12),
                                Text(
                                  "Hozircha o'zgarishlar tarixi mavjud emas",
                                  style: TextStyle(color: Colors.grey.shade500),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: _logs.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = _logs[index];
                              final action = item['action']?.toString() ?? 'ACTION';
                              final actionColor = _getActionColor(action);
                              final timestamp = item['timestamp']?.toString().replaceFirst('T', ' ').split('.').first ?? '';
                              final actor = item['user_id']?.toString() ?? 'System';
                              final table = item['table_name']?.toString() ?? '';

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: actionColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        _formatAction(action),
                                        style: TextStyle(
                                          color: actionColor,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                actor,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13,
                                                  color: LiquidColors.of(context).body,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                "• ${_formatTable(table)}",
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w500,
                                                  fontSize: 12,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            "Sana: $timestamp",
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: LiquidColors.of(context).muted.withValues(alpha: 0.7),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (item['record_id'] != null)
                                      Text(
                                        "ID: ${item['record_id'].toString().length > 8 ? item['record_id'].toString().substring(0, 8) + '...' : item['record_id']}",
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade500,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
