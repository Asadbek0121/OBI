import 'dart:io';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:flutter/foundation.dart';
import 'package:clinical_warehouse/core/database/database_helper.dart';

class ExcelService {
  static Future<Map<String, int>> importData(String path) async {
    int importedIn = 0;
    int importedOut = 0;

    try {
      var bytes = File(path).readAsBytesSync();
      var decoder = SpreadsheetDecoder.decodeBytes(bytes, update: false);

      debugPrint("📂 Excel Loaded. Tables: ${decoder.tables.keys.toList()}");

      for (var tableKey in decoder.tables.keys) {
        final sheetName = tableKey.toLowerCase();
        final table = decoder.tables[tableKey];
        if (table == null || table.rows.isEmpty) {
          debugPrint("⚠️ Sheet '$tableKey' is empty.");
          continue;
        }

        // 🔍 Find the Header Row dynamically
        final headerInfo = _findHeaderRow(table.rows);
        final headerRowIndex = headerInfo['index'] as int;
        final headerRow = headerInfo['headers'] as List<String>;

        if (headerRowIndex == -1) {
             debugPrint("⚠️ No recognizable header found in sheet '$tableKey'. Skipping.");
             continue;
        }

        debugPrint("📄 Sheet '$tableKey' Header found at Row $headerRowIndex: $headerRow");
        
        final dataRows = table.rows.sublist(headerRowIndex + 1);

        bool isStockIn = false;
        bool isStockOut = false;

        // 1. Check Sheet Name Keywords (High Priority)
        if (_hasKeyword(sheetName, ['kirim', 'income', 'in', 'prixod', 'giris', 'input', 'buy'])) isStockIn = true;
        if (_hasKeyword(sheetName, ['chiqim', 'out', 'export', 'rasxod', 'cikis', 'output', 'sell', 'sale'])) isStockOut = true;

        // 2. If name is ambiguous, Check Headers
        if (!isStockIn && !isStockOut) {
           // If it has "Supplier/From" OR "Price" -> Likely Stock In
           if (_findCol(headerRow, _kwSupplier) != -1 || _findCol(headerRow, _kwPrice) != -1) {
               isStockIn = true;
           } 
           // If it has "Receiver/To" -> Likely Stock Out
           else if (_findCol(headerRow, _kwReceiver) != -1) {
               isStockOut = true;
           }
        }
        
        // 3. Last Resort: Default to Stock In if it looks like a product list (Product + Qty exist)
        if (!isStockIn && !isStockOut) {
            // Assume Stock In (Safe default for inventory loading)
             debugPrint("⚠️ Sheet '$tableKey' ambiguous. Defaulting to 'Stock In'.");
             isStockIn = true; 
        }

        if (isStockIn) {
          debugPrint("✅ Detected 'Stock In' data in sheet: $tableKey");
          importedIn += await _processStockIn(dataRows, headerRow);
        } else if (isStockOut) {
          debugPrint("✅ Detected 'Stock Out' data in sheet: $tableKey");
          importedOut += await _processStockOut(dataRows, headerRow);
        }
      }
    } catch (e) {
      debugPrint("❌ Excel Import Error: $e");
      rethrow;
    }

    return {'in': importedIn, 'out': importedOut};
  }
  
  // --- Keywords Definitions (Multilingual) ---
  static final _kwProduct = ['product', 'nomi', 'mahsulot', 'item', 'name', 'наименование', 'товар', 'nazvanie', 'ürün', 'ad', 'ism'];
  static final _kwQty = ['qty', 'soni', 'quantity', 'miqdor', 'count', 'количество', 'kol-vo', 'adet', 'miktar'];
  static final _kwPrice = ['price', 'narx', 'summa', 'cost', 'rate', 'baho', 'цена', 'stoimost', 'fiyat', 'tutar'];
  static final _kwSupplier = ['supplier', 'kimdan', 'yetkazib', 'from', 'source', 'поставщик', 'ot kogo', 'tedarikçi', 'kimden', 'kaynak'];
  static final _kwReceiver = ['receiver', 'kimga', 'bo\'lim', 'bolim', 'to', 'dest', 'target', 'получатель', 'komu', 'alıcı', 'kime', 'hedef'];
  static final _kwDate = ['date', 'sana', 'vaqt', 'time', 'when', 'дата', 'vremya', 'tarih', 'zaman'];
  static final _kwId = ['id', 'kod', 'code', 'barcode', 'shtrix', 'код', 'barkod'];

  static bool _hasKeyword(String text, List<String> keywords) {
      for(var k in keywords) {
          if (text.contains(k)) return true;
      }
      return false;
  }

  // 🔍 Helper to find the header row
  static Map<String, dynamic> _findHeaderRow(List<List<dynamic>> rows) {
    int limit = rows.length > 20 ? 20 : rows.length; // Increased lookahead to 20
    
    for (int i = 0; i < limit; i++) {
        final rowStr = rows[i].map((e) => e?.toString().toLowerCase() ?? '').toList();
        int matches = 0;
        
        // Check for presence of key columns
        if (rowStr.any((cell) => _hasKeyword(cell, _kwProduct))) matches++;
        if (rowStr.any((cell) => _hasKeyword(cell, _kwQty))) matches++;
        if (rowStr.any((cell) => _hasKeyword(cell, _kwId))) matches++;
        
        // If we found at least 2 key columns, assume this is header
        if (matches >= 2) {
            return {'index': i, 'headers': rowStr};
        }
    }
    return {'index': -1, 'headers': <String>[]};
  }

  static Future<int> _processStockIn(List<List<dynamic>> rows, List<String> headerRow) async {
    int count = 0;
    if (rows.isEmpty) return 0;
    
    int idxProduct = _findCol(headerRow, _kwProduct);
    int idxQty = _findCol(headerRow, _kwQty);
    int idxPrice = _findCol(headerRow, _kwPrice);
    int idxSupplier = _findCol(headerRow, _kwSupplier);
    int idxDate = _findCol(headerRow, _kwDate);
    int idxId = _findCol(headerRow, _kwId);

    // --- FALLBACK LOGIC ---
    // If we can't find Product or Qty by name, try to guess by content type from the first row
    if (idxProduct == -1 || idxQty == -1) {
       debugPrint("⚠️ Named columns missing. Attempting content-based detection...");
       final firstRow = rows.first; // Check data row
       
       if (idxProduct == -1) {
          // Find first String column
          for(int i=0; i<firstRow.length; i++) {
             final val = firstRow[i]?.toString() ?? '';
             if (val.length > 3 && double.tryParse(val) == null) {
                idxProduct = i;
                debugPrint("   -> Guessed Product Col: $i ($val)");
                break;
             }
          }
       }
       
       if (idxQty == -1) {
          // Find first Number column (that isn't Price)
          for(int i=0; i<firstRow.length; i++) {
             if (i == idxProduct || i == idxPrice) continue;
             final val = firstRow[i]?.toString().replaceAll(RegExp(r'[^0-9.]'), '') ?? '';
             if (val.isNotEmpty && double.tryParse(val) != null) {
                idxQty = i;
                 debugPrint("   -> Guessed Qty Col: $i ($val)");
                break;
             }
          }
       }
    }
    // ---------------------

    debugPrint("   Testing In Columns: Prod=$idxProduct, Qty=$idxQty, From=$idxSupplier, ID=$idxId");

    if (idxProduct == -1 || idxQty == -1) {
       debugPrint("   ⚠️ Missing required columns (Product or Qty) for Stock In. Skipping.");
       return 0;
    }

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;

      try {
        final productName = _getVal(row, idxProduct);
        if (productName.isEmpty) continue;
        
        String excelId = idxId != -1 ? _getVal(row, idxId) : '';
        String productId = await _resolveProduct(excelId, productName);

        double qty = double.tryParse(_getVal(row, idxQty).replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
        double price = double.tryParse(_getVal(row, idxPrice).replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
        String supplier = idxSupplier != -1 ? _getVal(row, idxSupplier) : '';
        
        String rawDate = idxDate != -1 ? _getVal(row, idxDate) : '';
        String dateStr = _parseDate(rawDate);
        
        if (qty <= 0) continue;

        await DatabaseHelper.instance.insertStockIn({
          'id': DateTime.now().millisecondsSinceEpoch.toString() + i.toString(),
          'product_id': productId,
          'date_time': dateStr, 
          'quantity': qty,
          'price_per_unit': price,
          'total_amount': qty * price,
          'supplier_name': supplier,
          'created_at': DateTime.now().toIso8601String(),
        });
        count++;
      } catch (e) {
        debugPrint("Row $i error: $e");
      }
    }
    return count;
  }

  static Future<int> _processStockOut(List<List<dynamic>> rows, List<String> headerRow) async {
    int count = 0;
    if (rows.isEmpty) return 0;
    
    int idxProduct = _findCol(headerRow, _kwProduct);
    int idxQty = _findCol(headerRow, _kwQty);
    int idxReceiver = _findCol(headerRow, _kwReceiver);
    int idxDate = _findCol(headerRow, _kwDate);
    int idxId = _findCol(headerRow, _kwId);
    
    // --- FALLBACK LOGIC ---
    if (idxProduct == -1 || idxQty == -1) {
       debugPrint("⚠️ Named columns missing (Out). Attempting content-based detection...");
       final firstRow = rows.first;
       if (idxProduct == -1) {
          for(int i=0; i<firstRow.length; i++) {
             final val = firstRow[i]?.toString() ?? '';
             if (val.length > 3 && double.tryParse(val) == null) {
                idxProduct = i;
                break;
             }
          }
       }
       if (idxQty == -1) {
          for(int i=0; i<firstRow.length; i++) {
             if (i == idxProduct) continue;
             final val = firstRow[i]?.toString().replaceAll(RegExp(r'[^0-9.]'), '') ?? '';
             if (val.isNotEmpty && double.tryParse(val) != null) {
                idxQty = i;
                break;
             }
          }
       }
    }
    // ---------------------

    debugPrint("   Testing Out Columns: Prod=$idxProduct, Qty=$idxQty, Receiver=$idxReceiver, ID=$idxId");

    if (idxProduct == -1 || idxQty == -1) {
       debugPrint("   ⚠️ Missing required columns (Product or Qty) for Stock Out. Skipping.");
       return 0;
    }

    for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty) continue;
        
        try {
            final productName = _getVal(row, idxProduct);
            if (productName.isEmpty) continue;

            String excelId = idxId != -1 ? _getVal(row, idxId) : '';
            String productId = await _resolveProduct(excelId, productName);

            double qty = double.tryParse(_getVal(row, idxQty).replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
            String receiver = idxReceiver != -1 ? _getVal(row, idxReceiver) : '';
            
            String rawDate = idxDate != -1 ? _getVal(row, idxDate) : '';
            String dateStr = rawDate.isNotEmpty ? _parseDate(rawDate) : DateTime.now().toIso8601String();

            if (qty <= 0) continue;

            await DatabaseHelper.instance.insertStockOut({
                'id': DateTime.now().millisecondsSinceEpoch.toString() + i.toString(),
                'product_id': productId,
                'date_time': dateStr,
                'quantity': qty,
                'receiver_name': receiver,
                'created_at': DateTime.now().toIso8601String(),
            });
            count++;
        } catch (e) { debugPrint("Row Out $i error: $e"); }
    }
    return count;
  }

  static int _findCol(List<String> headers, List<String> candidates) {
    for (var i = 0; i < headers.length; i++) {
        for (var c in candidates) {
            if (headers[i].contains(c)) return i;
        }
    }
    return -1;
  }

  static String _getVal(List<dynamic> row, int idx) {
    if (idx >= row.length || idx < 0) return '';
    return row[idx]?.toString() ?? '';
  }

  static String _parseDate(String rawDate) {
    if (rawDate.isEmpty) return DateTime.now().toIso8601String();
    
    // Check if it's already a standard format
    if (DateTime.tryParse(rawDate) != null) return DateTime.parse(rawDate).toIso8601String();
    
    // Handle dd/MM/yyyy or dd.MM.yyyy
    try {
      String clean = rawDate.replaceAll('.', '/').replaceAll('\\', '/');
      if (clean.contains('/')) {
        final parts = clean.split('/');
        if (parts.length == 3) {
           final day = int.parse(parts[0]);
           final month = int.parse(parts[1]);
           final year = int.parse(parts[2]);
           return DateTime(year, month, day).toIso8601String();
        }
      }
    } catch (_) {}

    return DateTime.now().toIso8601String();
  }

  static Future<String> _resolveProduct(String excelId, String name) async {
    final products = await DatabaseHelper.instance.getAllProducts();
    
    // 1. Try Find by Excel ID first (most accurate)
    if (excelId.isNotEmpty) {
      for (var p in products) {
        if (p['id'].toString().trim().toLowerCase() == excelId.trim().toLowerCase()) {
           return p['id'].toString();
        }
      }
    }

    // 2. Try Find by Name
    for (var p in products) {
        if (p['name'].toString().toLowerCase() == name.toLowerCase()) {
            return p['id'].toString();
        }
    }

    // 3. Create New
    final newId = excelId.isNotEmpty ? excelId : DateTime.now().millisecondsSinceEpoch.toString();
    
    await DatabaseHelper.instance.insertProduct({
        'id': newId,
        'name': name,
        'unit': 'dona', 
        'created_at': DateTime.now().toIso8601String(),
    });
    return newId;
  }
}

