import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/database/database_helper.dart';
import 'package:intl/intl.dart';
import 'package:barcode/barcode.dart';
import 'package:image/image.dart' as img;
import 'package:zxing_lib/zxing.dart';
import 'package:zxing_lib/common.dart';
import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import './pdf_service.dart';

class TelegramService {
  static const String _baseUrl = 'https://api.telegram.org/bot';
  static const String _keyBotToken = 'telegram_bot_token';
  static const String _keyUsers = 'telegram_users';

  // --- Singleton Pattern ---
  static final TelegramService _instance = TelegramService._internal();
  factory TelegramService() => _instance;
  TelegramService._internal();

  // --- State Management ---
  final Map<String, String> _userStates = {};
  final Map<String, List<Map<String, dynamic>>> _userCarts = {};
  final Map<String, Map<String, dynamic>> _userSelection = {};
  final Map<String, Map<String, dynamic>> _userReportSessions = {};

  // --- Configuration ---

  Future<String?> getBotToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBotToken);
  }

  Future<void> saveBotToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBotToken, token.trim());
  }

  Future<String?> getBotUsername() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('bot_username')) {
      return prefs.getString('bot_username');
    }
    final token = await getBotToken();
    if (token == null) return null;
    try {
      final res = await http.get(Uri.parse('$_baseUrl$token/getMe'));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['ok'] == true) {
          final username = body['result']['username'];
          await prefs.setString('bot_username', username);
          return username;
        }
      }
    } catch (_) {}
    return null;
  }

  // --- User Management ---

  Future<void> migrateFromPrefsToDb() async {
    final prefs = await SharedPreferences.getInstance();
    final oldData = prefs.getString(_keyUsers);
    if (oldData != null) {
      final List<dynamic> list = jsonDecode(oldData);
      for (var u in list) {
        await addUser(u['name'] ?? '', u['chatId']?.toString() ?? '', u['role'] ?? 'pending');
      }
      await prefs.remove(_keyUsers); // Migration done
      debugPrint("✅ TelegramService: Migrated ${list.length} users to DB.");
    }
  }

  Future<List<Map<String, dynamic>>> getUsers() async {
    final db = await DatabaseHelper.instance.database;
    final list = await db.query('telegram_users');
    return list.map((e) => {
      'name': e['name'],
      'chatId': e['chat_id'],
      'role': e['role'],
    }).toList();
  }

  Future<void> addUser(String name, String chatId, String role) async {
    final db = await DatabaseHelper.instance.database;
    final exists = await db.query('telegram_users', where: 'chat_id = ?', whereArgs: [chatId]);
    
    if (exists.isEmpty) {
      await db.insert('telegram_users', {
        'chat_id': chatId,
        'name': name,
        'role': role,
        'created_at': DateTime.now().toIso8601String(),
        'sync_status': 'pending', 
        'updated_at': DateTime.now().toIso8601String(),
      });
    } else {
       await db.update('telegram_users', {
         'name': name,
         'role': role,
         'sync_status': 'pending',
         'updated_at': DateTime.now().toIso8601String(),
       }, where: 'chat_id = ?', whereArgs: [chatId]);
    }
  }

  Future<void> _cleanDuplicates() async {
    final users = await getUsers();
    final uniqueUsers = <String, Map<String, dynamic>>{};

    for (var u in users) {
      final id = u['chatId'].toString();
      if (uniqueUsers.containsKey(id)) {
        if (uniqueUsers[id]!['role'] == 'pending' && u['role'] != 'pending') {
          uniqueUsers[id] = u;
        }
      } else {
        uniqueUsers[id] = u;
      }
    }

    if (uniqueUsers.length != users.length) {
       // Clean up duplicates in DB
       final db = await DatabaseHelper.instance.database;
       await db.delete('telegram_users');
       for (var entry in uniqueUsers.values) {
          await addUser(entry['name'] ?? 'User', entry['chatId'].toString(), entry['role'] ?? 'pending');
       }
    }
  }

  Future<void> updateUserRole(String chatId, String newRole) async {
    final users = await getUsers();
    for (var u in users) {
      if (u['chatId'] == chatId) {
        u['role'] = newRole;
        break;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsers, jsonEncode(users));
  }

  Future<void> updateUserName(String chatId, String newName) async {
    final users = await getUsers();
    for (var u in users) {
      if (u['chatId'] == chatId) {
        u['name'] = newName;
        break;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsers, jsonEncode(users));
  }

  Future<void> deleteUser(String chatId) async {
    final users = await getUsers();
    users.removeWhere((u) => u['chatId'] == chatId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsers, jsonEncode(users));
  }

  Future<void> updateOrderStatus(
    int orderId,
    String status,
    String chatId, {
    String? adminComment,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final updates = {'status': status};
    if (adminComment != null) updates['admin_comment'] = adminComment;

    await db.update(
      'branch_orders',
      updates,
      where: 'id = ?',
      whereArgs: [orderId],
    );

    String msg = "";
    String commentPart = (adminComment != null && adminComment.isNotEmpty)
        ? "\n\n💬 *Admin izohi:* \n$adminComment"
        : "";

    if (status == 'approved') {
      msg =
          "📦 *BUYURTMA TASDIQLANDI*\n"
          "-------------------------\n"
          "🆔 ID: `#ORD-$orderId`\n"
          "📊 Holat: **Tayyorlanmoqda** ✅\n"
          "$commentPart\n"
          "-------------------------\n"
          "🚚 *Tez orada yetkazib beriladi.*";
    } else if (status == 'rejected') {
      msg =
          "❌ *BUYURTMA RAD ETILDI*\n"
          "-------------------------\n"
          "🆔 ID: `#ORD-$orderId`\n"
          "📊 Holat: **Rad etilgan** ❌\n"
          "$commentPart\n"
          "-------------------------\n"
          "ℹ️ Iltimos, qayta tekshirib yuboring yoki admin bilan bog'laning.";
    } else if (status == 'delivered') {
      msg =
          "✅ *BUYURTMANGIZ YETKAZILDI*\n"
          "-------------------------\n"
          "🆔 ID: `#ORD-$orderId`\n"
          "📊 Holat: **Yetkazilgan** 🚚\n\n"
          "🛍 Xarid uchun rahmat!";
    }

    if (msg.isNotEmpty) {
      await sendMessage(chatId, msg);
    }
  }

  // --- API Actions ---

  Future<String?> sendMessage(
    String chatId,
    String text, {
    Map<String, dynamic>? replyMarkup,
    String parseMode = 'Markdown',
  }) async {
    final token = await getBotToken();
    if (token == null || token.isEmpty) return "Bot tokeni sozlanmagan";

    try {
      final url = Uri.parse('$_baseUrl$token/sendMessage');
      final body = {'chat_id': chatId, 'text': text, 'parse_mode': parseMode};
      if (replyMarkup != null) {
        body['reply_markup'] = jsonEncode(replyMarkup);
      }

      final response = await http.post(url, body: body);

      if (response.statusCode == 200) {
        return null;
      } else {
        return "Xato: ${response.statusCode} - ${response.body}";
      }
    } catch (e) {
      debugPrint('Telegram Error: $e');
      return "Internet xatosi: $e";
    }
  }

  Future<String?> _sendHtmlMessage(
    String chatId,
    String text, {
    Map<String, dynamic>? replyMarkup,
  }) async {
    final token = await getBotToken();
    if (token == null || token.isEmpty) return "Bot tokeni sozlanmagan";

    try {
      final url = Uri.parse('$_baseUrl$token/sendMessage');
      final body = {'chat_id': chatId, 'text': text, 'parse_mode': 'HTML'};
      if (replyMarkup != null) {
        body['reply_markup'] = jsonEncode(replyMarkup);
      }

      final response = await http.post(url, body: body);

      if (response.statusCode == 200) {
        return null;
      } else {
        return "Xato: ${response.statusCode} - ${response.body}";
      }
    } catch (e) {
      debugPrint('Telegram HTML Error: $e');
      return "Internet xatosi: $e";
    }
  }

  Future<String?> sendPhotoByUrl(
    String chatId,
    String photoUrl, {
    String? caption,
    String parseMode = 'Markdown',
  }) async {
    final token = await getBotToken();
    if (token == null || token.isEmpty) return null;
    try {
      final url = Uri.parse('$_baseUrl$token/sendPhoto');
      await http.post(
        url,
        body: {
          'chat_id': chatId,
          'photo': photoUrl,
          'caption': caption ?? "",
          'parse_mode': parseMode,
        },
      );
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> sendPhotoBytes(
    String chatId,
    Uint8List bytes, {
    String? caption,
    String parseMode = 'Markdown',
  }) async {
    final token = await getBotToken();
    if (token == null || token.isEmpty) return "Bot tokeni sozlanmagan";

    try {
      final url = Uri.parse('$_baseUrl$token/sendPhoto');
      final request = http.MultipartRequest('POST', url)
        ..fields['chat_id'] = chatId
        ..files.add(http.MultipartFile.fromBytes('photo', bytes, filename: 'label.png'));

      if (caption != null) {
        request.fields['caption'] = caption;
      }
      request.fields['parse_mode'] = parseMode;

      final response = await request.send();
      if (response.statusCode == 200) return null;
      return "Error: ${response.statusCode}";
    } catch (e) {
      return "Error: $e";
    }
  }

  Future<void> answerCallbackQuery(String callbackQueryId) async {
    final token = await getBotToken();
    if (token == null) return;
    final url = Uri.parse('$_baseUrl$token/answerCallbackQuery');
    await http.post(url, body: {'callback_query_id': callbackQueryId});
  }

  Future<String?> editMessageText(
    String chatId,
    int messageId,
    String text, {
    Map<String, dynamic>? replyMarkup,
    String parseMode = 'Markdown',
  }) async {
    final token = await getBotToken();
    if (token == null) return "Token xatosi";
    try {
      final url = Uri.parse('$_baseUrl$token/editMessageText');
      final body = {
        'chat_id': chatId,
        'message_id': messageId.toString(),
        'text': text,
        'parse_mode': parseMode,
      };
      if (replyMarkup != null) {
        body['reply_markup'] = jsonEncode(replyMarkup);
      }

      final response = await http.post(url, body: body);
      if (response.statusCode == 200) {
        return null;
      } else {
        return "Xato: ${response.body}";
      }
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> sendDocument(
    String chatId,
    File file, {
    String? caption,
    String? parseMode,
    Map<String, dynamic>? replyMarkup,
  }) async {
    final token = await getBotToken();
    if (token == null || token.isEmpty) return "Bot tokeni sozlanmagan";

    try {
      final url = Uri.parse('$_baseUrl$token/sendDocument');
      final request = http.MultipartRequest('POST', url)
        ..fields['chat_id'] = chatId
        ..files.add(await http.MultipartFile.fromPath('document', file.path));

      if (caption != null) {
        request.fields['caption'] = caption;
      }
      if (parseMode != null) {
        request.fields['parse_mode'] = parseMode;
      }
      if (replyMarkup != null) {
        request.fields['reply_markup'] = jsonEncode(replyMarkup);
      }

      final response = await request.send();
      if (response.statusCode == 200) return null;
      return "Error: ${response.statusCode}";
    } catch (e) {
      return "Error: $e";
    }
  }

  Future<List<Map<String, dynamic>>> getUpdates() async {
    final token = await getBotToken();
    if (token == null || !token.contains(':')) return [];
    try {
      final url = Uri.parse('$_baseUrl$token/getUpdates');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = <Map<String, dynamic>>[];
        if (data['ok'] == true) {
          final List updates = data['result'];
          for (var u in updates) {
            if (u['message'] != null) {
              final chat = u['message']['chat'];
              if (chat['type'] == 'private') {
                result.add({
                  'chatId': chat['id'].toString(),
                  'firstName': u['message']['from']['first_name'] ?? 'User',
                });
              }
            }
          }
        }
        return result;
      }
    } catch (e) {
      debugPrint("getUpdates error: $e");
    }
    return [];
  }

  Future<String?> getFileUrl(String fileId) async {
    final token = await getBotToken();
    if (token == null) throw Exception("Bot Token topilmadi.");
    try {
      final url = Uri.parse('$_baseUrl$token/getFile?file_id=$fileId');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] == true) {
          final filePath = data['result']['file_path'];
          return "https://api.telegram.org/file/bot$token/$filePath";
        } else {
          final error = data['description'] ?? "Noma'lum xatolik";
          if (error.contains('wrong file_id')) {
            throw Exception("Fayl (rasm) muddati o'tgan yoki topilmadi.");
          }
          throw Exception("Telegram API xatosi: $error");
        }
      } else {
        final data = jsonDecode(response.body);
        final error = data['description'] ?? 'HTTP ${response.statusCode}';
        if (error.contains('wrong file_id')) {
          throw Exception("Fayl (rasm) muddati o'tgan yoki topilmadi.");
        }
        throw Exception("Server xatosi: $error");
      }
    } catch (e) {
      debugPrint("getFileUrl Error: $e");
      String msg = e.toString().replaceFirst('Exception: ', '');
      throw Exception(msg);
    }
  }

  // --- Scheduler ---
  static const String _keyLastBackupWeek = 'last_backup_week_v1';
  static const String _keyLastAlertDate = 'last_low_stock_alert_date_v1';

  Future<void> checkDailyLowStockAlert(dynamic databaseHelperInstance) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final todayStr = "${now.year}-${now.month}-${now.day}";
    if (prefs.getString(_keyLastAlertDate) != todayStr) {
      try {
        final List<Map<String, dynamic>> lowStockItems =
            await databaseHelperInstance.getLowStockProducts();
        if (lowStockItems.isNotEmpty) {
          final users = await getUsers();
          final sb = StringBuffer();
          sb.writeln("⚠️ *DIQQAT: MAHSULOTLAR TUGAMOQDA!* ⚠️\n");
          for (int i = 0; i < lowStockItems.length && i < 20; i++) {
            sb.writeln(
              "${i + 1}. *${lowStockItems[i]['name']}* - ${lowStockItems[i]['stock']} ${lowStockItems[i]['unit']}",
            );
          }
          final message = sb.toString();
          for (var user in users) {
            await sendMessage(user['chatId'], message);
          }
          await prefs.setString(_keyLastAlertDate, todayStr);
        }
      } catch (e) {
      debugPrint("getUpdates error: $e");
    }
    }
  }

  Future<void> sendDailyReport(dynamic databaseHelperInstance) async {
    try {
      final users = await getUsers();
      if (users.isEmpty) return;
      final stats = await databaseHelperInstance.getDashboardStatusToday();
      final now = DateTime.now();
      final dateStr = "${now.day}.${now.month}.${now.year}";
      final sumStr = stats['in_sum'].toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]} ',
      );
      final msg =
          "📅 *KUNLIK HISOBOT*\nSana: $dateStr\n-------------------------\n📉 *Kirim:* ${stats['in_count']} ta ($sumStr so'm)\n📈 *Chiqim:* ${stats['out_count']} ta\n-------------------------";
      for (var user in users) {
        await sendMessage(user['chatId'], msg);
      }
    } catch (e) {
      debugPrint("getUpdates error: $e");
    }
  }

  Future<void> checkDailyReportAuto(dynamic databaseHelperInstance) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final todayStr = "${now.year}-${now.month}-${now.day}";
    if (prefs.getString('last_daily_report_date_v1') == todayStr) return;
    if (now.hour >= 18) {
      await sendDailyReport(databaseHelperInstance);
      await prefs.setString('last_daily_report_date_v1', todayStr);
    }
  }

  Future<void> checkWeeklyBackup(DatabaseHelper databaseHelperInstance) async {
    final prefs = await SharedPreferences.getInstance();
    final currentWeek = (DateTime.now().millisecondsSinceEpoch / (1000 * 60 * 60 * 24 * 7)).floor();
    if (currentWeek > (prefs.getInt(_keyLastBackupWeek) ?? 0)) {
      final users = await getUsers();
      if (users.isEmpty) return;
      
      final admin = users.any((u) => u['role'] == 'admin') 
          ? users.firstWhere((u) => u['role'] == 'admin') 
          : users.first;
      
      try {
        final path = await databaseHelperInstance.createBackup(null);
        if (path != null) {
          await sendDocument(admin['chatId'], File(path), caption: "🛡️ Avtomatik Haftalik Zaxira (Arxiv)");
          await prefs.setInt(_keyLastBackupWeek, currentWeek);
        }
      } catch (e) {
        debugPrint("Weekly backup error: $e");
      }
    }
  }

  Future<void> checkDailyBackup(DatabaseHelper databaseHelperInstance) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final todayStr = "${now.year}-${now.month}-${now.day}";
    
    if (prefs.getString('last_daily_backup_date') == todayStr) return;
    
    // Auto backup every night at 23:00 or whenever opened after that
    if (now.hour >= 23 || now.hour < 6) {
      final users = await getUsers();
      if (users.isEmpty) return;

      final admin = users.any((u) => u['role'] == 'admin') 
          ? users.firstWhere((u) => u['role'] == 'admin') 
          : users.first;

      try {
        final path = await databaseHelperInstance.createBackup(null);
        if (path != null) {
          final error = await sendDocument(
            admin['chatId'], 
            File(path), 
            caption: "🔐 *KUNLIK AVTO-ZAXIRA*\nTizim xavfsizligi yuzasidan barcha ma'lumotlar arxivlandi."
          );
          if (error == null) {
            await prefs.setString('last_daily_backup_date', todayStr);
            debugPrint("✅ Kunlik zaxira yuborildi.");
          }
        }
      } catch (e) {
        debugPrint("Daily backup error: $e");
      }
    }
  }
  Future<void> checkHourlyExcelBackup(DatabaseHelper dbh) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();

    final lastRunStr = prefs.getString('last_hourly_excel_backup_check');
    if (lastRunStr != null) {
      final lastRun = DateTime.tryParse(lastRunStr);
      if (lastRun != null && now.difference(lastRun).inHours < 1) {
        debugPrint("📊 Hourly Excel: Next check in ${60 - now.difference(lastRun).inMinutes} minutes.");
        return;
      }
    }

    debugPrint("📊 Hourly Excel: Checking for data changes...");
    final lastDataUpdateRaw = await dbh.getLastUpdateTimestamp();
    final lastBackupDataTs = prefs.getString('last_excel_backup_data_timestamp');
    
    if (lastDataUpdateRaw == null) return;
    if (lastBackupDataTs == lastDataUpdateRaw) {
      debugPrint("📊 Hourly Excel: No changes detected.");
      await prefs.setString('last_hourly_excel_backup_check', now.toIso8601String());
      return;
    }

    debugPrint("📊 Hourly Excel: Changes detected! Generating report...");
    final users = await getUsers();
    final admins = users.where((u) => u['role'] == 'admin').toList();
    debugPrint("📊 Hourly Excel: Found ${admins.length} admins.");
    if (admins.isEmpty) return;

    try {
      // 1. Generate Excel
      final excelPath = await _generateFullExcelReport(dbh);
      
      // 2. Generate DB Backup
      final dbBackupPath = await dbh.createBackup(null);

      final timeStr = DateFormat('dd.MM.yyyy HH:mm').format(now);
      final caption = [
        "📊 *AVTOMATIK HISOBOT* — $timeStr",
        "",
        "📋 Tarkib:",
        "  • Omborxona holati (rangli)",
        "  • Mahsulotlar ro'yxati",
        "  • Kirim/Chiqim to'liq tarixi",
        "",
        "💾 DB zaxira fayli ham yuborildi."
      ].join('\n');

      for (var admin in admins) {
        // Send Excel
        if (excelPath != null) {
          final err = await sendDocument(
            admin['chatId'], File(excelPath),
            caption: caption,
            parseMode: 'Markdown'
          );
          if (err != null) debugPrint("❌ Excel send error: $err");
        }
        // Send DB Backup
        if (dbBackupPath != null) {
          final err2 = await sendDocument(
            admin['chatId'], File(dbBackupPath),
            caption: "💾 *DB ZAXIRA* — $timeStr\n(SQLite to'liq bazasi)",
            parseMode: 'Markdown'
          );
          if (err2 != null) debugPrint("❌ DB backup send error: $err2");
        }
      }
      
      await prefs.setString('last_hourly_excel_backup_check', now.toIso8601String());
      await prefs.setString('last_excel_backup_data_timestamp', lastDataUpdateRaw);
      debugPrint("✅ Hourly Excel + DB Backup: Sent successfully.");
    } catch (e) {
      debugPrint("❌ Hourly Excel Error: $e");
    }
  }

  // Helper: style a header row with bold + background color
  void _styleHeaderRow(Sheet sheet, int rowIndex, List<String> headers, String hexColor) {
    for (int col = 0; col < headers.length; col++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIndex));
      cell.value = TextCellValue(headers[col]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString(hexColor),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: HorizontalAlign.Center,
      );
    }
  }

  Future<String?> _generateFullExcelReport(DatabaseHelper dbh) async {
    final excel = Excel.createExcel();

    // ── Sheet 1: Omborxona (Inventory Summary) ──────────────────
    Sheet sInventory = excel['Omborxona'];
    excel.delete('Sheet1');
    final inventory = await dbh.getInventorySummary();
    _styleHeaderRow(sInventory, 0, ['ID', 'Nomi', 'Birlik', 'Zaxira', 'Minimal'], '#1565C0');
    for (var row in inventory) {
      final stock = (row['stock'] as num).toDouble();
      final minStock = (row['min_stock_alert'] as num).toInt();
      final dataRow = [
        TextCellValue(row['id'].toString()), 
        TextCellValue(row['name'] ?? ''), 
        TextCellValue(row['unit'] ?? ''), 
        DoubleCellValue(stock), 
        IntCellValue(minStock)
      ];
      sInventory.appendRow(dataRow);
      // Highlight low stock rows in red
      if (stock <= minStock) {
        final lastRowIdx = sInventory.maxRows - 1;
        for (int c = 0; c < dataRow.length; c++) {
          sInventory.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: lastRowIdx))
            .cellStyle = CellStyle(backgroundColorHex: ExcelColor.fromHexString('#FFCDD2'));
        }
      }
    }

    // ── Sheet 2: Baza (Products) ────────────────────────────────
    Sheet sProducts = excel['Baza'];
    final products = await dbh.getAllProducts();
    _styleHeaderRow(sProducts, 0, ['ID', 'Nomi', 'Birlik', 'Tavsif', 'Yaratilgan vaqt'], '#2E7D32');
    for (var row in products) {
      sProducts.appendRow([
        TextCellValue(row['id'].toString()), 
        TextCellValue(row['name'] ?? ''), 
        TextCellValue(row['unit'] ?? ''), 
        TextCellValue(row['description'] ?? ''), 
        TextCellValue(row['created_at'] ?? '')
      ]);
    }

    // ── Sheet 3: Kirim (Stock In) ───────────────────────────────
    Sheet sKirim = excel['Kirim'];
    final stockIn = await dbh.getAllStockInFull();
    _styleHeaderRow(sKirim, 0, ['Vaqt', 'Mahsulot nomi', 'Partiya', 'Yaroqlilik muddati', 'Miqdor', 'Narx (so\'m)', 'Jami (so\'m)', 'Yetkazuvchi', 'To\'lov'], '#00695C');
    for (var row in stockIn) {
      sKirim.appendRow([
        TextCellValue(row['date_time'] ?? ''), 
        TextCellValue(row['product_name'] ?? ''), 
        TextCellValue(row['batch_number'] ?? ''), 
        TextCellValue(row['expiry_date'] ?? ''), 
        DoubleCellValue((row['quantity'] as num? ?? 0).toDouble()), 
        DoubleCellValue((row['price_per_unit'] as num? ?? 0).toDouble()), 
        DoubleCellValue((row['total_amount'] as num? ?? 0).toDouble()),
        TextCellValue(row['supplier_name'] ?? ''),
        TextCellValue(row['payment_status'] ?? ''),
      ]);
    }

    // ── Sheet 4: Chiqim (Stock Out) ─────────────────────────────
    Sheet sChiqim = excel['Chiqim'];
    final stockOut = await dbh.getAllStockOutFull();
    _styleHeaderRow(sChiqim, 0, ['Vaqt', 'Mahsulot nomi', 'Miqdor', 'Kimga', 'Partiya ref.', 'Eslatma'], '#E65100');
    for (var row in stockOut) {
      sChiqim.appendRow([
        TextCellValue(row['date_time'] ?? ''), 
        TextCellValue(row['product_name'] ?? ''), 
        DoubleCellValue((row['quantity'] as num? ?? 0).toDouble()), 
        TextCellValue(row['receiver_name'] ?? ''),
        TextCellValue(row['batch_reference'] ?? ''), 
        TextCellValue(row['notes'] ?? '')
      ]);
    }

    // ── Save to temp ──────────────────────────────────────────
    try {
      final dir = await getTemporaryDirectory();
      if (!await dir.exists()) await dir.create(recursive: true);
      
      final now = DateTime.now();
      final stamp = "${now.day}_${now.month}_${now.hour}_${now.minute}_${now.second}";
      final fileName = "Excel_Report_$stamp.xlsx";
      final path = p.join(dir.path, fileName);
      
      final fileBytes = excel.save();
      if (fileBytes != null) {
        debugPrint("📊 [ExcelGen] Bytes generated: ${fileBytes.length}");
        await File(path).writeAsBytes(fileBytes, flush: true);
        if (await File(path).exists()) {
          debugPrint("📊 [ExcelGen] File saved: $path");
          return path;
        }
      }
    } catch (e) {
      debugPrint("❌ [ExcelGen] Error: $e");
    }
    return null;
  }

  Future<String?> _generateFilteredExcelReport(
    DatabaseHelper dbh,
    String type,
    DateTime start,
    DateTime end,
  ) async {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];
    
    final sStr = DateFormat('yyyy-MM-dd HH:mm').format(start);
    final eStr = DateFormat('yyyy-MM-dd HH:mm').format(end);
    
    if (type == 'in') {
      sheet.appendRow([TextCellValue('FILTRLANGAN KIRIM HISOBOTI')]);
      sheet.appendRow([TextCellValue('Sana oralig\'i: $sStr - $eStr')]);
      sheet.appendRow([]);
      sheet.appendRow([
        TextCellValue('ID'),
        TextCellValue('Mahsulot'),
        TextCellValue('Miqdori'),
        TextCellValue('Donasi'),
        TextCellValue('Narxi'),
        TextCellValue('Sana'),
        TextCellValue('Yetkazib beruvchi'),
      ]);

      final data = await dbh.database.then((db) => db.rawQuery('''
        SELECT si.*, p.name as product_name 
        FROM stock_in si
        LEFT JOIN products p ON si.product_id = p.id
        WHERE si.is_deleted = 0 AND si.date_time BETWEEN ? AND ?
        ORDER BY si.date_time DESC
      ''', [start.toIso8601String(), end.toIso8601String()]));

      for (var row in data) {
        sheet.appendRow([
          TextCellValue(row['id']?.toString() ?? ''),
          TextCellValue(row['product_name']?.toString() ?? 'Noma\'lum'),
          TextCellValue(row['quantity']?.toString() ?? '0'),
          TextCellValue(row['unit']?.toString() ?? ''),
          TextCellValue(row['price_per_unit']?.toString() ?? '0'),
          TextCellValue(row['date_time']?.toString() ?? ''),
          TextCellValue(row['supplier_name']?.toString() ?? ''),
        ]);
      }
    } else {
      sheet.appendRow([TextCellValue('FILTRLANGAN CHIQIM HISOBOTI')]);
      sheet.appendRow([TextCellValue('Sana oralig\'i: $sStr - $eStr')]);
      sheet.appendRow([]);
      sheet.appendRow([
        TextCellValue('ID'),
        TextCellValue('Mahsulot'),
        TextCellValue('Miqdori'),
        TextCellValue('Donasi'),
        TextCellValue('Sana'),
        TextCellValue('Filiat/Bo\'lim'),
      ]);

      final data = await dbh.database.then((db) => db.rawQuery('''
        SELECT so.*, p.name as product_name 
        FROM stock_out so
        LEFT JOIN products p ON so.product_id = p.id
        WHERE so.is_deleted = 0 AND so.date_time BETWEEN ? AND ?
        ORDER BY so.date_time DESC
      ''', [start.toIso8601String(), end.toIso8601String()]));

      for (var row in data) {
        sheet.appendRow([
          TextCellValue(row['id']?.toString() ?? ''),
          TextCellValue(row['product_name']?.toString() ?? 'Noma\'lum'),
          TextCellValue(row['quantity']?.toString() ?? '0'),
          TextCellValue(row['unit']?.toString() ?? ''),
          TextCellValue(row['date_time']?.toString() ?? ''),
          TextCellValue(row['branch_name']?.toString() ?? ''),
        ]);
      }
    }

    try {
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final path = p.join(dir.path, "Report_${type}_$stamp.xlsx");
      final bytes = excel.save();
      if (bytes != null) {
        await File(path).writeAsBytes(bytes);
        return path;
      }
    } catch (e) {
      debugPrint("❌ Filtered Excel Error: $e");
    }
    return null;
  }


  // 🧪 Force send for testing (bypasses hourly timer)

  // --- BOT LISTENER (Interactive Mode) ---
  bool _isListening = false;
  int _lastUpdateId = 0;

  void startBotListener() {
    if (_isListening) return;
    _isListening = true;
    _runListener();
  }

  void stopBotListener() {
    _isListening = false;
    debugPrint("🤖 Telegram Bot: Polling stopped.");
  }

  Future<void> _runListener() async {
    await migrateFromPrefsToDb();
    await _cleanDuplicates();
    debugPrint("🤖 Telegram Bot: Polling started...");
    while (_isListening) {
      try {
        await _checkUpdates();
      } catch (e) {
        await Future.delayed(const Duration(seconds: 5));
      }
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  Future<void> _checkUpdates() async {
    final token = await getBotToken();
    if (token == null || token.isEmpty) return;
    final url = Uri.parse(
      '$_baseUrl$token/getUpdates?offset=${_lastUpdateId + 1}&timeout=10',
    );
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['ok'] == true) {
        for (var u in data['result']) {
          _lastUpdateId = u['update_id'];
          if (u['message'] != null) await _processMessage(u['message']);
          if (u['callback_query'] != null) {
            await _processCallbackQuery(u['callback_query']);
          }
        }
      }
    }
  }

  Future<void> _processMessage(Map<String, dynamic> msg) async {
    final chatId = msg['chat']['id'].toString();
    final text = msg['text']?.toString() ?? '';
    final photos = msg['photo'] as List?;

    final users = await getUsers();
    final user = users.firstWhere(
      (u) => u['chatId'] == chatId,
      orElse: () => {},
    );

    if (user.isEmpty) {
      final firstName = msg['from']['first_name'] ?? 'User';
      await addUser(firstName, chatId, 'pending');
      await sendMessage(
        chatId,
        "⏳ *Arizangiz qabul qilindi.* \n\nSiz tizimda ro'yxatdan o'tmagansiz. Administrator ruxsat berishini kuting (ID: $chatId).",
      );
      return;
    }

    if (user['role'] == 'pending') {
      await sendMessage(
        chatId,
        "⏳ *Sizning so'rovingiz hali ko'rib chiqilmadi.* \n\nIltimos, administrator ruxsat berishini kuting.",
      );
      return;
    }

    final isAdmin = user['role'] == 'admin';
    final isBranch = user['role'] == 'branch';

    if (msg['voice'] != null && isAdmin) {
      await sendMessage(
        chatId,
        "🎙 *Ovoz qabul qilindi!* (AI tahrirlovchi...)\n\n_Hozirda AI ovozni matnga o'girish tizimlari faol emas. Iloji bo'lsa darhol quyidagi \n\"🧠 AI Analizator\" tugmasidan (yoki matn yozish orqali) foydalaning!_",
      );
      return;
    }

    // Handle states
    if (_userStates[chatId] == 'waiting_for_qty') {
      final qty = double.tryParse(text);
      if (qty != null && qty > 0) {
        await _handleAddToCart(chatId, qty);
        return;
      } else {
        await sendMessage(chatId, "⚠️ Iltimos, faqat musbat son kiriting:");
        return;
      }
    }

    if (photos != null && photos.isNotEmpty) {
      if (isBranch) {
        if (_userStates[chatId] == 'waiting_for_order_photo') {
          await _handleSubmitPhotoOrder(chatId, photos.last['file_id']);
        } else if (_userStates[chatId] == 'waiting_for_qr_scan') {
          _userStates[chatId] = "";
          await _handlePhotoBarcode(chatId, photos);
        } else {
          await sendMessage(
            chatId,
            "⚠️ Iltimos, rasm yuborishdan oldin '📷 Foto Buyurtma' yoki '📷 QR Skanerlash' tugmasini bosing.",
          );
        }
      } else if (isAdmin) {
        await _handlePhotoBarcode(chatId, photos);
      }
      return;
    }

    if (text.startsWith('/start confirm_')) {
      final orderIdStr = text.replaceAll('/start confirm_', '').trim();
      final orderId = int.tryParse(orderIdStr);
      if (orderId != null) {
        // 1. Fetch Order Details & Items
        final dbHelper = DatabaseHelper.instance;
        final db = await dbHelper.database;

        final orderParams = await db.query(
          'branch_orders',
          where: 'id = ?',
          whereArgs: [orderId],
        );
        final orderItems = await db.query(
          'branch_order_items',
          where: 'order_id = ?',
          whereArgs: [orderId],
        );

        if (orderParams.isEmpty) {
          await sendMessage(chatId, "❌ Buyurtma topilmadi (#$orderId).");
          return;
        }

        final order = orderParams.first;

        // 1. Send Photo if exists (Always show original request proof)
        if (order['photo_file_id'] != null) {
          final photoId = order['photo_file_id'] as String;
          final token = await getBotToken();
          if (token != null) {
            final url = Uri.parse('$_baseUrl$token/sendPhoto');
            await http.post(
              url,
              body: {
                'chat_id': chatId,
                'photo': photoId,
                'caption': "📸 Buyurtma asosi (#$orderId)",
              },
            );
          }
        }

        // 2. Send List if exists
        if (orderItems.isNotEmpty) {
          StringBuffer msg = StringBuffer(
            "📦 *BUYURTMA TARKIBI (#$orderId):*\n\n",
          );
          for (var item in orderItems) {
            msg.writeln(
              "▪️ ${item['product_name']} - ${item['quantity']} ${item['unit']}",
            );
          }
          msg.writeln("\n-----------------------------");
          msg.writeln("Iltimos, yukni tekshirib qabul qiling.");
          await sendMessage(chatId, msg.toString());
        }
        // 3. If NO Photo AND NO Items
        else if (order['photo_file_id'] == null) {
          await sendMessage(
            chatId,
            "⚠️ Buyurtma tarkibi bo'sh va rasm topilmadi.",
          );
        }

        // 2. Set State & Show Options (ALWAYS show this so flow continues)
        _userStates[chatId] = "waiting_for_confirmation_action_$orderId";

        final keyboard = {
          "keyboard": [
            [
              {"text": "✅ Tasdiqlash"},
              {"text": "⚠️ Kamchilik"},
            ],
            [
              {"text": "❌ Bekor qilish"},
            ],
          ],
          "resize_keyboard": true,
          "one_time_keyboard": true,
        };

        await sendMessage(
          chatId,
          "👇 Quyidagi tugmalar orqali tasdiqlang:",
          replyMarkup: keyboard,
        );
        return;
      }
    }

    // Handle Confirmation Actions
    if (_userStates[chatId]?.startsWith('waiting_for_confirmation_action_') ??
        false) {
      final orderId = int.parse(_userStates[chatId]!.split('_').last);

      if (text == "✅ Tasdiqlash") {
        await updateOrderStatus(orderId, 'delivered', chatId);

        final users = await getUsers();
        final admins = users.where((u) => u['role'] == 'admin').toList();
        for (var admin in admins) {
          await sendMessage(
            admin['chatId'],
            "🚚 *YUK QABUL QILINDI (QR)*\nID: #ORD-$orderId\nHolati: ✅ Muvaffaqiyatli",
          );
        }

        await sendMessage(
          chatId,
          "✅ Buyurtma qabul qilindi va yetkazildi statusiga o'tdi!",
        );
        _userStates[chatId] = "";
        await _sendMainMenu(chatId, "Asosiy menyu", role: user['role']);
        return;
      } else if (text == "⚠️ Kamchilik") {
        _userStates[chatId] = "waiting_for_issue_note_$orderId";
        await sendMessage(
          chatId,
          "✍️ Iltimos, aniqlangan kamchiliklarni yozib yuboring:\n(Masalan: 2 ta quti ezilgan, 1 ta yetishmovchilik)",
        );
        return;
      } else if (text == "❌ Bekor qilish") {
        _userStates[chatId] = "";
        await _sendMainMenu(chatId, "Bekor qilindi.", role: user['role']);
        return;
      }
    }

    // Handle Issue Note
    if (_userStates[chatId]?.startsWith('waiting_for_issue_note_') ?? false) {
      final orderId = int.parse(_userStates[chatId]!.split('_').last);

      // Update with Note
      // We use admin_comment or a new notes field. Using admin_comment for simplicity or we should add 'client_note'
      final db = await DatabaseHelper.instance.database;

      // Fetch existing comment to append
      final existing = await db.query(
        'branch_orders',
        columns: ['admin_comment'],
        where: 'id = ?',
        whereArgs: [orderId],
      );
      String oldComment = "";
      if (existing.isNotEmpty && existing.first['admin_comment'] != null) {
        oldComment = existing.first['admin_comment'] as String;
      }

      final newComment = "$oldComment\n[QABUL QILISHDA KAMCHILIK]: $text"
          .trim();

      await db.update(
        'branch_orders',
        {'status': 'delivered', 'admin_comment': newComment},
        where: 'id = ?',
        whereArgs: [orderId],
      );

      // Notify Admin
      final users = await getUsers();
      final admins = users.where((u) => u['role'] == 'admin').toList();
      for (var admin in admins) {
        await sendMessage(
          admin['chatId'],
          "⚠️ *YUK QABUL QILISHDA KAMCHILIK*\nID: #ORD-$orderId\n\nIzoh: $text",
        );
      }

      await sendMessage(
        chatId,
        "✅ Kamchiliklar qayd etildi va buyurtma yetkazildi deb belgilandi.",
      );
      _userStates[chatId] = "";
      await _sendMainMenu(chatId, "Asosiy menyu", role: user['role']);
      return;
    }

    if (text == '/start' ||
        text.contains("Yangilash") ||
        text.contains("Asosiy Menyu")) {
      _userStates[chatId] = "";
      await _sendMainMenu(
        chatId,
        "👋 Assalomu alaykum! Omborxona xizmatiga xush kelibsiz.",
        role: user['role'],
      );
    } else if (text.contains("Bugungi Holat") && isAdmin) {
      await _handleTodayStats(chatId);
    } else if (text.contains("Umumiy Hisobot") && isAdmin) {
      await _handleTotalStats(chatId);
    } else if (text.contains("AI Analizator") && isAdmin) {
      await _handleAIAnalytics(chatId);
    } else if (text.contains("Kam Qolganlar") && isAdmin) {
      await _handleLowStock(chatId);
    } else if (text.contains("Jihozlar")) {
      await _handleAssetsStatMenu(chatId);
    } else if (text.contains("Oxirgi Harakatlar") && isAdmin) {
      await _handleRecentActivityMenu(chatId);
    } else if (text.contains("Excel Hisobot") && isAdmin) {
      await _handleExcelExport(chatId);
    } else if (text.contains("Foto Buyurtma") && isBranch) {
      _userStates[chatId] = "waiting_for_order_photo";
      await sendMessage(
        chatId,
        "📷 *Marhamat, buyurtma qog'ozini rasmga olib yuboring:* \n(Iltimos, rasm aniq va yorug' bo'lishiga e'tibor bering)",
      );
    } else if (text.contains("QR Skanerlash")) {
      _userStates[chatId] = "waiting_for_qr_scan";
      await sendMessage(
        chatId,
        "📲 *QR KOD SKANERLASH* \n\nYuk qutisidagi QR kodni telefoningiz kamerasi (yoki QR Scanner ilovasi) orqali skanerlang. \n\nSkanerlanganda avtomatik Telegram ochiladi va yuk qabul qilinadi.",
      );
    } else if ((text.contains("Buyurtma Holati") || text.contains("📝")) &&
        isBranch) {
      await _sendOrderFilterMenu(chatId);
    } else if (text == "📋 Oxirgi Buyurtma") {
      await _handleLastOrder(chatId);
    } else if (text == "⏳ Kutilmoqda") {
      await _handleOrderStatuses(chatId, status: 'pending', limit: 50);
    } else if (text == "✅ Tasdiqlangan") {
      await _handleOrderStatuses(chatId, status: 'approved', limit: 50);
    } else if (text == "🚚 Yetkazilgan") {
      await _handleOrderStatuses(chatId, status: 'delivered', limit: 50);
    } else if (text == "❌ Rad etilgan") {
      await _handleOrderStatuses(chatId, status: 'rejected', limit: 50);
    } else if (text == "📑 Barchasi") {
      await _handleOrderStatuses(chatId, limit: 100);
    } else if (text.contains("Mahsulot Qidirish")) {
      await sendMessage(
        chatId,
        "🔍 Qidirish uchun nomini yozing yoki jihoz shtrix-kodi rasmini yuboring:",
      );
    } else if (text.length > 2) {
      await _handleSearchProduct(chatId, text, isBranch: isBranch);
    }
  }

  Future<void> _sendOrderFilterMenu(String chatId) async {
    final keyboard = {
      'keyboard': [
        [
          {'text': '📋 Oxirgi Buyurtma'},
          {'text': '⏳ Kutilmoqda'},
        ],
        [
          {'text': '✅ Tasdiqlangan'},
          {'text': '🚚 Yetkazilgan'},
        ],
        [
          {'text': '❌ Rad etilgan'},
          {'text': '📑 Barchasi'},
        ],
        [
          {'text': '🔙 Asosiy Menyu'},
        ],
      ],
      'resize_keyboard': true,
      'one_time_keyboard': false,
    };
    await sendMessage(
      chatId,
      "📂 *BUYURTMALAR TARIXI*\n\nQuyidagi bo'limlardan birini tanlang:",
      replyMarkup: keyboard,
    );
  }

  Future<void> _handleLastOrder(String chatId) async {
    await _handleOrderStatuses(chatId, limit: 1);
  }

  Future<void> _handleOrderStatuses(
    String chatId, {
    String? status,
    int limit = 10,
  }) async {
    try {
      final db = await DatabaseHelper.instance.database;

      String whereClause = 'chat_id = ?';
      List<dynamic> whereArgs = [chatId];

      if (status != null) {
        whereClause += ' AND status = ?';
        whereArgs.add(status);
      }

      final orders = await db.query(
        'branch_orders',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'id DESC',
        limit: limit,
      );

      if (orders.isEmpty) {
        await sendMessage(chatId, "📋 Ma'lumot topilmadi.");
        return;
      }

      String msg = "📋 *BUYURTMA NATIJALARI:*\n\n";
      for (var o in orders) {
        String statusIcon = "⏳";
        String statusText = "Kutilmoqda";

        if (o['status'] == 'approved') {
          statusIcon = "✅";
          statusText = "Tasdiqlandi";
        }
        if (o['status'] == 'rejected') {
          statusIcon = "❌";
          statusText = "Rad etildi";
        }
        if (o['status'] == 'delivered') {
          statusIcon = "🚚";
          statusText = "Yetkazildi";
        }

        final date = DateTime.tryParse(o['created_at'].toString());
        final dateStr = date != null
            ? DateFormat('dd.MM.yyyy HH:mm').format(date)
            : o['created_at'];

        msg += "$statusIcon *#ORD-${o['id']}* - $statusText\n";
        msg += "📅 $dateStr\n";
        msg += "-------------------------\n";
      }

      await sendMessage(chatId, msg);
    } catch (e) {
      await sendMessage(chatId, "⚠️ Xatolik: $e");
    }
  }

  // --- Branch Ordering Logic ---

  Future<void> _handleAddToCart(String chatId, double qty) async {
    final selection = _userSelection[chatId];
    if (selection == null) return;

    _userCarts[chatId] ??= [];
    _userCarts[chatId]!.add({
      'id': selection['id'],
      'name': selection['name'],
      'qty': qty,
      'unit': selection['unit'],
    });

    _userStates[chatId] = "";
    _userSelection.remove(chatId);

    final markup = {
      'inline_keyboard': [
        [
          {'text': "🛒 Savatni ko'rish", 'callback_data': "order_view"},
        ],
      ],
    };
    await sendMessage(
      chatId,
      "✅ Savatga qo'shildi! Yana mahsulot qo'shishingiz yoki savatni ko'rishingiz mumkin.",
      replyMarkup: markup,
    );
  }

  Future<void> _handleShowCart(String chatId) async {
    final cart = _userCarts[chatId] ?? [];
    if (cart.isEmpty) {
      await sendMessage(chatId, "🛒 Savatingiz hozircha bo'sh.");
      return;
    }

    String text = "🛒 *SIZNING SAVATINGIZ:*\n\n";
    for (int i = 0; i < cart.length; i++) {
      text +=
          "${i + 1}. *${cart[i]['name']}* - ${cart[i]['qty']} ${cart[i]['unit']}\n";
    }

    final markup = {
      'inline_keyboard': [
        [
          {'text': "🚀 Buyurtmani yuborish", 'callback_data': "order_confirm"},
        ],
        [
          {'text': "🗑 Savatni tozalash", 'callback_data': "order_clear"},
        ],
      ],
    };
    await sendMessage(chatId, text, replyMarkup: markup);
  }

  Future<void> _handleSubmitPhotoOrder(String chatId, String fileId) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final users = await getUsers();
      final user = users.firstWhere((u) => u['chatId'] == chatId);

      final orderId = await db.insert('branch_orders', {
        'chat_id': chatId,
        'branch_name': user['name'],
        'status': 'pending',
        'photo_file_id': fileId,
        'created_at': DateTime.now().toIso8601String(),
      });

      _userStates[chatId] = ""; // State reset
      await sendMessage(
        chatId,
        "✅ *Rasm qabul qilindi!* \nBuyurtmangiz navbatga qo'shildi (ID: #FOTO-$orderId). Admin tez orada ko'rib chiqadi.",
      );

      // Notify Admins
      final token = await getBotToken();
      final admins = users.where((u) => u['role'] == 'admin').toList();
      final adminMsg =
          "� *YANGI FOTO-BUYURTMA*\n"
          "-------------------------\n"
          "🏢 Filial: **${user['name']}**\n"
          "🆔 ID: `#FOTO-$orderId`\n"
          "-------------------------\n"
          "📸 Buyurtma rasmi quyida yuborildi:";

      for (var admin in admins) {
        // Send notification text
        await sendMessage(admin['chatId'], adminMsg);
        // Forward the original photo for quick view
        final photoUrl = Uri.parse('$_baseUrl$token/sendPhoto');
        await http.post(
          photoUrl,
          body: {
            'chat_id': admin['chatId'],
            'photo': fileId,
            'caption': "Buyurtma qog'ozi (#FOTO-$orderId)",
          },
        );
      }
    } catch (e) {
      await sendMessage(chatId, "⚠️ Foto-buyurtmada xatolik: $e");
    }
  }

  Future<void> _submitOrder(String chatId) async {
    final cart = _userCarts[chatId] ?? [];
    if (cart.isEmpty) return;

    try {
      final db = await DatabaseHelper.instance.database;
      final users = await getUsers();
      final user = users.firstWhere((u) => u['chatId'] == chatId);

      final orderId = await db.insert('branch_orders', {
        'chat_id': chatId,
        'branch_name': user['name'],
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });

      for (var item in cart) {
        await db.insert('branch_order_items', {
          'order_id': orderId,
          'product_id': item['id'],
          'product_name': item['name'],
          'quantity': item['qty'],
          'unit': item['unit'],
        });
      }

      _userCarts[chatId] = [];
      await sendMessage(
        chatId,
        "🚀 *Buyurtmangiz muvaffaqiyatli yuborildi!* \nID: #ORD-$orderId\nAdmin tasdiqlashini kuting.",
      );

      // Notify Admins
      final admins = users.where((u) => u['role'] == 'admin').toList();
      final adminMsg =
          "🔔 *YANGI SAVAT BUYURTMASI*\n"
          "-------------------------\n"
          "🏢 Filial: **${user['name']}**\n"
          "🆔 ID: `#ORD-$orderId`\n"
          "📦 Mahsulotlar: **${cart.length} xil**\n"
          "-------------------------\n"
          "Ilovaga kiring yoki darhol Telegram orqali tasdiqlang 👇";
          
      final inlineKb = {
        'inline_keyboard': [
          [
            {'text': "✅ Tasdiqlash", 'callback_data': "order_approve:$orderId"},
            {'text': "❌ Rad etish", 'callback_data': "order_reject:$orderId"},
          ]
        ]
      };
      
      for (var admin in admins) {
        await sendMessage(admin['chatId'], adminMsg, replyMarkup: inlineKb);
      }
    } catch (e) {
      await sendMessage(chatId, "⚠️ Xatolik yuz berdi: $e");
    }
  }

  Future<void> _processCallbackQuery(Map<String, dynamic> query) async {
    final data = query['data'] as String;
    final message = query['message'];
    final messageId = message['message_id'];
    final chatId = message['chat']['id'].toString();

    await answerCallbackQuery(query['id']);

    // 📊 EXCEL FLOW HANDLING
    if (data.startsWith('ex_type:')) {
      final type = data.split(':').last;
      await _handleExcelDateSelection(chatId, messageId, type);
    } else if (data == 'ex_back_to_type') {
      await _handleExcelExport(chatId);
    } else if (data.startsWith('ex_date:')) {
      final dr = data.split(':').last;
      if (dr == 'calendar_start') {
        await _showCalendar(chatId, messageId, DateTime.now(), isEndDate: false);
      } else {
        await _handleExcelGeneration(chatId, messageId, dr);
      }
    } else if (data.startsWith('ex_cal_nav:')) {
      final p = data.split(':');
      final m = DateTime(int.parse(p[1]), int.parse(p[2]), 1);
      final isEnd = p[3] == "1";
      await _showCalendar(chatId, messageId, m, isEndDate: isEnd);
    } else if (data.startsWith('ex_cal_pick:')) {
      final p = data.split(':');
      final date = DateTime(int.parse(p[1]), int.parse(p[2]), int.parse(p[3]));
      final isEnd = p[4] == "1";
      final session = _userReportSessions[chatId];
      if (session != null) {
        if (!isEnd) {
          session['custom_start'] = date;
          await _showCalendar(chatId, messageId, date, isEndDate: true);
        } else {
          final start = session['custom_start'] as DateTime? ?? date;
          final end = DateTime(date.year, date.month, date.day, 23, 59, 59);
          await _handleExcelGeneration(chatId, messageId, 'custom_cal', customStart: start, customEnd: end);
        }
      }
    } else if (data == 'ex_share_picker') {
      await _handleSharePicker(chatId);
    } else if (data.startsWith('ex_do_share:')) {
      final targetChatId = data.split(':')[1];
      final session = _userReportSessions[chatId];
      if (session != null && session['lastFilePath'] != null) {
        final path = session['lastFilePath']!;
        final file = File(path);
        if (await file.exists()) {
          final users = await getUsers();
          final sender = users.firstWhere((u) => u['chatId'] == chatId, orElse: () => {'name': 'Foydalanuvchi'});
          
          await sendDocument(
            targetChatId, 
            file, 
            caption: "📂 <b>${sender['name']}</b> sizga hisobot yubordi.",
            parseMode: 'HTML'
          );
          await sendMessage(chatId, "✅ Hisobot muvaffaqiyatli yuborildi!");
        } else {
          await sendMessage(chatId, "⚠️ Xatolik: Hisobot fayli topilmadi. Iltimos, hisobotni qaytadan generatsiya qiling.");
        }
      }
    } else if (data.startsWith('hist_limit:')) {
      final limit = int.tryParse(data.split(':').last) ?? 5;
      await _handleRecentActivity(chatId, limit: limit);
    } else if (data.startsWith('hist_hours:')) {
      final hours = int.tryParse(data.split(':').last) ?? 1;
      await _handleRecentActivity(chatId, hours: hours);
    } else if (data.startsWith('pdf_last:')) {
      final type = data.split(':').last;
      final db = await DatabaseHelper.instance.database;
      final table = type == 'in' ? 'stock_in' : 'stock_out';
      final res = await db.rawQuery('''
        SELECT t.*, p.name as product_name, p.unit
        FROM $table t
        LEFT JOIN products p ON t.product_id = p.id
        WHERE t.is_deleted = 0
        ORDER BY t.date_time DESC LIMIT 1
      ''');
      if (res.isNotEmpty) {
        await _handleSendInvoice(chatId, res.first, type);
      } else {
        await sendMessage(chatId, "❌ Oxirgi harakat topilmadi.");
      }
    }
    // (Existing callbacks below...)
    else if (data.startsWith('asset_loc:')) {
      final locId = int.tryParse(data.split(':')[1]);
      if (locId != null) await _handleShowLocation(chatId, messageId, locId);
    } else if (data == 'asset_root') {
      await _handleAssetsStatMenu(chatId, messageId: messageId);
    } else if (data.startsWith('order_add:')) {
      final pid = data.split(':')[1];
      final db = await DatabaseHelper.instance.database;
      final product = (await db.query(
        'products',
        where: 'id = ?',
        whereArgs: [pid],
      )).first;

      _userSelection[chatId] = product;
      _userStates[chatId] = "waiting_for_qty";
      await sendMessage(
        chatId,
        "🔢 *${product['name']}* uchun miqdorni kiriting (${product['unit']}):",
      );
    } else if (data == 'order_view') {
      await _handleShowCart(chatId);
    } else if (data == 'order_confirm') {
      await _submitOrder(chatId);
    } else if (data == 'order_clear') {
      _userCarts[chatId] = [];
      await sendMessage(chatId, "🗑 Savat tozalandi.");
    } else if (data.startsWith('order_approve:')) {
      final oid = int.tryParse(data.split(':')[1]);
      if (oid != null) {
        await updateOrderStatus(oid, 'approved', chatId, adminComment: "Telegram orqali tasdiqlandi");
        await editMessageText(chatId, messageId, "✅ Buyurtma #ORD-$oid muvaffaqiyatli tasdiqlandi!");
      }
    } else if (data.startsWith('order_reject:')) {
      final oid = int.tryParse(data.split(':')[1]);
      if (oid != null) {
        await updateOrderStatus(oid, 'rejected', chatId, adminComment: "Telegram orqali rad etildi");
        await editMessageText(chatId, messageId, "❌ Buyurtma #ORD-$oid rad etildi!");
      }
    } else if (data.startsWith('asset_label:')) {
      final aid = int.tryParse(data.split(':')[1]);
      if (aid != null) await _handleSendAssetLabel(chatId, aid);
    }
  }

  // --- Handlers ---
  
  Future<void> _handleExcelExport(String chatId) async {
    final buttons = [
      [
        {'text': "📥 Kirim hisoboti", 'callback_data': "ex_type:in"},
        {'text': "📤 Chiqim hisoboti", 'callback_data': "ex_type:out"},
      ],
      [
        {'text': "📦 To'liq hisobot + Backup", 'callback_data': "ex_type:full"},
      ],
    ];

    await sendMessage(
      chatId,
      "📊 <b>HISOBOT TURINI TANLANG:</b>\n\n"
      "<i>Qaysi turdagi amaliyotlar hisoboti kerak?</i>",
      replyMarkup: {'inline_keyboard': buttons},
      parseMode: 'HTML',
    );
  }

  Future<void> _handleExcelDateSelection(String chatId, int messageId, String type) async {
    _userReportSessions[chatId] = {'type': type};
    
    final buttons = [
      [
        {'text': "📅 Bugun", 'callback_data': "ex_date:today"},
        {'text': "📅 Kecha", 'callback_data': "ex_date:yesterday"},
      ],
      [
        {'text': "🗓 Oxirgi 7 kun", 'callback_data': "ex_date:7d"},
        {'text': "🗓 Shu oy", 'callback_data': "ex_date:month"},
      ],
      [
        {'text': "🌐 Barchasi (All)", 'callback_data': "ex_date:all"},
        {'text': "📅 Maxsus oraliq", 'callback_data': "ex_date:calendar_start"},
      ],
      [
        {'text': "⬅️ Orqaga", 'callback_data': "ex_back_to_type"},
      ]
    ];

    String typeTxt = type == 'in' ? "📥 KIRIM" : (type == 'out' ? "📤 CHIQIM" : "📦 TO'LIQ");
    await editMessageText(
      chatId,
      messageId,
      "📆 <b>SANA ORALIG'INI TANLANG:</b>\n\n"
      "Turi: <b>$typeTxt</b>\n"
      "<i>Hisobot qaysi muddatni o'z ichiga olsin?</i>",
      replyMarkup: {'inline_keyboard': buttons},
      parseMode: 'HTML',
    );
  }

  Future<void> _handleExcelGeneration(String chatId, int messageId, String dateRange, {DateTime? customStart, DateTime? customEnd}) async {
    final session = _userReportSessions[chatId];
    if (session == null) return;
    
    final type = session['type'];
    session['dateRange'] = dateRange;

    String loadingMsg = customStart != null ? "⏳ <b>Maxsus oraliq hisoboti tayyorlanmoqda...</b>" : "⏳ <b>Hisobot tayyorlanmoqda...</b>";
    if (messageId != 0) {
      await editMessageText(chatId, messageId, loadingMsg, parseMode: 'HTML');
    } else {
      await sendMessage(chatId, loadingMsg, parseMode: 'HTML');
    }

    try {
      final dbh = DatabaseHelper.instance;
      String? filePath;
      String? dbBackupPath;
      String title = "";

      DateTime now = DateTime.now();
      DateTime start = customStart ?? DateTime(2000);
      DateTime end = customEnd ?? DateTime(now.year, now.month, now.day, 23, 59, 59);

      if (customStart != null && customEnd != null) {
        title = "Maxsus";
      } else if (dateRange == 'today') {
        start = DateTime(now.year, now.month, now.day);
        title = "Bugungi";
      } else if (dateRange == 'yesterday') {
        start = DateTime(now.year, now.month, now.day - 1);
        end = DateTime(now.year, now.month, now.day - 1, 23, 59, 59);
        title = "Kecha";
      } else if (dateRange == '7d') {
        start = now.subtract(const Duration(days: 7));
        title = "7 kunlik";
      } else if (dateRange == 'month') {
        start = DateTime(now.year, now.month, 1);
        title = "Shu oylik";
      } else if (dateRange == 'custom') {
        _userStates[chatId] = 'waiting_for_custom_date';
        await sendMessage(chatId, "🎯 <b>SANA ORALIG'INI YOZING:</b>\n\nFormat: <code>01.01.2026 - 01.04.2026</code>", parseMode: 'HTML');
        return;
      } else {
        title = "Umumiy";
      }

      if (type == 'full') {
        filePath = await _generateFullExcelReport(dbh);
        dbBackupPath = await dbh.createBackup(null);
      } else {
        filePath = await _generateFilteredExcelReport(dbh, type, start, end);
      }

      if (filePath != null) {
        String typeTxt = type == 'in' ? "Kirim" : (type == 'out' ? "Chiqim" : "To'liq");
        final caption = "✅ <b>$title $typeTxt hisoboti tayyor!</b>\n\n"
            "🗓 Sana: ${DateFormat('dd.MM.yyyy').format(start)} - ${DateFormat('dd.MM.yyyy').format(end)}\n"
            "📦 Operatsiyalar soni tahlil qilindi.";

        final markup = {
          'inline_keyboard': [
            [{'text': "👤 Jo'natish (Share)", 'callback_data': "ex_share_picker"}]
          ]
        };

        await sendDocument(chatId, File(filePath), caption: caption, parseMode: 'HTML', replyMarkup: markup);
        session['lastFilePath'] = filePath;

        if (dbBackupPath != null) {
          await sendDocument(chatId, File(dbBackupPath), caption: "💾 Baza zaxira nusxasi (Backup)", parseMode: 'HTML');
        }
      }
    } catch (e) {
      await sendMessage(chatId, "⚠️ Xatolik: $e");
    }
  }

  Future<void> _showCalendar(String chatId, int messageId, DateTime month, {bool isEndDate = false}) async {
    final session = _userReportSessions[chatId];
    if (session == null) return;

    final List<List<Map<String, dynamic>>> keyboard = [];

    // Header: Month and Year
    final monthName = DateFormat('MMMM yyyy').format(month);
    final typeTxt = session['type'] == 'in' ? "Kirim" : "Chiqim";
    final stepTxt = isEndDate ? "TUGASH sanasini tanlang" : "BOSHLANISH sanasini tanlang";

    keyboard.add([
        {'text': "◀️", 'callback_data': "ex_cal_nav:${month.year}:${month.month - 1}:${isEndDate ? 1 : 0}"},
        {'text': monthName, 'callback_data': "ignore"},
        {'text': "▶️", 'callback_data': "ex_cal_nav:${month.year}:${month.month + 1}:${isEndDate ? 1 : 0}"},
    ]);

    // Weekday headers
    keyboard.add([
      {'text': "Du", 'callback_data': "ignore"},
      {'text': "Se", 'callback_data': "ignore"},
      {'text': "Ch", 'callback_data': "ignore"},
      {'text': "Pa", 'callback_data': "ignore"},
      {'text': "Ju", 'callback_data': "ignore"},
      {'text': "Sh", 'callback_data': "ignore"},
      {'text': "Ya", 'callback_data': "ignore"},
    ]);

    // Days
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0);
    
    int startOffset = firstDay.weekday - 1; // Mon=1 -> 0
    List<Map<String, dynamic>> currentRow = [];
    
    // Empty cells before first day
    for (int i = 0; i < startOffset; i++) {
      currentRow.add({'text': " ", 'callback_data': "ignore"});
    }

    for (int day = 1; day <= lastDay.day; day++) {
      currentRow.add({
        'text': "$day",
        'callback_data': "ex_cal_pick:${month.year}:${month.month}:$day:${isEndDate ? 1 : 0}"
      });
      if (currentRow.length == 7) {
        keyboard.add(currentRow);
        currentRow = [];
      }
    }
    if (currentRow.isNotEmpty) {
      while (currentRow.length < 7) {
        currentRow.add({'text': " ", 'callback_data': "ignore"});
      }
      keyboard.add(currentRow);
    }

    keyboard.add([{'text': "⬅️ Bekor qilish", 'callback_data': "ex_back_to_type"}]);

    final text = "📅 <b>KALENDAR: $typeTxt Hisoboti</b>\n\n📌 $stepTxt";
    await editMessageText(chatId, messageId, text, replyMarkup: {'inline_keyboard': keyboard}, parseMode: 'HTML');
  }

  Future<void> _handleSharePicker(String chatId) async {
    final users = await getUsers();
    final session = _userReportSessions[chatId];
    if (session == null || session['lastFilePath'] == null) {
      await sendMessage(chatId, "⚠️ Avval hisobotni yuklang.");
      return;
    }

    final buttons = <List<Map<String, dynamic>>>[];
    for (var u in users) {
      if (u['chatId'] != chatId) {
        buttons.add([
          {'text': "👤 ${u['name']} (${u['role']})", 'callback_data': "ex_do_share:${u['chatId']}"}
        ]);
      }
    }

    if (buttons.isEmpty) {
      await sendMessage(chatId, "📭 Tizimda boshqa foydalanuvchilar topilmadi.");
      return;
    }

    await sendMessage(
      chatId,
      "👥 <b>KIMGA YUBORAMIZ?</b>\n\n"
      "<i>Tizimdan foydalanuvchini tanlang:</i>",
      replyMarkup: {'inline_keyboard': buttons},
      parseMode: 'HTML',
    );
  }

  Future<void> _handleAssetsStatMenu(String chatId, {int? messageId}) async {
    final db = await DatabaseHelper.instance.database;
    final buildings = await db.query(
      'asset_locations',
      where: 'parent_id IS NULL AND is_deleted = 0',
    );

    final buttons = <List<Map<String, dynamic>>>[];
    for (var b in buildings) {
      buttons.add([
        {'text': "🏢 ${b['name']}", 'callback_data': "asset_loc:${b['id']}"},
      ]);
    }

    // Refresh button
    buttons.add([
      {'text': "🔄 Yangilash", 'callback_data': "asset_root"},
    ]);

    final markup = {'inline_keyboard': buttons};
    final text = "🖥 <b>JIHOZLAR VA AKTIVLAR</b>\n"
        "━━━━━━━━━━━━━━━━━━\n\n"
        "🏢 Tizimdagi binolar va manzillar:\n"
        "<i>Pastdan kerakli binoni tanlang:</i>";

    if (messageId != null) {
      await editMessageText(chatId, messageId, text, replyMarkup: markup, parseMode: 'HTML');
    } else {
      await sendMessage(chatId, text, replyMarkup: markup, parseMode: 'HTML');
    }
  }

  Future<void> _handleShowLocation(
    String chatId,
    int messageId,
    int locId,
  ) async {
    final db = await DatabaseHelper.instance.database;

    // 1. Get current location info
    final currentLoc = (await db.query(
      'asset_locations',
      where: 'id = ?',
      whereArgs: [locId],
    )).first;

    // 2. Get sub-locations (Floors/Rooms)
    final subLocs = await db.query(
      'asset_locations',
      where: 'parent_id = ? AND is_deleted = 0',
      whereArgs: [locId],
    );

    // 3. Get assets in this location with category info
    final assets = await db.rawQuery(
      '''
      SELECT a.*, c.name as category_name
      FROM assets a
      LEFT JOIN asset_categories c ON a.category_id = c.id
      WHERE a.location_id = ? AND a.is_deleted = 0
      ORDER BY a.name ASC
    ''',
      [locId],
    );

    final buttons = <List<Map<String, dynamic>>>[];

    // Add sub-locations as buttons
    for (var sl in subLocs) {
      String prefix = sl['type'] == 'floor' ? '📶' : '🚪';
      buttons.add([
        {
          'text': "$prefix ${sl['name']}",
          'callback_data': "asset_loc:${sl['id']}",
        },
      ]);
    }

    // Add assets as buttons (Label Generator)
    if (assets.isNotEmpty) {
      for (var a in assets) {
        buttons.add([
          {
            'text': "🏷 ${a['name']}",
            'callback_data': "asset_label:${a['id']}",
          },
        ]);
      }
    }

    // Back button
    final parentId = currentLoc['parent_id'];
    buttons.add([
      {
        'text': "⬅️ Orqaga",
        'callback_data': parentId == null
            ? 'asset_root'
            : "asset_loc:$parentId",
      },
    ]);

    final markup = {'inline_keyboard': buttons};

    StringBuffer sb = StringBuffer();
    sb.writeln("📍 <b>MANZIL:</b> ${currentLoc['name']}");
    sb.writeln("━━━━━━━━━━━━━━━━━━");

    if (assets.isNotEmpty) {
      sb.writeln("\n📦 <b>JIHOZLAR RO'YXATI:</b> (${assets.length} ta)");
      
      for (var a in assets) {
        String statusIcon = "✅";
        final statusLower = (a['status'] ?? '').toString().toLowerCase();
        if (statusLower.contains('tamir')) {
          statusIcon = "🛠";
        } else if (statusLower.contains('buz') || statusLower.contains('broken')) {
          statusIcon = "🔴";
        } else if (statusLower.contains('yoq') || statusLower.contains('missing')) {
          statusIcon = "❓";
        }

        String name = _e(a['name']);
        
        sb.writeln("");
        sb.writeln("$statusIcon <b>$name</b>");
        sb.writeln("   🔹 Tur: <i>${_e(a['category_name'])}</i>");
        
        if (a['brand'] != null && a['brand'] != '-' && a['brand'].toString().isNotEmpty) {
           sb.writeln("   🔹 Brend: ${_e(a['brand'])}");
        }
        if (a['model'] != null && a['model'] != '-' && a['model'].toString().isNotEmpty) {
           sb.writeln("   🔹 Model: ${_e(a['model'])}");
        }
        if (a['serial_number'] != null && a['serial_number'] != '-' && a['serial_number'].toString().isNotEmpty) {
           sb.writeln("   🔹 SN: <code>${_e(a['serial_number'])}</code>");
        }
        
        sb.writeln("   🔸 Holat: <i>${_e(a['status'])}</i>");
        
        if (a['barcode'] != null && a['barcode'].toString().isNotEmpty) {
          sb.writeln("   🔸 BC: <code>${_e(a['barcode'])}</code>");
        }
        
        if (a['description'] != null && a['description'] != '-' && a['description'].toString().isNotEmpty) {
          sb.writeln("   📝 <i>${_e(a['description'])}</i>");
        }
        
        sb.writeln("┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈");
      }
    } else if (subLocs.isEmpty) {
      sb.writeln("\n📭 <i>Ushbu manzilda hozircha jihozlar mavjud emas.</i>");
    } else {
      sb.writeln("\n👇 <b>KERAKLI BO'LIMNI TANLANG:</b>");
    }

    if (messageId != 0) {
      final error = await editMessageText(chatId, messageId, sb.toString(), replyMarkup: markup, parseMode: 'HTML');
      if (error != null) {
        debugPrint("❌ Assets Edit Error: $error");
      }
    }
  }

  // --- UI HELPERS ---

  String _getTimeBasedGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 5) return "Xayrli kech 🌙";
    if (hour < 11) return "Xayrli tong ☀️";
    if (hour < 17) return "Xayrli kun 🌤";
    return "Xayrli kech 🌙";
  }

  String _formatMoney(num amount) {
    return NumberFormat("#,###").format(amount);
  }

  // --- Handlers ---

  Future<void> _handleTodayStats(String chatId) async {
    try {
      final stats = await DatabaseHelper.instance.getDashboardStatusToday();
      final greeting = _getTimeBasedGreeting();
      final dateStr = DateFormat('dd.MM.yyyy').format(DateTime.now());

      final inCount = stats['in_count'] as int;
      final outCount = stats['out_count'] as int;
      final inSum = stats['in_sum'] as num;

      String msg =
          "$greeting, Hurmatli Admin!\n\n"
          "📊 *BUGUNGI HISOBOT ($dateStr)*\n"
          "-------------------------\n\n"
          "📥 *Kirim Operatsiyalari:*\n"
          "   - Jami: *$inCount ta* harakat\n"
          "   - Qiymati: *${_formatMoney(inSum)}* so'm\n\n"
          "📤 *Chiqim Operatsiyalari:*\n"
          "   - Jami: *$outCount ta* operatsiya\n"
          "   - Holat: Faoliyat davom etmoqda\n\n"
          "-------------------------\n"
          "📝 *Xulosa:* Bugun jami *${inCount + outCount} ta* ombor operatsiyasi amalga oshirildi. "
          "Tizim barcha harakatlarni muvaffaqiyatli nazorat qilmoqda.\n\n"
          "#hisobot #bugun";

      await sendMessage(chatId, msg);
    } catch (e) {
      await sendMessage(chatId, "⚠️ Ma'lumotlarni hisoblashda xatolik: $e");
    }
  }

  Future<void> _handleTotalStats(String chatId) async {
    try {
      final stats = await DatabaseHelper.instance.getDashboardStats();
      final totalVal = stats['total_value'] as double;
      final lowCount = stats['low_stock'] as int;
      final finishedCount = stats['finished'] as int;

      String msg =
          "💰 *OMBORXONA UMUMIY TAHLILI*\n"
          "-------------------------\n\n"
          "💵 *Moliyaviy Holat:*\n"
          "   - Jami qiymat: *${_formatMoney(totalVal)}* so'm\n\n"
          "📊 *Zaxira Sog'lig'i:*\n"
          "   - Kam qolgan: *$lowCount xil*\n"
          "   - Tugagan: *$finishedCount xil*\n\n"
          "💡 *Tavsiya:* Hozirgi kunda omborning holati barqaror. ";

      if (finishedCount > 0) {
        msg +=
            "Biroq, tugagan mahsulotlar uchun yangi buyurtma berishni tavsiya qilamiz.";
      }

      msg +=
          "\n\n-------------------------\n"
          "#hisobot #analitika";

      await sendMessage(chatId, msg);
    } catch (e) {
      await sendMessage(chatId, "⚠️ Hisobotda xatolik: $e");
    }
  }

  Future<void> _handleLowStock(String chatId) async {
    try {
      final allLow = await DatabaseHelper.instance.getLowStockProducts();
      final finished = await DatabaseHelper.instance.getFinishedProducts();

      if (allLow.isEmpty && finished.isEmpty) {
        await sendMessage(
          chatId,
          "✅ *Xushxabar!* Hozirda omborda barcha mahsulotlar yetarli miqdorda mavjud.",
        );
        return;
      }

      String list =
          "🚨 *ZAXIRA OGOHLANTIRISHLARI*\n"
          "-------------------------\n\n";

      if (finished.isNotEmpty) {
        list += "❌ *ZUDLIK BILAN (TUGAGAN):*\n";
        for (var i = 0; i < finished.length && i < 10; i++) {
          list +=
              "   • ${finished[i]['name']} (0 ${finished[i]['unit'] ?? ''})\n";
        }
        list += "\n";
      }

      if (allLow.isNotEmpty) {
        list += "⚠️ *KAM QOLGANLAR (YANGILASH KERAK):*\n";
        for (var i = 0; i < allLow.length && i < 10; i++) {
          bool exists = finished.any((f) => f['id'] == allLow[i]['id']);
          if (!exists) {
            list +=
                "   • ${allLow[i]['name']} (*${allLow[i]['stock']} ${allLow[i]['unit'] ?? ''}*)\n";
          }
        }
      }

      list +=
          "\n-------------------------\n"
          "Iltimos, zaxiralarni nazorat qilib boring.\n"
          "#ogohlantirish #zaxira";

      await sendMessage(chatId, list);
    } catch (e) {
      await sendMessage(chatId, "⚠️ Ma'lumot yuklashda xatolik: $e");
    }
  }

  Future<void> _handleRecentActivity(String chatId, {int limit = 5, int? hours}) async {
    try {
      final activity = await DatabaseHelper.instance.getRecentActivity(
        limit: limit,
        hours: hours,
      );
      if (activity.isEmpty) {
        await sendMessage(chatId, "📭 Tanlangan vaqt oralig'ida harakatlar tarixi topilmadi.");
        return;
      }

      String title = hours != null ? "⏳ OXIRGI $hours SOATDAGI HARAKATLAR" : "🔄 OXIRGI $limit TA HARAKAT";
      String list =
          "*$title*\n"
          "-------------------------\n\n";

      for (var item in activity) {
        final isKirim = item['type'] == 'in';
        final typeIcon = isKirim ? "📥 KIRIM" : "📤 CHIQIM";
        final partyInfo = isKirim
            ? "Yetkazuvchi: ${item['party']}"
            : "Qabul qiluvchi: ${item['party']}";
        final dtRaw = item['date_time'].toString();

        String dateDisplay = dtRaw;
        final parsed = DateTime.tryParse(dtRaw);
        if (parsed != null) {
          dateDisplay = DateFormat('dd.MM.yyyy HH:mm').format(parsed.toLocal());
        }

        list +=
            "*$typeIcon*\n"
            "📦 *${item['product_name']}*\n"
            "🔢 Miqdori: *${item['quantity']}*\n"
            "🤝 $partyInfo\n"
            "📅 Vaqti: $dateDisplay\n"
            "-------------------------\n";
      }

      await sendMessage(chatId, list);
    } catch (e) {
      await sendMessage(chatId, "⚠️ Tarixni yuklashda xatolik: $e");
    }
  }

  Future<void> _handleRecentActivityMenu(String chatId) async {
    final markup = {
      'inline_keyboard': [
        [
          {'text': "🔢 Oxirgi 5 ta", 'callback_data': "hist_limit:5"},
          {'text': "🔢 Oxirgi 20 ta", 'callback_data': "hist_limit:20"},
        ],
        [
          {'text': "⏱ Oxirgi 1 soat", 'callback_data': "hist_hours:1"},
          {'text': "⏱ Oxirgi 6 soat", 'callback_data': "hist_hours:6"},
        ],
        [
          {'text': "📅 Oxirgi 24 soat", 'callback_data': "hist_hours:24"},
          {'text': "📅 Oxirgi 7 kun", 'callback_data': "hist_hours:168"},
        ],
        [
          {'text': "📄 Oxirgi Kirim (PDF)", 'callback_data': "pdf_last:in"},
          {'text': "📄 Oxirgi Chiqim (PDF)", 'callback_data': "pdf_last:out"},
        ],
      ],
    };
    await sendMessage(
      chatId,
      "🔍 *Harakatlar tarixi uchun vaqtni tanlang:*",
      replyMarkup: markup,
    );
  }

  Future<void> _handleSearchProduct(
    String chatId,
    String query, {
    bool isBranch = false,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final sanitized = '%$query%';
    final productResults = await db.rawQuery(
      'SELECT id, name, unit, ((SELECT IFNULL(SUM(quantity), 0) FROM stock_in WHERE product_id = p.id) - (SELECT IFNULL(SUM(quantity), 0) FROM stock_out WHERE product_id = p.id)) as stock FROM products p WHERE name LIKE ? LIMIT 5',
      [sanitized],
    );
    final assetResults = await db.rawQuery(
      'SELECT a.name, a.model, l.name as loc_name FROM assets a LEFT JOIN asset_locations l ON a.location_id = l.id WHERE a.name LIKE ? LIMIT 5',
      [sanitized],
    );

    if (productResults.isEmpty && assetResults.isEmpty) {
      await sendMessage(chatId, "📌 Topilmadi.");
      return;
    }

    if (productResults.isNotEmpty) {
      for (var item in productResults) {
        String msg =
            "📦 *MAHSULOT:*\n"
            " - Nomi: ${item['name']}\n"
            " - Mavjud: *${item['stock']} ${item['unit']}*";

        Map<String, dynamic>? markup;
        if (isBranch) {
          markup = {
            'inline_keyboard': [
              [
                {
                  'text': "➕ Savatga qo'shish",
                  'callback_data': "order_add:${item['id']}",
                },
              ],
            ],
          };
        }
        await sendMessage(chatId, msg, replyMarkup: markup);
      }
    }

    if (assetResults.isNotEmpty) {
      String list = "🖥 *JIHOZLAR:*\n";
      for (var item in assetResults) {
        list += " - ${item['name']} 📍 ${item['loc_name']}\n";
      }
      await sendMessage(chatId, list);
    }
  }

  Future<void> _handlePhotoBarcode(String chatId, List maps) async {
    final token = await getBotToken();
    if (token == null) return;

    await sendMessage(chatId, "🔍 *Rasm qabul qilindi.* Analiz qilinmoqda...");

    try {
      final fileId = maps.last['file_id'];
      final getFileUrl = Uri.parse('$_baseUrl$token/getFile?file_id=$fileId');
      final fileRes = await http.get(getFileUrl);
      final fileData = jsonDecode(fileRes.body);

      if (fileData['ok'] != true) throw "Faylni olib bo'lmadi";

      final filePath = fileData['result']['file_path'];
      final downloadUrl = 'https://api.telegram.org/file/bot$token/$filePath';
      final imgRes = await http.get(Uri.parse(downloadUrl));
      final bytes = imgRes.bodyBytes;

      final image = img.decodeImage(bytes);
      if (image == null) throw "Rasmni o'qib bo'lmadi";

      // Multi-format support (1D + 2D) using zxing_lib
      final source = RGBLuminanceSource(
        image.width,
        image.height,
        image.getBytes(order: img.ChannelOrder.rgba).buffer.asInt32List(),
      );
      final bitmap = BinaryBitmap(HybridBinarizer(source));

      final reader = MultiFormatReader();
      final result = reader.decode(
        bitmap,
      ); // Default hints are usually enough for Code 128

      final barcode = result.text.trim();
      await sendMessage(
        chatId,
        "✅ *Skanerlandi:* `$barcode` \nMa'lumotlar qidirilmoqda...",
      );

      final db = await DatabaseHelper.instance.database;

      // --- CASE 1: DELIVERY CONFIRMATION (#ORD-XXX) ---
      if (barcode.startsWith("#ORD-")) {
        final orderIdStr = barcode.replaceFirst("#ORD-", "");
        final orderId = int.tryParse(orderIdStr);
        if (orderId == null) throw "Buyurtma ID noto'g'ri";

        final orders = await db.query(
          'branch_orders',
          where: 'id = ?',
          whereArgs: [orderId],
        );
        if (orders.isEmpty) {
          await sendMessage(
            chatId,
            "❌ Kechiraiz, `#ORD-$orderId` buyurtma topilmadi.",
          );
          return;
        }

        final order = orders.first;
        if (order['status'] == 'delivered') {
          await sendMessage(chatId, "ℹ️ Bu buyurtma avvalroq qabul qilingan.");
          return;
        }

        // Update to Delivered
        await updateOrderStatus(orderId, 'delivered', chatId);

        // Notify Admins
        final users = await getUsers();
        final admins = users.where((u) => u['role'] == 'admin').toList();
        final adminMsg =
            "🚚 *YUK QABUL QILINDI*\n"
            "-------------------------\n"
            "🏢 Filial: **${order['branch_name']}**\n"
            "🆔 ID: `#ORD-$orderId`\n"
            "-------------------------\n"
            "✅ Filial yukni skanerladi va qabul qildi.";
        for (var admin in admins) {
          await sendMessage(admin['chatId'], adminMsg);
        }
        return;
      }

      // --- CASE 2: ASSET SEARCH (Standard) ---
      final assets = await db.rawQuery(
        '''
        SELECT a.*, c.name as category_name, l.name as loc_name
        FROM assets a
        LEFT JOIN asset_categories c ON a.category_id = c.id
        LEFT JOIN asset_locations l ON a.location_id = l.id
        WHERE a.barcode = ?
      ''',
        [barcode],
      );

      if (assets.isEmpty) {
        await sendMessage(
          chatId,
          "❌ Kechirasiz, bazada `$barcode` shtrix-kodli jihoz yoki buyurtma topilmadi.",
        );
      } else {
        final a = assets.first;
        String msg =
            "🖥 *JIHOZ TOPILDI!*\n"
            "-------------------------\n"
            "📦 *${a['name']}*\n"
            "   - Tur: ${a['category_name'] ?? 'Noma\'lum'}\n"
            "   - Model: ${a['model'] ?? '-'}\n"
            "   - Seriya: `${a['serial_number'] ?? '-'}`\n"
            "   - Rangi: ${a['color'] ?? '-'}\n"
            "   📍 Joyi: *${a['loc_name'] ?? 'Noma\'lum'}*\n"
            "   🛠 Holati: ${a['status']}\n"
            "   🔢 Barcode: `${a['barcode']}`\n"
            "-------------------------";
        await sendMessage(chatId, msg);
      }
    } catch (e) {
      debugPrint("Barcode Error: $e");
      await sendMessage(
        chatId,
        "❌ *Xatolik:* Rasmdan shtrix-kodni o'qib bo'lmadi. \n\nIltimos, rasmni aniqroq olib qayta yuboring.",
      );
    }
  }

  Future<void> _sendMainMenu(String chatId, String text, {String? role}) async {
    List<List<Map<String, String>>> keyboard = [];

    if (role == 'admin') {
      keyboard = [
        [
          {"text": "📊 Bugungi Holat"},
          {"text": "💰 Umumiy Hisobot"},
        ],
        [
          {"text": "🧠 AI Analizator"},
        ],
        [
          {"text": "⚠️ Kam Qolganlar"},
          {"text": "🖥 Jihozlar"},
        ],
        [
          {"text": "🔄 Oxirgi Harakatlar"},
          {"text": "🔎 Mahsulot Qidirish"},
        ],
        [
          {"text": "📥 Excel Hisobot Yuklash"},
          {"text": "🔄 Yangilash"},
        ],
      ];
    } else if (role == 'branch') {
      keyboard = [
        [
          {"text": "📷 Foto Buyurtma"},
          {"text": "📷 QR Skanerlash"},
        ],
        [
          {"text": "📝 Buyurtma Holati"},
        ],
        [
          {"text": "🔄 Yangilash"},
        ],
      ];
    } else {
      keyboard = [
        [
          {"text": "🔎 Mahsulot Qidirish"},
          {"text": "🖥 Jihozlar"},
        ],
        [
          {"text": "🔄 Yangilash"},
        ],
      ];
    }

    final markup = {"keyboard": keyboard, "resize_keyboard": true};
    await sendMessage(chatId, text, replyMarkup: markup);
  }

  Future<void> _handleAIAnalytics(String chatId) async {
    try {
      debugPrint("🤖 [UltraAI] Starting analysis for $chatId");
      await sendMessage(chatId, "🧠 *ULTRA AI: Tahlil amalga oshirilmoqda...*");
      
      final db = await DatabaseHelper.instance.database;
      
      // 1. Financial: Real inventory value = current stock × last purchase price
      debugPrint("🤖 [UltraAI] Calculating Financials...");
      double totalStockValue = 0;
      try {
        final res = await db.rawQuery('''
          SELECT SUM(
            (
              (SELECT IFNULL(SUM(si.quantity), 0) FROM stock_in si WHERE si.product_id = p.id AND si.is_deleted = 0) - 
              (SELECT IFNULL(SUM(so.quantity), 0) FROM stock_out so WHERE so.product_id = p.id AND so.is_deleted = 0)
            ) * IFNULL((SELECT si2.price_per_unit FROM stock_in si2 WHERE si2.product_id = p.id AND si2.is_deleted = 0 ORDER BY si2.date_time DESC LIMIT 1), 0)
          ) as total_val
          FROM products p WHERE p.is_deleted = 0
        ''');
        totalStockValue = (double.tryParse(res.first['total_val']?.toString() ?? '0')) ?? 0.0;
      } catch (e) {
        debugPrint("🤖 [UltraAI] Financials Error: $e");
      }

      // 2. Top movers — ALL TIME (no 30-day filter)
      debugPrint("🤖 [UltraAI] Fetching topOut...");
      List<Map<String, dynamic>> topOut = [];
      try {
        topOut = await db.rawQuery('''
          SELECT COALESCE(p.name, so.product_id) AS name, 
                 SUM(so.quantity) as qty,
                 COUNT(*) as ops
          FROM stock_out so 
          LEFT JOIN products p ON so.product_id = p.id 
          WHERE so.is_deleted = 0
          GROUP BY so.product_id ORDER BY qty DESC LIMIT 5
        ''');
      } catch (e) {
        debugPrint("🤖 [UltraAI] topOut Error: $e");
      }

      // 3. Current stock per product
      debugPrint("🤖 [UltraAI] Fetching inventory balance...");
      List<Map<String, dynamic>> stockBalance = [];
      try {
        stockBalance = await db.rawQuery('''
          SELECT p.name, p.unit,
            ROUND((SELECT IFNULL(SUM(quantity),0) FROM stock_in WHERE product_id = p.id AND is_deleted = 0) -
                  (SELECT IFNULL(SUM(quantity),0) FROM stock_out WHERE product_id = p.id AND is_deleted = 0), 2) AS stock,
            p.min_stock_alert
          FROM products p
          WHERE p.is_deleted = 0
          ORDER BY stock ASC
        ''');
      } catch (e) {
        debugPrint("🤖 [UltraAI] stockBalance Error: $e");
      }

      // 4. Shortage risks
      debugPrint("🤖 [UltraAI] Fetching shortageRisks...");
      List<Map<String, dynamic>> lowStockItems = stockBalance
          .where((r) => (r['stock'] as num? ?? 0) <= (r['min_stock_alert'] as num? ?? 0))
          .toList();

      // Build report
      StringBuffer sb = StringBuffer();
      sb.writeln("<b>🦁 ULTRA AI OMBORXONA TAHLILI</b>");
      sb.writeln("━━━━━━━━━━━━━━━━━━━━━━━━━━");
      sb.writeln("");

      // Financials
      sb.writeln("💰 <b>MOLIYAVIY KO'RSATKICHLAR:</b>");
      sb.writeln("   • Omborning haqiqiy qiymati: <b>${_formatMoney(totalStockValue)} so'm</b>");
      final totalIn = await db.rawQuery("SELECT COUNT(*) as c, IFNULL(SUM(quantity),0) as q FROM stock_in WHERE is_deleted=0");
      final totalOut = await db.rawQuery("SELECT COUNT(*) as c, IFNULL(SUM(quantity),0) as q FROM stock_out WHERE is_deleted=0");
      sb.writeln("   • Jami kirim operatsiyalar: <b>${totalIn.first['c']} ta</b> (${(totalIn.first['q'] as num?)?.round() ?? 0} dona)");
      sb.writeln("   • Jami chiqim operatsiyalar: <b>${totalOut.first['c']} ta</b> (${(totalOut.first['q'] as num?)?.round() ?? 0} dona)");
      sb.writeln("");

      // Current stock 
      sb.writeln("📦 <b>HOZIRGI ZAXIRA HOLATI:</b>");
      final displayStock = stockBalance.take(30).toList();
      for (var row in displayStock) {
        final stock = (row['stock'] as num? ?? 0);
        final min = (row['min_stock_alert'] as num? ?? 0);
        final icon = stock <= 0 ? "🔴" : (stock <= min ? "⚠️" : "✅");
        final name = _e(row['name']);
        sb.writeln("   $icon <b>$name</b>: ${stock.toStringAsFixed(1)} ${_e(row['unit'])}");
      }
      if (stockBalance.length > 30) {
        sb.writeln("   ... (va yana ${stockBalance.length - 30} ta mahsulot)");
      }
      sb.writeln("");

      // Top movers
      sb.writeln("🔥 <b>ENG KO'P SARFLANGAN (Top-5):</b>");
      if (topOut.isEmpty) {
        sb.writeln("   ➖ Chiqim operatsiyalar yo'q.");
      } else {
        for (var row in topOut) {
          String name = _e(row['name']);
          sb.writeln("   🔺 <b>$name</b> — ${row['qty']} dona (${row['ops']} marta)");
        }
      }
      sb.writeln("");

      // Shortage warnings
      sb.writeln("🚨 <b>DIQQAT — KAM QOLGANLAR:</b>");
      if (lowStockItems.isEmpty) {
        sb.writeln("   ✅ Barcha zaxiralar normal darajada.");
      } else {
        final displayLow = lowStockItems.take(20).toList();
        for (var row in displayLow) {
          String name = _e(row['name']);
          sb.writeln("   ❗ <b>$name</b>: ${(row['stock'] as num).toStringAsFixed(1)} qoldi (min: ${row['min_stock_alert']})");
        }
        if (lowStockItems.length > 20) {
          sb.writeln("   ... (va yana ${lowStockItems.length - 20} ta tanqislik)");
        }
      }
      sb.writeln("");

      // Recommendations
      sb.writeln("💡 <b>TAVSIYALAR:</b>");
      if (lowStockItems.isNotEmpty) {
        sb.writeln("   1. ❗ Kam qolgan mahsulotlarni <b>shoshilinch buyurtma qiling</b>.");
        sb.writeln("   2.📋 Yetkazuvchilar bilan aloqa o'rnating.");
      } else {
        sb.writeln("   1. ✅ Hozirgi zaxira strategiyasini davom ettiring.");
        sb.writeln("   2. 📊 Har hafta inventarizatsiya hisobotini tekshiring.");
      }
      sb.writeln("");
      sb.writeln("━━━━━━━━━━━━━━━━━━━━━━━━━━");
      sb.writeln("#ultra_ai #omborxona");

      debugPrint("🤖 [UltraAI] Sending report to $chatId...");
      final error = await _sendHtmlMessage(chatId, sb.toString());
      if (error != null) {
        // Fallback or truncated send...
      }
      
    } catch (e) {
      debugPrint("🤖 [UltraAI] Global Error: $e");
      try {
        await sendMessage(chatId, "❌ Ultra AI: Tahlil xatosi yuz berdi. Iltimos keyinroq urinib ko'ring.");
      } catch (_) {}
    }
  }

  // --- PDF Invoicing ---
  Future<void> _handleSendInvoice(String chatId, Map<String, dynamic> transaction, String type) async {
    try {
      await sendMessage(chatId, "⏳ <b>Invoy-faktura (PDF) tayyorlanmoqda...</b>", parseMode: 'HTML');
      final file = await PdfService.generateTransactionInvoice(transaction: transaction, type: type);
      
      await sendDocument(
        chatId, 
        file, 
        caption: "📄 <b>${type == 'in' ? 'Kirim' : 'Chiqim'} hujjati (#${transaction['id']})</b>",
        parseMode: 'HTML'
      );
    } catch (e) {
      await sendMessage(chatId, "⚠️ PDF yuborishda xatolik: $e");
    }
  }

  // --- Helpers ---
  String _e(dynamic val) {
    if (val == null) return '';
    return val.toString()
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  Future<void> _handleSendAssetLabel(String chatId, int aid) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final assets = await db.rawQuery('''
        SELECT a.*, c.name as category_name, l.name as location_name
        FROM assets a
        LEFT JOIN asset_categories c ON a.category_id = c.id
        LEFT JOIN asset_locations l ON a.location_id = l.id
        WHERE a.id = ? AND a.is_deleted = 0
      ''', [aid]);

      if (assets.isEmpty) {
        await sendMessage(chatId, "❌ Jihoz topilmadi.");
        return;
      }

      final a = assets.first;
      await sendMessage(chatId, "⏳ <b>Etiketka (ID: #${a['id']}) generatsiya qilinmoqda...</b>", parseMode: 'HTML');

      // Generate Image using 'image' and 'barcode' packages
      final bytes = await _generateAssetLabelBytes(a);
      
      final info = StringBuffer();
      info.writeln("📦 <b>${_e(a['name'])}</b>");
      info.writeln("📍 ${_e(a['location_name'])}");
      info.writeln("🔢 ${_e(a['barcode'])}");

      await sendPhotoBytes(chatId, bytes, caption: info.toString(), parseMode: 'HTML');
    } catch (e) {
      debugPrint("❌ Generate Label Error: $e");
      await sendMessage(chatId, "⚠️ Etiketka generatsiya qilishda xatolik yub berdi: $e");
    }
  }

  Future<Uint8List> _generateAssetLabelBytes(Map<String, dynamic> asset) async {
    // 1. Create a 600x400 white canvas
    final image = img.Image(width: 600, height: 400);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));

    // 2. Draw Text (Header)
    img.drawString(image, "OBI CLINICAL WAREHOUSE", font: img.arial24, x: 20, y: 15, color: img.ColorRgb8(0, 50, 200));
    img.drawLine(image, x1: 20, y1: 50, x2: 580, y2: 50, color: img.ColorRgb8(100, 100, 100));

    // 3. Asset Basic Info
    final fontTitle = img.arial48;
    final fontNormal = img.arial24;

    img.drawString(image, asset['name']?.toString() ?? '', font: fontTitle, x: 20, y: 70, color: img.ColorRgb8(0, 0, 0));
    img.drawString(image, "Tur: ${asset['category_name'] ?? '-'}", font: fontNormal, x: 20, y: 130, color: img.ColorRgb8(50, 50, 50));
    img.drawString(image, "Brend: ${asset['brand'] ?? '-'}", font: fontNormal, x: 20, y: 165, color: img.ColorRgb8(50, 50, 50));
    img.drawString(image, "Model: ${asset['model'] ?? '-'}", font: fontNormal, x: 20, y: 200, color: img.ColorRgb8(50, 50, 50));
    img.drawString(image, "SN: ${asset['serial_number'] ?? '-'}", font: fontNormal, x: 20, y: 235, color: img.ColorRgb8(50, 50, 50));

    // 4. Generate Barcode Bars using 'barcode' package
    final bcValue = asset['barcode']?.toString() ?? 'NO-BC';
    try {
      final bc = Barcode.code128();
      // Generate the internal data
      final bars = bc.make(bcValue, width: 400, height: 80);
      
      const baseX = 100;
      const baseY = 290;
      
    for (var bar in bars) {
      if (bar is BarcodeBar && bar.black) {
        img.fillRect(
           image, 
           x1: (baseX + bar.left).toInt(), 
           y1: baseY, 
           x2: (baseX + bar.left + bar.width).toInt(), 
           y2: baseY + 70, 
           color: img.ColorRgb8(0,0,0)
        );
      }
    }
    // Add text below barcode
    img.drawString(image, bcValue, font: fontNormal, x: 220, y: 365, color: img.ColorRgb8(0, 0, 0));
  } catch (e) {
     img.drawString(image, "BARCODE ERROR: $bcValue", font: fontNormal, x: 20, y: 300, color: img.ColorRgb8(200, 0, 0));
  }

  return Uint8List.fromList(img.encodePng(image));
}

}
