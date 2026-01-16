import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/database/database_helper.dart';
import 'package:intl/intl.dart';

class TelegramService {
  static const String _baseUrl = 'https://api.telegram.org/bot';
  static const String _keyBotToken = 'telegram_bot_token';
  static const String _keyUsers = 'telegram_users';

  // --- Configuration ---

  Future<String?> getBotToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBotToken);
  }

  Future<void> saveBotToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBotToken, token.trim());
  }

  // --- User Management ---

  Future<List<Map<String, dynamic>>> getUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyUsers);
    if (raw == null) return [];
    return List<Map<String, dynamic>>.from(jsonDecode(raw));
  }

  Future<void> addUser(String name, String chatId, String role) async {
    final users = await getUsers();
    users.add({'name': name, 'chatId': chatId, 'role': role});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsers, jsonEncode(users));
  }
  
  Future<void> deleteUser(String chatId) async {
    final users = await getUsers();
    users.removeWhere((u) => u['chatId'] == chatId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsers, jsonEncode(users));
  }

  // --- API Actions ---

  Future<String?> sendMessage(String chatId, String text, {Map<String, dynamic>? replyMarkup}) async {
    final token = await getBotToken();
    if (token == null || token.isEmpty) return "Bot tokeni sozlanmagan";

    try {
      final url = Uri.parse('$_baseUrl$token/sendMessage');
      final body = {
        'chat_id': chatId, 
        'text': text, 
        'parse_mode': 'Markdown',
      };
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
      print('Telegram Error: $e');
      return "Internet xatosi: $e";
    }
  }

  Future<void> answerCallbackQuery(String callbackQueryId) async {
    final token = await getBotToken();
    if (token == null) return;
    final url = Uri.parse('$_baseUrl$token/answerCallbackQuery');
    await http.post(url, body: {'callback_query_id': callbackQueryId});
  }

  Future<void> editMessageText(String chatId, int messageId, String text, {Map<String, dynamic>? replyMarkup}) async {
    final token = await getBotToken();
    if (token == null) return;
    try {
      final url = Uri.parse('$_baseUrl$token/editMessageText');
      final body = {
        'chat_id': chatId,
        'message_id': messageId.toString(),
        'text': text,
        'parse_mode': 'Markdown',
      };
      if (replyMarkup != null) {
        body['reply_markup'] = jsonEncode(replyMarkup);
      }
      await http.post(url, body: body);
    } catch (e) {
      print('EditMsg Error: $e');
    }
  }

  Future<String?> sendDocument(String chatId, File file, {String? caption}) async {
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
    } catch (e) {}
    return [];
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
        final List<Map<String, dynamic>> lowStockItems = await databaseHelperInstance.getLowStockProducts();
        if (lowStockItems.isNotEmpty) {
           final users = await getUsers();
           final sb = StringBuffer();
           sb.writeln("⚠️ *DIQQAT: MAHSULOTLAR TUGAMOQDA!* ⚠️\n");
           for (int i = 0; i < lowStockItems.length && i < 20; i++) {
             sb.writeln("${i + 1}. *${lowStockItems[i]['name']}* - ${lowStockItems[i]['stock']} ${lowStockItems[i]['unit']}");
           }
           final message = sb.toString();
           for (var user in users) await sendMessage(user['chatId'], message);
           await prefs.setString(_keyLastAlertDate, todayStr);
        }
      } catch (e) {}
    }
  }

  Future<void> sendDailyReport(dynamic databaseHelperInstance) async {
    try {
      final users = await getUsers();
      if (users.isEmpty) return;
      final stats = await databaseHelperInstance.getDashboardStatusToday();
      final now = DateTime.now();
      final dateStr = "${now.day}.${now.month}.${now.year}";
      final sumStr = stats['in_sum'].toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]} ');
      final msg = "📅 *KUNLIK HISOBOT*\nSana: $dateStr\n-------------------------\n📉 *Kirim:* ${stats['in_count']} ta (${sumStr} so'm)\n📈 *Chiqim:* ${stats['out_count']} ta\n-------------------------";
      for (var user in users) await sendMessage(user['chatId'], msg);
    } catch (e) {}
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

  Future<void> checkWeeklyBackup(final databaseHelperInstance) async {
    final prefs = await SharedPreferences.getInstance();
    final currentWeek = (DateTime.now().millisecondsSinceEpoch / (1000 * 60 * 60 * 24 * 7)).floor();
    if (currentWeek > (prefs.getInt(_keyLastBackupWeek) ?? 0)) {
      final users = await getUsers();
      if (users.isEmpty) return;
      try {
        final path = await databaseHelperInstance.createBackup(null);
        if (path != null) {
          final error = await sendDocument(users.first['chatId'], File(path), caption: "🛡️ Avtomatik Haftalik Zaxira");
          if (error == null) await prefs.setInt(_keyLastBackupWeek, currentWeek);
        }
      } catch (e) {}
    }
  }

  // --- BOT LISTENER (Interactive Mode) ---
  bool _isListening = false;
  int _lastUpdateId = 0;

  void startBotListener() async {
    if (_isListening) return;
    _isListening = true;
    print("🤖 Telegram Bot: Polling started...");
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
    final url = Uri.parse('$_baseUrl$token/getUpdates?offset=${_lastUpdateId + 1}&timeout=10');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['ok'] == true) {
        for (var u in data['result']) {
          _lastUpdateId = u['update_id'];
          if (u['message'] != null) await _processMessage(u['message']);
          if (u['callback_query'] != null) await _processCallbackQuery(u['callback_query']);
        }
      }
    }
  }

  Future<void> _processMessage(Map<String, dynamic> msg) async {
    final chatId = msg['chat']['id'].toString();
    final text = msg['text']?.toString() ?? '';
    final users = await getUsers();
    if (!users.any((u) => u['chatId'] == chatId)) {
       await sendMessage(chatId, "⛔️ Ro'yxatdan o'tmagansiz. ID: $chatId");
       return;
    }

    if (text == '/start' || text.contains("Yangilash")) {
      await _sendMainMenu(chatId, "👋 Assalomu alaykum! Omborxona xizmatiga xush kelibsiz.");
    } else if (text.contains("Bugungi Holat")) {
      await _handleTodayStats(chatId);
    } else if (text.contains("Umumiy Hisobot")) {
      await _handleTotalStats(chatId);
    } else if (text.contains("Kam Qolganlar")) {
      await _handleLowStock(chatId);
    } else if (text.contains("Jihozlar")) {
      await _handleAssetsStatMenu(chatId);
    } else if (text.contains("Oxirgi Harakatlar")) {
      await _handleRecentActivity(chatId);
    } else if (text.contains("Mahsulot Qidirish")) {
      await sendMessage(chatId, "🔍 Qidirish uchun nomini yozing:");
    } else if (text.length > 2) {
      await _handleSearchProduct(chatId, text);
    }
  }

  Future<void> _processCallbackQuery(Map<String, dynamic> query) async {
    final chatId = query['message']['chat']['id'].toString();
    final messageId = query['message']['message_id'];
    final data = query['data']?.toString() ?? '';
    
    await answerCallbackQuery(query['id']);

    if (data.startsWith('asset_loc:')) {
      final locId = int.tryParse(data.split(':')[1]);
      if (locId != null) await _handleShowLocation(chatId, messageId, locId);
    } else if (data == 'asset_root') {
      await _handleAssetsStatMenu(chatId, messageId: messageId);
    }
  }

  // --- Handlers ---

  Future<void> _handleAssetsStatMenu(String chatId, {int? messageId}) async {
    final db = await DatabaseHelper.instance.database;
    final buildings = await db.query('asset_locations', where: 'parent_id IS NULL');
    
    final buttons = <List<Map<String, dynamic>>>[];
    for (var b in buildings) {
      buttons.add([{'text': "🏢 ${b['name']}", 'callback_data': "asset_loc:${b['id']}"}]);
    }

    final markup = {'inline_keyboard': buttons};
    final text = "🖥 *Jihozlar bo'limi*\n\nIltimos, kerakli binoni tanlang:";

    if (messageId != null) {
      await editMessageText(chatId, messageId, text, replyMarkup: markup);
    } else {
      await sendMessage(chatId, text, replyMarkup: markup);
    }
  }

  Future<void> _handleShowLocation(String chatId, int messageId, int locId) async {
    final db = await DatabaseHelper.instance.database;
    
    // 1. Get current location info
    final currentLoc = (await db.query('asset_locations', where: 'id = ?', whereArgs: [locId])).first;
    
    // 2. Get sub-locations (Floors/Rooms)
    final subLocs = await db.query('asset_locations', where: 'parent_id = ?', whereArgs: [locId]);
    
    // 3. Get assets in this location
    final assets = await db.query('assets', where: 'location_id = ?', whereArgs: [locId]);

    final buttons = <List<Map<String, dynamic>>>[];
    
    // Add sub-locations as buttons
    for (var sl in subLocs) {
      String prefix = sl['type'] == 'floor' ? '📶' : '🚪';
      buttons.add([{'text': "$prefix ${sl['name']}", 'callback_data': "asset_loc:${sl['id']}"}]);
    }

    // Back button
    final parentId = currentLoc['parent_id'];
    buttons.add([{'text': "⬅️ Orqaga", 'callback_data': parentId == null ? 'asset_root' : "asset_loc:$parentId"}]);

    final markup = {'inline_keyboard': buttons};
    
    String text = "📍 *Manzil:* ${currentLoc['name']}\n";
    if (assets.isNotEmpty) {
      text += "\n📦 *Bu yerdagi jihozlar:* (${assets.length} ta)\n";
      for (var a in assets) {
        text += "   ▫️ ${a['name']} (${a['status']})\n";
      }
    } else if (subLocs.isEmpty) {
      text += "\n📭 Bu yerda hozircha jihozlar yo'q.";
    } else {
      text += "\n👇 Kerakli bo'limni tanlang:";
    }

    await editMessageText(chatId, messageId, text, replyMarkup: markup);
  }

  Future<void> _handleTodayStats(String chatId) async {
    final stats = await DatabaseHelper.instance.getDashboardStatusToday();
    final formatter = NumberFormat("#,###");
    final msg = "📊 *BUGUNGI HISOBOT*\n-------------------------\n📥 *Kirim:* ${stats['in_count']} ta (${formatter.format(stats['in_sum'])} so'm)\n📤 *Chiqim:* ${stats['out_count']} ta\n-------------------------";
    await sendMessage(chatId, msg);
  }

  Future<void> _handleTotalStats(String chatId) async {
    final stats = await DatabaseHelper.instance.getDashboardStats();
    final formatter = NumberFormat("#,###");
    final msg = "💰 *OMBOR HOLATI*\n-------------------------\n💵 Qiymat: *${formatter.format(stats['total_value'])}* so'm\n📉 Kam qolgan: ${stats['low_stock']} ta\n🚫 Tugagan: ${stats['finished']} ta\n-------------------------";
    await sendMessage(chatId, msg);
  }

  Future<void> _handleLowStock(String chatId) async {
    final items = await DatabaseHelper.instance.getLowStockProducts();
    if (items.isEmpty) { await sendMessage(chatId, "✅ Hamma narsa yetarli."); return; }
    String list = "⚠️ *Kam qolganlar:*\n\n";
    for (var i = 0; i < items.length && i < 10; i++) list += "${i+1}. ${items[i]['name']} — *${items[i]['stock']}*\n";
    await sendMessage(chatId, list);
  }

  Future<void> _handleRecentActivity(String chatId) async {
    final activity = await DatabaseHelper.instance.getRecentActivity();
    if (activity.isEmpty) { await sendMessage(chatId, "📭 Harakat yo'q."); return; }
    String list = "🔄 *Oxirgi harakatlar:*\n\n";
    for (var item in activity) {
      final icon = item['type'] == 'in' ? "📥" : "📤";
      list += "$icon *${item['product_name']}* (${item['quantity']})\n   🕒 ${item['date_time']}\n";
    }
    await sendMessage(chatId, list);
  }

  Future<void> _handleSearchProduct(String chatId, String query) async {
    final db = await DatabaseHelper.instance.database;
    final sanitized = '%$query%';
    final productResults = await db.rawQuery('SELECT name, unit, ((SELECT IFNULL(SUM(quantity), 0) FROM stock_in WHERE product_id = p.id) - (SELECT IFNULL(SUM(quantity), 0) FROM stock_out WHERE product_id = p.id)) as stock FROM products p WHERE name LIKE ? LIMIT 5', [sanitized]);
    final assetResults = await db.rawQuery('SELECT a.name, a.model, l.name as loc_name FROM assets a LEFT JOIN asset_locations l ON a.location_id = l.id WHERE a.name LIKE ? LIMIT 5', [sanitized]);
    
    if (productResults.isEmpty && assetResults.isEmpty) { await sendMessage(chatId, "📌 Topilmadi."); return; }
    String list = "🔎 *NATIJALAR:*\n\n";
    if (productResults.isNotEmpty) {
      list += "📦 *MAHSULOTLAR:*\n";
      for (var item in productResults) list += "▫️ ${item['name']} (*${item['stock']} ${item['unit']}*)\n";
      list += "\n";
    }
    if (assetResults.isNotEmpty) {
      list += "🖥 *JIHOZLAR:*\n";
      for (var item in assetResults) list += "▫️ ${item['name']} 📍 ${item['loc_name']}\n";
    }
    await sendMessage(chatId, list);
  }

  Future<void> _sendMainMenu(String chatId, String text) async {
    final markup = {
      "keyboard": [
        [{"text": "📊 Bugungi Holat"}, {"text": "💰 Umumiy Hisobot"}],
        [{"text": "⚠️ Kam Qolganlar"}, {"text": "🖥 Jihozlar"}],
        [{"text": "🔄 Oxirgi Harakatlar"}, {"text": "🔎 Mahsulot Qidirish"}],
        [{"text": "🔄 Yangilash"}]
      ],
      "resize_keyboard": true
    };
    await sendMessage(chatId, text, replyMarkup: markup);
  }
}
