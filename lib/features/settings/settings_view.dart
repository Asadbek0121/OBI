import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_container.dart';
import '../../core/localization/app_translations.dart';
import '../../core/theme/theme_provider.dart';
import '../../core/services/profile_provider.dart';
import '../../core/services/auth_provider.dart';
import '../splash/splash_screen.dart';
import '../../core/utils/app_notifications.dart';
import '../../core/widgets/app_dialogs.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/database/database_helper.dart';
import '../../core/database/database_helper.dart';
import '../../core/services/telegram_service.dart';
import '../../core/services/excel_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  final _userController = TextEditingController();
  final _passController = TextEditingController();

  void _showEditAuth(BuildContext context, AuthProvider auth) {
    _userController.text = auth.username;
    _passController.text = auth.password;
    final t = Provider.of<AppTranslations>(context, listen: false);

    AppDialogs.showBlurDialog(
      context: context,
      title: t.text('set_auth'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _userController,
            decoration: InputDecoration(
              labelText: t.text('login'),
              prefixIcon: const Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: t.text('password'),
              prefixIcon: const Icon(Icons.lock_outline),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.text('btn_cancel'))),
        ElevatedButton(
          onPressed: () {
            auth.updateCredentials(_userController.text, _passController.text);
            AppNotifications.showSuccess(context, t.text('msg_saved'));
            Navigator.pop(context);
          },
          child: Text(t.text('btn_save')),
        ),
      ],
    );
  }

  void _showEditProfile(BuildContext context, ProfileProvider profile) {
    _nameController.text = profile.name;
    _emailController.text = profile.email;
    final t = Provider.of<AppTranslations>(context, listen: false);

    AppDialogs.showBlurDialog(
      context: context,
      title: t.text('set_profile'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: t.text('col_name'),
              prefixIcon: const Icon(Icons.face_outlined),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: "Email",
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.text('btn_cancel'))),
        ElevatedButton(
          onPressed: () {
            profile.updateProfile(_nameController.text, _emailController.text);
            AppNotifications.showSuccess(context, t.text('msg_saved'));
            Navigator.pop(context);
          },
          child: Text(t.text('btn_save')),
        ),
      ],
    );
  }

  void _showBackupDialog(BuildContext context) {
    final t = Provider.of<AppTranslations>(context, listen: false);
    AppDialogs.showBlurDialog(
      context: context,
      title: t.text('dlg_backup_title'),
      content: Text(t.text('dlg_backup_content')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.text('btn_cancel'))),
        ElevatedButton(
          onPressed: () async {
            // Close the initial dialog FIRST to avoid UI stacking issues
            Navigator.pop(context);
            
            // Pick Directory
            String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
              dialogTitle: "Papkani tanlash",
            );
            
            if (selectedDirectory != null) {
               // Show loading indicator or toast? Quick operation usually.
               
               // Create Backup
               final savedPath = await DatabaseHelper.instance.createBackup(selectedDirectory);
               
               if (mounted) {
                 if (savedPath != null) {
                    AppNotifications.showSuccess(context, "Zaxira saqlandi: $savedPath");
                 } else {
                    AppNotifications.showError(context, "Xatolik yuz berdi");
                 }
               }
            }
          },
          child: Text(t.text('btn_select_folder')),
        ),
      ],
    );
  }

  Future<void> _restoreBackup(BuildContext context) async {
    // Pick File
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null && result.files.single.path != null) {
      String path = result.files.single.path!;
      
      // Confirm Dialog
      if (!mounted) return;
      final t = Provider.of<AppTranslations>(context, listen: false); // Ensure t is available
      
      AppDialogs.showBlurDialog(
        context: context,
        title: "Tasdiqlash", 
        content: const Text("Bu amal joriy ma'lumotlarni to'liq o'chirib yuboradi va tanlangan nusxani tiklaydi. Davom etasizmi?"),
        actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), 
              child: Text(t.text('btn_cancel'))
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () async {
                Navigator.pop(context); // Close dialog
                
                bool success = await DatabaseHelper.instance.restoreBackup(path);
                if (mounted) {
                  if (success) {
                    AppNotifications.showSuccess(context, "Ma'lumotlar tiklandi! Dastur qayta ishga tushirilmoqda...");
                    
                    // Restart App Flow
                    Future.delayed(const Duration(seconds: 2), () {
                        Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (c) => const SplashScreen()),
                        (route) => false,
                      );
                    });
                  } else {
                    AppNotifications.showError(context, t.text('msg_error'));
                  }
                }
              },
              child: Text(t.text('btn_confirm')),
            ),
        ],
      );
    }
  }


  Future<void> _importExcel(BuildContext context) async {
    debugPrint("📥 Excel Import Button Pressed");
    FilePickerResult? result = await FilePicker.platform.pickFiles(
       type: FileType.custom,
       allowedExtensions: ['xlsx', 'xls'],
    );
     
    if (result != null && result.files.single.path != null) {
       if (!mounted) return;
       AppDialogs.showBlurDialog(context: context, title: "Yuklanmoqda...", content: const CircularProgressIndicator());
       try {
          final res = await ExcelService.importData(result.files.single.path!);
          if (!mounted) return;
          Navigator.pop(context); // close loader
          
          if (res['in'] == 0 && res['out'] == 0) {
             // Show helpful error
             AppDialogs.showBlurDialog(
               context: context, 
               title: "Hech narsa yuklanmadi", 
               content: const Text("Fayl ichidan 'mahsulot' va 'soni' (yoki 'qty') ustunlari topilmadi.\n\nIltimos, ustunlar nomini to'g'rilang yoki boshqa faylni sinab ko'ring."),
               actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Tushunarli"))],
             );
          } else {
             AppNotifications.showSuccess(context, "Muvaffaqiyatli! Kirim: ${res['in']}, Chiqim: ${res['out']} ta.");
          }
       } catch (e) {
          if (!mounted) return;
          Navigator.pop(context);
          AppNotifications.showError(context, "Xatolik: $e");
       }
    }
  }

  // --- Telegram Logic ---
  final _telegramService = TelegramService();
  final _tgTokenController = TextEditingController();

  void _showTelegramSettings(BuildContext context) async {
    // Load current Token
    final token = await _telegramService.getBotToken();
    _tgTokenController.text = token ?? '';
    
    // Load Users
    List<Map<String, dynamic>> users = await _telegramService.getUsers();

    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Row(
                children: [
                   Container(
                     padding: const EdgeInsets.all(8), 
                     decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                     child: const Icon(Icons.send, color: Colors.white, size: 20),
                   ),
                   const SizedBox(width: 12),
                   const Text("Telegram Bot"),
                ],
              ),
              content: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _tgTokenController,
                      decoration: const InputDecoration(
                        labelText: "Bot Token",
                        hintText: "123456:ABC-...",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () async {
                        await _telegramService.saveBotToken(_tgTokenController.text);
                        AppNotifications.showSuccess(context, "Token saqlandi!");
                      }, 
                      child: const Text("Tokenni Saqlash")
                    ),
                    const Divider(height: 30),
                      Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Foydalanuvchilar", style: TextStyle(fontWeight: FontWeight.bold)),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: () async {
                                 // Manual add dialog
                                 final nameCtrl = TextEditingController();
                                 final idCtrl = TextEditingController();
                                 await showDialog(
                                   context: context,
                                   builder: (c) => AlertDialog(
                                     title: const Text("Qo'lda qo'shish"),
                                     content: Column(
                                       mainAxisSize: MainAxisSize.min,
                                       children: [
                                          const Text(
                                            "ESLATMA: Telegram username orqali xabar yuborib bo'lmaydi. Faqat 'Chat ID' raqami orqali yuborish mumkin.\n\nChat ID ni bilish uchun @userinfobot ga xabar yozing yoki habarni forward qiling.",
                                            style: TextStyle(fontSize: 12, color: Colors.grey),
                                          ),
                                          const SizedBox(height: 10),
                                          TextField(
                                            controller: nameCtrl,
                                            decoration: const InputDecoration(labelText: "Ism (Masalan: Bugalter)"),
                                          ),
                                          TextField(
                                            controller: idCtrl,
                                            keyboardType: TextInputType.number,
                                            decoration: const InputDecoration(labelText: "Telegram Chat ID (Raqam)"),
                                          ),
                                       ],
                                     ),
                                     actions: [
                                       TextButton(onPressed: () => Navigator.pop(c), child: const Text("Bekor qilish")),
                                       ElevatedButton(
                                         onPressed: () async {
                                           if (nameCtrl.text.isNotEmpty && idCtrl.text.isNotEmpty) {
                                              await _telegramService.addUser(nameCtrl.text, idCtrl.text, 'Viewer');
                                              final newUsers = await _telegramService.getUsers();
                                              setState(() => users = newUsers);
                                              Navigator.pop(c);
                                           }
                                         }, 
                                         child: const Text("Qo'shish")
                                       ),
                                     ],
                                   )
                                 );
                              },
                              icon: const Icon(Icons.add),
                              label: const Text("Qo'lda"),
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: () async {
                                 // "Scan" for new users
                                 AppDialogs.showBlurDialog(context: context, title: "Qidirilmoqda...", content: const CircularProgressIndicator());
                                 final updates = await _telegramService.getUpdates();
                                 Navigator.pop(context); // close loader
                                 
                                 if (updates.isEmpty) {
                                   AppNotifications.showError(context, "Yangi user topilmadi. Botga /start bosing.");
                                 } else {
                                   // Show picker
                                   final selected = await showDialog<Map<String,dynamic>>(
                                     context: context, 
                                     builder: (c) => SimpleDialog(
                                       title: const Text("Userni tanlang"),
                                       children: updates.map((u) => SimpleDialogOption(
                                         child: Text("${u['firstName']} (${u['username']})"),
                                         onPressed: () => Navigator.pop(c, u),
                                       )).toList(),
                                     )
                                   );
                                   
                                   if (selected != null) {
                                      await _telegramService.addUser(selected['firstName'], selected['chatId'], 'Viewer');
                                      // Refresh list
                                      final newUsers = await _telegramService.getUsers();
                                      setState(() => users = newUsers);
                                   }
                                 }
                              },
                              icon: const Icon(Icons.person_add),
                              label: const Text("Scan"),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      height: 200,
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                      child: users.isEmpty 
                        ? const Center(child: Text("Hozircha user yo'q"))
                        : ListView.separated(
                          itemCount: users.length,
                          separatorBuilder: (c,i) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final u = users[index];
                            return ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.person, size: 16)),
                              title: Text(u['name']),
                              subtitle: Text("ID: ${u['chatId']}"),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.send, color: Colors.blue, size: 20),
                                    tooltip: "Test Xabar",
                                    onPressed: () async {
                                      final error = await _telegramService.sendMessage(u['chatId'], "🔔 Test Xabar: Tizim ishlamoqda!");
                                      if (error == null) {
                                         AppNotifications.showSuccess(context, "Test xabar yuborildi!");
                                      } else {
                                         AppDialogs.showBlurDialog(
                                           context: context, 
                                           title: "Xatolik", 
                                           content: Text("Batafsil: $error\n\nMaslahat: Foydalanuvchi botga /start bosganiga ishonch hosil qiling.")
                                         );
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                    onPressed: () async {
                                      await _telegramService.deleteUser(u['chatId']);
                                      final newUsers = await _telegramService.getUsers();
                                      setState(() => users = newUsers);
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ),
                    const SizedBox(height: 20),
                    const Text("Qo'shimcha", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              Navigator.pop(context); // Close dialog first
                              AppNotifications.showInfo(context, "Hisobot yuborilmoqda...");
                              await _telegramService.sendDailyReport(DatabaseHelper.instance);
                              AppNotifications.showSuccess(context, "Bugungi hisobot barcha userlarga yuborildi!");
                            }, 
                            icon: const Icon(Icons.bar_chart),
                            label: const Text("Bugungi Hisobot"),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                               final prefs = await SharedPreferences.getInstance();
                               await prefs.remove('last_low_stock_alert_date_v1'); // Clear flag to force run
                               
                               Navigator.pop(context);
                               AppNotifications.showInfo(context, "Tekshirilmoqda...");
                               
                               await _telegramService.checkDailyLowStockAlert(DatabaseHelper.instance); 
                               
                               AppNotifications.showSuccess(context, "Tekshiruv yakunlandi.");
                            },
                            icon: const Icon(Icons.warning_amber_rounded),
                            label: const Text("Kam Qoldiq"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Yopish")),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _clearAllData(BuildContext context) async {
    final t = Provider.of<AppTranslations>(context, listen: false);
    final confirm = await AppDialogs.showConfirmDialog(
      context: context,
      title: "Diqqat!",
      content: "Siz haqiqatdan ham barcha KIRIM, CHIQIM va HISOBOT ma'lumotlarini o'chirib yubormoqchimisiz?\n\nBu amalni orqaga qaytarib bo'lmaydi! Mahsulotlar ro'yxati saqlanib qoladi.",
    );

    if (confirm == true) {
      if (!context.mounted) return;
      
      // Secondary Confirmation
      final confirm2 = await AppDialogs.showConfirmDialog(
        context: context,
        title: "Tasdiqlash",
        content: "Iltimos, qayta tasdiqlang. Barcha tarixiy ma'lumotlar o'chib ketadi.",
      );

      if (confirm2 == true) {
        if (!context.mounted) return;
        AppDialogs.showBlurDialog(context: context, title: "Tozalanmoqda...", content: const CircularProgressIndicator());
        
        try {
          await DatabaseHelper.instance.clearAllData();
          if (!context.mounted) return;
          Navigator.pop(context); // Close loader
          AppNotifications.showSuccess(context, "Barcha ma'lumotlar tozalandi!");
        } catch (e) {
          if (!context.mounted) return;
          Navigator.pop(context); // Close loader
          AppNotifications.showError(context, "Xatolik: $e");
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<AppTranslations>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final profile = Provider.of<ProfileProvider>(context);
    final auth = Provider.of<AuthProvider>(context);
    final isDark = themeProvider.isDarkMode;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.text('menu_settings'), style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 24),
          
          // Profile Section
          _SectionHeader(title: t.text('set_profile')),
          const SizedBox(height: 12),
          GlassContainer(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary, width: 2),
                  ),
                  child: const CircleAvatar(
                    radius: 35, 
                    backgroundColor: AppColors.primary, 
                    child: Icon(Icons.person, size: 40, color: Colors.white)
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 22)),
                      const SizedBox(height: 4),
                       Text(profile.email, style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _showEditProfile(context, profile),
                  icon: const Icon(Icons.edit, color: AppColors.primary),
                  tooltip: t.text('btn_edit'),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Preferences Section
          _SectionHeader(title: t.text('set_general')),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _SettingCard(
                width: 350,
                icon: Icons.dark_mode,
                title: t.text('set_theme'),
                subtitle: isDark ? "Tun rejimi faol" : "Kun rejimi faol",
                color: Colors.blue,
                trailing: Switch(
                  value: isDark,
                  onChanged: (v) {
                    themeProvider.toggleTheme(v);
                    AppNotifications.showInfo(context, v ? "Tun rejimi yoqildi" : "Kun rejimi yoqildi");
                  },
                  activeColor: AppColors.primary,
                ),
              ),
              const _LanguageCard(),
            ],
          ),
          
          const SizedBox(height: 32),
          
          // Security & System Section
          _SectionHeader(title: t.text('set_security')),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _SettingCard(
                width: 350,
                icon: Icons.security_rounded,
                title: t.text('set_auth'),
                subtitle: t.text('set_change_pass'),
                color: Colors.orange,
                onTap: () => _showEditAuth(context, auth),
              ),
              _SettingCard(
                width: 350,
                icon: Icons.cloud_upload_outlined,
                title: t.text('menu_backup'),
                subtitle: "Oxirgi zaxira: Bugun, 14:00",
                color: AppColors.success,
                onTap: () => _showBackupDialog(context),
              ),
              _SettingCard(
                width: 350,
                icon: Icons.file_upload,
                title: "Excel Import",
                subtitle: "Tayyor ma'lumotlarni yuklash",
                color: Colors.teal,
                onTap: () => _importExcel(context),
              ),
            ],
          ),

          const SizedBox(height: 32),
          
          // Telegram Integration
          _SectionHeader(title: "Telegram Integratsiyasi"),
          const SizedBox(height: 12),
          GlassContainer(
            child: InkWell(
              onTap: () => _showTelegramSettings(context),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.send, color: Colors.blue, size: 28),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Telegram Bot Sozlamalari", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text("Bot tokeni va foydalanuvchilarni boshqarish", style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 32),

          // Danger Zone
          _SectionHeader(title: "Xavflilar", color: AppColors.error),
          const SizedBox(height: 12),
          _SettingCard(
            width: 350,
            icon: Icons.restore_page_rounded,
            title: "Backupdan Tiklash",
            subtitle: "Eski ma'lumotlarni qayta tiklash",
            color: AppColors.warning, // Yellow/Orange for caution
            onTap: () => _restoreBackup(context),
          ),
          const SizedBox(height: 16),
           _SettingCard(
            width: 350,
            icon: Icons.delete_forever,
            title: "Ma'lumotlarni Tozalash",
            subtitle: "Kirim, Chiqim va Hisobotlarni o'chirish",
            color: AppColors.error, 
            onTap: () => _clearAllData(context),
          ),

          const SizedBox(height: 40),
          Center(
            child: Column(
              children: [
                const Text("Omborxona Boshqaruv Tizimi v2.0.1", style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 4),
                Text("© 2026 OMBORXONA SYSTEMS", style: TextStyle(color: Colors.grey.withValues(alpha: 0.6), fontSize: 11)),
                const SizedBox(height: 4),
                Text("Created by Davronov Asadbek", style: TextStyle(color: Colors.grey.withValues(alpha: 0.6), fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color? color;
  const _SectionHeader({required this.title, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title.toUpperCase(), 
        style: TextStyle(
          fontSize: 13, 
          fontWeight: FontWeight.bold, 
          color: color ?? AppColors.primary,
          letterSpacing: 1.2
        )
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Widget? trailing;
  final double width;
  final VoidCallback? onTap;

  const _SettingCard({
    required this.icon, 
    required this.title, 
    required this.subtitle, 
    required this.color, 
    this.trailing,
    this.width = 300,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: GlassContainer(
        width: width,
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard();

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<AppTranslations>(context);
    
    return GlassContainer(
      width: 350,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.language, color: Colors.purple, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Til Sozlamalari", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text("Interfeys tilini tanlang", style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _LangBtn(label: "O'zbek", isActive: t.currentLocale == 'uz', onTap: () => t.setLocale('uz')),
              const SizedBox(width: 8),
              _LangBtn(label: "Русский", isActive: t.currentLocale == 'ru', onTap: () => t.setLocale('ru')),
              const SizedBox(width: 8),
              _LangBtn(label: "Türkçe", isActive: t.currentLocale == 'tr', onTap: () => t.setLocale('tr')),
            ],
          )
        ],
      ),
    );
  }
}

class _LangBtn extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _LangBtn({required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isActive ? AppColors.primary : AppColors.glassBorder),
          ),
          child: Center(
            child: Text(
              label, 
              style: TextStyle(
                color: isActive ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal
              )
            ),
          ),
        ),
      ),
    );
  }
}
