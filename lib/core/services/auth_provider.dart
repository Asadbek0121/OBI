import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:io';
import 'sync_service.dart';

class AuthProvider extends ChangeNotifier {
  static const String _kUsernameKey = 'login_username';
  static const String _kPasswordKey = 'login_password';
  static const String _kPinKey = 'auth_pin_code';
  static const String _kPinEnabledKey = 'auth_pin_enabled';

  final _supabase = Supabase.instance.client;
  User? _user;
  bool _isLoggedIn = false;
  bool _isPinEnabled = false;
  String _username = 'Depo';
  String _password = 'depo11';
  String _pinCode = '';

  User? get user => _user;
  bool get isLoggedIn => _isLoggedIn || _user != null;
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
    
    // Check Supabase session
    _user = _supabase.auth.currentUser;
    _isLoggedIn = _user != null;
    
    _supabase.auth.onAuthStateChange.listen((data) {
      _user = data.session?.user;
      _isLoggedIn = _user != null;
      notifyListeners();
    });
    
    notifyListeners();
  }

  /// Original local login (Legacy support)
  bool login(String user, String pass) {
    if (user == _username && pass == _password) {
      _isLoggedIn = true;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// New Google Sign In Method
  Future<bool> signInWithGoogle() async {
    try {
      // For Desktop (macOS/Windows), standard google_sign_in can behave differently.
      // We will use the Supabase OAuth flow.
      final googleSignIn = GoogleSignIn(
        clientId: Platform.isIOS || Platform.isMacOS 
            ? '575519548512-eid704v2ghhoe1e49qaeqfaj4u0jftjh.apps.googleusercontent.com' 
            : '575519548512-9cmofokav83sd3mv9j5v0ma5tdpd77q9.apps.googleusercontent.com', // Web Client for Windows
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
      _isLoggedIn = true;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> logout() async {
    await _supabase.auth.signOut();
    await SyncService().resetSyncMetadata(); // Reset sync timestamps on logout
    _isLoggedIn = false;
    _user = null;
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
