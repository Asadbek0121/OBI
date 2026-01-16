import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
// import 'package:sqflite_sqlcipher/sqflite_sqlcipher.dart'; // Temporarily disabled for build fix
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  final _secureStorage = const FlutterSecureStorage();
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
    
    // 3. Ensure Indexes for better performance
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_in_product_id ON stock_in(product_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_out_product_id ON stock_out(product_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_in_date ON stock_in(date_time)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_out_date ON stock_out(date_time)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_name ON products(name)');
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
        payment_status TEXT, -- 'Naqd', 'Qarzga', 'O\'tkazma'
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
  
  // --- Product Logic ---
  Future<Map<String, dynamic>?> getProductById(String id) async {
    final db = await instance.database;
    final results = await db.query('products', where: 'id = ?', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<void> insertProduct(Map<String, dynamic> product) async {
    final db = await instance.database;
    await db.insert('products', product, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  
   Future<List<Map<String, dynamic>>> getAllProducts() async {
    final db = await instance.database;
    return await db.query('products');
  }

  Future<void> deleteProduct(String id) async {
    final db = await instance.database;
    // Optional: Delete related transactions first if no CASCADE
    await db.delete('stock_in', where: 'product_id = ?', whereArgs: [id]);
    await db.delete('stock_out', where: 'product_id = ?', whereArgs: [id]);
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  // --- Transactions ---
  Future<void> insertStockIn(Map<String, dynamic> data) async {
    final db = await instance.database;
    await db.insert('stock_in', data);
  }

  Future<void> insertStockOut(Map<String, dynamic> data) async {
    final db = await instance.database;
    await db.insert('stock_out', data);
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
        FROM stock_in GROUP BY product_id
      ) si ON p.id = si.product_id
      LEFT JOIN (
        SELECT product_id, SUM(quantity) as total_out 
        FROM stock_out GROUP BY product_id
      ) so ON p.id = so.product_id
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
    final db = await instance.database;
    
    // 1. Total Inventory Value (Optimized index query)
    final valueRes = await db.rawQuery('SELECT IFNULL(SUM(total_amount), 0) as total_value FROM stock_in');
    final totalValue = (valueRes.first['total_value'] as num).toDouble();

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
      args.add(endDate + ' 23:59:59');
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
      args.add(endDate + ' 23:59:59');
    }

    return await db.rawQuery('''
      SELECT so.*, p.name as product_name, p.unit
      FROM stock_out so
      JOIN products p ON so.product_id = p.id
      WHERE $where
      ORDER BY date_time DESC
    ''', args);
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) await db.close();
    _database = null;
  }

  Future<bool> restoreBackup(String backupPath) async {
    try {
      await close();
      
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'clinical_warehouse_v3_connected.db');
      
      final backupFile = File(backupPath);
      final currentDbFile = File(path);

      if (await backupFile.exists()) {
        await backupFile.copy(path);
        // Force re-init
        _database = await _initDB('clinical_warehouse_v3_connected.db');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Restore Failed: $e");
      // Attempt to re-open anyway
      _database = await _initDB('clinical_warehouse_v3_connected.db');
      return false;
    }
  }

  Future<String?> createBackup(String? targetDirectory) async {
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'clinical_warehouse_v3_connected.db');
      final sourceFile = File(path);

      if (!await sourceFile.exists()) return null;

      String dirPath;
      if (targetDirectory == null) {
         final temp = await getTemporaryDirectory();
         dirPath = temp.path;
      } else {
         dirPath = targetDirectory;
      }

      final timestamp = DateTime.now().toString().replaceAll(':', '-').replaceAll(' ', '_').substring(0, 19);
      final filename = "backup_clinical_warehouse_$timestamp.db";
      final targetPath = join(dirPath, filename);
      
      await sourceFile.copy(targetPath);
      return targetPath;
    } catch (e) {
      return null;
    }
  }

  // --- DASHBOARD ENHANCEMENTS ---

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

  Future<List<Map<String, dynamic>>> searchGlobal(String query) async {
    final db = await instance.database;
    final sanitized = '%$query%';
    final results = <Map<String, dynamic>>[];

    // 1. Products & Stock
    final products = await db.rawQuery('''
      SELECT 
        'product' as type,
        p.id, 
        p.name, 
        p.unitRaw,
        ((SELECT IFNULL(SUM(quantity), 0) FROM stock_in WHERE product_id = p.id) - 
         (SELECT IFNULL(SUM(quantity), 0) FROM stock_out WHERE product_id = p.id)) as stock
      FROM products p
      WHERE p.name LIKE ?
      LIMIT 5
    ''', [sanitized]);
    results.addAll(products);

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
        WHERE p.name LIKE ? OR si.supplier_name LIKE ?
        
        UNION ALL
        
        SELECT 
          'history_out' as type,
          so.date_time,
          p.name as title,
          so.receiver_name as subtitle,
          so.quantity
        FROM stock_out so
        JOIN products p ON so.product_id = p.id
        WHERE p.name LIKE ? OR so.receiver_name LIKE ?
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

    // 4. ASSETS (JIHOZLAR) - NEW
    final assets = await db.rawQuery('''
      SELECT 
        'asset' as type,
        a.id,
        a.name as title,
        (c.name || ' • ' || l.name) as subtitle,
        a.photo_path
      FROM assets a
      LEFT JOIN asset_categories c ON a.category_id = c.id
      LEFT JOIN asset_locations l ON a.location_id = l.id
      WHERE a.name LIKE ? OR a.model LIKE ? OR a.serial_number LIKE ?
      LIMIT 5
    ''', [sanitized, sanitized, sanitized]);
    
    for (var a in assets) {
      results.add({
        'type': 'asset', 
        'title': a['name'], 
        'subtitle': "Joyi: ${a['location_name'] ?? 'Noma\'lum'} • Barcode: ${a['barcode']}",
        'barcode': a['barcode']
      });
    }

    return results;
  }

  // --- Hierarchical Assets Management ---

  // Locations
  Future<List<Map<String, dynamic>>> getLocations({int? parentId}) async {
    final db = await instance.database;
    if (parentId == null) {
      return await db.query('asset_locations', where: 'parent_id IS NULL');
    }
    return await db.query('asset_locations', where: 'parent_id = ?', whereArgs: [parentId]);
  }

  Future<int> insertLocation(Map<String, dynamic> data) async {
    final db = await instance.database;
    return await db.insert('asset_locations', data);
  }

  Future<void> deleteLocation(int id) async {
    final db = await instance.database;
    await db.delete('asset_locations', where: 'id = ?', whereArgs: [id]);
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
      ORDER BY a.id DESC
    ''');
  }

  Future<void> insertAsset(Map<String, dynamic> data) async {
    final db = await instance.database;
    await db.insert('assets', data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteAsset(int id) async {
    final db = await instance.database;
    await db.delete('assets', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateAsset(int id, Map<String, dynamic> data) async {
    final db = await instance.database;
    await db.update('assets', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, dynamic>?> getAssetByBarcode(String barcode) async {
    final db = await instance.database;
    final res = await db.rawQuery('''
      SELECT a.*, l.name as location_name, c.name as category_name
      FROM assets a
      LEFT JOIN asset_locations l ON a.location_id = l.id
      LEFT JOIN asset_categories c ON a.category_id = c.id
      WHERE a.barcode = ?
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

  Future<void> clearAllData() async {
    final db = await instance.database;
    await db.delete('stock_in');
    await db.delete('stock_out');
  }
}
