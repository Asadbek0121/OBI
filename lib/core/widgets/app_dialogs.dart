import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'glass_container.dart';

class AppDialogs {
  static Future<T?> showBlurDialog<T>({
    required BuildContext context,
    required String title,
    required Widget content,
    List<Widget>? actions,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withValues(alpha: 0.1),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => const SizedBox(),
      transitionBuilder: (context, anim1, anim2, child) {
        final curve = Curves.easeOutBack.transform(anim1.value);
        return Transform.scale(
          scale: curve,
          child: Opacity(
            opacity: anim1.value,
            child: AlertDialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              contentPadding: EdgeInsets.zero,
              content: GlassContainer(
                borderRadius: 28,
                padding: const EdgeInsets.all(24),
                blur: 30,
                opacity: 0.8,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                    ),
                    const SizedBox(height: 16),
                    content,
                    const SizedBox(height: 24),
                    if (actions != null)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: actions.map((a) {
                          return Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: a,
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
