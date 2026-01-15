import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clinical_warehouse/core/localization/app_translations.dart';
import 'package:clinical_warehouse/core/theme/app_colors.dart';
import 'package:clinical_warehouse/core/widgets/glass_container.dart';

class OutputView extends StatelessWidget {
  const OutputView({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<AppTranslations>(context);
    
    return Column(
      children: [
        Expanded(
          child: Center(
            child: GlassContainer(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.upload, size: 64, color: AppColors.error),
                  const SizedBox(height: 24),
                  Text(t.text('out_title'), style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 12),
                  Text(t.text('out_desc')),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(t.text('msg_items_dist')),
                          action: SnackBarAction(
                            label: t.text('btn_undo'),
                            onPressed: () {
                              // Undo logic here
                            },
                          ),
                          duration: const Duration(seconds: 5),
                        ),
                      );
                    }, 
                    child: Text(t.text('btn_create_out'))
                  )
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
