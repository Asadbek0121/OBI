import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clinical_warehouse/core/localization/app_translations.dart';
import 'package:clinical_warehouse/core/theme/app_colors.dart';
import 'package:clinical_warehouse/core/widgets/glass_container.dart';

class LocationsView extends StatelessWidget {
  const LocationsView({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<AppTranslations>(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(t.text('loc_title'), style: Theme.of(context).textTheme.headlineMedium),
            Row(
              children: [
                _buildAddButton(Icons.add, t.text('loc_new_shelf')),
                const SizedBox(width: 12),
                _buildAddButton(Icons.ac_unit, t.text('loc_new_fridge')),
                const SizedBox(width: 12),
                _buildAddButton(Icons.lock, t.text('loc_new_safe')),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        Expanded(
          child: GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            children: [
              _buildLocationCard(context, "${t.text('loc_fridge')} #1", "${t.text('loc_temp_label')}: 4°C\n${t.text('loc_items')}: 45", Icons.ac_unit, AppColors.primary),
              _buildLocationCard(context, "${t.text('loc_shelf')} A-1", "${t.text('loc_general_storage')}\n${t.text('loc_items')}: 120", Icons.shelves, Colors.orange),
              _buildLocationCard(context, "${t.text('loc_safe')} L-3", "${t.text('loc_controlled')}\n${t.text('loc_items')}: 12", Icons.lock, Colors.red),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAddButton(IconData icon, String label) {
    return ElevatedButton.icon(
      onPressed: () {},
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildLocationCard(BuildContext context, String title, String subtitle, IconData icon, Color color) {
    return GlassContainer(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: color.withValues(alpha: 0.1),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
