import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'database_security_service.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  final DatabaseSecurityService _securityService = DatabaseSecurityService();

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('clinical_vault.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, filePath);

    // 🔐 "The Vault" Logic: Retrieve the key from Secure Enclave
    final String encryptionKey = await _securityService.getDatabaseEncryptionKey();

    print("🛡️ Database: Opening generic Secure Database...");

    // Open the database with AES-256 Encryption
    return await openDatabase(
      path,
      version: 1,
      password: encryptionKey, // <--- MILITARY-GRADE ENCRYPTION HERE
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    print("📝 Database: Creating fresh tables...");

    // 1. UNITS
    await db.execute('''
      CREATE TABLE units (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        symbol TEXT NOT NULL
      )
    ''');

    // 2. CATEGORIES
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL, -- 'reagent', 'consumable', 'general'
        description TEXT
      )
    ''');

    // 3. ITEMS
    await db.execute('''
      CREATE TABLE items (
        id TEXT PRIMARY KEY,
        category_id TEXT,
        name TEXT NOT NULL,
        barcode TEXT,
        current_stock REAL DEFAULT 0,
        min_stock_alert REAL DEFAULT 10,
        
        -- Unit Conversion Logic (Type B)
        base_unit_id TEXT,
        purchase_unit_id TEXT,
        conversion_rate REAL DEFAULT 1,
        
        -- Type A: Reagents
        storage_temp TEXT,
        
        -- Type B: Consumables
        dimensions TEXT,
        
        FOREIGN KEY (category_id) REFERENCES categories (id),
        FOREIGN KEY (base_unit_id) REFERENCES units (id),
        FOREIGN KEY (purchase_unit_id) REFERENCES units (id)
      )
    ''');

    // 4. BATCHES (Critical for Expiry - Type A)
    await db.execute('''
      CREATE TABLE batches (
        id TEXT PRIMARY KEY,
        item_id TEXT NOT NULL,
        batch_number TEXT NOT NULL,
        expiry_date TEXT, -- ISO8601 String
        quantity REAL DEFAULT 0,
        
        FOREIGN KEY (item_id) REFERENCES items (id) ON DELETE CASCADE
      )
    ''');

    // 5. TRANSACTIONS
    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        item_id TEXT NOT NULL,
        type TEXT NOT NULL, -- 'IN', 'OUT'
        quantity REAL NOT NULL,
        date TEXT NOT NULL, -- ISO8601 String
        user TEXT,
        
        FOREIGN KEY (item_id) REFERENCES items (id)
      )
    ''');
    
    // Seed some initial data for visual confirmation
    await _seedData(db);
  }

  Future<void> _seedData(Database db) async {
    // Basic Units
    await db.rawInsert('INSERT INTO units(id, name, symbol) VALUES("u1", "Piece", "pcs")');
    await db.rawInsert('INSERT INTO units(id, name, symbol) VALUES("u2", "Box", "bx")');
    await db.rawInsert('INSERT INTO units(id, name, symbol) VALUES("u3", "Milliliter", "ml")');
    
    // Categories
    await db.rawInsert('INSERT INTO categories(id, name, type) VALUES("c1", "Reagents", "reagent")');
    await db.rawInsert('INSERT INTO categories(id, name, type) VALUES("c2", "Consumables", "consumable")');

    print("🌱 Database: Seed data inserted.");
  }
}
