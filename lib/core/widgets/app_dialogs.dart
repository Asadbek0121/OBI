import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class AppDialogs {
  static Future<T?> showBlurDialog<T>({
    required BuildContext context,
    required String title,
    required Widget content,
    List<Widget>? actions,
  }) {
    return showDialog<T>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420, minWidth: 320),
          decoration: BoxDecoration(
            color: Theme.of(context).dialogBackgroundColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
              ),
              const SizedBox(height: 12),
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
    );
  }

  static Future<bool?> showConfirmDialog({
    required BuildContext context,
    required String title,
    required String content,
    String? confirmText,
    String? cancelText,
  }) {
    return showBlurDialog<bool>(
      context: context,
      title: title,
      content: Text(
        content,
        style: TextStyle(
          fontSize: 14,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(cancelText ?? "Yo'q"),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: Text(confirmText ?? "Ha"),
        ),
      ],
    );
  }
}
