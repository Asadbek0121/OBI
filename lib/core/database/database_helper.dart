import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
// import 'package:sqflite_sqlcipher/sqflite_sqlcipher.dart'; // Temporarily disabled for build fix
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  final _secureStorage = const FlutterSecureStorage();
  final String _keyStorageName = 'clinical_warehouse_db_key_v1';

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('clinical_warehouse_v3_connected.db'); // Forced fresh start
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    // 1. Initialize FFI for Desktop
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

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
      CREATE TABLE stock_out (
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
    
    // 1. Total Inventory Value (Current Stock * Last Price)
    final valueRes = await db.rawQuery('''
      SELECT 
        SUM((total_in - total_out) * last_price) as total_value
      FROM (
        SELECT 
           p.id,
           (SELECT IFNULL(SUM(quantity), 0) FROM stock_in WHERE product_id = p.id) as total_in,
           (SELECT IFNULL(SUM(quantity), 0) FROM stock_out WHERE product_id = p.id) as total_out,
           (SELECT price_per_unit FROM stock_in WHERE product_id = p.id ORDER BY date_time DESC LIMIT 1) as last_price
        FROM products p
      )
    ''');
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

  Future<void> clearAllData() async {
    final db = await instance.database;
    await db.delete('stock_in');
    await db.delete('stock_out');
    // We do NOT delete products, units, or suppliers/receivers to keep master data.
    // Only transaction history is cleared.
  }
}
