import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileProvider extends ChangeNotifier {
  static const String _kNameKey = 'manager_name';
  static const String _kEmailKey = 'manager_email';
  static const String _kImageKey = 'manager_image';

  String _name = 'Admin Manager';
  String _email = 'admin@lab.com';
  String? _imagePath;

  String get name => _name;
  String get email => _email;
  String? get imagePath => _imagePath;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Default fallback
    _name = prefs.getString(_kNameKey) ?? 'Admin Manager';
    _email = prefs.getString(_kEmailKey) ?? 'admin@lab.com';
    _imagePath = prefs.getString(_kImageKey);

    // TRY TO UPDATE FROM SUPABASE IF LOGGED IN
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        _email = user.email ?? _email;
        final meta = user.userMetadata;
        if (meta != null) {
          debugPrint("👤 Supabase User Metadata: $meta");
          _name = meta['full_name'] ?? meta['name'] ?? _name;
          // Check multiple possible keys for the profile picture
          _imagePath = meta['avatar_url'] ?? meta['picture'] ?? _imagePath;
          debugPrint("🖼️ Resolved Profile Image Path: $_imagePath");
        }
      }
    } catch (e) {
      debugPrint("❌ ProfileProvider: Error fetching Supabase metadata: $e");
    }

    notifyListeners();
  }

  Future<void> updateProfile(String newName, String newEmail, {String? imagePath}) async {
    _name = newName;
    _email = newEmail;
    if (imagePath != null) _imagePath = imagePath;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNameKey, _name);
    await prefs.setString(_kEmailKey, _email);
    if (_imagePath != null) await prefs.setString(_kImageKey, _imagePath!);
    notifyListeners();
  }

  Future<void> updateImage(String path) async {
    _imagePath = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kImageKey, _imagePath!);
    notifyListeners();
  }
}
