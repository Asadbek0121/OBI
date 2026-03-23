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
  String _lastError = "";
  String get currentStatus => _currentStatus;
  String get lastError => _lastError;
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

  Future<void> init({bool autoStart = true}) async {
    // Start periodic sync every 5 minutes
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) => startSync());
    
    // Initial sync - only if autoStart is true
    if (autoStart) {
      startSync();
    }
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
      _lastError = e.toString();
      _updateStatus("Error");
      debugPrint("❌ SyncService Error: $e");
    } finally {
      _isSyncing = false;
    }
  }

  /// Clears the last sync timestamp and performs a deep pull from Supabase.
  /// This ensures ALL data from the cloud is fetched to the local machine.
  Future<void> fullResync({List<String>? tables}) async {
    if (tables == null || tables.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastSyncKey);
      await startSync();
    } else {
      await pullCloudChanges(tables: tables, forceFull: true);
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

  Future<void> pullCloudChanges({List<String>? tables, bool forceFull = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncStr = prefs.getString(_lastSyncKey);
    
    // 🛡️ SECURITY/UX FIX: If never synced before and not forced, SKIP pulling.
    // This prevents automatic messy restore after factory reset.
    if (lastSyncStr == null && !forceFull) {
      debugPrint("⏭️ SyncService: Skipping automatic pull (No previous sync history). Use Manual Restore.");
      return;
    }

    final db = await DatabaseHelper.instance.database;
    final tablesToPull = tables ?? syncTables;

    debugPrint("⬇️ SyncService: Pulling changes from cloud since ${forceFull ? 'BEGINNING' : lastSyncStr}...");

    for (var table in tablesToPull) {
      var query = _supabase.from(table).select();
      
      // If we are NOT forcing full, use the last sync timestamp
      if (lastSyncStr != null && !forceFull) {
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

    // Update last sync timestamp to the current time.
    // This allows subsequent periodic syncs to be incremental.
    await prefs.setString(_lastSyncKey, DateTime.now().toUtc().toIso8601String());
  }

  void dispose() {
    _syncTimer?.cancel();
  }
}
