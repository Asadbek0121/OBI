import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class WindowButtons extends StatelessWidget {
  const WindowButtons({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _WindowButton(
            icon: Icons.remove,
            onTap: () => windowManager.minimize(),
            tooltip: 'Minimize',
          ),
          const SizedBox(width: 4),
          _WindowButton(
            icon: Icons.crop_square,
            onTap: () async {
              if (await windowManager.isMaximized()) {
                windowManager.restore();
              } else {
                windowManager.maximize();
              }
            },
            tooltip: 'Maximize',
          ),
          const SizedBox(width: 4),
          _WindowButton(
            icon: Icons.close,
            color: Colors.red,
            hoverColor: Colors.red.withOpacity(0.1),
            onTap: () => windowManager.close(),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final Color? color;
  final Color? hoverColor;

  const _WindowButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.color,
    this.hoverColor,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        hoverColor: hoverColor ?? Colors.grey.withOpacity(0.1),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: color ?? Colors.grey[700]),
        ),
      ),
    );
  }
}
