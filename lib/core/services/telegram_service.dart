import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

  Future<void> checkWeeklyBackup(dynamic databaseHelperInstance) async {
    // 1. Check Schedule
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    // Simple week number: Days since epoch / 7
    final currentWeek = (now.millisecondsSinceEpoch / (1000 * 60 * 60 * 24 * 7)).floor();
    
    final lastWeek = prefs.getInt(_keyLastBackupWeek) ?? 0;
    
    if (currentWeek > lastWeek) {
      print("📅 Scheduler: Weekly backup needed for Week $currentWeek");
      
      // 2. Get Admin/Recipients
      final users = await getUsers();
      if (users.isEmpty) {
        print("⚠️ Scheduler: No users configured for backup.");
        return;
      }
      // Send to ALL or just first? Let's send to the first user found or anyone marked 'Admin' (future).
      // For now, send to the first user.
      final targetUser = users.first; 
      
      // 3. Create Backup
      // We need a temp folder for the backup
      try {
        final path = await databaseHelperInstance.createBackup(null); // null = use default/temp location in DB helper?
        // Note: modify DB Helper to handle null path or generate temp path.
        // Assuming createBackup returns the File Path string.
        
        if (path != null) {
          final file = File(path);
          final error = await sendDocument(
            targetUser['chatId'], 
            file, 
            caption: "🛡️ Avtomatik Haftalik Zaxira (Backup)\nSana: ${now.toString()}\n#backup"
          );
          
          if (error == null) {
            print("✅ Scheduler: Backup sent to ${targetUser['name']}");
            await prefs.setInt(_keyLastBackupWeek, currentWeek);
          } else {
             print("❌ Scheduler: Failed to send backup to Telegram. $error");
          }
        }
      } catch (e) {
        print("❌ Scheduler Error: $e");
      }
    }
  }
}
