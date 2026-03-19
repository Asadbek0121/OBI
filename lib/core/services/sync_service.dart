import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../database/database_helper.dart';


class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  bool _isSyncing = false;
  Timer? _syncTimer;
  final _supabase = Supabase.instance.client;

  final _syncStatusController = StreamController<String>.broadcast();
  Stream<String> get syncStatusStream => _syncStatusController.stream;
  String _currentStatus = "Disconnected";
  String get currentStatus => _currentStatus;
  bool get isSyncing => _isSyncing;

  void _updateStatus(String status) {
    _currentStatus = status;
    _syncStatusController.add(status);
  }

  static const String _lastSyncKey = 'last_successful_sync';

  // Tables that need synchronization
  static const List<String> syncTables = [
    'products',
    'stock_in',
    'stock_out',
    'asset_categories',
    'asset_locations',
    'assets',
    'branch_orders',
    'branch_order_items'
  ];

  Future<void> init() async {
    // Start periodic sync every 5 minutes
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) => startSync());
    // Initial sync
    startSync();
  }

  Future<void> startSync() async {
    if (_isSyncing) return;
    _isSyncing = true;
    _updateStatus("Syncing...");
    debugPrint("🔄 SyncService: Starting background synchronization...");

    try {
      // 1. Push Local Changes to Cloud
      await pushLocalChanges();

      // 2. Pull Cloud Changes to Local
      await pullCloudChanges();

      _updateStatus("Synced");
      debugPrint("✅ SyncService: Synchronization completed successfully.");
    } catch (e) {
      _updateStatus("Error");
      debugPrint("❌ SyncService Error: $e");
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> pushLocalChanges() async {
    final db = await DatabaseHelper.instance.database;

    for (var table in syncTables) {
      final unsynced = await db.query(
        table,
        where: "sync_status != 'synced'",
      );

      if (unsynced.isEmpty) continue;

      debugPrint("⬆️ SyncService: Pushing ${unsynced.length} records from '$table'...");

      for (var row in unsynced) {
        try {
          final data = Map<String, dynamic>.from(row);
          
          // 🛡️ Filter out local-only columns to prevent Cloud Sync errors
          // These columns might not exist in the basic Supabase schema yet
          final localOnlyColumns = [
            'sync_status', 
            'is_deleted', 
            'deleted_at',
            'short_code',     // Only for asset_locations
            'payment_status', // Only for stock_in
            'location',        // Error log mention
            'tax_percent',    // New column mismatch with cloud
            'tax_sum',
            'surcharge_percent',
            'surcharge_sum',
            // 'min_stock_alert'  // Now allowed to sync as it exists in Supabase
          ];
          
          for (var col in localOnlyColumns) {
            data.remove(col);
          }
          
          // Only send if not empty (besides ID)
          if (data.length > 1) {
             await _supabase.from(table).upsert(data);
          }
          
          // Mark as synced locally
          await db.update(
            table,
            {'sync_status': 'synced'},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        } catch (e) {
          debugPrint("⚠️ SyncService Push Error ($table, ID: ${row['id']}): $e");
        }
      }
    }
  }

  Future<void> pullCloudChanges() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncStr = prefs.getString(_lastSyncKey);
    final db = await DatabaseHelper.instance.database;

    debugPrint("⬇️ SyncService: Pulling changes from cloud since $lastSyncStr...");

    for (var table in syncTables) {
      var query = _supabase.from(table).select();
      
      if (lastSyncStr != null) {
        query = query.gt('updated_at', lastSyncStr);
      }

      final cloudData = await query;

      if (cloudData.isEmpty) continue;

      debugPrint("⬇️ SyncService: Downloading ${cloudData.length} records for '$table'...");

      for (var row in cloudData) {
        final localData = Map<String, dynamic>.from(row);
        localData['sync_status'] = 'synced'; // Mark as synced after pulling

        await db.insert(
          table,
          localData,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }

    // Update last sync timestamp
    await prefs.setString(_lastSyncKey, DateTime.now().toUtc().toIso8601String());
  }

  void dispose() {
    _syncTimer?.cancel();
  }
}
