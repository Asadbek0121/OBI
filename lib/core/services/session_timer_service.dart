import 'dart:async';
import 'package:flutter/material.dart';

class SessionTimerService extends ChangeNotifier {
  static const Duration _timeout = Duration(minutes: 5); // Default 5 minutes
  Timer? _timer;
  bool _isLocked = false;
  bool _isEnabled = false;

  bool get isLocked => _isLocked;

  void enable(bool value) {
    _isEnabled = value;
    if (_isEnabled) {
      resetTimer();
    } else {
      _timer?.cancel();
    }
    notifyListeners();
  }

  void resetTimer() {
    if (!_isEnabled) return;
    
    _timer?.cancel();
    _timer = Timer(_timeout, () {
      _lockApp();
    });
  }

  void _lockApp() {
    if (_isLocked || !_isEnabled) return;
    _isLocked = true;
    notifyListeners();
  }

  void unlock() {
    _isLocked = false;
    resetTimer();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
