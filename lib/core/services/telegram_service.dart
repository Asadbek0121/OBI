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

  Future<String?> sendMessage(String chatId, String text) async {
    final token = await getBotToken();
    if (token == null || token.isEmpty) return "Bot tokeni sozlanmagan";

    try {
      final url = Uri.parse('$_baseUrl$token/sendMessage');
      final response = await http.post(
        url,
        body: {'chat_id': chatId, 'text': text, 'parse_mode': 'Markdown'},
      );
      
      if (response.statusCode == 200) {
        return null; // Success
      } else {
        return "Xato: ${response.statusCode} - ${response.body}";
      }
    } catch (e) {
      print('Telegram Error: $e');
      return "Internet xatosi: $e";
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
      
      if (response.statusCode == 200) {
        return null;
      } else if (response.statusCode == 404) {
        return "Bot topilmadi (404). Token noto'g'ri kiritilgan.";
      } else {
        final respStr = await response.stream.bytesToString();
        print("Telegram SendDoc Failed: ${response.statusCode} - $respStr");
        return "Xato: ${response.statusCode} - $respStr";
      }
    } catch (e) {
      print('Telegram SendDoc Error: $e');
      return "Internet xatosi: $e";
    }
  }

  // Simple polling to find new users who started the bot
  Future<List<Map<String, dynamic>>> getUpdates() async {
    final token = await getBotToken();
    // Basic validation
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
              final from = u['message']['from'];
              // Only collect private chats
              if (chat['type'] == 'private') {
                result.add({
                  'chatId': chat['id'].toString(),
                  'firstName': from['first_name'] ?? 'User',
                  'username': from['username'] ?? '',
                });
              }
            }
          }
        }
        return result; // Allows UI to show "Found X users, pick one to add"
      }
    } catch (e) {
      print('Telegram Updates Error: $e');
    }

    return [];
  }

  // --- Scheduler ---
  static const String _keyLastBackupWeek = 'last_backup_week_v1';
  static const String _keyLastAlertDate = 'last_low_stock_alert_date_v1';

  Future<void> checkDailyLowStockAlert(dynamic databaseHelperInstance) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final todayStr = "${now.year}-${now.month}-${now.day}"; // YYYY-M-D
    
    final lastAlertDate = prefs.getString(_keyLastAlertDate);

    // Run only if we haven't run today
    if (lastAlertDate != todayStr) {
      print("📅 Scheduler: Checking for Low Stock Alerts (Daily)...");

      try {
        // 1. Get Low Stock Items
        // We use dynamic because we don't import DatabaseHelper here to avoid circular depends if unnecessary, 
        // but ideally we should import it or use a callback. 
        // Assuming databaseHelperInstance has getLowStockProducts()
        final List<Map<String, dynamic>> lowStockItems = await databaseHelperInstance.getLowStockProducts();

        if (lowStockItems.isNotEmpty) {
           // 2. Get Recipients
           final users = await getUsers();
           if (users.isEmpty) {
             print("⚠️ Scheduler: No telegram users found to receive alerts.");
             return;
           }

           // 3. Construct Message
           final sb = StringBuffer();
           sb.writeln("⚠️ *DIQQAT: MAHSULOTLAR TUGAMOQDA!* ⚠️");
           sb.writeln("Sanasi: $todayStr");
           sb.writeln("");
           
           for (int i = 0; i < lowStockItems.length; i++) {
             final item = lowStockItems[i];
             // Limit to top 20 to avoid message size limits
             if (i >= 20) {
               sb.writeln("... va yana ${lowStockItems.length - 20} ta mahsulot.");
               break;
             }
             sb.writeln("${i + 1}. *${item['name']}* - ${item['stock']} ${item['unit']}");
           }
           
           sb.writeln("");
           sb.writeln("#lowstock #omborxona");

           final message = sb.toString();

           // 4. Send to ALL users (Since this is critical info)
           int successCount = 0;
           for (var user in users) {
              final err = await sendMessage(user['chatId'], message);
              if (err == null) successCount++;
           }
           
           print("✅ Scheduler: Low stock alert sent to $successCount users.");
           
           // 5. Mark as done for today
           if (successCount > 0) {
             await prefs.setString(_keyLastAlertDate, todayStr);
           }
        } else {
          print("✅ Scheduler: No low stock items found today.");
          // Mark as done anyway so we don't query DB on every restart today
          await prefs.setString(_keyLastAlertDate, todayStr);
        }
      } catch (e) {
        print("❌ Scheduler Alert Error: $e");
      }
    }
  }

  Future<void> sendDailyReport(dynamic databaseHelperInstance) async {
    print("📤 Telegram: Sending Daily Report...");
    try {
      // 1. Get Users
      final users = await getUsers();
      if (users.isEmpty) {
        return; 
      }

      // 2. Get Data
      final stats = await databaseHelperInstance.getDashboardStatusToday();
      final now = DateTime.now();
      final dateStr = "${now.day}.${now.month}.${now.year}";

      // 3. Format Message
      final sb = StringBuffer();
      sb.writeln("📅 *KUNLIK HISOBOT*");
      sb.writeln("Sana: $dateStr");
      sb.writeln("-------------------------");
      sb.writeln("📉 *Kirim (Import):*");
      sb.writeln("   • Soni: ${stats['in_count']} ta");
      // Format number for better readability if possible, using simple replacing logic for now
      final sumStr = stats['in_sum'].toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]} ');
      sb.writeln("   • Summa: $sumStr so'm"); 
      sb.writeln("");
      sb.writeln("📈 *Chiqim (Export):*");
      sb.writeln("   • Soni: ${stats['out_count']} ta");
      sb.writeln("-------------------------");
      sb.writeln("#hisobot #daily");

      final message = sb.toString();

      // 4. Send
      int successCount = 0;
      for (var user in users) {
          final err = await sendMessage(user['chatId'], message);
          if (err == null) successCount++;
      }
      print("✅ Telegram: Daily report sent to $successCount users.");

    } catch (e) {
      print("❌ Telegram Daily Report Error: $e");
    }
  }

  static const String _keyLastReportDate = 'last_daily_report_date_v1';

  Future<void> checkDailyReportAuto(dynamic databaseHelperInstance) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final todayStr = "${now.year}-${now.month}-${now.day}"; 
    
    // Check if already sent today
    if (prefs.getString(_keyLastReportDate) == todayStr) return;

    // TARGET TIME: 18:00 (6 PM)
    // Only send if it's 18:00 or later
    if (now.hour >= 18) {
       print("🕕 Scheduler: It's past 18:00. Sending Automatic Daily Report...");
       await sendDailyReport(databaseHelperInstance);
       await prefs.setString(_keyLastReportDate, todayStr);
    }
  }

  // --- BOT LISTENER (Interactive Mode) ---
  bool _isListening = false;
  int _lastUpdateId = 0;

  void startBotListener() async {
    if (_isListening) return; // Already running
    _isListening = true;
    print("🤖 Telegram Bot: Eshitish rejimi yoqildi (Polling)...");

    while (_isListening) {
      try {
        await _checkUpdates();
      } catch (e) {
        print("❌ Bot Listener Error: $e");
        await Future.delayed(const Duration(seconds: 5)); // Wait before retry
      }
      await Future.delayed(const Duration(seconds: 2)); // Polling interval
    }
  }

  void stopBotListener() {
    _isListening = false;
    print("🛑 Telegram Bot: To'xtatildi.");
  }

  Future<void> _checkUpdates() async {
    final token = await getBotToken();
    if (token == null || token.isEmpty) return;

    final url = Uri.parse('$_baseUrl$token/getUpdates?offset=${_lastUpdateId + 1}&timeout=10');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['ok'] == true) {
        final List updates = data['result'];
        for (var u in updates) {
          _lastUpdateId = u['update_id'];
          if (u['message'] != null) {
            await _processMessage(u['message']);
          }
        }
      }
    }
  }

  Future<void> _processMessage(Map<String, dynamic> msg) async {
    final chatId = msg['chat']['id'].toString();
    final text = msg['text']?.toString() ?? '';
    
    // Check if user is authorized (simple check against local list)
    final users = await getUsers();
    final isAuthorized = users.any((u) => u['chatId'] == chatId);

    if (!isAuthorized) {
       // Auto-reply to unknown users
       sendMessage(chatId, "⛔️ Kechirasiz, siz tizimda ro'yxatdan o'tmagansiz.\nID: $chatId\nIltimos, adminga murojaat qiling.");
       return;
    }

    print("📩 Bot Message [$chatId]: $text");

    // --- COMMAND HANDLER ---
    if (text == '/start') {
      await _sendMainMenu(chatId, "👋 Assalomu alaykum! Omborxona Botingizga xush kelibsiz.\nQuyidagi menyudan foydalaning:");
    } 
    else if (text.contains("Bugungi Holat")) {
      await _handleTodayStats(chatId);
    }
    else if (text.contains("Umumiy Hsobot")) { // Hsobot typo fix if needed, but lets match exact
       await _handleTotalStats(chatId);
    }
    else if (text.contains("Umumiy Hisobot")) {
       await _handleTotalStats(chatId);
    }
    else if (text.contains("Kam Qolganlar")) {
      await _handleLowStock(chatId);
    }
    else if (text.contains("Oxirgi Harakatlar")) {
      await _handleRecentActivity(chatId);
    }
    else if (text.contains("Mahsulot Qidirish")) {
      await sendMessage(chatId, "🔍 *Qidirish uchun:*\n\nShunchaki mahsulot nomini yozib yuboring.\nMasalan: `Paracetamol` yoki `Stol`");
    }
    else {
      // Treat as Search Query
      if (text.length > 2) {
        await _handleSearchProduct(chatId, text);
      } else {
        await sendMessage(chatId, "⚠️ Iltimos, menyudan tanlang yoki qidirish uchun kamida 3 ta harf yozing.");
      }
    }
  }

  // --- HANDLERS ---
  
  // --- COMMAND HANDLERS IMPLEMENTATION ---
  
  Future<void> _handleTodayStats(String chatId) async {
     try {
       final stats = await DatabaseHelper.instance.getDashboardStatusToday();
       final formatter = NumberFormat("#,###");
       
       final msg = "📊 *Bugungi Holat (${DateTime.now().toString().substring(0,10)})*\n\n"
                   "⬇️ *Kirim:* ${stats['in_count']} ta operatsiya\n"
                   "💰 *Jami:* ${formatter.format(stats['in_sum'])} so'm\n\n"
                   "⬆️ *Chiqim:* ${stats['out_count']} ta operatsiya";
       
       await sendMessage(chatId, msg);
     } catch (e) {
       await sendMessage(chatId, "⚠️ Xatolik yuz berdi: $e");
     }
  }

  Future<void> _handleTotalStats(String chatId) async {
    try {
      final stats = await DatabaseHelper.instance.getDashboardStats();
       final formatter = NumberFormat("#,###"); // Requires intl package
      
      final totalVal = stats['total_value'] as double;
      
      final msg = "💰 *Umumiy Ombor Hisoboti*\n\n"
                  "💵 *Qiymat:* ${formatter.format(totalVal)} so'm\n"
                  "📉 *Kam Qolgan:* ${stats['low_stock']} xil tovar\n"
                  "🚫 *Tugagan:* ${stats['finished']} xil tovar";
      
      await sendMessage(chatId, msg);
    } catch (e) {
       await sendMessage(chatId, "⚠️ Xatolik: $e");
    }
  }

  Future<void> _handleLowStock(String chatId) async {
     try {
       final items = await DatabaseHelper.instance.getLowStockProducts();
       if (items.isEmpty) {
         await sendMessage(chatId, "✅ Ajoyib! Hozircha kam qolgan tovarlar yo'q.");
         return;
       }
       
       String list = "⚠️ *Kam Qolgan Tovarlar (Top 10)*\n\n";
       for (var i = 0; i < items.length && i < 10; i++) {
          final item = items[i];
          list += "${i+1}. ${item['name']} — *${item['stock']} ${item['unit']}*\n";
       }
       
       await sendMessage(chatId, list);
     } catch (e) {
       await sendMessage(chatId, "⚠️ Xatolik: $e");
     }
  }

  Future<void> _handleRecentActivity(String chatId) async {
    try {
      final activity = await DatabaseHelper.instance.getRecentActivity(); // Gets 5 items
      if (activity.isEmpty) {
        await sendMessage(chatId, "📭 Hozircha hech qanday harakat yo'q.");
        return;
      }
      
      String list = "🔄 *Oxirgi Harakatlar*\n\n";
      for (var item in activity) {
        final icon = item['type'] == 'in' ? "⬇️" : "⬆️";
        final time = item['date_time'].toString().substring(11, 16); // HH:mm
        list += "$icon *${item['product_name']}*\n"
                "   └ ${item['quantity']} dona | 🕒 $time\n";
      }
      
      await sendMessage(chatId, list);
    } catch (e) {
      await sendMessage(chatId, "⚠️ Xatolik: $e");
    }
  }

  Future<void> _handleSearchProduct(String chatId, String query) async {
    try {
      // Reuse the global search logic but filter for products only or just use it as is
      // Or create a direct product search query for cleaner results
      final db = await DatabaseHelper.instance.database;
      final sanitized = '%$query%';
      
      final results = await db.rawQuery('''
        SELECT name, unit, 
          ((SELECT IFNULL(SUM(quantity), 0) FROM stock_in WHERE product_id = p.id) - 
           (SELECT IFNULL(SUM(quantity), 0) FROM stock_out WHERE product_id = p.id)) as stock
        FROM products p
        WHERE name LIKE ?
        LIMIT 5
      ''', [sanitized]);
      
      if (results.isEmpty) {
        await sendMessage(chatId, "🤷‍♂️ '$query' bo'yicha hech narsa topilmadi.");
        return;
      }
      
      String list = "🔎 *Qidiruv Natijasi:*\n\n";
      for (var item in results) {
         list += "🔹 ${item['name']}\n"
                 "   📦 Qoldiq: *${item['stock']} ${item['unit']}*\n\n";
      }
      
      await sendMessage(chatId, list);

    } catch (e) {
       await sendMessage(chatId, "⚠️ Qidirishda xatolik: $e");
    }
  }

  Future<void> _sendMainMenu(String chatId, String text) async {
    final token = await getBotToken();
    if (token == null) return;
    
    // CUSTOM KEYBOARD JSON
    final keyboard = {
      "keyboard": [
        [{"text": "📊 Bugungi Holat"}, {"text": "💰 Umumiy Hisobot"}],
        [{"text": "⚠️ Kam Qolganlar"}, {"text": "🔄 Oxirgi Harakatlar"}],
        [{"text": "🔎 Mahsulot Qidirish"}]
      ],
      "resize_keyboard": true,
      "one_time_keyboard": false
    };

    final url = Uri.parse('$_baseUrl$token/sendMessage');
    await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'chat_id': chatId,
        'text': text,
        'parse_mode': 'Markdown',
        'reply_markup': keyboard
      }),
    );
  }
}
