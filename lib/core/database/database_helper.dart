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
    return await openDatabase(
      path,
      version: 2,
      // password: encryptionKey, // Disabled
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> createAssetsTableIfNeeded() async {
    final db = await instance.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS assets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        model TEXT,
        color TEXT,
        location TEXT,
        barcode TEXT UNIQUE,
        created_at TEXT
      )
    ''');
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
        FOREIGN KEY (product_id) REFERENCES products (id)
      )
    ''');

    await db.execute('''
      CREATED TABLE stock_out (
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
    
    // 5. FIXED ASSETS (New Module)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS assets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        model TEXT,
        color TEXT,
        location TEXT,
        barcode TEXT UNIQUE,
        created_at TEXT
      )
    ''');

    // 4. SEED DATA INSERTION
    debugPrint("🌱 Seeding Data...");
    
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
    
    // Complex query to aggregate Stock In and Stock Out
    // We group by product_id
    final res = await db.rawQuery('''
      SELECT 
        p.id, 
        p.name, 
        p.unit,
        (SELECT IFNULL(SUM(quantity), 0) FROM stock_in WHERE product_id = p.id) as total_in,
        (SELECT IFNULL(SUM(quantity), 0) FROM stock_out WHERE product_id = p.id) as total_out
      FROM products p
    ''');
    
    // Calculate compiled list
    return res.map((row) {
      final totalIn = (row['total_in'] as num).toDouble();
      final totalOut = (row['total_out'] as num).toDouble();
      return {
        'id': row['id'],
        'name': row['name'],
        'unit': row['unit'],
        'stock': totalIn - totalOut,
      };
    }).toList();
  }

  // --- Dashboard Analytics ---
  Future<Map<String, dynamic>> getDashboardStats() async {
    final db = await instance.database;
    
    // 1. Total Inventory Value (Now matched to Total Stock In Sum)
    final valueRes = await db.rawQuery('SELECT SUM(total_amount) as total_value FROM stock_in');
    final totalValue = (valueRes.first['total_value'] as num?)?.toDouble() ?? 0.0;

    // 2. Low Stock Items Count ( > 0 but <= min_alert)
    final lowStockRes = await db.rawQuery('''
      SELECT COUNT(*) as count
      FROM (
        SELECT 
          p.id,
          p.min_stock_alert,
          ((SELECT IFNULL(SUM(quantity), 0) FROM stock_in WHERE product_id = p.id) - 
           (SELECT IFNULL(SUM(quantity), 0) FROM stock_out WHERE product_id = p.id)) as current_stock
        FROM products p
      )
      WHERE current_stock <= min_stock_alert AND current_stock > 0
    ''');
    final lowStockCount = (lowStockRes.first['count'] as num?)?.toInt() ?? 0;

    // 3. Finished Items Count ( <= 0 )
    final finishedRes = await db.rawQuery('''
      SELECT COUNT(*) as count
      FROM (
        SELECT 
          p.id,
          ((SELECT IFNULL(SUM(quantity), 0) FROM stock_in WHERE product_id = p.id) - 
           (SELECT IFNULL(SUM(quantity), 0) FROM stock_out WHERE product_id = p.id)) as current_stock
        FROM products p
      )
      WHERE current_stock <= 0
    ''');
    final finishedCount = (finishedRes.first['count'] as num?)?.toInt() ?? 0;

    return {
      'total_value': totalValue,
      'low_stock': lowStockCount,
      'finished': finishedCount,
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
      debugPrint("Backup Failed: $e");
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> searchGlobal(String query) async {
    final db = await instance.database;
    final sanitized = '%$query%';
    final results = <Map<String, dynamic>>[];

    // 1. Products & Stock
    // We join with stock calc to show "Aspirin - 50 ta"
    final products = await db.rawQuery('''
      SELECT 
        'product' as type,
        p.id, 
        p.name, 
        p.unit,
        ((SELECT IFNULL(SUM(quantity), 0) FROM stock_in WHERE product_id = p.id) - 
         (SELECT IFNULL(SUM(quantity), 0) FROM stock_out WHERE product_id = p.id)) as stock
      FROM products p
      WHERE p.name LIKE ?
      LIMIT 5
    ''', [sanitized]);
    results.addAll(products);

    // 2. Recent Transactions (History) - Search by Product Name or Party
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
    
    // 4. Fixed Assets (Items)
    // Checks Name, Location, or Barcode
    final assets = await db.query(
      'assets', 
      where: 'name LIKE ? OR barcode LIKE ? OR location LIKE ?', 
      whereArgs: [sanitized, sanitized, sanitized], 
      limit: 5
    );
    for (var a in assets) {
      results.add({
        'type': 'asset', 
        'title': a['name'], 
        'subtitle': "Joyi: ${a['location']} • Model: ${a['model']}",
        'barcode': a['barcode']
      });
    }

    return results;
  }

  // --- Assets CRUD ---
  Future<void> insertAsset(Map<String, dynamic> asset) async {
    final db = await instance.database;
    await db.insert('assets', asset);
  }

  Future<List<Map<String, dynamic>>> getAllAssets() async {
    final db = await instance.database;
    return await db.query('assets', orderBy: 'id DESC');
  }

  Future<void> deleteAsset(int id) async {
    final db = await instance.database;
    await db.delete('assets', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAllData() async {
    final db = await instance.database;
    await db.delete('stock_in');
    await db.delete('stock_out');
    // We do NOT delete products, units, or suppliers/receivers to keep master data.
    // Only transaction history is cleared.
  }
}
