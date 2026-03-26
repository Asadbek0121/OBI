import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/database/database_helper.dart';
import 'package:intl/intl.dart';

class ReportsDashboardView extends StatefulWidget {
  const ReportsDashboardView({super.key});

  @override
  State<ReportsDashboardView> createState() => _ReportsDashboardViewState();
}

class _ReportsDashboardViewState extends State<ReportsDashboardView> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _weeklyStats = [];
  Map<String, double> _categoryData = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final db = await DatabaseHelper.instance.database;
      
      // 1. Weekly Movement (Last 7 days)
      final now = DateTime.now();
      final List<Map<String, dynamic>> stats = [];
      for (int i = 6; i >= 0; i--) {
        final day = now.subtract(Duration(days: i));
        final dayStr = DateFormat('yyyy-MM-dd').format(day);
        
        final inRes = await db.rawQuery("SELECT SUM(quantity) as q FROM stock_in WHERE date_time LIKE '$dayStr%' AND is_deleted = 0");
        final outRes = await db.rawQuery("SELECT SUM(quantity) as q FROM stock_out WHERE date_time LIKE '$dayStr%' AND is_deleted = 0");
        
        stats.add({
          'day': DateFormat('E').format(day),
          'in': double.tryParse(inRes.first['q']?.toString() ?? '0') ?? 0,
          'out': double.tryParse(outRes.first['q']?.toString() ?? '0') ?? 0,
        });
      }

      // 2. Category Distribution
      final Map<String, double> cats = {};
      try {
        final catRes = await db.rawQuery('''
          SELECT c.name, COUNT(p.id) as count
          FROM products p
          LEFT JOIN categories c ON p.category_id = c.id
          WHERE p.is_deleted = 0
          GROUP BY c.id
        ''');
        for (var row in catRes) {
          final name = row['name']?.toString() ?? 'No Category';
          cats[name] = double.tryParse(row['count'].toString()) ?? 0;
        }
      } catch (_) {
        final totalRes = await db.rawQuery("SELECT COUNT(*) as count FROM products WHERE is_deleted = 0");
        cats['Total Products'] = double.tryParse(totalRes.first['count'].toString()) ?? 0;
      }

      if (mounted) {
        setState(() {
          _weeklyStats = stats;
          _categoryData = cats;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Analytics Error: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_weeklyStats.isEmpty && _categoryData.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text("Hozircha ma'lumot yo'q")),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLineChart(),
          const SizedBox(height: 24),
          _buildPieChart(),
        ],
      ),
    );
  }

  Widget _buildLineChart() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text("Haftalik Kirim/Chiqim Trendi", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (val, meta) {
                          if (val.toInt() >= 0 && val.toInt() < _weeklyStats.length) {
                            return Text(_weeklyStats[val.toInt()]['day']);
                          }
                          return const Text("");
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: _weeklyStats.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value['in'])).toList(),
                      isCurved: true,
                      color: Colors.green,
                      barWidth: 3,
                    ),
                    LineChartBarData(
                      spots: _weeklyStats.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value['out'])).toList(),
                      isCurved: true,
                      color: Colors.red,
                      barWidth: 3,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPieChart() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text("Kategoriyalar Bo'yicha Taqsimot", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: _categoryData.entries.map((e) {
                    final index = _categoryData.keys.toList().indexOf(e.key);
                    return PieChartSectionData(
                      value: e.value,
                      title: "${e.key}\n${e.value.toInt()}",
                      radius: 50,
                      color: Colors.primaries[index % Colors.primaries.length],
                      titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
