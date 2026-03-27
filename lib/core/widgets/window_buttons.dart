import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';

/// macOS-style (left, circles) or Windows-style (right, rectangles)
/// depending on the current platform.
class WindowButtons extends StatelessWidget {
  const WindowButtons({super.key});

  @override
  Widget build(BuildContext context) {
    if (Platform.isWindows) {
      return const _WindowsButtons();
    }
    return const _MacOSButtons();
  }
}

// ─── macOS Style ──────────────────────────────────────────────
class _MacOSButtons extends StatelessWidget {
  const _MacOSButtons();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CircleButton(
            color: const Color(0xFF28C840),
            onTap: () async {
              if (await windowManager.isMaximized()) {
                windowManager.restore();
              } else {
                windowManager.maximize();
              }
            },
            tooltip: 'Kattalashtirish',
          ),
          const SizedBox(width: 8),
          _CircleButton(
            color: const Color(0xFFFFBD2E),
            onTap: () => windowManager.minimize(),
            tooltip: 'Kichraytirish',
          ),
          const SizedBox(width: 8),
          _CircleButton(
            color: const Color(0xFFFF5F57),
            onTap: () => windowManager.close(),
            tooltip: 'Yopish',
          ),
        ],
      ),
    );
  }
}

// ─── Windows Style ─────────────────────────────────────────────
class _WindowsButtons extends StatelessWidget {
  const _WindowsButtons();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WinButton(
          icon: Icons.remove,
          tooltip: 'Kichraytirish',
          isDark: isDark,
          onTap: () => windowManager.minimize(),
        ),
        _WinButton(
          icon: Icons.crop_square_rounded,
          tooltip: 'Kattalashtirish',
          isDark: isDark,
          onTap: () async {
            if (await windowManager.isMaximized()) {
              windowManager.restore();
            } else {
              windowManager.maximize();
            }
          },
        ),
        _WinButton(
          icon: Icons.close,
          tooltip: 'Yopish',
          isDark: isDark,
          isClose: true,
          onTap: () => windowManager.close(),
        ),
      ],
    );
  }
}

class _WinButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final bool isDark;
  final bool isClose;
  final VoidCallback onTap;

  const _WinButton({
    required this.icon,
    required this.tooltip,
    required this.isDark,
    required this.onTap,
    this.isClose = false,
  });

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverColor = widget.isClose
        ? const Color(0xFFE81123)
        : (widget.isDark
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.08));

    final iconColor = _hovered && widget.isClose
        ? Colors.white
        : (widget.isDark ? Colors.white70 : Colors.black87);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Tooltip(
          message: widget.tooltip,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 46,
            height: 32,
            color: _hovered ? hoverColor : Colors.transparent,
            child: Icon(widget.icon, size: 16, color: iconColor),
          ),
        ),
      ),
    );
  }
}

// ─── macOS Circle Button ────────────────────────────────────────
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
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.5),
                        blurRadius: 4,
                        spreadRadius: 1,
                      )
                    ]
                  : [],
            ),
            child: _isHovered
                ? Center(
                    child: Icon(
                      _getIcon(),
                      size: 8,
                      color: Colors.black.withValues(alpha: 0.5),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  IconData _getIcon() {
    if (widget.color.toARGB32() == 0xFFFF5F57) return Icons.close;
    if (widget.color.toARGB32() == 0xFFFFBD2E) return Icons.remove;
    return Icons.add;
  }
}
