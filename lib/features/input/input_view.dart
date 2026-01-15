import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clinical_warehouse/core/localization/app_translations.dart';
import 'package:clinical_warehouse/core/theme/app_colors.dart';
import 'package:clinical_warehouse/core/widgets/glass_container.dart';

class InputView extends StatelessWidget {
  const InputView({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<AppTranslations>(context);
    
    return Center(
      child: GlassContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.download, size: 64, color: AppColors.success),
            const SizedBox(height: 24),
            Text(t.text('inp_title'), style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            Text(t.text('inp_desc')),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: (){}, child: Text(t.text('btn_start_receive')))
          ],
        ),
      ),
    );
  }
}
