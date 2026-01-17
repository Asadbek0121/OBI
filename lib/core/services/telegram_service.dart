import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/database/database_helper.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'package:zxing_lib/zxing.dart';
import 'package:zxing_lib/common.dart';
import 'package:zxing_lib/oned.dart';

class TelegramService {
  static const String _baseUrl = 'https://api.telegram.org/bot';
  static const String _keyBotToken = 'telegram_bot_token';
  static const String _keyUsers = 'telegram_users';

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
    if (prefs.containsKey('bot_username')) return prefs.getString('bot_username');
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

  Future<List<Map<String, dynamic>>> getUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyUsers);
    if (raw == null) return [];
    
    final List<dynamic> jsonList = jsonDecode(raw);
    return jsonList.map((e) {
      final m = Map<String, dynamic>.from(e);
      m['chatId'] = m['chatId'].toString(); // Ensure String
      return m;
    }).toList();
  }

  Future<void> _cleanDuplicates() async {
    final users = await getUsers();
    final uniqueUsers = <String, Map<String, dynamic>>{};
    
    for (var u in users) {
      final id = u['chatId'].toString();
      // If duplicate exists, prefer the one with a role other than pending
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
    if (adminComment != null) updates['admin_comment'] = adminComment;
    
    await db.update('branch_orders', updates, where: 'id = ?', whereArgs: [orderId]);
    
    String msg = "";
    String commentPart = (adminComment != null && adminComment.isNotEmpty) 
        ? "\n\n💬 *Admin izohi:* \n$adminComment" 
        : "";

    if (status == 'approved') {
      msg = "📦 *BUYURTMA TASDIQLANDI*\n"
            "-------------------------\n"
            "🆔 ID: `#ORD-$orderId`\n"
            "📊 Holat: **Tayyorlanmoqda** ✅\n"
            "$commentPart\n"
            "-------------------------\n"
            "🚚 *Tez orada yetkazib beriladi.*";
    } else if (status == 'rejected') {
      msg = "❌ *BUYURTMA RAD ETILDI*\n"
            "-------------------------\n"
            "🆔 ID: `#ORD-$orderId`\n"
            "📊 Holat: **Rad etilgan** ❌\n"
            "$commentPart\n"
            "-------------------------\n"
            "ℹ️ Iltimos, qayta tekshirib yuboring yoki admin bilan bog'laning.";
    } else if (status == 'delivered') {
      msg = "✅ *BUYURTMANGIZ YETKAZILDI*\n"
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

  Future<String?> sendPhotoByUrl(String chatId, String photoUrl, {String? caption}) async {
    final token = await getBotToken();
    if (token == null || token.isEmpty) return null;
    try {
      final url = Uri.parse('$_baseUrl$token/sendPhoto');
      await http.post(url, body: {
        'chat_id': chatId,
        'photo': photoUrl,
        'caption': caption ?? "",
        'parse_mode': 'Markdown',
      });
      return null;
    } catch (e) {
      return e.toString();
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

  Future<String?> getFileUrl(String fileId) async {
    final token = await getBotToken();
    if (token == null) return null;
    try {
      final url = Uri.parse('$_baseUrl$token/getFile?file_id=$fileId');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] == true) {
          final filePath = data['result']['file_path'];
          return "https://api.telegram.org/file/bot$token/$filePath";
        }
      }
    } catch (e) {
      print("getFileUrl Error: $e");
    }
    return null;
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
    await _cleanDuplicates();
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
    final photos = msg['photo'] as List?;
    
    final users = await getUsers();
    final user = users.firstWhere((u) => u['chatId'] == chatId, orElse: () => {});
    
    if (user.isEmpty) {
       final firstName = msg['from']['first_name'] ?? 'User';
       await addUser(firstName, chatId, 'pending');
       await sendMessage(chatId, "⏳ *Arizangiz qabul qilindi.* \n\nSiz tizimda ro'yxatdan o'tmagansiz. Administrator ruxsat berishini kuting (ID: $chatId).");
       return;
    }

    if (user['role'] == 'pending') {
       await sendMessage(chatId, "⏳ *Sizning so'rovingiz hali ko'rib chiqilmadi.* \n\nIltimos, administrator ruxsat berishini kuting.");
       return;
    }

    final isAdmin = user['role'] == 'admin';
    final isBranch = user['role'] == 'branch';

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
          await sendMessage(chatId, "⚠️ Iltimos, rasm yuborishdan oldin '📷 Foto Buyurtma' yoki '📷 QR Skanerlash' tugmasini bosing.");
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
         
         final orderParams = await db.query('branch_orders', where: 'id = ?', whereArgs: [orderId]);
         final orderItems = await db.query('branch_order_items', where: 'order_id = ?', whereArgs: [orderId]);
         
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
               await http.post(url, body: {
                  'chat_id': chatId,
                  'photo': photoId,
                  'caption': "📸 Buyurtma asosi (#$orderId)",
               });
            }
         }
         
         // 2. Send List if exists
         if (orderItems.isNotEmpty) {
             StringBuffer msg = StringBuffer("📦 *BUYURTMA TARKIBI (#$orderId):*\n\n");
             for (var item in orderItems) {
               msg.writeln("▪️ ${item['product_name']} - ${item['quantity']} ${item['unit']}");
             }
             msg.writeln("\n-----------------------------");
             msg.writeln("Iltimos, yukni tekshirib qabul qiling.");
             await sendMessage(chatId, msg.toString());
         } 
         // 3. If NO Photo AND NO Items
         else if (order['photo_file_id'] == null) {
             await sendMessage(chatId, "⚠️ Buyurtma tarkibi bo'sh va rasm topilmadi.");
         }

         // 2. Set State & Show Options (ALWAYS show this so flow continues)
         _userStates[chatId] = "waiting_for_confirmation_action_$orderId";
         
         final keyboard = {
           "keyboard": [
             [{"text": "✅ Tasdiqlash"}, {"text": "⚠️ Kamchilik"}],
             [{"text": "❌ Bekor qilish"}]
           ],
           "resize_keyboard": true,
           "one_time_keyboard": true
         };

         await sendMessage(chatId, "👇 Quyidagi tugmalar orqali tasdiqlang:", replyMarkup: keyboard);
         return;
      }
    }

    // Handle Confirmation Actions
    if (_userStates[chatId]?.startsWith('waiting_for_confirmation_action_') ?? false) {
      final orderId = int.parse(_userStates[chatId]!.split('_').last);
      
      if (text == "✅ Tasdiqlash") {
          await updateOrderStatus(orderId, 'delivered', chatId);
          
          final users = await getUsers();
          final admins = users.where((u) => u['role'] == 'admin').toList();
          for (var admin in admins) await sendMessage(admin['chatId'], "🚚 *YUK QABUL QILINDI (QR)*\nID: #ORD-$orderId\nHolati: ✅ Muvaffaqiyatli");
          
          await sendMessage(chatId, "✅ Buyurtma qabul qilindi va yetkazildi statusiga o'tdi!");
          _userStates[chatId] = "";
          await _sendMainMenu(chatId, "Asosiy menyu", role: user['role']);
          return;

      } else if (text == "⚠️ Kamchilik") {
          _userStates[chatId] = "waiting_for_issue_note_$orderId";
          await sendMessage(chatId, "✍️ Iltimos, aniqlangan kamchiliklarni yozib yuboring:\n(Masalan: 2 ta quti ezilgan, 1 ta yetishmovchilik)");
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
       final existing = await db.query('branch_orders', columns: ['admin_comment'], where: 'id = ?', whereArgs: [orderId]);
       String oldComment = "";
       if (existing.isNotEmpty && existing.first['admin_comment'] != null) {
         oldComment = existing.first['admin_comment'] as String;
       }
       
       final newComment = "$oldComment\n[QABUL QILISHDA KAMCHILIK]: $text".trim();
       
       await db.update('branch_orders', {
         'status': 'delivered',
         'admin_comment': newComment
       }, where: 'id = ?', whereArgs: [orderId]);

       // Notify Admin
       final users = await getUsers();
       final admins = users.where((u) => u['role'] == 'admin').toList();
       for (var admin in admins) {
         await sendMessage(admin['chatId'], "⚠️ *YUK QABUL QILISHDA KAMCHILIK*\nID: #ORD-$orderId\n\nIzoh: $text");
       }

       await sendMessage(chatId, "✅ Kamchiliklar qayd etildi va buyurtma yetkazildi deb belgilandi.");
       _userStates[chatId] = "";
       await _sendMainMenu(chatId, "Asosiy menyu", role: user['role']);
       return;
    }

    if (text == '/start' || text.contains("Yangilash") || text.contains("Asosiy Menyu")) {
      _userStates[chatId] = "";
      await _sendMainMenu(chatId, "👋 Assalomu alaykum! Omborxona xizmatiga xush kelibsiz.", role: user['role']);
    } else if (text.contains("Bugungi Holat") && isAdmin) {
      await _handleTodayStats(chatId);
    } else if (text.contains("Umumiy Hisobot") && isAdmin) {
      await _handleTotalStats(chatId);
    } else if (text.contains("Kam Qolganlar") && isAdmin) {
      await _handleLowStock(chatId);
    } else if (text.contains("Jihozlar")) {
      await _handleAssetsStatMenu(chatId);
    } else if (text.contains("Oxirgi Harakatlar") && isAdmin) {
      await _handleRecentActivity(chatId);
    } else if (text.contains("Foto Buyurtma") && isBranch) {
      _userStates[chatId] = "waiting_for_order_photo";
      await sendMessage(chatId, "📷 *Marhamat, buyurtma qog'ozini rasmga olib yuboring:* \n(Iltimos, rasm aniq va yorug' bo'lishiga e'tibor bering)");
    } else if (text.contains("QR Skanerlash")) {
      _userStates[chatId] = "waiting_for_qr_scan";
      await sendMessage(chatId, "📲 *QR KOD SKANERLASH* \n\nYuk qutisidagi QR kodni telefoningiz kamerasi (yoki QR Scanner ilovasi) orqali skanerlang. \n\nSkanerlanganda avtomatik Telegram ochiladi va yuk qabul qilinadi.");
    } else if ((text.contains("Buyurtma Holati") || text.contains("📝")) && isBranch) {
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
      await sendMessage(chatId, "🔍 Qidirish uchun nomini yozing yoki jihoz shtrix-kodi rasmini yuboring:");
    } else if (text.length > 2) {
      await _handleSearchProduct(chatId, text, isBranch: isBranch);
    }
  }

  Future<void> _sendOrderFilterMenu(String chatId) async {
    final keyboard = {
      'keyboard': [
        [{'text': '📋 Oxirgi Buyurtma'}, {'text': '⏳ Kutilmoqda'}],
        [{'text': '✅ Tasdiqlangan'}, {'text': '🚚 Yetkazilgan'}],
        [{'text': '❌ Rad etilgan'}, {'text': '📑 Barchasi'}],
        [{'text': '🔙 Asosiy Menyu'}]
      ],
      'resize_keyboard': true,
      'one_time_keyboard': false
    };
    await sendMessage(chatId, "📂 *BUYURTMALAR TARIXI*\n\nQuyidagi bo'limlardan birini tanlang:", replyMarkup: keyboard);
  }

  Future<void> _handleLastOrder(String chatId) async {
     await _handleOrderStatuses(chatId, limit: 1);
  }

  Future<void> _handleOrderStatuses(String chatId, {String? status, int limit = 10}) async {
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
        limit: limit
      );

      if (orders.isEmpty) {
        await sendMessage(chatId, "📋 Ma'lumot topilmadi.");
        return;
      }

      String msg = "📋 *BUYURTMA NATIJALARI:*\n\n";
      for (var o in orders) {
        String statusIcon = "⏳";
        String statusText = "Kutilmoqda";
        
        if (o['status'] == 'approved') { statusIcon = "✅"; statusText = "Tasdiqlandi"; }
        if (o['status'] == 'rejected') { statusIcon = "❌"; statusText = "Rad etildi"; }
        if (o['status'] == 'delivered') { statusIcon = "🚚"; statusText = "Yetkazildi"; }

        final date = DateTime.tryParse(o['created_at'].toString());
        final dateStr = date != null ? DateFormat('dd.MM.yyyy HH:mm').format(date) : o['created_at'];

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

  Future<void> _handleStartOrder(String chatId) async {
    _userStates[chatId] = ""; // Reset
    _userCarts[chatId] = [];
    await sendMessage(chatId, "📦 *Yangi Buyurtma*\n\nIltimos, kerakli mahsulotni qidirish uchun uning nomini yozing.");
  }

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
        [{'text': "🛒 Savatni ko'rish", 'callback_data': "order_view"}]
      ]
    };
    await sendMessage(chatId, "✅ Savatga qo'shildi! Yana mahsulot qo'shishingiz yoki savatni ko'rishingiz mumkin.", replyMarkup: markup);
  }

  Future<void> _handleShowCart(String chatId) async {
    final cart = _userCarts[chatId] ?? [];
    if (cart.isEmpty) {
      await sendMessage(chatId, "🛒 Savatingiz hozircha bo'sh.");
      return;
    }

    String text = "🛒 *SIZNING SAVATINGIZ:*\n\n";
    for (int i = 0; i < cart.length; i++) {
       text += "${i + 1}. *${cart[i]['name']}* - ${cart[i]['qty']} ${cart[i]['unit']}\n";
    }

    final markup = {
      'inline_keyboard': [
        [{'text': "🚀 Buyurtmani yuborish", 'callback_data': "order_confirm"}],
        [{'text': "🗑 Savatni tozalash", 'callback_data': "order_clear"}]
      ]
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
      await sendMessage(chatId, "✅ *Rasm qabul qilindi!* \nBuyurtmangiz navbatga qo'shildi (ID: #FOTO-$orderId). Admin tez orada ko'rib chiqadi.");

      // Notify Admins
      final token = await getBotToken();
      final admins = users.where((u) => u['role'] == 'admin').toList();
      final adminMsg = "� *YANGI FOTO-BUYURTMA*\n"
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
        await http.post(photoUrl, body: {
          'chat_id': admin['chatId'],
          'photo': fileId,
          'caption': "Buyurtma qog'ozi (#FOTO-$orderId)"
        });
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
      await sendMessage(chatId, "🚀 *Buyurtmangiz muvaffaqiyatli yuborildi!* \nID: #ORD-$orderId\nAdmin tasdiqlashini kuting.");

      // Notify Admins
      final admins = users.where((u) => u['role'] == 'admin').toList();
      final adminMsg = "🔔 *YANGI SAVAT BUYURTMASI*\n"
                       "-------------------------\n"
                       "🏢 Filial: **${user['name']}**\n"
                       "🆔 ID: `#ORD-$orderId`\n"
                       "📦 Mahsulotlar: **${cart.length} xil**\n"
                       "-------------------------\n"
                       "📝 Tasdiqlash uchun ilovaga kiring.";
      for (var admin in admins) {
        await sendMessage(admin['chatId'], adminMsg);
      }

    } catch (e) {
      await sendMessage(chatId, "⚠️ Xatolik yuz berdi: $e");
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
    } else if (data.startsWith('order_add:')) {
      final pid = data.split(':')[1];
      final db = await DatabaseHelper.instance.database;
      final product = (await db.query('products', where: 'id = ?', whereArgs: [pid])).first;
      
      _userSelection[chatId] = product;
      _userStates[chatId] = "waiting_for_qty";
      await sendMessage(chatId, "🔢 *${product['name']}* uchun miqdorni kiriting (${product['unit']}):");
    } else if (data == 'order_view') {
      await _handleShowCart(chatId);
    } else if (data == 'order_confirm') {
      await _submitOrder(chatId);
    } else if (data == 'order_clear') {
      _userCarts[chatId] = [];
      await sendMessage(chatId, "🗑 Savat tozalandi.");
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
    
    // 3. Get assets in this location with category info
    final assets = await db.rawQuery('''
      SELECT a.*, c.name as category_name
      FROM assets a
      LEFT JOIN asset_categories c ON a.category_id = c.id
      WHERE a.location_id = ?
    ''', [locId]);

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
      text += "\n📦 *Bu yerdagi jihozlar:* (${assets.length} ta)\n"
              "-------------------------\n";
              
      for (var a in assets) {
        text += "🖥 *${a['name']}*\n"
                "   - Tur: ${a['category_name'] ?? 'Noma\'lum'}\n"
                "   - Model: ${a['model'] ?? '-'}\n"
                "   - Seriya: `${a['serial_number'] ?? '-'}`\n"
                "   - Rangi: ${a['color'] ?? '-'}\n"
                "   - Holati: ${a['status']}\n";
        if (a['barcode'] != null) {
          text += "   - Barcode: `${a['barcode']}`\n";
        }
        text += "-------------------------\n";
      }
    } else if (subLocs.isEmpty) {
      text += "\n📭 Bu yerda hozircha jihozlar yo'q.";
    } else {
      text += "\n👇 Kerakli bo'limni tanlang:";
    }

    await editMessageText(chatId, messageId, text, replyMarkup: markup);
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

      String msg = "$greeting, Hurmatli Admin!\n\n"
                  "📊 *BUGUNGI HISOBOT ($dateStr)*\n"
                  "-------------------------\n\n"
                  "📥 *Kirim Operatsiyalari:*\n"
                  "   - Jami: *${inCount} ta* harakat\n"
                  "   - Qiymati: *${_formatMoney(inSum)}* so'm\n\n"
                  "📤 *Chiqim Operatsiyalari:*\n"
                  "   - Jami: *${outCount} ta* operatsiya\n"
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
      
      String msg = "💰 *OMBORXONA UMUMIY TAHLILI*\n"
                  "-------------------------\n\n"
                  "💵 *Moliyaviy Holat:*\n"
                  "   - Jami qiymat: *${_formatMoney(totalVal)}* so'm\n\n"
                  "📊 *Zaxira Sog'lig'i:*\n"
                  "   - Kam qolgan: *${lowCount} xil*\n"
                  "   - Tugagan: *${finishedCount} xil*\n\n"
                  "💡 *Tavsiya:* Hozirgi kunda omborning holati barqaror. ";
                  
      if (finishedCount > 0) {
        msg += "Biroq, tugagan mahsulotlar uchun yangi buyurtma berishni tavsiya qilamiz.";
      }
      
      msg += "\n\n-------------------------\n"
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
        await sendMessage(chatId, "✅ *Xushxabar!* Hozirda omborda barcha mahsulotlar yetarli miqdorda mavjud.");
        return;
      }
      
      String list = "🚨 *ZAXIRA OGOHLANTIRISHLARI*\n"
                  "-------------------------\n\n";
      
      if (finished.isNotEmpty) {
        list += "❌ *ZUDLIK BILAN (TUGAGAN):*\n";
        for (var i = 0; i < finished.length && i < 10; i++) {
          list += "   • ${finished[i]['name']} (0 ${finished[i]['unit'] ?? ''})\n";
        }
        list += "\n";
      }
      
      if (allLow.isNotEmpty) {
        list += "⚠️ *KAM QOLGANLAR (YANGILASH KERAK):*\n";
        for (var i = 0; i < allLow.length && i < 10; i++) {
          bool exists = finished.any((f) => f['id'] == allLow[i]['id']);
          if (!exists) {
            list += "   • ${allLow[i]['name']} (*${allLow[i]['stock']} ${allLow[i]['unit'] ?? ''}*)\n";
          }
        }
      }
      
      list += "\n-------------------------\n"
              "Iltimos, zaxiralarni nazorat qilib boring.\n"
              "#ogohlantirish #zaxira";
      
      await sendMessage(chatId, list);
    } catch (e) {
      await sendMessage(chatId, "⚠️ Ma'lumot yuklashda xatolik: $e");
    }
  }

  Future<void> _handleRecentActivity(String chatId) async {
    try {
      final activity = await DatabaseHelper.instance.getRecentActivity(limit: 5);
      if (activity.isEmpty) {
        await sendMessage(chatId, "📭 Hozircha harakatlar tarixi bo'sh.");
        return;
      }
      
      String list = "🔄 *OXIRGI 5 TA HARAKAT*\n"
                  "-------------------------\n\n";
                  
      for (var item in activity) {
        final isKirim = item['type'] == 'in';
        final typeIcon = isKirim ? "📥 KIRIM" : "📤 CHIQIM";
        final partyInfo = isKirim ? "Yetkazuvchi: ${item['party']}" : "Qabul qiluvchi: ${item['party']}";
        final dtRaw = item['date_time'].toString();
        
        String dateDisplay = dtRaw;
        final parsed = DateTime.tryParse(dtRaw);
        if (parsed != null) {
          dateDisplay = DateFormat('dd.MM.yyyy HH:mm').format(parsed);
        }

        list += "*$typeIcon*\n"
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

  Future<void> _handleSearchProduct(String chatId, String query, {bool isBranch = false}) async {
    final db = await DatabaseHelper.instance.database;
    final sanitized = '%$query%';
    final productResults = await db.rawQuery('SELECT id, name, unit, ((SELECT IFNULL(SUM(quantity), 0) FROM stock_in WHERE product_id = p.id) - (SELECT IFNULL(SUM(quantity), 0) FROM stock_out WHERE product_id = p.id)) as stock FROM products p WHERE name LIKE ? LIMIT 5', [sanitized]);
    final assetResults = await db.rawQuery('SELECT a.name, a.model, l.name as loc_name FROM assets a LEFT JOIN asset_locations l ON a.location_id = l.id WHERE a.name LIKE ? LIMIT 5', [sanitized]);
    
    if (productResults.isEmpty && assetResults.isEmpty) { await sendMessage(chatId, "📌 Topilmadi."); return; }
    
    if (productResults.isNotEmpty) {
      for (var item in productResults) {
        String msg = "📦 *MAHSULOT:*\n"
                    " - Nomi: ${item['name']}\n"
                    " - Mavjud: *${item['stock']} ${item['unit']}*";
        
        Map<String, dynamic>? markup;
        if (isBranch) {
          markup = {
            'inline_keyboard': [
              [{'text': "➕ Savatga qo'shish", 'callback_data': "order_add:${item['id']}"}]
            ]
          };
        }
        await sendMessage(chatId, msg, replyMarkup: markup);
      }
    }
    
    if (assetResults.isNotEmpty) {
      String list = "🖥 *JIHOZLAR:*\n";
      for (var item in assetResults) list += " - ${item['name']} 📍 ${item['loc_name']}\n";
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
        image.getBytes(order: img.ChannelOrder.rgba).buffer.asInt32List()
      );
      final bitmap = BinaryBitmap(HybridBinarizer(source));
      
      final reader = MultiFormatReader();
      final result = reader.decode(bitmap); // Default hints are usually enough for Code 128
      
      final barcode = result.text.trim();
      await sendMessage(chatId, "✅ *Skanerlandi:* `$barcode` \nMa'lumotlar qidirilmoqda...");
      
      final db = await DatabaseHelper.instance.database;

      // --- CASE 1: DELIVERY CONFIRMATION (#ORD-XXX) ---
      if (barcode.startsWith("#ORD-")) {
        final orderIdStr = barcode.replaceFirst("#ORD-", "");
        final orderId = int.tryParse(orderIdStr);
        if (orderId == null) throw "Buyurtma ID noto'g'ri";

        final orders = await db.query('branch_orders', where: 'id = ?', whereArgs: [orderId]);
        if (orders.isEmpty) {
          await sendMessage(chatId, "❌ Kechiraiz, `#ORD-$orderId` buyurtma topilmadi.");
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
        final adminMsg = "🚚 *YUK QABUL QILINDI*\n"
                         "-------------------------\n"
                         "🏢 Filial: **${order['branch_name']}**\n"
                         "🆔 ID: `#ORD-$orderId`\n"
                         "-------------------------\n"
                         "✅ Filial yukni skanerladi va qabul qildi.";
        for (var admin in admins) await sendMessage(admin['chatId'], adminMsg);
        return;
      }

      // --- CASE 2: ASSET SEARCH (Standard) ---
      final assets = await db.rawQuery('''
        SELECT a.*, c.name as category_name, l.name as loc_name
        FROM assets a
        LEFT JOIN asset_categories c ON a.category_id = c.id
        LEFT JOIN asset_locations l ON a.location_id = l.id
        WHERE a.barcode = ?
      ''', [barcode]);
      
      if (assets.isEmpty) {
        await sendMessage(chatId, "❌ Kechirasiz, bazada `$barcode` shtrix-kodli jihoz yoki buyurtma topilmadi.");
      } else {
        final a = assets.first;
        String msg = "🖥 *JIHOZ TOPILDI!*\n"
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
      print("Barcode Error: $e");
      await sendMessage(chatId, "❌ *Xatolik:* Rasmdan shtrix-kodni o'qib bo'lmadi. \n\nIltimos, rasmni aniqroq olib qayta yuboring.");
    }
  }

  Future<void> _sendMainMenu(String chatId, String text, {String? role}) async {
    List<List<Map<String, String>>> keyboard = [];

    if (role == 'admin') {
      keyboard = [
        [{"text": "📊 Bugungi Holat"}, {"text": "💰 Umumiy Hisobot"}],
        [{"text": "⚠️ Kam Qolganlar"}, {"text": "🖥 Jihozlar"}],
        [{"text": "🔄 Oxirgi Harakatlar"}, {"text": "🔎 Mahsulot Qidirish"}],
        [{"text": "🔄 Yangilash"}]
      ];
    } else if (role == 'branch') {
      keyboard = [
        [{"text": "📷 Foto Buyurtma"}, {"text": "📷 QR Skanerlash"}],
        [{"text": "📝 Buyurtma Holati"}],
        [{"text": "🔄 Yangilash"}]
      ];
    } else {
      keyboard = [
        [{"text": "🔎 Mahsulot Qidirish"}, {"text": "🖥 Jihozlar"}],
        [{"text": "🔄 Yangilash"}]
      ];
    }

    final markup = {
      "keyboard": keyboard,
      "resize_keyboard": true
    };
    await sendMessage(chatId, text, replyMarkup: markup);
  }
}
