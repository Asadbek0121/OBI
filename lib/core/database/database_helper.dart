import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
// import 'package:sqflite_sqlcipher/sqflite_sqlcipher.dart'; // Temporarily disabled for build fix

import 'package:shared_preferences/shared_preferences.dart';


class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  final String _prefKeyDbPath = 'clinical_warehouse_db_path';
  String? _customDbPath;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    
    // 1. Try to load custom path if not set in memory
    if (_customDbPath == null) {
      final prefs = await SharedPreferences.getInstance();
      _customDbPath = prefs.getString(_prefKeyDbPath);
    }
    
    // 2. If still null, use default internal default (fallback) 
    // BUT strictly we want the user to pick one. For now, we keep a fallback for safety 
    // or if the UI flow hasn't been blocked yet.
    if (_customDbPath != null) {
       _database = await _initDB(_customDbPath!);
    } else {
       // Fallback to internal app storage if nothing configured
       final dbPath = await getDatabasesPath();
       final path = join(dbPath, 'clinical_warehouse_v3_connected.db');
       _database = await _initDB(path);
    }
    
    return _database!;
  }

  // New method to set user-selected path
  Future<void> setDatabasePath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyDbPath, path);
    _customDbPath = path;
    
    // Reset connection
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<String?> getConfiguredPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKeyDbPath);
  }

  Future<Database> _initDB(String filePath) async {
    // 1. Initialize FFI for Desktop
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    
    // Check if it's an absolute path (User selected) or relative (Default)
    String path = filePath;
    if (!isAbsolute(path)) {
       final dbPath = await getDatabasesPath();
       path = join(dbPath, filePath);
    }
    
    debugPrint("📂 OPENING DATABASE AT: $path");

    // Encryption Temporarily Disabled to fix Build
    // String? encryptionKey = await _secureStorage.read(key: _keyStorageName);
    
    // 3. Open Standard Database
    final db = await openDatabase(
      path,
      version: 6,
      // password: encryptionKey, // Disabled
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );

    // After opening, ensure optimizations and missing tables
    await _ensureOptimized(db);

    return db;
  }

  Future<void> _ensureOptimized(Database db) async {
    // 1. Ensure WAL mode
    await db.execute('PRAGMA journal_mode = WAL;');
    await db.execute('PRAGMA synchronous = NORMAL;');

    // 2. FORCE CHECK: Ensure 'assets' table has 'photo_path' column
    // This is critical for fixing the specific missing column crash on existing Windows deployments
    try {
      await db.execute('ALTER TABLE assets ADD COLUMN photo_path TEXT');
      debugPrint("✅ Schema Repair: Added 'photo_path' to assets table.");
    } catch (e) {
      if (!e.toString().toLowerCase().contains('duplicate')) {}
    }

    // 🚀 STEP 1 for CLOUD SYNC: Ensure ALL tables have 'updated_at' and 'sync_status'
    final tablesToSync = [
      'products', 'stock_in', 'stock_out', 'assets', 
      'asset_locations', 'asset_categories', 'asset_movements',
      'branch_orders', 'branch_order_items'
    ];

    for (var table in tablesToSync) {
      // Add 'updated_at' column
      try {
        await db.execute('ALTER TABLE $table ADD COLUMN updated_at TEXT CURRENT_TIMESTAMP');
      } catch (e) {
        // Ignore if exists
      }
      
      // Add 'sync_status' column (default: pending_insert for cloud sync logic)
      try {
        await db.execute("ALTER TABLE $table ADD COLUMN sync_status TEXT DEFAULT 'pending_insert'");
      } catch (e) {
        // Ignore if exists
      }

      // Add 'is_deleted' column (default: 0)
      try {
        await db.execute("ALTER TABLE $table ADD COLUMN is_deleted INTEGER DEFAULT 0");
        // Ensure all existing rows have 0 if they were NULL
        await db.execute("UPDATE $table SET is_deleted = 0 WHERE is_deleted IS NULL");
      } catch (e) {
        // Ignore if exists
      }
      try {
        await db.execute("ALTER TABLE $table ADD COLUMN deleted_at TEXT");
      } catch (e) {
        // Ignore if exists
      }
    }


    // 2. Assets Module Tables (RESTACKED)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS asset_locations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        parent_id INTEGER,
        name TEXT NOT NULL,
        type TEXT NOT NULL, -- 'building', 'floor', 'room', 'spot'
        FOREIGN KEY (parent_id) REFERENCES asset_locations (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS asset_categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS assets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        model TEXT,
        serial_number TEXT,
        color TEXT,
        category_id INTEGER,
        location_id INTEGER,
        status TEXT, -- 'Yangi', 'Ishlatilgan', 'Tamirtalab', 'Eskirgan'
        photo_path TEXT,
        barcode TEXT UNIQUE,
        created_at TEXT,
        FOREIGN KEY (category_id) REFERENCES asset_categories (id),
        FOREIGN KEY (location_id) REFERENCES asset_locations (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS branch_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chat_id TEXT,
        branch_name TEXT,
        status TEXT, -- 'pending', 'approved', 'rejected', 'delivered'
        photo_file_id TEXT, -- Added for image-based orders
        admin_comment TEXT, -- Added for feedback
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS branch_order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER,
        product_id TEXT,
        product_name TEXT,
        quantity REAL,
        unit TEXT,
        FOREIGN KEY (order_id) REFERENCES branch_orders (id) ON DELETE CASCADE
      )
    ''');

    // 2.2 Branch Orders migration
    try {
      await db.execute('ALTER TABLE branch_orders ADD COLUMN photo_file_id TEXT');
    } catch (e) {
      // Ignore if column already exists
    }

    try {
      await db.execute('ALTER TABLE branch_orders ADD COLUMN admin_comment TEXT');
    } catch (e) {
      // Ignore if column already exists
    }

    // Missing columns check for existing DBs (STRICTER)
    final List<String> columnsToAdd = [
      'short_code', 'serial_number', 'color', 'category_id', 
      'location_id', 'barcode', 'status', 'created_at', 'model', 
      'photo_path' // NEWLY ADDED
    ];

    for (var col in columnsToAdd) {
      try {
        if (col == 'short_code') {
          await db.execute('ALTER TABLE asset_locations ADD COLUMN $col TEXT');
        } else {
          await db.execute('ALTER TABLE assets ADD COLUMN $col TEXT');
        }
      } catch (e) {
        final err = e.toString().toLowerCase();
        if (!err.contains('duplicate') && !err.contains('already exists')) {
          debugPrint("⚠️ Schema migration warning ($col): $e");
        }
      }
    }

    // 2.2 Inbound table extra columns
    try {
      await db.execute('ALTER TABLE stock_in ADD COLUMN payment_status TEXT');
    } catch (e) {
      final err = e.toString().toLowerCase();
      if (!err.contains('duplicate') && !err.contains('already exists')) {
        debugPrint("⚠️ StockIn migration warning: $e");
      }
    }

    // 2.3 Create Asset Movements table if missing
    await db.execute('''
      CREATE TABLE IF NOT EXISTS asset_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        asset_id INTEGER NOT NULL,
        from_location_id INTEGER,
        to_location_id INTEGER NOT NULL,
        moved_at TEXT NOT NULL,
        notes TEXT,
        FOREIGN KEY (asset_id) REFERENCES assets (id) ON DELETE CASCADE,
        FOREIGN KEY (from_location_id) REFERENCES asset_locations (id),
        FOREIGN KEY (to_location_id) REFERENCES asset_locations (id)
      )
    ''');

    // 2.4 Notifications Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        message TEXT NOT NULL,
        type TEXT NOT NULL,
        created_at TEXT NOT NULL,
        is_read INTEGER DEFAULT 0
      )
    ''');
    
    // 3. Ensure Indexes for better performance
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_in_product_id ON stock_in(product_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_out_product_id ON stock_out(product_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_in_date ON stock_in(date_time)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_out_date ON stock_out(date_time)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_name ON products(name)');

    // 4. Payment Types Table
    await db.execute('CREATE TABLE IF NOT EXISTS payment_types (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)');
    // Seed if empty
    try {
      final res = await db.rawQuery('SELECT COUNT(*) FROM payment_types');
      final ptCount = res.isNotEmpty ? (res.first.values.first as int) : 0;
      
      if (ptCount == 0) {
        final pts = ['Naqd', 'Qarzga', "O'tkazma"];
        for (var p in pts) {
           await db.insert('payment_types', {'name': p});
        }
      }
    } catch (e) {
      debugPrint("⚠️ Payment Types Seed Error: $e");
    }
  }

  Future<void> createAssetsTableIfNeeded() async {
    final db = await instance.database;
    await _ensureOptimized(db);
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE stock_in ADD COLUMN tax_percent REAL DEFAULT 0');
      await db.execute('ALTER TABLE stock_in ADD COLUMN tax_sum REAL DEFAULT 0');
      await db.execute('ALTER TABLE stock_in ADD COLUMN surcharge_percent REAL DEFAULT 0');
      await db.execute('ALTER TABLE stock_in ADD COLUMN surcharge_sum REAL DEFAULT 0');
    }
  }

  Future<void> _createDB(Database db, int version) async {
    debugPrint("🛠 Creating Database Schema with SEED DATA...");
    
    // 1. Reference Tables (Lookups)
    await db.execute('CREATE TABLE units (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)');
    await db.execute('CREATE TABLE suppliers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)');
    await db.execute('CREATE TABLE receivers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)');

    // 2. Products Master Table
    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY, -- Manual ID (e.g. "101")
        name TEXT NOT NULL,
        unit TEXT, -- Denormalized for simpler UI or FK to units
        min_stock_alert INTEGER DEFAULT 10,
        description TEXT,
        created_at TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_products_id ON products(id)');

    // 3. Transactions (Updated to use new ID logic)
    await db.execute('''
      CREATE TABLE stock_in (
        id TEXT PRIMARY KEY,
        product_id TEXT,
        date_time TEXT,
        batch_number TEXT,
        expiry_date TEXT,
        quantity REAL,
        price_per_unit REAL,
        total_amount REAL,
        supplier_name TEXT,
        tax_percent REAL DEFAULT 0,
        tax_sum REAL DEFAULT 0,
        surcharge_percent REAL DEFAULT 0,
        surcharge_sum REAL DEFAULT 0,
        payment_status TEXT, -- 'Naqd', 'Qarzga', 'O'tkazma'
        FOREIGN KEY (product_id) REFERENCES products (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_out (
        id TEXT PRIMARY KEY,
        product_id TEXT,
        date_time TEXT,
        quantity REAL,
        receiver_name TEXT, 
        batch_reference TEXT,
        notes TEXT,
        FOREIGN KEY (product_id) REFERENCES products (id)
      )
    ''');

    // 5. ASSETS (Hierarchical)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS asset_locations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        parent_id INTEGER,
        name TEXT NOT NULL,
        short_code TEXT, -- Added for Smart SKU (e.g., 'TTL', 'ACC')
        type TEXT NOT NULL,
        FOREIGN KEY (parent_id) REFERENCES asset_locations (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE TABLE IF NOT EXISTS asset_categories (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS assets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        model TEXT,
        serial_number TEXT,
        color TEXT,
        category_id INTEGER,
        location_id INTEGER,
        status TEXT,
        photo_path TEXT,
        barcode TEXT UNIQUE,
        created_at TEXT,
        FOREIGN KEY (category_id) REFERENCES asset_categories (id),
        FOREIGN KEY (location_id) REFERENCES asset_locations (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS asset_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        asset_id INTEGER NOT NULL,
        from_location_id INTEGER,
        to_location_id INTEGER NOT NULL,
        moved_at TEXT NOT NULL,
        notes TEXT,
        FOREIGN KEY (asset_id) REFERENCES assets (id) ON DELETE CASCADE,
        FOREIGN KEY (from_location_id) REFERENCES asset_locations (id),
        FOREIGN KEY (to_location_id) REFERENCES asset_locations (id)
      )
    ''');

    // 4. SEED DATA INSERTION
    debugPrint("🌱 Seeding Data...");
    
    // Seed Asset Categories
    final assetCats = ['Mebel', 'Kompyuter texnikasi', 'Maishiy texnika', 'Asbob-uskunalar', 'Boshqa'];
    for (var c in assetCats) {
      await db.insert('asset_categories', {'name': c});
    }

    // Seed a Default Building
    await db.insert('asset_locations', {'name': 'Bosh OFIS', 'type': 'building'});

    
    // Units
    final units = ['QADOQ', 'KG', 'L', 'DONA', 'GR', 'QUTI', 'PACHKA'];
    for (var u in units) {
      await db.insert('units', {'name': u});
    }

    // Suppliers (KIMDAN)
    final suppliers = ['FOCUSMED', 'MEDTEXNIKA', 'ABDULLA PHARM'];
    for (var s in suppliers) {
      await db.insert('suppliers', {'name': s});
    }

    // Receivers (KIMGA)
    final receivers = [
      'ASADBEK DAVRONOV', 'ISHONCH(XURRAMOVA NOZIGUL)', 'BAK LABARATORIYA', 
      'XUSHIYVA SITORA', "JO'RAYEVA SABINA", 'KARIMOVA MOHINUR BOYSUN', 
      "JARQURG'ON TTB", "JARQURG'ON POLIKLINIKA", 'KARDIOLOGIYA', 'PRINATAL', 
      'ANGOR', 'SHEROBOD', 'XASANOVA SEVINCH', 'LABARATORIYA', 'SIL DISPANSER', 
      "MAXMADMO'MINOVA AZIZA", 'QON QUYISH MARKAZI', "ESHPO'LATOV SUNNATILLO", 
      "TURK GLOBAL CENTER AYSIN BISARO'G'LU"
    ];
    for (var r in receivers) {
      await db.insert('receivers', {'name': r});
    }

    debugPrint("✅ Database Schema & Seed Data Ready.");
  }

  // --- Lookups ---
  Future<List<String>> getUnits() async {
    final db = await instance.database;
    final res = await db.query('units', orderBy: 'name');
    return res.map((e) => e['name'] as String).toList();
  }

  Future<List<String>> getSuppliers() async {
    final db = await instance.database;
    final res = await db.query('suppliers', orderBy: 'name');
    return res.map((e) => e['name'] as String).toList();
  }

  Future<List<String>> getReceivers() async {
    final db = await instance.database;
    final res = await db.query('receivers', orderBy: 'name');
    return res.map((e) => e['name'] as String).toList();
  }

  Future<void> insertSupplier(String name) async {
    final db = await instance.database;
    await db.insert('suppliers', {'name': name}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> insertReceiver(String name) async {
    final db = await instance.database;
    await db.insert('receivers', {'name': name}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> deleteSupplier(String name) async {
    final db = await instance.database;
    await db.delete('suppliers', where: 'name = ?', whereArgs: [name]);
  }

  Future<void> deleteReceiver(String name) async {
    final db = await instance.database;
    await db.delete('receivers', where: 'name = ?', whereArgs: [name]);
  }

  Future<List<String>> getPaymentTypes() async {
    final db = await instance.database;
    final res = await db.query('payment_types', orderBy: 'id ASC');
    return res.map((e) => e['name'] as String).toList();
  }

  Future<void> insertPaymentType(String name) async {
    final db = await instance.database;
    await db.insert('payment_types', {'name': name}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  // --- Helper for Sync ---

  Map<String, dynamic> _prepareInsert(Map<String, dynamic> data) {
    var map = Map<String, dynamic>.from(data);
    map['updated_at'] = DateTime.now().toUtc().toIso8601String();
    map['sync_status'] = 'pending_insert';
    return map;
  }

  Map<String, dynamic> _prepareUpdate(Map<String, dynamic> data) {
    var map = Map<String, dynamic>.from(data);
    map['updated_at'] = DateTime.now().toUtc().toIso8601String();
    map['sync_status'] = 'pending_update';
    return map;
  }

  // --- Products Master ---
  Future<void> deletePaymentType(String name) async {
    final db = await instance.database;
    await db.delete('payment_types', where: 'name = ?', whereArgs: [name]);
  }
  
  // --- Product Logic ---
  Future<Map<String, dynamic>?> getProductById(String id) async {
    final db = await instance.database;
    final results = await db.query('products', where: 'id = ? AND is_deleted = 0', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }
  Future<Map<String, dynamic>?> getProductByName(String name) async {
    final db = await instance.database;
    final results = await db.query(
      'products', 
      where: 'name LIKE ? AND is_deleted = 0', 
      whereArgs: ['%$name%'], 
      limit: 1
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<void> insertProduct(Map<String, dynamic> product) async {
    final db = await instance.database;
    await db.insert('products', _prepareInsert(product), conflictAlgorithm: ConflictAlgorithm.replace);
  }
  
   Future<List<Map<String, dynamic>>> getAllProducts() async {
    final db = await instance.database;
    return await db.query('products', where: 'is_deleted = 0');
  }

  Future<void> deleteProduct(String id) async {
    final db = await instance.database;
    final deletedAt = DateTime.now().toUtc().toIso8601String();
    await db.update('stock_in', {'is_deleted': 1, 'deleted_at': deletedAt, 'sync_status': 'pending_update'}, where: 'product_id = ?', whereArgs: [id]);
    await db.update('stock_out', {'is_deleted': 1, 'deleted_at': deletedAt, 'sync_status': 'pending_update'}, where: 'product_id = ?', whereArgs: [id]);
    await db.update('products', {'is_deleted': 1, 'deleted_at': deletedAt, 'sync_status': 'pending_update'}, where: 'id = ?', whereArgs: [id]);
  }

  // --- Transactions ---
  Future<void> insertStockIn(Map<String, dynamic> data) async {
    final db = await instance.database;
    await db.insert('stock_in', _prepareInsert(data));
  }

  Future<void> insertStockOut(Map<String, dynamic> data) async {
    final db = await instance.database;
    await db.insert('stock_out', _prepareInsert(data));
  }

  // --- Inventory Logic ---
  // Calculates Current Stock = (Total In) - (Total Out) for each product
  Future<List<Map<String, dynamic>>> getInventorySummary() async {
    final db = await instance.database;
    
    final res = await db.rawQuery('''
      SELECT 
        p.id, 
        p.name, 
        p.unit,
        p.min_stock_alert,
        IFNULL(si.total_in, 0) as total_in,
        IFNULL(so.total_out, 0) as total_out
      FROM products p
      LEFT JOIN (
        SELECT product_id, SUM(quantity) as total_in 
        FROM stock_in WHERE is_deleted = 0 GROUP BY product_id
      ) si ON p.id = si.product_id
      LEFT JOIN (
        SELECT product_id, SUM(quantity) as total_out 
        FROM stock_out WHERE is_deleted = 0 GROUP BY product_id
      ) so ON p.id = so.product_id
      WHERE (p.is_deleted = 0 OR p.is_deleted IS NULL)
    ''');
    
    return res.map((row) {
      final tIn = (row['total_in'] as num).toDouble();
      final tOut = (row['total_out'] as num).toDouble();
      return {
        'id': row['id'],
        'name': row['name'],
        'unit': row['unit'],
        'stock': tIn - tOut,
        'min_stock_alert': row['min_stock_alert'],
      };
    }).toList();
  }

  Future<Map<String, dynamic>> getDashboardStats() async {
    // 1. Total Inventory Value (Current stock * purchase price)
    final totalValue = await calculateTotalStockValue();

    // 2 & 3. Low stock and Finished items (Calculated in one pass for performance)
    final summary = await getInventorySummary();
    int lowStock = 0;
    int finished = 0;

    for (var item in summary) {
      double stock = (item['stock'] as num).toDouble();
      int alert = (item['min_stock_alert'] as num?)?.toInt() ?? 10;
      
      if (stock <= 0) {
        finished++;
      } else if (stock <= alert) {
        lowStock++;
      }
    }

    return {
      'total_value': totalValue,
      'low_stock': lowStock,
      'finished': finished,
    };
  }

  Future<List<Map<String, dynamic>>> getLowStockProducts() async {
     final all = await getInventorySummary();
     // Client side filtering for simplicity reusing getInventorySummary logic
     return all.where((p) {
        final stock = (p['stock'] as num).toDouble();
        return stock > 0 && stock <= 5; // Hardcoded threshold 5 for now, or match DB logic
     }).toList();
  }

  Future<List<Map<String, dynamic>>> getFinishedProducts() async {
     final all = await getInventorySummary();
     return all.where((p) {
        return (p['stock'] as num).toDouble() <= 0;
     }).toList();
  }

  Future<List<Map<String, dynamic>>> getRecentActivity({int limit = 10}) async {
    final db = await instance.database;
    
    // Union of Stock In and Stock Out for a unified feed
    final res = await db.rawQuery('''
      SELECT * FROM (
        SELECT 
          'in' as type,
          si.date_time,
          p.name as product_name,
          si.quantity,
          si.supplier_name as party
        FROM stock_in si
        JOIN products p ON si.product_id = p.id
        
        UNION ALL
        
        SELECT 
          'out' as type,
          so.date_time,
          p.name as product_name,
          so.quantity,
          so.receiver_name as party
        FROM stock_out so
        JOIN products p ON so.product_id = p.id
      )
      ORDER BY date_time DESC
      LIMIT ?
    ''', [limit]);
    
    return res;
  }

  // --- Reports Query ---
  Future<List<Map<String, dynamic>>> getStockInReport({String? startDate, String? endDate}) async {
    final db = await instance.database;
    String where = '1=1';
    List<dynamic> args = [];
    
    if (startDate != null) {
      where += ' AND date_time >= ?';
      args.add(startDate);
    }
    if (endDate != null) {
      where += ' AND date_time <= ?';
      args.add('$endDate 23:59:59');
    }

    return await db.rawQuery('''
      SELECT si.*, p.name as product_name, p.unit
      FROM stock_in si
      JOIN products p ON si.product_id = p.id
      WHERE $where
      ORDER BY date_time DESC
    ''', args);
  }

  Future<List<Map<String, dynamic>>> getStockOutReport({String? startDate, String? endDate}) async {
    final db = await instance.database;
    String where = '1=1';
    List<dynamic> args = [];
    
    if (startDate != null) {
      where += ' AND date_time >= ?';
      args.add(startDate);
    }
    if (endDate != null) {
      where += ' AND date_time <= ?';
      args.add('$endDate 23:59:59');
    }

    return await db.rawQuery('''
      SELECT so.*, p.name as product_name, p.unit
      FROM stock_out so
      JOIN products p ON so.product_id = p.id
      WHERE $where
      ORDER BY date_time DESC
    ''', args);
  }

  // --- Notifications Logic ---
  Future<void> insertNotification(Map<String, dynamic> data) async {
    final db = await instance.database;
    await db.insert('notifications', {
       'title': data['title'],
       'message': data['message'],
       'type': data['type'],
       'created_at': DateTime.now().toLocal().toIso8601String(),
       'is_read': 0,
    });
  }

  Future<List<Map<String, dynamic>>> getNotifications({int limit = 50}) async {
    final db = await instance.database;
    return await db.query('notifications', orderBy: 'created_at DESC', limit: limit);
  }

  Future<int> getUnreadNotificationCount() async {
    final db = await instance.database;
    final res = await db.rawQuery('SELECT COUNT(*) FROM notifications WHERE is_read = 0');
    if (res.isEmpty) return 0;
    return (res.first.values.first as num?)?.toInt() ?? 0;
  }

  Future<void> markNotificationAsRead(int id) async {
    final db = await instance.database;
    await db.update('notifications', {'is_read': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markAllNotificationsAsRead() async {
    final db = await instance.database;
    await db.update('notifications', {'is_read': 1}, where: 'is_read = 0');
  }

  Future<void> clearAllNotifications() async {
    final db = await instance.database;
    await db.delete('notifications');
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) await db.close();
    _database = null;
  }

  Future<bool> restoreBackup(String backupPath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? dbPath = prefs.getString(_prefKeyDbPath);

      // Fallback if no custom path set
      if (dbPath == null || dbPath.isEmpty) {
        final internalDir = await getDatabasesPath();
        dbPath = join(internalDir, 'clinical_warehouse_v3_connected.db');
      }

      final sourceFile = File(backupPath);
      final destFile = File(dbPath);

      if (!await sourceFile.exists()) {
        debugPrint("❌ Restore Error: Source backup file missing at $backupPath");
        return false;
      }

      // Close current DB before overwrite
      await close();

      // Perform Copy
      await sourceFile.copy(destFile.path);
      debugPrint("✅ Restore Success: Copy $backupPath -> ${destFile.path}");

      // Re-initialize (this will open the newly copied file)
      _database = await _initDB(destFile.path);
      return true;
    } catch (e) {
      debugPrint("❌ Restore CRITICAL Failed: $e");
      // Fallback
      _database = await _initDB('clinical_warehouse_v3_connected.db');
      return false;
    }
  }

  Future<String?> createBackup(String? targetDirectory) async {
    try {
      // Use the configured path (same as the app uses at startup)
      final prefs = await SharedPreferences.getInstance();
      String? dbFilePath = prefs.getString('clinical_warehouse_db_path');
      
      if (dbFilePath == null || dbFilePath.isEmpty) {
        // Fallback: search known locations
        final candidates = [
          '/Users/macbookairm1/OBI/omborxona_data.db',
        ];
        for (final c in candidates) {
          if (await File(c).exists()) { dbFilePath = c; break; }
        }
      }

      if (dbFilePath == null) {
        debugPrint('❌ createBackup: DB file not found');
        return null;
      }

      final sourceFile = File(dbFilePath);
      if (!await sourceFile.exists()) {
        debugPrint('❌ createBackup: Source DB missing at $dbFilePath');
        return null;
      }

      final dirPath = targetDirectory ?? (await getTemporaryDirectory()).path;
      final ts = DateTime.now();
      final timestamp = "${ts.day}-${ts.month}-${ts.year}_${ts.hour}-${ts.minute}";
      final filename = "Omborxona_DB_$timestamp.db";
      final targetPath = join(dirPath, filename);
      
      await sourceFile.copy(targetPath);
      debugPrint('✅ createBackup: Saved to $targetPath');
      return targetPath;
    } catch (e) {
      debugPrint('❌ createBackup error: $e');
      return null;
    }
  }

  // --- DASHBOARD ENHANCEMENTS ---

  Future<List<Map<String, dynamic>>> getBranchAnalytics() async {
    final db = await instance.database;
    // Get aggregated stats by branch name
    return await db.rawQuery('''
      SELECT 
        branch_name, 
        COUNT(*) as total_orders,
        COUNT(CASE WHEN status = 'pending' THEN 1 END) as pending_count,
        COUNT(CASE WHEN status = 'approved' THEN 1 END) as approved_count,
        COUNT(CASE WHEN status = 'delivered' THEN 1 END) as delivered_count,
        MAX(created_at) as last_order_date
      FROM branch_orders
      GROUP BY branch_name
      ORDER BY total_orders DESC
    ''');
  }

  Future<Map<String, dynamic>> getDashboardStatusToday() async {
     final db = await instance.database;
     final now = DateTime.now();
     final todayStr = now.toString().substring(0, 10); // yyyy-MM-dd

     // Total IN Today
     final resIn = await db.rawQuery("SELECT COUNT(*) as cnt, SUM(total_amount) as sm FROM stock_in WHERE date_time LIKE '$todayStr%'");
     
     // Total OUT Today
     final resOut = await db.rawQuery("SELECT COUNT(*) as cnt FROM stock_out WHERE date_time LIKE '$todayStr%'");

     return {
       'in_count': resIn.first['cnt'] ?? 0,
       'in_sum': resIn.first['sm'] ?? 0.0,
       'out_count': resOut.first['cnt'] ?? 0,
     };
  }

  // --- AI PREDICTOR ENGINE (Smart Weighted Average) ---
  Future<List<Map<String, dynamic>>> getAiPredictions() async {
    final db = await instance.database;
    final stats = <Map<String, dynamic>>[];

    try {
      // 1. Calculate Date Ranges
      final now = DateTime.now();
      final date30d = now.subtract(const Duration(days: 30)).toIso8601String();
      final date7d = now.subtract(const Duration(days: 7)).toIso8601String();
      
      // 2. Get Usage Data for both periods
      final rawUsage = await db.rawQuery('''
        SELECT 
          p.id, p.name, p.unit, so.quantity, so.date_time
        FROM products p
        JOIN stock_out so ON p.id = so.product_id
        WHERE so.date_time >= ? AND so.is_deleted = 0
      ''', [date30d]);

      // Group by Product
      final productUsage = <String, Map<String, dynamic>>{};
      for (var row in rawUsage) {
        final pid = row['id'].toString();
        final qty = row['quantity'] as num;
        final date = row['date_time'] as String;
        
        if (!productUsage.containsKey(pid)) {
           productUsage[pid] = {
             'name': row['name'],
             'unit': row['unit'],
             'total30': 0.0,
             'total7': 0.0,
           };
        }
        productUsage[pid]!['total30'] += qty;
        if (date.compareTo(date7d) >= 0) {
           productUsage[pid]!['total7'] += qty;
        }
      }

      // 3. Get ALL active products to check current stock
      final inventory = await getInventorySummary();
      
      for (var item in inventory) {
        final pid = item['id'].toString();
        final currentStock = (item['stock'] as num?) ?? 0;
        final minStock = (item['min_stock_alert'] as num?) ?? 10;
        
        double predictedDailyRate = 0.0;
        if (productUsage.containsKey(pid)) {
          final usage = productUsage[pid]!;
          final rate30 = usage['total30'] / 30.0;
          final rate7 = usage['total7'] / 7.0;
          predictedDailyRate = (rate7 * 0.6) + (rate30 * 0.4);
        }

        bool shouldAdd = false;
        String reason = "";

        // Case A: High usage, running out soon
        if (predictedDailyRate > 0.05) {
          final daysLeft = currentStock / predictedDailyRate;
          if (daysLeft < 15) {
            shouldAdd = true;
            reason = "predicted_out";
          }
        }
        
        // Case B: Low stock vs Min Alert (Even if no history)
        if (currentStock <= minStock && !shouldAdd) {
          shouldAdd = true;
          reason = "low_stock_static";
        }

        if (shouldAdd) {
           final daysLeft = predictedDailyRate > 0 ? (currentStock / predictedDailyRate).floor() : 999;
           stats.add({
             'name': item['name'],
             'id': pid,
             'days_left': daysLeft,
             'daily_use': predictedDailyRate > 0 ? predictedDailyRate.toStringAsFixed(1) : '0',
             'current_stock': currentStock,
             'min_stock': minStock,
             'unit': item['unit'],
             'reason': reason,
             'trend': predictedDailyRate > 0 ? 'active' : 'static'
           });
        }
      }
      
      // Sort by urgency
      stats.sort((a, b) {
        if (a['reason'] == 'low_stock_static' && b['reason'] != 'low_stock_static') return -1;
        if (a['reason'] != 'low_stock_static' && b['reason'] == 'low_stock_static') return 1;
        return (a['days_left'] as int).compareTo(b['days_left'] as int);
      });

    } catch (e) {
      debugPrint("🤖 AI Prediction Error: $e");
    }

    return stats;
  }

  Future<void> clearAllAssets() async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete('assets');
      await txn.delete('asset_movements');
      // We don't delete asset_locations or asset_categories as they are master data
    });
  }

  Future<List<Map<String, dynamic>>> searchGlobal(String query) async {
    final db = await instance.database;
    final sanitized = '%$query%';
    final results = <Map<String, dynamic>>{}; // Use a Set or Map to avoid duplicates if needed, or just List

    // 1. Products & Stock
    try {
      final products = await db.rawQuery('''
        SELECT 
          'product' as type,
          p.id, 
          p.name, 
          p.unit,
          ((SELECT IFNULL(SUM(quantity), 0) FROM stock_in WHERE product_id = p.id AND is_deleted = 0) - 
           (SELECT IFNULL(SUM(quantity), 0) FROM stock_out WHERE product_id = p.id AND is_deleted = 0)) as stock
        FROM products p
        WHERE p.name LIKE ? AND p.is_deleted = 0
        LIMIT 5
      ''', [sanitized]);
      results.addAll(products);
    } catch (e) {
      debugPrint("❌ Product Search Error: $e");
    }

    // 2. Recent Transactions (History)
    final transactions = await db.rawQuery('''
       SELECT * FROM (
        SELECT 
          'history_in' as type,
          si.date_time,
          p.name as title,
          si.supplier_name as subtitle,
          si.quantity
        FROM stock_in si
        JOIN products p ON si.product_id = p.id
        WHERE (p.name LIKE ? OR si.supplier_name LIKE ?) AND si.is_deleted = 0 AND p.is_deleted = 0
        
        UNION ALL
        
        SELECT 
          'history_out' as type,
          so.date_time,
          p.name as title,
          so.receiver_name as subtitle,
          so.quantity
        FROM stock_out so
        JOIN products p ON so.product_id = p.id
        WHERE (p.name LIKE ? OR so.receiver_name LIKE ?) AND so.is_deleted = 0 AND p.is_deleted = 0
      )
      ORDER BY date_time DESC
      LIMIT 5
    ''', [sanitized, sanitized, sanitized, sanitized]);
    results.addAll(transactions);
    
    // 3. Suppliers / Receivers (People)
    final suppliers = await db.query('suppliers', where: 'name LIKE ?', whereArgs: [sanitized], limit: 3);
    for (var s in suppliers) {
      results.add({'type': 'person', 'title': s['name'], 'subtitle': 'Yetkazib beruvchi'});
    }
    
    final receivers = await db.query('receivers', where: 'name LIKE ?', whereArgs: [sanitized], limit: 3);
    for (var r in receivers) {
      results.add({'type': 'person', 'title': r['name'], 'subtitle': 'Qabul qiluvchi'});
    }

    debugPrint("🔍 Global Search Query: $query");
    
    // 4. ASSETS (JIHOZLAR)
    debugPrint("🔍 Global Search Query: $query");
    
    // 4. ASSETS (JIHOZLAR)
    try {
      final assets = await db.rawQuery('''
        SELECT 
          'asset' as type,
          a.id,
          a.name as title,
          (COALESCE(c.name, 'Guruhsiz') || ' • ' || COALESCE(l.name, 'Joylashuvsiz')) as subtitle,
          a.photo_path
        FROM assets a
        LEFT JOIN asset_categories c ON a.category_id = c.id
        LEFT JOIN asset_locations l ON a.location_id = l.id
        WHERE LOWER(a.name) LIKE ? OR LOWER(a.model) LIKE ? OR a.serial_number LIKE ?
        LIMIT 5
      ''', [sanitized.toLowerCase(), sanitized.toLowerCase(), sanitized]);
      
      debugPrint("✅ Assets Found: ${assets.length}");
      results.addAll(assets);
    } catch (e) {
      debugPrint("❌ Assets Search Error: $e");
    }

    return results.toList();
  }

  // --- Hierarchical Assets Management ---

  // Locations
  Future<List<Map<String, dynamic>>> getLocations({int? parentId}) async {
    final db = await instance.database;
    if (parentId == null) {
      return await db.query('asset_locations', where: 'parent_id IS NULL AND (is_deleted = 0 OR is_deleted IS NULL)');
    }
    return await db.query('asset_locations', where: 'parent_id = ? AND (is_deleted = 0 OR is_deleted IS NULL)', whereArgs: [parentId]);
  }

  Future<int> insertLocation(Map<String, dynamic> data) async {
    final db = await instance.database;
    return await db.insert('asset_locations', data);
  }

  Future<void> deleteLocation(int id) async {
    final db = await instance.database;
    await db.update('asset_locations', {
      'is_deleted': 1, 
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
      'sync_status': 'pending_update'
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, dynamic>?> getLocationById(int id) async {
    final db = await instance.database;
    final res = await db.query('asset_locations', where: 'id = ?', whereArgs: [id]);
    return res.isNotEmpty ? res.first : null;
  }

  // Categories
  Future<List<Map<String, dynamic>>> getAssetCategories() async {
    final db = await instance.database;
    return await db.query('asset_categories', orderBy: 'name');
  }

  Future<int> insertAssetCategory(String name) async {
    final db = await instance.database;
    return await db.insert('asset_categories', {'name': name}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<int> getOrCreateAssetCategory(String name) async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'asset_categories',
      where: 'name = ?',
      whereArgs: [name],
    );
    if (maps.isNotEmpty) {
      return maps.first['id'] as int;
    } else {
      return await db.insert('asset_categories', {'name': name});
    }
  }

  Future<void> deleteAssetCategory(int id) async {
    final db = await instance.database;
    await db.delete('asset_categories', where: 'id = ?', whereArgs: [id]);
  }

  // Assets (Updated)
  Future<List<Map<String, dynamic>>> getAllAssetsDetailed() async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT 
        a.*, 
        c.name as category_name, 
        l.name as location_name,
        l.parent_id as parent_id,
        p.name as parent_location_name,
        p.parent_id as grandparent_id,
        g.name as grandparent_location_name
      FROM assets a
      LEFT JOIN asset_categories c ON a.category_id = c.id
      LEFT JOIN asset_locations l ON a.location_id = l.id
      LEFT JOIN asset_locations p ON l.parent_id = p.id
      LEFT JOIN asset_locations g ON p.parent_id = g.id
      WHERE (a.is_deleted = 0 OR a.is_deleted IS NULL)
      ORDER BY a.id DESC
    ''');
  }

  Future<void> insertAsset(Map<String, dynamic> data) async {
    final db = await instance.database;
    await db.insert('assets', _prepareInsert(data), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteAsset(int id) async {
    final db = await instance.database;
    await db.update('assets', {
      'is_deleted': 1, 
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
      'sync_status': 'pending_update'
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateAsset(int id, Map<String, dynamic> data) async {
    final db = await instance.database;
    await db.update('assets', _prepareUpdate(data), where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, dynamic>?> getAssetByBarcode(String barcode) async {
    final db = await instance.database;
    final res = await db.rawQuery('''
      SELECT a.*, l.name as location_name, c.name as category_name
      FROM assets a
      LEFT JOIN asset_locations l ON a.location_id = l.id
      LEFT JOIN asset_categories c ON a.category_id = c.id
      WHERE a.barcode = ? AND a.is_deleted = 0
      LIMIT 1
    ''', [barcode]);
    return res.isNotEmpty ? res.first : null;
  }

  // --- Smart SKU Generation (Updated for 3 levels) ---
  Future<String> generateSmartSKU({required int buildingId, int? floorId, required int roomId}) async {
    final db = await instance.database;
    
    // 1. Get Building Info
    final buildRes = await db.query('asset_locations', where: 'id = ?', whereArgs: [buildingId]);
    String bCode = "GEN";
    if (buildRes.isNotEmpty) {
      final customCode = buildRes.first['short_code'];
      final name = buildRes.first['name'].toString().toUpperCase();
      bCode = (customCode != null && customCode.toString().isNotEmpty) 
              ? customCode.toString() 
              : name.substring(0, name.length >= 3 ? 3 : name.length);
    }

    // 2. Get Floor Info (Extract number)
    String fNum = "01";
    if (floorId != null) {
      final floorRes = await db.query('asset_locations', where: 'id = ?', whereArgs: [floorId]);
      if (floorRes.isNotEmpty) {
        final floorName = floorRes.first['name'].toString();
        // Try to extract digits: "2-qavat" -> "02"
        final reg = RegExp(r'(\d+)');
        final match = reg.firstMatch(floorName);
        if (match != null) {
          fNum = match.group(1)!.padLeft(2, '0');
        } else {
           final customCode = floorRes.first['short_code'];
           if (customCode != null && customCode.toString().isNotEmpty) fNum = customCode.toString().padLeft(2, '0');
        }
      }
    }

    // 3. Get Room Info
    final roomRes = await db.query('asset_locations', where: 'id = ?', whereArgs: [roomId]);
    String rCode = "RM";
    if (roomRes.isNotEmpty) {
      final customCode = roomRes.first['short_code'];
      rCode = (customCode != null && customCode.toString().isNotEmpty) 
              ? customCode.toString().toUpperCase() 
              : "RM";
    }

    // 4. Get Next ID
    final countRes = await db.rawQuery('SELECT COUNT(*) as total FROM assets');
    int nextId = (countRes.first['total'] as int) + 1;
    String idPadding = nextId.toString().padLeft(4, '0');

    // Format: [BUILD]-[FLOOR]-[ROOM]-[ID]
    return "$bCode-$fNum-$rCode-$idPadding";
  }

  Future<void> transferAsset(int assetId, int toLocationId, {String? notes}) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      // 1. Get current location
      final asset = await txn.query('assets', columns: ['location_id'], where: 'id = ?', whereArgs: [assetId]);
      final fromLocationId = asset.isNotEmpty ? asset.first['location_id'] as int? : null;

      // 2. Add History Record
      await txn.insert('asset_movements', {
        'asset_id': assetId,
        'from_location_id': fromLocationId,
        'to_location_id': toLocationId,
        'moved_at': DateTime.now().toIso8601String(),
        'notes': notes,
      });

      // 3. Update Asset Location
      await txn.update('assets', {'location_id': toLocationId}, where: 'id = ?', whereArgs: [assetId]);
    });
  }

  Future<List<Map<String, dynamic>>> getAssetHistory(int assetId) async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT 
        m.*, 
        fl.name as from_location_name, 
        tl.name as to_location_name,
        fpl.name as from_parent_name,
        tpl.name as to_parent_name
      FROM asset_movements m
      LEFT JOIN asset_locations fl ON m.from_location_id = fl.id
      LEFT JOIN asset_locations tl ON m.to_location_id = tl.id
      LEFT JOIN asset_locations fpl ON fl.parent_id = fpl.id
      LEFT JOIN asset_locations tpl ON tl.parent_id = tpl.id
      WHERE m.asset_id = ?
      ORDER BY m.moved_at DESC
    ''', [assetId]);
  }

  Future<int> getPendingBranchOrdersCount() async {
    final db = await instance.database;
    final res = await db.rawQuery("SELECT COUNT(*) as count FROM branch_orders WHERE status = 'pending'");
    return (res.first['count'] as int?) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getTelegramOrders() async {
    final db = await instance.database;
    return await db.query('branch_orders', orderBy: 'id DESC');
  }

  Future<List<Map<String, dynamic>>> getBranchOrderItems(int orderId) async {
    final db = await instance.database;
    return await db.query('branch_order_items', where: 'order_id = ?', whereArgs: [orderId]);
  }

  Future<void> clearAllData() async {
    final db = await instance.database;
    await db.delete('stock_in');
    await db.delete('stock_out');
    await db.delete('assets');
    await db.delete('branch_orders');
    await db.delete('branch_order_items');
  }

  Future<void> factoryReset() async {
    final db = await instance.database;
    await db.transaction((txn) async {
       await txn.delete('stock_in');
       await txn.delete('stock_out');
       await txn.delete('branch_orders');
       await txn.delete('branch_order_items');
       await txn.delete('assets');
       await txn.delete('asset_movements');
       await txn.delete('asset_locations');
       await txn.delete('asset_categories');
       await txn.delete('products');
       await txn.delete('suppliers');
       await txn.delete('receivers');
    });
  }

  // Transaction Management (Edit/Delete)
  Future<void> deleteStockIn(dynamic id) async {
    final db = await instance.database;
    await db.update('stock_in', {
      'is_deleted': 1, 
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
      'sync_status': 'pending_update'
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteStockOut(dynamic id) async {
    final db = await instance.database;
    await db.update('stock_out', {
      'is_deleted': 1, 
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
      'sync_status': 'pending_update'
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateStockIn(String id, Map<String, dynamic> data) async {
    final db = await instance.database;
    await db.update('stock_in', _prepareUpdate(data), where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateStockOut(String id, Map<String, dynamic> data) async {
    final db = await instance.database;
    await db.update('stock_out', _prepareUpdate(data), where: 'id = ?', whereArgs: [id]);
  }

  Future<double> calculateTotalStockValue() async {
    final db = await instance.database;
    final res = await db.rawQuery('''
      SELECT SUM(
        (
          (SELECT IFNULL(SUM(quantity), 0) FROM stock_in WHERE product_id = p.id AND is_deleted = 0) - 
          (SELECT IFNULL(SUM(quantity), 0) FROM stock_out WHERE product_id = p.id AND is_deleted = 0)
        ) * IFNULL((SELECT price_per_unit FROM stock_in WHERE product_id = p.id AND is_deleted = 0 ORDER BY date_time DESC LIMIT 1), 0)
      ) as total_value
    FROM products p
    WHERE p.is_deleted = 0
    ''');
    return (double.tryParse(res.first['total_value']?.toString() ?? '0')) ?? 0.0;
  }

  // --- Backup & Export Helpers ---
  
  Future<List<Map<String, dynamic>>> getAllStockInFull() async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT 
        si.date_time,
        si.id,
        COALESCE(p.name, si.product_id) AS product_name,
        si.batch_number,
        si.expiry_date,
        si.quantity,
        si.price_per_unit,
        si.total_amount,
        si.supplier_name,
        si.payment_status
      FROM stock_in si
      LEFT JOIN products p ON p.id = si.product_id
      WHERE si.is_deleted = 0
      ORDER BY si.date_time DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> getAllStockOutFull() async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT 
        so.date_time,
        so.id,
        COALESCE(p.name, so.product_id) AS product_name,
        so.quantity,
        so.receiver_name,
        so.batch_reference,
        so.notes
      FROM stock_out so
      LEFT JOIN products p ON p.id = so.product_id
      WHERE so.is_deleted = 0
      ORDER BY so.date_time DESC
    ''');
  }

  Future<String?> getLastUpdateTimestamp() async {
    final db = await instance.database;
    final res = await db.rawQuery('''
      SELECT MAX(updated_at) as last_upd 
      FROM (
        SELECT updated_at FROM stock_in UNION ALL 
        SELECT updated_at FROM stock_out UNION ALL 
        SELECT updated_at FROM products
      )
    ''');
    return res.first['last_upd']?.toString();
  }
}
