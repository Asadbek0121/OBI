import 'package:flutter/material.dart';
import 'package:clinical_warehouse/core/theme/app_colors.dart';
import 'package:clinical_warehouse/core/widgets/glass_container.dart';
import 'package:clinical_warehouse/core/utils/mock_data.dart';

class TransactionsView extends StatelessWidget {
  const TransactionsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Recent Transactions", style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 24),
        Expanded(
          child: GlassContainer(
            padding: EdgeInsets.zero,
            child: ListView.separated(
              itemCount: MockData.transactions.length,
              separatorBuilder: (c, i) => const Divider(height: 1, color: AppColors.glassBorder),
              itemBuilder: (context, index) {
                final tx = MockData.transactions[index];
                bool isOut = tx['type'] == 'OUT';
                
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: isOut ? AppColors.error.withValues(alpha: 0.1) : AppColors.success.withValues(alpha: 0.1),
                        child: Icon(
                          isOut ? Icons.arrow_upward : Icons.arrow_downward, 
                          color: isOut ? AppColors.error : AppColors.success
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tx['item'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Text("${tx['qty']} • ${tx['user']}", style: const TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                      Text(tx['date'], style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
