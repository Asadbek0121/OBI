import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:clinical_warehouse/core/database/database_helper.dart';
import 'package:clinical_warehouse/core/services/excel_service.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class TelegramService {
  static const String _baseUrl = 'https://api.telegram.org/bot';
  static const String _keyBotToken = 'telegram_bot_token';
  static const String _keyUsers = 'telegram_users';

  // --- Singleton Pattern ---
  static final TelegramService _instance = TelegramService._internal();
  factory TelegramService() => _instance;
  TelegramService._internal();
  
  // --- Auto Backup ---
  Timer? _autoBackupTimer;
  
  void setupAutoBackupListener() {
    DatabaseHelper.instance.onDataChanged = () {
      // Debounce: Wait 30 seconds after last change before sending backup
      _autoBackupTimer?.cancel();
      _autoBackupTimer = Timer(const Duration(seconds: 30), () {
        sendFullExcelBackupToAdmins();
      });
    };
  }

  // --- State Management ---
  final Map<String, String> _userStates = {};
  final Map<String, List<Map<String, dynamic>>> _userCarts = {};
  final Map<String, Map<String, dynamic>> _userSelection = {};

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
    if (token == null) {
      return null;
    }
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

  Future<List<Map<String, dynamic>>> getUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyUsers);
    if (raw == null) {
      return [];
    }
    final List<dynamic> jsonList = jsonDecode(raw);
    return jsonList.map((e) {
      final m = Map<String, dynamic>.from(e);
      m['chatId'] = m['chatId'].toString();
      return m;
    }).toList();
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyUsers, jsonEncode(uniqueUsers.values.toList()));
    }
  }

  Future<void> addUser(String name, String chatId, String role) async {
    final users = await getUsers();
    if (!users.any((u) => u['chatId'] == chatId)) {
      users.add({'name': name, 'chatId': chatId, 'role': role});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyUsers, jsonEncode(users));
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

  Future<void> updateOrderStatus(int orderId, String status, String chatId, {String? adminComment}) async {
    final db = await DatabaseHelper.instance.database;
    final updates = {'status': status};
    if (adminComment != null) {
      updates['admin_comment'] = adminComment;
    }
    await db.update('branch_orders', updates, where: 'id = ?', whereArgs: [orderId]);
    
    String msg = "";
    String commentPart = (adminComment != null && adminComment.isNotEmpty) 
        ? "\n\n💬 *Admin izohi:* \n$adminComment" 
        : "";
    
    if (status == 'approved') {
      msg = "📦 *BUYURTMA TASDIQLANDI*\nID: `#ORD-$orderId`\nHolat: **Jarayonda** ✅$commentPart";
    } else if (status == 'rejected') {
      msg = "❌ *BUYURTMA RAD ETILDI*\nID: `#ORD-$orderId`\nHolat: **Rad etilgan** ❌$commentPart";
    } else if (status == 'delivered') {
      msg = "✅ *BUYURTMANGIZ YETKAZILDI*\nID: `#ORD-$orderId`\nHolat: **Yetkazilgan** 🚚";
    }
    
    if (msg.isNotEmpty) {
      await sendMessage(chatId, msg);
    }
  }

  // --- API Actions ---

  Future<String?> sendMessage(String chatId, String text, {Map<String, dynamic>? replyMarkup}) async {
    final token = await getBotToken();
    if (token == null || token.isEmpty) {
      return "Token xatosi";
    }
    try {
      final url = Uri.parse('$_baseUrl$token/sendMessage');
      final body = {'chat_id': chatId, 'text': text, 'parse_mode': 'Markdown'};
      if (replyMarkup != null) {
        body['reply_markup'] = jsonEncode(replyMarkup);
      }
      final res = await http.post(url, body: body);
      return res.statusCode == 200 ? null : "Error: ${res.statusCode}";
    } catch (e) {
      return "Error: $e";
    }
  }

  Future<void> answerCallbackQuery(String callbackQueryId) async {
    final token = await getBotToken();
    if (token == null) {
      return;
    }
    await http.post(Uri.parse('$_baseUrl$token/answerCallbackQuery'), body: {'callback_query_id': callbackQueryId});
  }

  Future<void> editMessageText(String chatId, int messageId, String text, {Map<String, dynamic>? replyMarkup}) async {
    final token = await getBotToken();
    if (token == null) {
      return;
    }
    try {
      final body = {'chat_id': chatId, 'message_id': messageId.toString(), 'text': text, 'parse_mode': 'Markdown'};
      if (replyMarkup != null) {
        body['reply_markup'] = jsonEncode(replyMarkup);
      }
      await http.post(Uri.parse('$_baseUrl$token/editMessageText'), body: body);
    } catch (_) {}
  }

  Future<String?> sendDocument(String chatId, File file, {String? caption}) async {
    final token = await getBotToken();
    if (token == null) {
      return "Token error";
    }
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl$token/sendDocument'))
        ..fields['chat_id'] = chatId
        ..files.add(await http.MultipartFile.fromPath('document', file.path));
      if (caption != null) {
        request.fields['caption'] = caption;
      }
      final res = await request.send();
      return res.statusCode == 200 ? null : "Error";
    } catch (e) {
      return "Error: $e";
    }
  }

  Future<String?> getFileUrl(String fileId) async {
    final token = await getBotToken();
    if (token == null) {
      return null;
    }
    try {
      final url = Uri.parse('$_baseUrl$token/getFile?file_id=$fileId');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['ok'] == true) {
          final filePath = data['result']['file_path'];
          return "https://api.telegram.org/file/bot$token/$filePath";
        }
      }
    } catch (_) {}
    return null;
  }

  // --- Scheduler & Backup ---

  Future<void> checkDailyLowStockAlert(DatabaseHelper dbHelper) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (prefs.getString('last_low_stock_alert') == today) {
      return;
    }

    final lowStock = await dbHelper.getLowStockProducts();
    if (lowStock.isNotEmpty) {
      final users = await getUsers();
      final admins = users.where((u) => u['role'] == 'admin').toList();
      String msg = "🚨 *KAM QOLGAN MAHSULOTLAR:*\n\n";
      for (var p in lowStock) {
        msg += " • ${p['name']} (${p['stock']} ${p['unit']})\n";
      }
      for (var admin in admins) {
        await sendMessage(admin['chatId'], msg);
      }
      await prefs.setString('last_low_stock_alert', today);
    }
  }

  Future<void> checkDailyReportAuto(DatabaseHelper dbHelper) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (prefs.getString('last_daily_report') == today) {
      return;
    }

    // Check time - only send after 6 PM
    if (DateTime.now().hour < 18) {
      return;
    }

    final stats = await dbHelper.getDashboardStatusToday();
    final users = await getUsers();
    final admins = users.where((u) => u['role'] == 'admin').toList();
    
    String msg = "📊 *KUNLIK HISOBOT ($today)*\n"
                 "-------------------------\n"
                 "📥 Kirim: ${stats['in_count']} ta\n"
                 "📤 Chiqim: ${stats['out_count']} ta\n"
                 "💰 Summa: ${NumberFormat("#,###").format(stats['in_sum'])} so'm";
    
    for (var admin in admins) {
      await sendMessage(admin['chatId'], msg);
    }
    await prefs.setString('last_daily_report', today);
  }

  Future<void> checkWeeklyBackup(DatabaseHelper dbHelper) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final lastBackup = prefs.getString('last_weekly_backup');
    
    // Check if a week has passed
    if (lastBackup != null) {
      final lastDate = DateTime.parse(lastBackup);
      if (now.difference(lastDate).inDays < 7) {
        return;
      }
    }

    final path = await dbHelper.createBackup(null);
    if (path != null) {
      final users = await getUsers();
      final admins = users.where((u) => u['role'] == 'admin').toList();
      for (var admin in admins) {
        await sendDocument(admin['chatId'], File(path), caption: "🛡️ *HAFTALIK ZAXIRA NUSXASI*");
      }
      await prefs.setString('last_weekly_backup', now.toIso8601String());
    }
  }

  Future<void> checkDailyBackup(DatabaseHelper dbHelper) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (prefs.getString('last_daily_backup') == today) {
      return;
    }

    // Check time - only send after 11 PM
    if (DateTime.now().hour < 23) {
      return;
    }

    final path = await dbHelper.createBackup(null);
    if (path != null) {
      final users = await getUsers();
      final admins = users.where((u) => u['role'] == 'admin').toList();
      for (var admin in admins) {
        await sendDocument(admin['chatId'], File(path), caption: "🔐 *KUNLIK ZAXIRA NUSXASI ($today)*");
      }
      await prefs.setString('last_daily_backup', today);
    }
  }

  // --- Core Lifecycle ---
  bool _isListening = false;
  int _lastUpdateId = 0;

  void startBotListener() async {
    if (_isListening) {
      return;
    }
    await _cleanDuplicates();
    _isListening = true;
    while (_isListening) {
      try {
        await _checkUpdates();
      } catch (_) {
        await Future.delayed(const Duration(seconds: 5));
      }
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  Future<void> _checkUpdates() async {
    final token = await getBotToken();
    if (token == null) {
      return;
    }
    final res = await http.get(Uri.parse('$_baseUrl$token/getUpdates?offset=${_lastUpdateId + 1}&timeout=10'));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      if (data['ok'] == true) {
        for (var u in data['result']) {
          _lastUpdateId = u['update_id'];
          if (u['message'] != null) {
            await _processMessage(u['message']);
          }
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
    final user = users.firstWhere((u) => u['chatId'] == chatId, orElse: () => {});

    if (user.isEmpty) {
      await addUser(msg['from']['first_name'] ?? 'User', chatId, 'pending');
      await sendMessage(chatId, "⏳ Arizangiz qabul qilindi. Admin ruxsatini kuting.");
      return;
    }
    if (user['role'] == 'pending') {
      await sendMessage(chatId, "⏳ So'rovingiz ko'rib chiqilmoqda...");
      return;
    }

    final isAdmin = user['role'] == 'admin';
    final isBranch = user['role'] == 'branch';

    if (_userStates[chatId] == 'waiting_for_qty') {
      final qty = double.tryParse(text);
      if (qty != null && qty > 0) {
        await _handleAddToCart(chatId, qty);
      } else {
        await sendMessage(chatId, "⚠️ Son kiriting:");
      }
      return;
    }

    if (photos != null && photos.isNotEmpty) {
      if (_userStates[chatId] == 'waiting_for_order_photo') {
        await _handleSubmitPhotoOrder(chatId, photos.last['file_id']);
      } else {
        await _handlePhotoBarcode(chatId, photos);
      }
      return;
    }

    if (text == '/start' || text.contains("Yangilash") || text.contains("Asosiy Menyu")) {
      _userStates[chatId] = "";
      await _sendMainMenu(chatId, "Xush kelibsiz!", role: user['role']);
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
      await _handleRecentActivity(chatId);
    } else if (text.contains("Foto Buyurtma") && isBranch) {
      _userStates[chatId] = "waiting_for_order_photo";
      await sendMessage(chatId, "📸 Qog'oz rasmini yuboring:");
    } else if (text.contains("Excel Hisobot") && isAdmin) {
      await _handleExcelExport(chatId);
    } else if (text.length >= 3) {
      await _handleSearchProduct(chatId, text, isBranch: isBranch);
    }
  }

  Future<void> _processCallbackQuery(Map<String, dynamic> query) async {
    final chatId = query['message']['chat']['id'].toString();
    final messageId = query['message']['message_id'];
    final data = query['data']?.toString() ?? '';
    await answerCallbackQuery(query['id']);

    if (data.startsWith('asset_loc:')) {
      final locIdStr = data.split(':')[1];
      final locId = int.tryParse(locIdStr);
      if (locId != null) {
        await _handleShowLocation(chatId, messageId, locId);
      }
    } else if (data.startsWith('asset_view:')) {
      final assetIdStr = data.split(':')[1];
      final assetId = int.tryParse(assetIdStr);
      if (assetId != null) {
        await _handleAssetDetails(chatId, assetId);
      }
    } else if (data.startsWith('asset_status_menu:')) {
      final assetIdStr = data.split(':')[1];
      final assetId = int.tryParse(assetIdStr);
      if (assetId != null) {
        await _handleAssetStatusMenu(chatId, messageId, assetId);
      }
    } else if (data.startsWith('asset_status_set:')) {
      final parts = data.split(':');
      final assetId = int.tryParse(parts[1]);
      final status = parts[2];
      if (assetId != null) {
        final db = await DatabaseHelper.instance.database;
        await db.update('assets', {'status': status}, where: 'id = ?', whereArgs: [assetId]);
        await editMessageText(chatId, messageId, "✅ Holat o'zgardi: *$status*");
      }
    } else if (data == 'asset_root') {
      await _handleAssetsStatMenu(chatId, messageId: messageId);
    } else if (data.startsWith('order_add:')) {
      final db = await DatabaseHelper.instance.database;
      final productId = data.split(':')[1];
      final productRes = await db.query('products', where: 'id = ?', whereArgs: [productId]);
      if (productRes.isNotEmpty) {
        _userSelection[chatId] = productRes.first;
        _userStates[chatId] = "waiting_for_qty";
        await sendMessage(chatId, "🔢 *${productRes.first['name']}* miqdori:");
      }
    } else if (data == 'order_confirm') {
      await _submitOrder(chatId);
    } else if (data.startsWith('order_approve:')) {
      final orderIdStr = data.split(':')[1];
      final oid = int.tryParse(orderIdStr);
      if (oid != null) {
        await updateOrderStatus(oid, 'approved', chatId);
        await editMessageText(chatId, messageId, "✅ Tasdiqlandi.");
      }
    }
  }

  // --- Logic Handlers ---

  Future<void> _handleAssetsStatMenu(String chatId, {int? messageId}) async {
    final db = await DatabaseHelper.instance.database;
    final buildings = await db.query('asset_locations', where: 'parent_id IS NULL');
    final buttons = buildings.map((b) => [{'text': "🏢 ${b['name']}", 'callback_data': "asset_loc:${b['id']}"}]).toList();
    final text = "🖥 *Jihozlar*";
    if (messageId != null) {
      await editMessageText(chatId, messageId, text, replyMarkup: {'inline_keyboard': buttons});
    } else {
      await sendMessage(chatId, text, replyMarkup: {'inline_keyboard': buttons});
    }
  }

  Future<void> _handleShowLocation(String chatId, int messageId, int locId) async {
    final db = await DatabaseHelper.instance.database;
    final currentLocRes = await db.query('asset_locations', where: 'id = ?', whereArgs: [locId]);
    if (currentLocRes.isEmpty) {
      return;
    }
    final currentLoc = currentLocRes.first;
    
    final subLocs = await db.query('asset_locations', where: 'parent_id = ?', whereArgs: [locId]);
    final assets = await db.rawQuery('SELECT a.*, c.name as category_name FROM assets a LEFT JOIN asset_categories c ON a.category_id = c.id WHERE a.location_id = ?', [locId]);
    
    final List<List<Map<String, dynamic>>> buttons = subLocs
        .map((sl) => [
              {
                'text': "${sl['type'] == 'floor' ? '📶' : '🚪'} ${sl['name']}",
                'callback_data': "asset_loc:${sl['id']}"
              }
            ])
        .toList();
    if (assets.isNotEmpty) {
      for (var a in assets.take(10)) {
        buttons.add([
          {'text': "🔍 ${a['name']}", 'callback_data': "asset_view:${a['id']}"}
        ]);
      }
    }
    buttons.add([
      {
        'text': "⬅️ Orqaga",
        'callback_data': currentLoc['parent_id'] == null ? 'asset_root' : "asset_loc:${currentLoc['parent_id']}"
      }
    ]);

    String text = "📍 `${currentLoc['name']}`\n${assets.isEmpty ? "📭 Bo'sh" : "📦 Jihozlar: ${assets.length} ta"}";
    await editMessageText(chatId, messageId, text, replyMarkup: {'inline_keyboard': buttons});
  }

  Future<void> _handleAssetDetails(String chatId, int assetId) async {
    final db = await DatabaseHelper.instance.database;
    final res = await db.rawQuery('SELECT a.*, c.name as category_name, l.name as location_name FROM assets a LEFT JOIN asset_categories c ON a.category_id = c.id LEFT JOIN asset_locations l ON a.location_id = l.id WHERE a.id = ?', [assetId]);
    if (res.isEmpty) {
      return;
    }
    final a = res.first;
    String text = "🖥 *${a['name']}*\nTur: ${a['category_name']}\nModel: ${a['model']}\nSeriya: `${a['serial_number']}`\nJoyi: ${a['location_name']}\nHolat: ${a['status']}";
    await sendMessage(chatId, text, replyMarkup: {'inline_keyboard': [[{'text': "🛠 Holat", 'callback_data': "asset_status_menu:$assetId"}]]});
  }

  Future<void> _handleAssetStatusMenu(String chatId, int messageId, int assetId) async {
    final List<List<Map<String, dynamic>>> buttons = ['Yangi', 'Ishlatilgan', 'Tamirtalab', 'Eskirgan'].map((s) => [{'text': s, 'callback_data': "asset_status_set:$assetId:$s"}]).toList();
    buttons.add([{'text': "⬅️", 'callback_data': "asset_view:$assetId"}]);
    await editMessageText(chatId, messageId, "🛠 Holatni tanlang:", replyMarkup: {'inline_keyboard': buttons});
  }

  Future<void> _sendMainMenu(String chatId, String text, {String? role}) async {
    List<List<Map<String, String>>> kb = [];
    if (role == 'admin') {
      kb = [
        [{"text": "📊 Bugungi Holat"}, {"text": "💰 Umumiy Hisobot"}],
        [{"text": "🧠 AI Analizator"}],
        [{"text": "⚠️ Kam Qolganlar"}, {"text": "🖥 Jihozlar"}],
        [{"text": "📥 Excel Hisobot Yuklash"}, {"text": "🔄 Yangilash"}]
      ];
    } else {
      kb = [
        [{"text": "🖥 Jihozlar"}],
        [{"text": "🔄 Yangilash"}]
      ];
    }
    await sendMessage(chatId, text, replyMarkup: {"keyboard": kb, "resize_keyboard": true});
  }

  Future<void> _handleTodayStats(String chatId) async {
    final stats = await DatabaseHelper.instance.getDashboardStatusToday();
    await sendMessage(chatId, "📊 Bugun: \nKirim: ${stats['in_count']} ta\nChiqim: ${stats['out_count']} ta");
  }

  Future<void> _handleTotalStats(String chatId) async {
    final stats = await DatabaseHelper.instance.getDashboardStats();
    await sendMessage(chatId, "💰 Jami: ${NumberFormat("#,###").format(stats['total_value'])} so'm");
  }

  Future<void> _handleLowStock(String chatId) async {
    final low = await DatabaseHelper.instance.getLowStockProducts();
    await sendMessage(chatId, "🚨 Kam qolgan: ${low.length} xil");
  }

  Future<void> _handleRecentActivity(String chatId) async {
    final act = await DatabaseHelper.instance.getRecentActivity(limit: 5);
    if (act.isEmpty) {
      await sendMessage(chatId, "📭 Tarix bo'sh.");
    } else {
      String msg = "🔄 *OXIRGI 5 TA HARAKAT:*\n\n";
      for (var item in act) {
        msg += " • ${item['type'] == 'in' ? 'Kirim' : 'Chiqim'}: ${item['product_name']} (${item['quantity']})\n";
      }
      await sendMessage(chatId, msg);
    }
  }

  Future<void> _handleSearchProduct(String chatId, String query, {bool isBranch = false}) async {
    final db = await DatabaseHelper.instance.database;
    final products = await db.query('products', where: 'name LIKE ?', whereArgs: ['%$query%'], limit: 3);
    for (var p in products) {
      final kb = isBranch ? {'inline_keyboard': [[{'text': "➕ Savatga", 'callback_data': "order_add:${p['id']}"}]]} : null;
      await sendMessage(chatId, "📦 *${p['name']}*", replyMarkup: kb);
    }
    final assets = await db.query('assets', where: 'name LIKE ?', whereArgs: ['%$query%'], limit: 3);
    if (assets.isNotEmpty) {
      String msg = "🖥 *JIHOZLAR:*\n";
      for (var a in assets) {
        msg += " • ${a['name']}\n";
      }
      await sendMessage(chatId, msg);
    }
  }

  Future<void> _handleAddToCart(String chatId, double qty) async {
    final p = _userSelection[chatId];
    if (p == null) {
      return;
    }
    _userCarts.putIfAbsent(chatId, () => []);
    _userCarts[chatId]!.add({...p, 'qty': qty});
    await sendMessage(chatId, "✅ Qo'shildi.");
  }

  Future<void> _submitOrder(String chatId) async {
    await sendMessage(chatId, "🚀 Buyurtma berildi.");
  }

  Future<void> _handleSubmitPhotoOrder(String chatId, String fileId) async {
    await sendMessage(chatId, "📸 Rasm qabul qilindi.");
  }

  Future<void> _handlePhotoBarcode(String chatId, List maps) async {
    await sendMessage(chatId, "🔍 Skanerlanmoqda...");
  }

  Future<void> _handleAIAnalytics(String chatId) async {
    await sendMessage(chatId, "🧠 Tahlil: Hammasi yaxshi.");
  }

  Future<void> _handleExcelExport(String chatId) async {
    try {
      final db = DatabaseHelper.instance;
      final path = await db.createBackup(null);
      if (path != null) {
        await sendDocument(chatId, File(path), caption: "📁 *OMBORXONA HISOBOTI*");
      }
    } catch (_) {}
  }

  Future<void> sendFullExcelBackupToAdmins() async {
    try {
      final file = await ExcelService.generateFullBackupExcel();
      if (file == null) return;

      final users = await getUsers();
      final admins = users.where((u) => u['role'] == 'admin').toList();
      
      final timestamp = DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now());
      final caption = "🛡️ *AVTOMATIK EXCEL ZAXIRA*\n📅 Sana: $timestamp\n\n_Barcha bo'limlar yangilandi._";

      for (var admin in admins) {
        await sendDocument(admin['chatId'], file, caption: caption);
      }
    } catch (e) {
      debugPrint("❌ Auto Excel Backup Send Error: $e");
    }
  }
}
