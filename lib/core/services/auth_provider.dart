import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider extends ChangeNotifier {
  static const String _kUsernameKey = 'login_username';
  static const String _kPasswordKey = 'login_password';
  static const String _kPinKey = 'auth_pin_code';
  static const String _kPinEnabledKey = 'auth_pin_enabled';

  bool _isLoggedIn = false;
  bool _isPinEnabled = false;
  String _username = 'Depo';
  String _password = 'depo11';
  String _pinCode = '';

  bool get isLoggedIn => _isLoggedIn;
  bool get isPinEnabled => _isPinEnabled;
  String get username => _username;
  String get password => _password;
  String get pinCode => _pinCode;
  bool get hasPin => _pinCode.isNotEmpty;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _username = prefs.getString(_kUsernameKey) ?? 'Depo';
    _password = prefs.getString(_kPasswordKey) ?? 'depo11';
    _pinCode = prefs.getString(_kPinKey) ?? '';
    _isPinEnabled = prefs.getBool(_kPinEnabledKey) ?? false;
    _isLoggedIn = false; 
    notifyListeners();
  }

  bool login(String user, String pass) {
    if (user == _username && pass == _password) {
      _isLoggedIn = true;
      notifyListeners();
      return true;
    }
    return false;
  }

  bool verifyPin(String code) {
    if (_isPinEnabled && code == _pinCode) {
      _isLoggedIn = true;
      notifyListeners();
      return true;
    }
    return false;
  }

  void logout() {
    _isLoggedIn = false;
    notifyListeners();
  }

  Future<void> updatePin(String newPin) async {
    _pinCode = newPin;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPinKey, _pinCode);
    notifyListeners();
  }

  Future<void> togglePin(bool enabled) async {
    _isPinEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPinEnabledKey, _isPinEnabled);
    notifyListeners();
  }

  Future<void> updateCredentials(String newUser, String newPass) async {
    _username = newUser;
    _password = newPass;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUsernameKey, _username);
    await prefs.setString(_kPasswordKey, _password);
    notifyListeners();
  }
}
