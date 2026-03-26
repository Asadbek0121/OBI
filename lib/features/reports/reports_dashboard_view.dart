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
  List<Map<String, dynamic>> _aiPredictions = [];
  Map<String, int> _abcData = {'A': 0, 'B': 0, 'C': 0};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final db = await DatabaseHelper.instance.database;
      
      // 1. Weekly Movement
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

      // 3. AI Predictive & ABC Analysis
      // Calculate avg daily use over last 30 days
      final thirtyDaysAgo = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 30)));
      
      // Calculate real current stock and movement in one query
      final productUsageRes = await db.rawQuery('''
        SELECT p.id, p.name,
               ((SELECT COALESCE(SUM(quantity), 0) FROM stock_in WHERE product_id = p.id AND is_deleted = 0) - 
                (SELECT COALESCE(SUM(quantity), 0) FROM stock_out WHERE product_id = p.id AND is_deleted = 0)) as currentStock,
               (SELECT COALESCE(SUM(quantity), 0) FROM stock_out WHERE product_id = p.id AND date_time >= ? AND is_deleted = 0) as totalOut
        FROM products p
        WHERE p.is_deleted = 0
      ''', [thirtyDaysAgo]);

      List<Map<String, dynamic>> predictions = [];
      List<double> velocities = [];

      for (var row in productUsageRes) {
        final currentStock = double.tryParse(row['currentStock']?.toString() ?? '0') ?? 0;
        final totalOut = double.tryParse(row['totalOut']?.toString() ?? '0') ?? 0;
        final dailyVelocity = totalOut / 30.0;
        velocities.add(totalOut);

        if (dailyVelocity > 0) {
          final daysLeft = currentStock / dailyVelocity;
          if (daysLeft < 30) { // Only show items running out soon
            predictions.add({
              'name': row['name'],
              'days': daysLeft.round(),
              'velocity': dailyVelocity.toStringAsFixed(2),
              'risk': daysLeft < 7 ? 'HIGH' : 'MEDIUM'
            });
          }
        }
      }
      
      predictions.sort((a, b) => a['days'].compareTo(b['days']));

      // ABC Classification based on velocity
      if (velocities.isNotEmpty) {
        velocities.sort((a, b) => b.compareTo(a));
        final aLimit = velocities[(velocities.length * 0.2).floor()];
        final bLimit = velocities[(velocities.length * 0.5).floor()];
        
        int aCount = 0, bCount = 0, cCount = 0;
        for (var v in velocities) {
          if (v >= aLimit && v > 0) aCount++;
          else if (v >= bLimit && v > 0) bCount++;
          else cCount++;
        }
        _abcData = {'A': aCount, 'B': bCount, 'C': cCount};
      }

      if (mounted) {
        setState(() {
          _weeklyStats = stats;
          _categoryData = cats;
          _aiPredictions = predictions.take(5).toList(); // Show top 5 risks
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Analytics Error: $e");
      if (mounted) setState(() => _isLoading = false);
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildAIRiskSection(),
            const SizedBox(height: 16),
            _buildABCSection(),
            const SizedBox(height: 24),
            _buildLineChart(),
            const SizedBox(height: 24),
            _buildPieChart(),
          ],
        ),
      ),
    );
  }

  Widget _buildAIRiskSection() {
    if (_aiPredictions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text("🤖 AI BASHORATCHI (Zaxira xavfi)", 
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        ),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _aiPredictions.length,
            itemBuilder: (context, index) {
              final item = _aiPredictions[index];
              final isHighRisk = item['risk'] == 'HIGH';
              return Container(
                width: 180,
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isHighRisk ? Colors.redAccent.withOpacity(0.15) : Colors.orangeAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isHighRisk ? Colors.redAccent.withOpacity(0.3) : Colors.orangeAccent.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(item['name'], maxLines: 1, overflow: TextOverflow.ellipsis, 
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.timer_outlined, size: 14, color: isHighRisk ? Colors.redAccent : Colors.orangeAccent),
                        const SizedBox(width: 4),
                        Text("${item['days']} kun qoldi", 
                            style: TextStyle(color: isHighRisk ? Colors.redAccent : Colors.orangeAccent, 
                                           fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                    Text("Tezlik: ${item['velocity']}/kun", 
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildABCSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildABCItem("A - FAOL", _abcData['A'] ?? 0, Colors.greenAccent),
          _buildABCItem("B - O'RTA", _abcData['B'] ?? 0, Colors.blueAccent),
          _buildABCItem("C - KAM", _abcData['C'] ?? 0, Colors.grey),
        ],
      ),
    );
  }

  Widget _buildABCItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: color.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(count.toString(), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        Text("mahsulot", style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9)),
      ],
    );
  }

  Widget _buildLineChart() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.blue.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.show_chart_rounded, color: Colors.blue, size: 20),
              ),
              const SizedBox(width: 12),
              const Text("Haftalik Trend", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 30),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 1,
                      getTitlesWidget: (val, meta) {
                        if (val.toInt() < 0 || val.toInt() >= _weeklyStats.length) return const Text("");
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            _weeklyStats[val.toInt()]['day'],
                            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (val, meta) => Text(
                        val.toInt().toString(),
                        style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10),
                      ),
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: _weeklyStats.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value['in'])).toList(),
                    isCurved: true,
                    curveSmoothness: 0.3, // Changed from curveLib.cubic to curveSmoothness
                    color: Colors.greenAccent,
                    barWidth: 4,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.greenAccent.withOpacity(0.1),
                    ),
                  ),
                  LineChartBarData(
                    spots: _weeklyStats.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value['out'])).toList(),
                    isCurved: true,
                    curveSmoothness: 0.3, // Changed from curveLib.cubic to curveSmoothness
                    color: Colors.redAccent,
                    barWidth: 4,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.redAccent.withOpacity(0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendRow(Colors.greenAccent, "Kirim"),
              const SizedBox(width: 24),
              _buildLegendRow(Colors.redAccent, "Chiqim"),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildLegendRow(Color color, String label) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
      ],
    );
  }

  Widget _buildPieChart() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.pie_chart_rounded, color: Colors.orange, size: 20),
              ),
              const SizedBox(width: 12),
              const Text("Kategoriyalar", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 200,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 4,
                      centerSpaceRadius: 40,
                      sections: _categoryData.entries.map((e) {
                        final index = _categoryData.keys.toList().indexOf(e.key);
                        final color = Colors.primaries[index % Colors.primaries.length];
                        return PieChartSectionData(
                          value: e.value,
                          title: "", // Title hidden, legend used instead
                          radius: 30,
                          color: color,
                          badgeWidget: _buildBadge(e.value.toInt().toString(), color),
                          badgePositionPercentageOffset: 1.4,
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 1,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _categoryData.entries.map((e) {
                    final index = _categoryData.keys.toList().indexOf(e.key);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: _buildLegendRow(Colors.primaries[index % Colors.primaries.length], e.key),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4)],
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
    );
  }
}
