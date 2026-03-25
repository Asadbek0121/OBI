import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clinical_warehouse/core/services/auth_provider.dart';
import 'package:clinical_warehouse/features/dashboard/dashboard_screen.dart';
import 'package:clinical_warehouse/features/auth/pin_entry_screen.dart';
import '../../core/localization/app_translations.dart';
import '../../core/widgets/window_buttons.dart';
import 'dart:io';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  // Animation Controllers
  late AnimationController _layoutController;
  late Animation<double> _widthAnimation;
  late Animation<double> _formOpacityAnimation;

  late AnimationController _logoController;
  late Animation<double> _logoScaleAnimation;

  bool _showLogin = false;
  bool _isLoading = false;
  bool _isPinMode = false;
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  String _errorText = '';

  @override
  void initState() {
    super.initState();

    // 1. Layout Transition (Full Screen -> Split Screen)
    _layoutController = AnimationController(
       vsync: this, 
       duration: const Duration(milliseconds: 1200)
    );
    
    // Width fraction: 1.0 (Full) -> 0.4 (Left Side)
    _widthAnimation = Tween<double>(begin: 1.0, end: 0.4).animate(
      CurvedAnimation(parent: _layoutController, curve: Curves.easeInOutCubicEmphasized)
    );

    _formOpacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _layoutController, curve: const Interval(0.6, 1.0, curve: Curves.easeOut))
    );

    // 2. Logo Pulse
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    
    _logoScaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOut)
    );

    _runSequence();
  }

  void _runSequence() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    // Initial loading phase
    await Future.delayed(const Duration(milliseconds: 2000));
    
    if (mounted) {
      if (auth.isPinEnabled) {
        setState(() => _isPinMode = true);
      }
      setState(() => _showLogin = true);
      _layoutController.forward();
    }
  }

  @override
  void dispose() {
    _layoutController.dispose();
    _logoController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    
    setState(() {
      _isLoading = true;
      _errorText = ''; 
    });

    await Future.delayed(const Duration(milliseconds: 1200));

    if (auth.login(_userController.text, _passController.text)) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 1000),
          pageBuilder: (ctx, anim, secAnim) => const DashboardScreen(),
          transitionsBuilder: (ctx, anim, secAnim, child) => FadeTransition(opacity: anim, child: child),
        ),
      );
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorText = AppTranslations().text('msg_login_error');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<AppTranslations>(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Row(
            children: [
          // --- LEFT PANEL (BRANDING) ---
          // Animates from width 100% -> 40%
          AnimatedBuilder(
            animation: _widthAnimation,
            builder: (context, child) {
              return Expanded(
                flex: (_widthAnimation.value * 100).toInt(),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0A0D14), Color(0xFF1E293B)], // Vibrant Premium Dark
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Decorative Circles
                      Positioned(
                        top: -100, right: -100,
                        child: Container(
                          width: 400, height: 400,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.05)),
                        ),
                      ),
                      Positioned(
                        bottom: -50, left: -50,
                        child: Container(
                          width: 300, height: 300,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.05)),
                        ),
                      ),
                      
                      // Content
                      Center(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ScaleTransition(
                                scale: _logoScaleAnimation,
                                child: Image.asset('assets/logo.png', width: 200, height: 200, fit: BoxFit.contain),
                              ),
                              const SizedBox(height: 32),
                              const Text(
                                "OMBORXONA",
                                style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 6),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white24),
                                  borderRadius: BorderRadius.circular(20),
                                  color: Colors.white10,
                                ),
                                child: const Text(
                                  "BOSHQARUV TIZIMI",
                                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 2),
                                ),
                              ),
                              
                              if (!_showLogin) ...[
                                const SizedBox(height: 60),
                                const SizedBox(
                                  width: 24, height: 24, 
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  t.text('msg_loading'),
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                                ),
                              ]
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // --- RIGHT PANEL (LOGIN) ---
          // Animates from width 0% -> 60%
          AnimatedBuilder(
            animation: _widthAnimation,
            builder: (context, child) {
              // Calculate remaining flex
              int flex = 100 - (_widthAnimation.value * 100).toInt();
              if (flex <= 0) return const SizedBox.shrink();

              return Expanded(
                flex: flex,
                child: FadeTransition(
                  opacity: _formOpacityAnimation,
                  child: Container(
                    color: const Color(0xFFF8F9FE), // Very light grey clean background
                    padding: const EdgeInsets.all(48),
                    child: Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              t.text('text_welcome'), // Xush Kelibsiz!
                              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              t.text('set_auth'), // Iltimos...
                              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                            ),
                            const SizedBox(height: 48),

                            // Inputs
                            _buildInputLabel(t.text('login')), // Foydalanuvchi (Login)
                            const SizedBox(height: 8),
                            _buildInput(
                              controller: _userController, 
                              hint: "admin", 
                              icon: Icons.person_outline
                            ),
                            
                            const SizedBox(height: 24),
                            
                            _buildInputLabel(t.text('password')), // Parol
                            const SizedBox(height: 8),
                            _buildInput(
                              controller: _passController, 
                              hint: "••••••", 
                              icon: Icons.lock_outline, 
                              isPassword: true,
                              onSubmit: _handleLogin
                            ),

                            // Error Box
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              height: _errorText.isNotEmpty ? 40 : 0,
                              margin: EdgeInsets.only(top: _errorText.isNotEmpty ? 24 : 0),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFEBEE),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFFFCDD2)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error, color: Colors.red, size: 20),
                                  const SizedBox(width: 8),
                                  Text(_errorText, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),

                            const SizedBox(height: 40),

                            // Button
                            Container(
                              height: 56,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF0038F3), Color(0xFF00D2FF)],
                                ),
                                boxShadow: [
                                  BoxShadow(color: const Color(0xFF0038F3).withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 8)),
                                ]
                              ),
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _handleLogin,
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                child: _isLoading 
                                 ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                 : Row(
                                   mainAxisAlignment: MainAxisAlignment.center,
                                   children: [
                                     Text(t.text('btn_login'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                     const SizedBox(width: 8),
                                     const Icon(Icons.login_rounded),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
          if (_isPinMode)
            PinEntryScreen(
              onCancel: () => setState(() => _isPinMode = false),
            ),
          if (!Platform.isMacOS)
            const Positioned(
              top: 0,
              right: 0,
              child: SafeArea(child: WindowButtons()),
            ),
        ],
      ),
    );
  }

  Widget _buildInputLabel(String label) {
    return Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF333333)));
  }

  Widget _buildInput({
    required TextEditingController controller, 
    required String hint, 
    required IconData icon, 
    bool isPassword = false,
    VoidCallback? onSubmit
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(color: Colors.grey.withValues(alpha: 0.05), blurRadius: 4, offset:const Offset(0, 2))
        ]
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black),
        cursorColor: const Color(0xFF0038F3),
        onSubmitted: onSubmit != null ? (_) => onSubmit() : null,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400),
          prefixIcon: Icon(icon, color: Colors.grey.shade500),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}
