// =====================================================================
// LIQUID GLASS UI v2 — Apple iOS/macOS 26 accurate
// =====================================================================

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

class LiquidColors {
  final bool dark;
  const LiquidColors(this.dark);
  static LiquidColors of(BuildContext ctx) =>
      LiquidColors(Theme.of(ctx).brightness == Brightness.dark);

  List<Color> get bg => dark
      ? const [
          Color(0xFF0A1628), // yuqori chap — to'q ko'k
          Color(0xFF1A0A3D), // o'rta — to'q binafsha
          Color(0xFF0D1F4A), // quyi o'ng — indigo
        ]
      : const [
          Color(0xFFD0EAFF),
          Color(0xFFE8F5FF),
          Color(0xFFF0F8FF),
        ];

  // ── Glass Colors ───────────────────────────────────────────────────
  Color get cardBg => dark
      ? const Color(0x0AFFFFFF)  // 4% opacity
      : const Color(0x0FFFFFFF); // 6% opacity

  Color get cardBorder => dark
      ? const Color(0x4DFFFFFF)  // 30% opacity
      : const Color(0x61FFFFFF); // 38% opacity

  Color get sidebarBg => dark
      ? const Color(0x12FFFFFF)
      : const Color(0x22FFFFFF);
  Color get sidebarBorder => dark
      ? const Color(0x3DFFFFFF)
      : const Color(0x61FFFFFF); // 38% opacity

  Color get topbarBg => dark
      ? const Color(0x0EFFFFFF)
      : const Color(0x1AFFFFFF);
  Color get topbarBorder => dark
      ? const Color(0x24FFFFFF)
      : const Color(0x47FFFFFF);

  Color get navActiveBg => dark
      ? const Color(0x18FFFFFF)
      : const Color(0x28FFFFFF);
  Color get navActiveBorder => dark
      ? const Color(0x66FFFFFF) // 40%
      : const Color(0x80FFFFFF); // 50% opacity
  Color get navActiveText => dark ? const Color(0xFF96C8FF) : const Color(0xFF005ADC);
  Color get navActiveDot  => dark ? const Color(0xFF78B4FF) : const Color(0xFF0064FF);

  Color get title    => dark ? const Color(0xFF64AAFF) : const Color(0xFF005ADC);
  Color get body     => dark ? const Color(0xCCFFFFFF) : const Color(0xCC000000);
  Color get muted    => dark ? const Color(0x59FFFFFF) : const Color(0x61000000);
  Color get subtitle => dark ? const Color(0x4DFFFFFF) : const Color(0x6B000000);

  Color get thBg     => dark ? const Color(0x08FFFFFF) : const Color(0x0A005ADC);
  Color get thText   => dark ? const Color(0xCC64A0FF) : const Color(0xCC005ADC);
  Color get divider  => dark ? const Color(0x0AFFFFFF) : const Color(0x08000000);
  Color get hover    => dark ? const Color(0x09FFFFFF) : const Color(0x09005ADC);

  Color get statusBg     => dark ? const Color(0x07FFFFFF) : const Color(0x14FFFFFF);
  Color get statusBorder => dark ? const Color(0x0FFFFFFF) : const Color(0x2AFFFFFF);

  Color get pillBg     => dark ? const Color(0x1A6496FF) : const Color(0x140064FF);
  Color get pillBorder => dark ? const Color(0x2E6496FF) : const Color(0x260064FF);
  Color get logoIconBg => dark ? const Color(0x18FFFFFF) : const Color(0x33FFFFFF);
  Color get dividerLine => dark ? const Color(0x10FFFFFF) : const Color(0x0C000000);

  // Specular Gradients
  LinearGradient get specularTop => LinearGradient(colors: [
    Colors.transparent,
    Colors.white.withValues(alpha: dark ? 0.35 : 0.95),
    Colors.white.withValues(alpha: dark ? 0.15 : 0.60),
    Colors.white.withValues(alpha: dark ? 0.35 : 0.95),
    Colors.transparent,
  ], stops: const [0.0, 0.15, 0.50, 0.85, 1.0]);

  LinearGradient get specularLeft => LinearGradient(
    colors: [
      Colors.white.withValues(alpha: dark ? 0.15 : 0.45),
      Colors.transparent,
    ],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
}

// ── Background ────────────────────────────────────────────────────────

class LiquidBackground extends StatelessWidget {
  final Widget child;
  const LiquidBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = LiquidColors.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: c.bg,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: child,
    );
  }
}

// ── Glass Card ───────────────────────────────────────────────────────

class LiquidCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsets? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final bool specular;
  final VoidCallback? onTap;

  const LiquidCard({
    super.key,
    required this.child,
    this.radius = 16,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.specular = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = LiquidColors.of(context);
    return MouseRegion(
      cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: margin,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                width: width,
                height: height,
                padding: padding,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1.0),
                ),
                child: Stack(children: [
                  child,
                  if (specular) ...[
                    Positioned(top: 0, left: 0, right: 0,
                      child: Container(height: 1,
                          decoration: BoxDecoration(gradient: c.specularTop))),
                    Positioned(top: 0, left: 0, bottom: 0,
                      child: Container(width: 1,
                          decoration: BoxDecoration(gradient: c.specularLeft))),
                    Positioned(bottom: 0, left: 0, right: 0,
                      child: Container(height: 1,
                          color: Colors.black.withValues(alpha: c.dark ? 0.12 : 0.04))),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Sidebar ───────────────────────────────────────────────────────────

class LiquidNavItem {
  final IconData icon;
  final String label;
  final String route;
  final VoidCallback? onTap;
  final int? badgeCount;
  const LiquidNavItem({
    required this.icon, required this.label,
    required this.route, this.onTap, this.badgeCount,
  });
}

class LiquidSidebar extends StatelessWidget {
  final List<LiquidNavItem> items;
  final String activeRoute;
  final String logoTitle;
  final String logoSubtitle;
  final Widget? logoIcon;
  final String userName;
  final String userEmail;
  final String? userImagePath;
  final VoidCallback? onLogout;

  const LiquidSidebar({
    super.key,
    required this.items, required this.activeRoute,
    required this.logoTitle, required this.logoSubtitle,
    required this.userName, required this.userEmail,
    this.userImagePath, this.logoIcon, this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final c = LiquidColors.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50, tileMode: TileMode.mirror),
        child: Container(
          width: 220,
          decoration: BoxDecoration(
            color: c.sidebarBg,
            border: Border(right: BorderSide(color: c.sidebarBorder, width: 0.5)),
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: c.logoIconBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25), width: 0.5),
                  ),
                  child: logoIcon ??
                      Icon(Icons.inventory_2_outlined, size: 18, color: c.body),
                ),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(logoTitle, style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: c.body)),
                  Text(logoSubtitle,
                      style: TextStyle(fontSize: 10, color: c.muted)),
                ]),
              ]),
            ),
            Divider(height: 0.5, thickness: 0.5, color: c.dividerLine),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: items.map((item) => _NavTile(
                    item: item, isActive: activeRoute == item.route, c: c))
                    .toList(),
              ),
            ),
            _UserPill(name: userName, email: userEmail, imagePath: userImagePath, c: c, onLogout: onLogout),
          ]),
        ),
      ),
    );
  }
}

class _NavTile extends StatefulWidget {
  final LiquidNavItem item;
  final bool isActive;
  final LiquidColors c;
  const _NavTile({required this.item, required this.isActive, required this.c});
  @override State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final a = widget.isActive;

    final row = Row(children: [
      Icon(widget.item.icon, size: 17, color: a ? c.navActiveText : c.body),
      const SizedBox(width: 10),
      Expanded(child: Text(widget.item.label, style: TextStyle(
          fontSize: 12.5,
          fontWeight: a ? FontWeight.w600 : FontWeight.w400,
          color: a ? c.navActiveText : c.body))),
      if (widget.item.badgeCount != null && widget.item.badgeCount! > 0)
        Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFFF3B30),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            "${widget.item.badgeCount}",
            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
          ),
        ),
      if (a)
        Container(width: 3.5, height: 16,
          decoration: BoxDecoration(
            color: c.navActiveDot,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [BoxShadow(
                color: c.navActiveDot.withValues(alpha: 0.55), blurRadius: 6)],
          )),
    ]);

    final navContent = a
        ? ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  color: c.navActiveBg,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: c.navActiveBorder, width: 1.0),
                ),
                child: row,
              ),
            ),
          )
        : AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: _hover ? Colors.white.withValues(alpha: c.dark ? 0.05 : 0.06)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
            ),
            child: row,
          );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit:  (_) => setState(() => _hover = false),
      child: LiquidInkWell(
        onTap: widget.item.onTap,
        borderRadius: BorderRadius.circular(11),
        child: navContent,
      ),
    );
  }
}

class _UserPill extends StatelessWidget {
  final String name, email;
  final String? imagePath;
  final LiquidColors c;
  final VoidCallback? onLogout;
  const _UserPill({required this.name, required this.email, this.imagePath,
      required this.c, this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: c.pillBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.pillBorder, width: 0.5),
            ),
            child: Row(children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  image: imagePath != null ? DecorationImage(
                    image: FileImage(File(imagePath!)),
                    fit: BoxFit.cover,
                  ) : null,
                ),
                child: imagePath == null ? const Icon(Icons.person_rounded, size: 18) : null,
              ),
              const SizedBox(width: 8),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: TextStyle(fontSize: 12.5,
                      fontWeight: FontWeight.w600, color: c.body)),
                  Text(email, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: c.muted)),
                ],
              )),
              if (onLogout != null)
                GestureDetector(onTap: onLogout,
                    child: Icon(Icons.logout_rounded, size: 15, color: c.muted)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── TopBar ────────────────────────────────────────────────────────────

class LiquidTopBar extends StatelessWidget {
  final String title, subtitle;
  final List<Widget> actions;
  const LiquidTopBar({super.key, required this.title, this.subtitle = '', this.actions = const []});
  @override
  Widget build(BuildContext context) {
    final c = LiquidColors.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50, tileMode: TileMode.mirror),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 14),
          decoration: BoxDecoration(
            color: c.topbarBg,
            border: Border(bottom: BorderSide(color: c.topbarBorder, width: 0.5)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w700,
                    color: c.title, letterSpacing: -0.5, height: 1.1)),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(subtitle, style: TextStyle(
                      fontSize: 11.5, color: c.subtitle)),
                ],
              ],
            )),
            ...actions.map((a) => Padding(padding: const EdgeInsets.only(left: 8), child: a)),
          ]),
        ),
      ),
    );
  }
}

// ── Button ────────────────────────────────────────────────────────────

enum LiquidButtonVariant { ghost, success, primary, danger, warning }

class LiquidButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final LiquidButtonVariant variant;
  final VoidCallback? onTap;
  final bool loading;

  const LiquidButton({
    super.key, required this.label,
    this.icon, this.variant = LiquidButtonVariant.ghost,
    this.onTap, this.loading = false,
  });

  @override
  State<LiquidButton> createState() => _LiquidButtonState();
}

class _LiquidButtonState extends State<LiquidButton> {
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Color bg, border, text;
    switch (widget.variant) {
      case LiquidButtonVariant.ghost:
        bg = Colors.white.withValues(alpha: dark ? 0.10 : 0.28);
        border = Colors.white.withValues(alpha: dark ? 0.15 : 0.40);
        text = dark ? const Color(0xB3FFFFFF) : const Color(0xA6000000);
        break;
      case LiquidButtonVariant.success:
        bg = const Color(0xFF34C759).withValues(alpha: 0.20);
        border = const Color(0xFF34C759).withValues(alpha: 0.35);
        text = dark ? const Color(0xFF5FD87A) : const Color(0xFF1A7A35);
        break;
      case LiquidButtonVariant.primary:
        bg = const Color(0xFF007AFF).withValues(alpha: 0.85);
        border = const Color(0xFF007AFF).withValues(alpha: 0.50);
        text = Colors.white;
        break;
      case LiquidButtonVariant.danger:
        bg = const Color(0xFFFF3B30).withValues(alpha: dark ? 0.18 : 0.14);
        border = const Color(0xFFFF3B30).withValues(alpha: 0.28);
        text = dark ? const Color(0xFFFF6B63) : const Color(0xFF9A1A14);
        break;
      case LiquidButtonVariant.warning:
        bg = const Color(0xFFFF9500).withValues(alpha: dark ? 0.18 : 0.14);
        border = const Color(0xFFFF9500).withValues(alpha: 0.30);
        text = dark ? const Color(0xFFFFB340) : const Color(0xFF9A5500);
        break;
    }

    final button = LiquidInkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.loading) ...[
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              const SizedBox(width: 10),
            ] else if (widget.icon != null) ...[
              Icon(widget.icon, size: 16, color: text),
              const SizedBox(width: 8),
            ],
            Text(
              widget.label,
              style: TextStyle(color: text, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: widget.onTap == null || widget.loading ? 0.6 : 1.0,
      child: button,
    );
  }
}

// ── Status Bar ────────────────────────────────────────────────────────

class LiquidStatusBar extends StatelessWidget {
  final String left, right;
  final bool online;
  const LiquidStatusBar({super.key, this.left = '', this.right = 'Tizim faol.', this.online = true});
  @override
  Widget build(BuildContext context) {
    final c = LiquidColors.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          decoration: BoxDecoration(
            color: c.statusBg,
            border: Border(top: BorderSide(color: c.statusBorder, width: 0.5)),
          ),
          child: Row(children: [
            if (left.isNotEmpty) Text(left, style: TextStyle(fontSize: 11, color: c.muted)),
            const Spacer(),
            Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: online ? const Color(0xFF34C759) : const Color(0xFFFF3B30))),
            const SizedBox(width: 6),
            Text(right, style: TextStyle(fontSize: 11, color: c.muted)),
          ]),
        ),
      ),
    );
  }
}

// ── CUSTOM LIQUID SPLASH ──────────────────────────────────────────────

class LiquidInkWell extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  const LiquidInkWell({super.key, required this.child, this.onTap, this.borderRadius});
  @override State<LiquidInkWell> createState() => _LiquidInkWellState();
}

class _LiquidInkWellState extends State<LiquidInkWell> with TickerProviderStateMixin {
  final List<_RippleModel> _ripples = [];
  
  void _addRipple(Offset position) {
    final controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500));
    final ripple = _RippleModel(position: position, controller: controller);
    setState(() => _ripples.add(ripple));
    controller.forward().then((_) {
      setState(() => _ripples.remove(ripple));
      controller.dispose();
    });
  }

  @override
  void dispose() {
    for (var r in _ripples) { r.controller.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (details) {
        _addRipple(details.localPosition);
      },
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: widget.borderRadius ?? BorderRadius.zero,
        child: Stack(
          children: [
            widget.child,
            ..._ripples.map((ripple) => AnimatedBuilder(
              animation: ripple.controller,
              builder: (context, child) {
                final curvedValue = CurvedAnimation(
                  parent: ripple.controller,
                  curve: Curves.easeOutSine,
                ).value;
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return CustomPaint(
                  painter: _LiquidSplashPainter(
                    position: ripple.position,
                    progress: curvedValue,
                    isDark: isDark,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.28)
                        : Colors.black.withValues(alpha: 0.12),
                  ),
                );
              },
            )),
          ],
        ),
      ),
    );
  }
}

class _RippleModel {
  final Offset position;
  final AnimationController controller;
  _RippleModel({required this.position, required this.controller});
}

class _LiquidSplashPainter extends CustomPainter {
  final Offset position;
  final double progress;
  final Color color;
  final bool isDark;
  _LiquidSplashPainter({required this.position, required this.progress, required this.color, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress < 0.20) {
      final p = progress / 0.20;
      final dropY = position.dy - (15.0 * (1.0 - p));
      
      // Tomchi quyrug'i (Droplet tail/glow)
      final glowPaint = Paint()
        ..color = color.withValues(alpha: color.a * 0.3 * p)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
      canvas.drawCircle(Offset(position.dx, dropY), 4.0, glowPaint);

      // Asosiy tomchi (Main droplet)
      final dropPaint = Paint()
        ..color = color.withValues(alpha: color.a * 0.9)
        ..style = PaintingStyle.fill;
      final dropRect = Rect.fromCenter(
        center: Offset(position.dx, dropY),
        width: 3.5 + (1.0 - p) * 1.5,
        height: 6.0 + (1.0 - p) * 2.0,
      );
      canvas.drawOval(dropRect, dropPaint);
      return;
    }

    final rp = (progress - 0.20) / 0.80;
    final alpha = color.a * (1.0 - Curves.easeIn.transform(rp));
    final radius = rp * 160.0;
    
    // 1. Markaziy "Urilish" porlashi (Center impact glow)
    if (rp < 0.3) {
      final impactAlpha = (1.0 - (rp / 0.3)) * 0.4;
      final impactPaint = Paint()
        ..color = Colors.white.withValues(alpha: impactAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
      canvas.drawCircle(position, 15.0 + rp * 30, impactPaint);
    }

    // 2. Maximum Fidelity Organic Ripples (7 Layers with Prism Shimmer)
    for (int i = 0; i < 7; i++) {
      final delay = i * 0.08 * (1.0 + i * 0.05); // Murakkabroq kechikish (Staggered delay)
      if (rp > delay) {
        final localRp = (rp - delay) / (1.0 - delay);
        final waveAlpha = alpha * (1.3 - localRp);
        final baseWaveRadius = radius * (1.1 + (i * 0.16)) * localRp;
        final waveWidth = 3.0 + (1.0 - localRp) * 4.0;
        
        final wavePath = Path();
        const segments = 45; 
        for (int j = 0; j <= segments; j++) {
          final angle = (j * 360 / segments) * (3.14159 / 180.0);
          final wobble = (i % 2 == 0 ? 1.8 : -1.8) * math.sin(angle * 3.8 + rp * 5.5) * (1.0 - localRp) * 2.2;
          final r = baseWaveRadius + wobble;
          final x = position.dx + r * math.cos(angle);
          final y = position.dy + r * math.sin(angle);
          if (j == 0) { wavePath.moveTo(x, y); } else { wavePath.lineTo(x, y); }
        }
        wavePath.close();

        // 3D Soya (Deep Blue/Black)
        final shadowPaint = Paint()
          ..color = (isDark ? const Color(0xFF001133) : const Color(0xFF0D47A1))
              .withValues(alpha: waveAlpha * 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = waveWidth * 1.6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);
        canvas.drawPath(wavePath.shift(const Offset(2.2, 2.2)), shadowPaint);

        // Prism Shimmer (Subtle Chromatic Aberration)
        final prismPaint = Paint()
          ..color = Colors.cyan.withValues(alpha: waveAlpha * 0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = waveWidth;
        canvas.drawPath(wavePath.shift(const Offset(0.5, 0.5)), prismPaint);

        // Asosiy to'lqin (Main Transparent Body)
        final wavePaint = Paint()
          ..color = color.withValues(alpha: waveAlpha.clamp(0.0, 1.0))
          ..style = PaintingStyle.stroke
          ..strokeWidth = waveWidth
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
        canvas.drawPath(wavePath, wavePaint);

        // Maksimal yaltiroq Crest (Crisp Highlight)
        final highlightPaint = Paint()
          ..color = Colors.white.withValues(alpha: waveAlpha * (isDark ? 0.85 : 0.55))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0; 
        canvas.drawPath(wavePath.shift(const Offset(-1.5, -1.5)), highlightPaint);
      }
    }

    // 4. Multi-Phase Bounce (Two small droplets jumping out)
    void drawBounce(double startTime, double endTime, double h, double sizeMul) {
      if (rp > startTime && rp < endTime) {
        final bpp = (rp - startTime) / (endTime - startTime);
        final bh = math.sin(bpp * 3.14159) * h;
        final bpnt = Paint()
          ..color = color.withValues(alpha: color.a * (1.0 - bpp))
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(position.dx, position.dy - bh), (2.5 * sizeMul) * (1.1 - bpp), bpnt);
      }
    }
    drawBounce(0.05, 0.45, 22.0, 1.0); // 1-chi sakrash (Katta)
    drawBounce(0.40, 0.80, 8.0, 0.5);  // 2-chi sakrash (Kichik)

    // Markaziy to'ldirilgan to'lqin (Center filled pulse)
    final ripple1Paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: alpha * 0.6),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.7, 1.0],
      ).createShader(Rect.fromCircle(center: position, radius: radius * 0.5))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(position, radius * 0.5, ripple1Paint);

    // 3. Markaziy sachrash (Crown splash - simple simulation)
    if (rp < 0.5) {
      final cp = rp / 0.5;
      final crownPaint = Paint()
        ..color = color.withValues(alpha: alpha * (1.0 - cp))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawArc(
        Rect.fromCircle(center: position, radius: 10 + cp * 20),
        0, 6.28, false, crownPaint
      );
    }

    // 4. Sachrash zarrachalari (Dynamic particles)
    if (rp < 0.45) {
      final sp = rp / 0.45;
      final particlePaint = Paint()
        ..color = color.withValues(alpha: alpha * (1.0 - sp))
        ..style = PaintingStyle.fill;
      
      for (int i = 0; i < 6; i++) {
        final dist = sp * 35.0;
        final spreadX = (i % 2 == 0 ? 1.0 : 1.3);
        canvas.drawCircle(
          Offset(position.dx + dist * spreadX * (i < 3 ? 1 : -1), 
                 position.dy + dist * 0.6 * (i % 3 == 0 ? 1 : -1)), 
          1.8 * (1.0 - sp), 
          particlePaint
        );
      }
    }
  }

  @override
  bool shouldRepaint(_LiquidSplashPainter oldDelegate) => true;
}
