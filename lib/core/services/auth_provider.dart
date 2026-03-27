import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:io';
import 'sync_service.dart';

class AuthProvider extends ChangeNotifier {
  static const String _kPinKey = 'auth_pin_code';
  static const String _kPinEnabledKey = 'auth_pin_enabled';

  final _supabase = Supabase.instance.client;
  User? _user;
  bool _isPinEnabled = false;
  String _pinCode = '';

  User? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get isPinEnabled => _isPinEnabled;
  String get pinCode => _pinCode;
  bool get hasPin => _pinCode.isNotEmpty;

  // Profiles and names from metadata or DB
  String get firstName => _user?.userMetadata?['first_name'] ?? '';
  String get lastName => _user?.userMetadata?['last_name'] ?? '';
  String get displayName => "$firstName $lastName".trim().isNotEmpty 
      ? "$firstName $lastName" 
      : (_user?.userMetadata?['full_name'] ?? _user?.email?.split('@')[0] ?? 'User');

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _pinCode = prefs.getString(_kPinKey) ?? '';
    _isPinEnabled = prefs.getBool(_kPinEnabledKey) ?? false;
    
    // Check Supabase session
    _user = _supabase.auth.currentUser;
    
    _supabase.auth.onAuthStateChange.listen((data) {
      _user = data.session?.user;
      notifyListeners();
    });
    
    notifyListeners();
  }

  /// Real Supabase Login (Email/Password)
  Future<bool> login(String email, String password) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response.user != null;
    } catch (e) {
      debugPrint("❌ [Auth] Login Failed: $e");
      return false;
    }
  }

  /// Real Supabase Registration
  Future<bool> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'first_name': firstName,
          'last_name': lastName,
        },
      );
      return response.user != null;
    } catch (e) {
      debugPrint("❌ [Auth] Registration Failed: $e");
      return false;
    }
  }

  /// New Google Sign In Method (Updated for both macOS and Windows)
  Future<bool> signInWithGoogle() async {
    try {
      if (Platform.isWindows) {
        debugPrint("🪟 [Auth] Starting Browser-based Google Sign-In for Windows...");
        await _supabase.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: 'com.obi.clinicalwarehouse://login-callback',
        );
        return true; 
      }

      final googleSignIn = GoogleSignIn(
        clientId: Platform.isIOS || Platform.isMacOS 
            ? '575519548512-eid704v2ghhoe1e49qaeqfaj4u0jftjh.apps.googleusercontent.com' 
            : '575519548512-9cmofokav83sd3mv9j5v0ma5tdpd77q9.apps.googleusercontent.com',
        scopes: ['email', 'profile'],
      );
      
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) return false;
      
      final googleAuth = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (accessToken == null || idToken == null) {
        throw 'Missing Google Auth Tokens';
      }

      final response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      
      return response.user != null;
    } catch (e) {
      debugPrint("❌ [Auth] Google Sign-In Failed: $e");
      return false;
    }
  }

  bool verifyPin(String code) {
    if (_isPinEnabled && code == _pinCode) {
      // In a real multi-user app, PIN just unlocks the screen
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> logout() async {
    await _supabase.auth.signOut();
    await SyncService().resetSyncMetadata();
    _user = null;
    notifyListeners();
  }

  Future<bool> updatePassword(String newPassword) async {
    try {
      await _supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      return true;
    } catch (e) {
      debugPrint("❌ [Auth] Password Update Failed: $e");
      return false;
    }
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
}
