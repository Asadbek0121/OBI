import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileProvider extends ChangeNotifier {
  static const String _kNameKey = 'manager_name';
  static const String _kEmailKey = 'manager_email';
  static const String _kImageKey = 'manager_image';

  String _name = 'Foydalanuvchi';
  String _email = '';
  String? _imagePath;

  String get name => _name;
  String get email => _email;
  String? get imagePath => _imagePath;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    // Default fallback from SharedPreferences
    _name = prefs.getString(_kNameKey) ?? 'Foydalanuvchi';
    _email = prefs.getString(_kEmailKey) ?? '';
    _imagePath = prefs.getString(_kImageKey);

    // Try to load real data from Supabase if logged in
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        // Always use real email from Supabase
        _email = user.email ?? _email;

        final meta = user.userMetadata;
        if (meta != null) {
          debugPrint('👤 Supabase User Metadata: $meta');

          // Email/password signup stores first_name + last_name
          final firstName = (meta['first_name'] ?? '').toString().trim();
          final lastName = (meta['last_name'] ?? '').toString().trim();
          final combined = [firstName, lastName]
              .where((s) => s.isNotEmpty)
              .join(' ');

          // Google/OAuth stores full_name or name
          final fullName =
              (meta['full_name'] ?? meta['name'] ?? '').toString().trim();

          if (combined.isNotEmpty) {
            _name = combined;
          } else if (fullName.isNotEmpty) {
            _name = fullName;
          } else if (_email.isNotEmpty) {
            // Fallback: use email prefix before @
            _name = _email.split('@').first;
          }

          // Profile picture: avatar_url (Google) or picture
          final avatarUrl =
              (meta['avatar_url'] ?? meta['picture'] ?? '').toString().trim();
          if (avatarUrl.isNotEmpty) {
            _imagePath = avatarUrl;
          }

          debugPrint('👤 Resolved Profile: name=$_name, email=$_email, image=$_imagePath');

          // Persist to SharedPreferences so next time is faster
          await prefs.setString(_kNameKey, _name);
          await prefs.setString(_kEmailKey, _email);
          if (_imagePath != null) {
            await prefs.setString(_kImageKey, _imagePath!);
          }
        }
      }
    } catch (e) {
      debugPrint('❌ ProfileProvider: Error fetching Supabase metadata: $e');
    }

    notifyListeners();
  }

  Future<void> updateProfile(String newName, String newEmail,
      {String? imagePath}) async {
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

  /// Clear profile on logout
  Future<void> clear() async {
    _name = 'Foydalanuvchi';
    _email = '';
    _imagePath = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kNameKey);
    await prefs.remove(_kEmailKey);
    await prefs.remove(_kImageKey);
    notifyListeners();
  }
}
