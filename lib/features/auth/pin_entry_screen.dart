import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/services/auth_provider.dart';
import '../../core/localization/app_translations.dart';
import '../../core/theme/app_colors.dart';
import '../dashboard/dashboard_screen.dart';
import 'dart:ui';
import '../../core/widgets/glass_container.dart';

class PinEntryScreen extends StatefulWidget {
  final VoidCallback onCancel;
  const PinEntryScreen({super.key, required this.onCancel});

  @override
  State<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<PinEntryScreen> {
  String _enteredPin = '';
  bool _isError = false;

  void _onNumberPressed(String number) {
    if (_enteredPin.length < 4) {
      setState(() {
        _enteredPin += number;
        _isError = false;
      });
      if (_enteredPin.length == 4) {
        _verifyPin();
      }
    }
  }

  void _onBackspace() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        _isError = false;
      });
    }
  }

  void _verifyPin() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    await Future.delayed(const Duration(milliseconds: 200));
    
    if (auth.verifyPin(_enteredPin)) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 800),
          pageBuilder: (ctx, anim, secAnim) => const DashboardScreen(),
          transitionsBuilder: (ctx, anim, secAnim, child) => FadeTransition(opacity: anim, child: child),
        ),
      );
    } else {
      setState(() {
        _enteredPin = '';
        _isError = true;
      });
      // Haptic feedback or shake?
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<AppTranslations>(context);
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            final key = event.logicalKey;
            if (key.keyLabel.length == 1 && RegExp(r'[0-9]').hasMatch(key.keyLabel)) {
              _onNumberPressed(key.keyLabel);
              return KeyEventResult.handled;
            } else if (key == LogicalKeyboardKey.backspace) {
              _onBackspace();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          children: [
            // Background Blur
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(color: Colors.white.withValues(alpha: 0.1)),
            ),
            
            Center(
              child: Container(
                width: 400,
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_rounded, size: 64, color: AppColors.primary),
                    const SizedBox(height: 24),
                    Text(
                      t.text('enter_pin').toUpperCase(),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: 2),
                    ),
                    const SizedBox(height: 32),
                    
                    // PIN Dots
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (index) {
                        bool isFilled = index < _enteredPin.length;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isError ? Colors.red : (isFilled ? AppColors.primary : Colors.grey.shade300),
                            boxShadow: isFilled && !_isError ? [
                              BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 8, spreadRadius: 2)
                            ] : null,
                          ),
                        );
                      }),
                    ),
                    
                    if (_isError) ...[
                      const SizedBox(height: 16),
                      const Text(
                        "PIN kod noto'g'ri!",
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                    ],
                    
                    const SizedBox(height: 48),
                    
                    // Keypad
                    GridView.count(
                      shrinkWrap: true,
                      crossAxisCount: 3,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 1.5,
                      children: [
                        ...List.generate(9, (index) => _buildKey((index + 1).toString())),
                        const SizedBox.shrink(),
                        _buildKey('0'),
                        _buildKey('backspace', isIcon: true),
                      ],
                    ),
                    
                    const SizedBox(height: 40),
                    
                    TextButton(
                      onPressed: widget.onCancel,
                      child: Text(
                        t.text('btn_auth_password').toUpperCase(),
                        style: TextStyle(color: AppColors.textPrimary.withValues(alpha: 0.6), fontWeight: FontWeight.w800, letterSpacing: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKey(String value, {bool isIcon = false}) {
    return GlassContainer(
      onTap: () => isIcon ? _onBackspace() : _onNumberPressed(value),
      borderRadius: 24,
      blur: 20,
      opacity: 0.08,
      padding: EdgeInsets.zero,
      child: Center(
        child: isIcon 
          ? const Icon(Icons.backspace_outlined, color: AppColors.textPrimary, size: 22)
          : Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
      ),
    );
  }
}
