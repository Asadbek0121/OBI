import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider extends ChangeNotifier {
  static const String _kIsLoggedInKey = 'is_logged_in';
  static const String _kUsernameKey = 'login_username';
  static const String _kPasswordKey = 'login_password';

  bool _isLoggedIn = false;
  String _username = 'Depo';
  String _password = 'depo11';

  bool get isLoggedIn => _isLoggedIn;
  String get username => _username;
  String get password => _password;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    // For now, we reset login status on every app restart for security/demo
    // But we keep credentials persistent
    _username = prefs.getString(_kUsernameKey) ?? 'Depo';
    _password = prefs.getString(_kPasswordKey) ?? 'depo11';
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

  void logout() {
    _isLoggedIn = false;
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
