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
    // 🛡️ RE-MOVED: Bot stays local only as per request
    // 'branch_orders',
    // 'branch_order_items',
    // 'telegram_users'
  ];

  Future<void> init({bool autoStart = true}) async {
    // 🛡️ Safety: Cancel existing timer if any
    _syncTimer?.cancel();
    
    // Start periodic sync every 5 minutes (reduced frequency for performance)
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) => startSync());
    
    // Initial sync - only if autoStart is true
    if (autoStart) {
      startSync();
    }
  }

  Future<void> startSync() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      // Session might still be loading — retry once after a short delay
      _updateStatus("Connecting...");
      await Future.delayed(const Duration(seconds: 4));
      final retryUser = _supabase.auth.currentUser;
      if (retryUser == null) {
        _updateStatus("Not Auth");
        return;
      }
    }
    
    final activeUser = _supabase.auth.currentUser!;
    if (_isSyncing) return;
    _isSyncing = true;
    _updateStatus("Syncing...");
    debugPrint("🔄 SyncService: Starting background synchronization for user: ${activeUser.email}...");

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
      await resetSyncMetadata();
      await startSync();
    } else {
      await pullCloudChanges(tables: tables, forceFull: true);
    }
  }

  Future<void> resetSyncMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastSyncKey);
    debugPrint("🧹 SyncService: Last sync timestamp cleared.");
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
          // Special Check: If we are pushing stock_in/out, verify the product_id is synced first
          if (table == 'stock_in' || table == 'stock_out') {
             final productId = row['product_id'];
             final productCheck = await db.query('products', where: 'id = ? AND sync_status = ?', whereArgs: [productId, 'synced']);
             if (productCheck.isEmpty) {
               debugPrint("⏳ SyncService: Skipping $table ID: ${row['id']} because Product $productId is not yet synced.");
               continue; 
             }
          }

          final user = _supabase.auth.currentUser;
          if (user == null) return;

          final data = Map<String, dynamic>.from(row);
          data['user_id'] = user.id; // Assign current user
          
          final localOnlyColumns = [
            'sync_status', 
            'is_deleted', 
            'deleted_at',
            'short_code',
            'payment_status',
            'location',
            'tax_percent',
            'tax_sum',
            'surcharge_percent',
            'surcharge_sum',
          ];
          
          for (var col in localOnlyColumns) {
            data.remove(col);
          }
          
          if (data.length > 2) { // 2 because id + user_id
             await _supabase.from(table).upsert(data);
          }
          
          await db.update(
            table,
            {'sync_status': 'synced'},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        } catch (e) {
          debugPrint("❌ SyncService Push Error ($table, ID: ${row['id']}): $e");
          // If a product fails to push, we don't mark it synced, so dependencies will naturally wait.
        }
      }
    }
  }

  Future<void> pullCloudChanges({List<String>? tables, bool forceFull = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncStr = prefs.getString(_lastSyncKey);
    final db = await DatabaseHelper.instance.database;
    final tablesToPull = tables ?? syncTables;

    // Ensure we pull core tables first (products, etc) before transactional ones (stock_in)
    // to avoid dependency/foreign key errors.
    
    debugPrint("⬇️ SyncService: Pulling changes from cloud since ${forceFull || lastSyncStr == null ? 'BEGINNING' : lastSyncStr}...");

    final user = _supabase.auth.currentUser;
    if (user == null) return;

    for (var table in tablesToPull) {
      var query = _supabase.from(table).select().eq('user_id', user.id);
      
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
