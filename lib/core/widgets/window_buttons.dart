import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class WindowButtons extends StatelessWidget {
  const WindowButtons({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mac-style traffic lights
          _CircleButton(
            color: const Color(0xFFFF5F57), // Red
            onTap: () => windowManager.close(),
            tooltip: 'Yopish',
          ),
          const SizedBox(width: 10),
          _CircleButton(
            color: const Color(0xFFFFBD2E), // Yellow
            onTap: () => windowManager.minimize(),
            tooltip: 'Kichraytirish',
          ),
          const SizedBox(width: 10),
          _CircleButton(
            color: const Color(0xFF28C840), // Green
            onTap: () async {
              if (await windowManager.isMaximized()) {
                windowManager.restore();
              } else {
                windowManager.maximize();
              }
            },
            tooltip: 'Kattalashtirish',
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatefulWidget {
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  const _CircleButton({
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  @override
  State<_CircleButton> createState() => _CircleButtonState();
}

class _CircleButtonState extends State<_CircleButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Tooltip(
          message: widget.tooltip,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              boxShadow: _isHovered ? [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.5),
                  blurRadius: 4,
                  spreadRadius: 1,
                )
              ] : [],
            ),
            child: _isHovered ? Center(
              child: Icon(
                _getIconForColor(widget.color),
                size: 8,
                color: Colors.black.withValues(alpha: 0.5),
              ),
            ) : null,
          ),
        ),
      ),
    );
  }

  IconData _getIconForColor(Color color) {
    if (color.toARGB32() == 0xFFFF5F57) return Icons.close;
    if (color.toARGB32() == 0xFFFFBD2E) return Icons.remove;
    return Icons.add;
  }
}
