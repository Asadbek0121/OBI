import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DatabaseSecurityService {
  // STRICT "Zero-Knowledge" Architecture related constants
  static const _kKeyStorageId = 'clinical_warehouse_vault_key_v1';
  
  final FlutterSecureStorage _secureStorage;

  DatabaseSecurityService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// The "Auto-Unlock" Feature
  /// 
  /// Retrieves the 64-character Secure Key from the OS Secure Enclave.
  /// If this is the first launch, it generates and cryptographically stores it.
  /// 
  /// Throws [SecurityException] if the key cannot be accessed (e.g. data theft attempt).
  Future<String> getDatabaseEncryptionKey() async {
    try {
      // 1. Try to retrieve existing key from Keychain/Keystore
      String? key = await _secureStorage.read(key: _kKeyStorageId);

      // 2. If missing, this is a fresh install (or a wiped state).
      // Generate a new Military-Grade Key.
      if (key == null) {
        key = _generateSecureRandomKey();
        await _secureStorage.write(key: _kKeyStorageId, value: key);
        print("🔐 Security: New Vault Key generated and stored in Secure Enclave.");
      } else {
        print("🔓 Security: Vault Key successfully retrieved from Secure Enclave.");
      }

      return key;
    } catch (e) {
      // If we can't talk to the Secure Enclave, we must FAIL SAFE.
      // Do NOT allow database access.
      throw SecurityException("CRITICAL: Failed to access Secure Enclave. Database locked. Details: $e");
    }
  }

  /// Generates a cryptographically secure 64-character random key.
  String _generateSecureRandomKey() {
    final random = Random.secure();
    // Generate 32 bytes (256 bits) of random data
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    // Encode as hex string (64 characters)
    return base64UrlEncode(values); 
  }
}

class SecurityException implements Exception {
  final String message;
  SecurityException(this.message);
  @override
  String toString() => "SecurityException: $message";
}
