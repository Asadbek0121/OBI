# Ultra-Secure Clinical Warehouse - Deliverables

## 1. Dependencies and Versions
To achieve the "zero-knowledge" local encryption for Windows and macOS, we utilize the following architecture.

Add these to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # 🔐 Security Core
  flutter_secure_storage: ^9.0.0
  sqflite_sqlcipher: ^3.0.0
  uuid: ^4.2.0
  
  # 🖥️ Desktop Support
  path_provider: ^2.1.2
  window_manager: ^0.3.9
  glass_kit: ^0.2.0
  
  # 🛠️ Utilities
  intl: ^0.19.0
  equatable: ^2.0.5
  get_it: ^7.6.0
  flutter_bloc: ^8.1.3
```

## 2. "The Vault" Security Architecture
We have implemented the `DatabaseSecurityService` class which adheres to your strict "Zero-Knowledge" requirement.

*   **File**: `lib/core/services/database_security_service.dart`
*   **Mechanism**: 
    1.  Checks OS Secure Enclave (Keychain on macOS, Credential Manager on Windows) for a key.
    2.  If missing, generates a **64-character cryptographically secure key**.
    3.  Stores it immediately in the Enclave.
    4.  Returns the key to the app *in memory userspace only* (never written to disk).

## 3. Database Factory Code (SQLCipher)
We have implemented the `DatabaseHelper` class to orchestrate the encrypted connection.

*   **File**: `lib/core/services/database_helper.dart`
*   **Mechanism**:
    1.  Interacts with `DatabaseSecurityService` to retrieve the key.
    2.  Calls `openDatabase` (from `sqflite_sqlcipher`) passing the `password` parameter.
    3.  This ensures the `.db` file is AES-256 encrypted at rest.

## 4. Polymorphic Inventory Schema
The SQL schema has been designed to support your 3 item types (Reagents, Consumables, Stationery).

```sql
-- Core Items Table
CREATE TABLE items (
  id TEXT PRIMARY KEY,
  category_id TEXT,
  name TEXT NOT NULL,
  
  -- Type A (Reagents): Storage Temp
  storage_temp TEXT,
  
  -- Type B (Consumables): Unit Conversion
  base_unit_id TEXT,      -- e.g., "Piece"
  purchase_unit_id TEXT,  -- e.g., "Box"
  conversion_rate REAL,   -- e.g., 50.0 (50 pieces per box)
  
  FOREIGN KEY (category_id) REFERENCES categories (id)
);

-- Batches Table (For Type A: Expiry Logic)
CREATE TABLE batches (
  id TEXT PRIMARY KEY,
  item_id TEXT NOT NULL,
  expiry_date TEXT,       -- Critical for Type A
  quantity REAL DEFAULT 0
);
```

## 5. Next Steps
1.  **Run the App**: The `main.dart` has been updated to initialize the Secure Database on launch.
2.  **Verify Logs**: Look for "🔐 Security: New Vault Key generated..." in your debug console.
3.  **UI Connection**: The current Dashboard is using `MockData`. The next step is to replace `MockData` usage with `DatabaseHelper` queries.
