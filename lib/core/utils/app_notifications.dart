import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_container.dart';

class AppNotifications {
  static void showSuccess(BuildContext context, String message) {
    _showOverlay(
      context,
      message,
      AppColors.success,
      Icons.check_circle_rounded,
      "Muvaffaqiyatli",
    );
  }

  static void showError(BuildContext context, String message) {
    _showOverlay(
      context,
      message,
      AppColors.error,
      Icons.warning_rounded,
      "Tizim xatoligi",
    );
  }

  static void showInfo(BuildContext context, String message) {
    _showOverlay(
      context,
      message,
      Colors.blue,
      Icons.info_rounded,
      "Ma'lumot",
    );
  }

  static void _showOverlay(
    BuildContext context,
    String message,
    Color color,
    IconData icon,
    String title,
  ) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => _NotificationWidget(
        message: message,
        title: title,
        color: color,
        icon: icon,
        onDismiss: () => entry.remove(),
      ),
    );

    overlay.insert(entry);
  }
}

class _NotificationWidget extends StatefulWidget {
  final String message;
  final String title;
  final Color color;
  final IconData icon;
  final VoidCallback onDismiss;

  const _NotificationWidget({
    required this.message,
    required this.title,
    required this.color,
    required this.icon,
    required this.onDismiss,
  });

  @override
  State<_NotificationWidget> createState() => _NotificationWidgetState();
}

class _NotificationWidgetState extends State<_NotificationWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    ));

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 40,
      right: 20,
      child: SlideTransition(
        position: _offsetAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 350,
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: GlassContainer(
                onTap: () => _controller.reverse().then((_) => widget.onDismiss()),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                borderRadius: 16,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: widget.color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(widget.icon, color: widget.color, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.message,
                            style: TextStyle(
                              color: Colors.black.withOpacity(0.7),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                      onPressed: () {
                        _controller.reverse().then((_) => widget.onDismiss());
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
