import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'dart:async'; // Import for Completer and StreamSubscription
import 'sync_service.dart';

class AuthProvider extends ChangeNotifier {
  static const String _kPinKey = 'auth_pin_code';
  static const String _kPinEnabledKey = 'auth_pin_enabled';

  final _supabase = Supabase.instance.client;
  User? _user;
  bool _isPinEnabled = false;
  Completer<bool>? _authCompleter;
  String _pinCode = '';
  String? _lastError;

  User? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get isPinEnabled => _isPinEnabled;
  String get pinCode => _pinCode;
  bool get hasPin => _pinCode.isNotEmpty;
  String? get lastError => _lastError;

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
      if (data.event == AuthChangeEvent.signedIn || data.event == AuthChangeEvent.initialSession) {
        if (_authCompleter != null && !_authCompleter!.isCompleted) {
          _authCompleter!.complete(true);
          _authCompleter = null;
        }
      } else if (data.event == AuthChangeEvent.signedOut) {
        if (_authCompleter != null && !_authCompleter!.isCompleted) {
          _authCompleter!.complete(false);
          _authCompleter = null;
        }
      }
      notifyListeners();
    });
    
    notifyListeners();
  }

  /// Real Supabase Login (Email/Password)
  Future<bool> login(String email, String password) async {
    _lastError = null;
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response.user != null;
    } on AuthException catch (e) {
      debugPrint("❌ [Auth] Login AuthException: ${e.message}");
      _lastError = e.message;
      return false;
    } catch (e) {
      debugPrint("❌ [Auth] Login Failed: $e");
      _lastError = e.toString();
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
    _lastError = null;
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'first_name': firstName,
          'last_name': lastName,
        },
      );
      if (response.user != null) {
        if (response.session == null) {
          _lastError = "Emailingizga tasdiqlash xati yuborildi! Iltimos, pochtangizni tekshiring.";
        }
        return true;
      }
      return false;
    } on AuthException catch (e) {
      debugPrint("❌ [Auth] Registration AuthException: ${e.message}");
      _lastError = e.message;
      return false;
    } catch (e) {
      debugPrint("❌ [Auth] Registration Failed: $e");
      _lastError = e.toString();
      return false;
    }
  }

  /// New Google Sign In Method (Updated with Direct ID Token for Web)
  Future<bool> signInWithGoogle() async {
    _lastError = null;
    const String webClientId = '176655995611-ee5d2p1jmicjf1j2ugjlo42fpa9jm8a9.apps.googleusercontent.com';

    try {
      if (kIsWeb) {
        final origin = '${Uri.base.scheme}://${Uri.base.host}${Uri.base.port != 80 && Uri.base.port != 443 ? ":${Uri.base.port}" : ""}';
        debugPrint("🌐 [Auth] Starting Supabase OAuth for Web origin: $origin");
        return await _supabase.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: origin,
          queryParams: {
            'prompt': 'select_account',
          },
        );
      } else if (Platform.isWindows || Platform.isLinux) {
        debugPrint("🪟 [Auth] Starting Browser-based Google Sign-In for Linux/Windows...");
        _authCompleter = Completer<bool>();
        await _supabase.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: 'com.obi.clinicalwarehouse://login-callback/',
          queryParams: {
            'prompt': 'select_account',
          },
        );
        // Wait for onAuthStateChange to complete the completer
        return await _authCompleter!.future.timeout(
          const Duration(minutes: 5), 
          onTimeout: () {
            _authCompleter = null;
            return false;
          }
        );
      }

      final googleSignIn = GoogleSignIn(
        clientId: '176655995611-jpcr86v24mpsqa7c451ud2hph56vhn87.apps.googleusercontent.com',
        serverClientId: '176655995611-ee5d2p1jmicjf1j2ugjlo42fpa9jm8a9.apps.googleusercontent.com',
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
    } on AuthException catch (e) {
      debugPrint("❌ [Auth] Google Sign-In AuthException: ${e.message}");
      _lastError = e.message;
      return false;
    } catch (e) {
      debugPrint("❌ [Auth] Google Sign-In Failed: $e");
      final str = e.toString();
      if (str.contains("ClientException") || str.contains("Bad ID token") || str.contains("unregistered")) {
        _lastError = "Google orqali autentifikatsiya rad etildi. Supabase sozlamalarini tekshiring.";
      } else {
        _lastError = str;
      }
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
    try {
      if (kIsWeb) {
        final googleSignIn = GoogleSignIn(
          clientId: '176655995611-ee5d2p1jmicjf1j2ugjlo42fpa9jm8a9.apps.googleusercontent.com',
        );
        await googleSignIn.signOut();
      }
    } catch (_) {}
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
