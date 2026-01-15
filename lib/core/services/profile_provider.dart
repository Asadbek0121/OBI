import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileProvider extends ChangeNotifier {
  static const String _kNameKey = 'manager_name';
  static const String _kEmailKey = 'manager_email';

  String _name = 'Admin Manager';
  String _email = 'admin@lab.com';

  String get name => _name;
  String get email => _email;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _name = prefs.getString(_kNameKey) ?? 'Admin Manager';
    _email = prefs.getString(_kEmailKey) ?? 'admin@lab.com';
    notifyListeners();
  }

  Future<void> updateProfile(String newName, String newEmail) async {
    _name = newName;
    _email = newEmail;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNameKey, _name);
    await prefs.setString(_kEmailKey, _email);
    notifyListeners();
  }
}
