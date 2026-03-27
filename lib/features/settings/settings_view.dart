import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:clinical_warehouse/core/theme/theme_provider.dart';
import 'package:clinical_warehouse/core/localization/app_translations.dart';
import 'package:clinical_warehouse/core/services/auth_provider.dart';
import 'package:clinical_warehouse/core/services/profile_provider.dart';
import 'package:clinical_warehouse/core/services/sync_service.dart';
import 'package:clinical_warehouse/core/database/database_helper.dart';
import 'package:clinical_warehouse/core/widgets/app_dialogs.dart';
import 'package:clinical_warehouse/core/widgets/liquid_glass.dart';
import 'package:clinical_warehouse/core/utils/app_notifications.dart';
import 'package:clinical_warehouse/core/services/update_service.dart';
import 'package:clinical_warehouse/core/widgets/glass_container.dart';
import 'package:clinical_warehouse/core/theme/app_colors.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsView extends StatefulWidget {
  final bool showHeader;
  const SettingsView({super.key, this.showHeader = true});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  String _appVersion = "...";

  @override
  void initState() {
    super.initState();
    final profile = context.read<ProfileProvider>();
    _nameController.text = profile.name;
    _emailController.text = profile.email;
    _getAppInfo();
    _loadDeviceName();
  }

  Future<void> _getAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = "${info.version}+${info.buildNumber}";
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _loginController.dispose();
    _passwordController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }

  Future<void> _updateProfile() async {
    final profile = context.read<ProfileProvider>();
    await profile.updateProfile(_nameController.text, _emailController.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppTranslations().text('saved'))),
      );
    }
  }


  Future<void> _fullCloudSync() async {
    final trans = AppTranslations();
    
    // Initial state for granular selection
    final selectedTables = <String, bool>{
      'restore_baza': true,
      'restore_kirim': true,
      'restore_chiqim': true,
      'restore_jihozlar': true,
      'restore_orders': true,
    };

    final result = await showDialog<Map<String, bool>>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.1),
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) => Center(
          child: GlassContainer(
            width: 360,
            padding: const EdgeInsets.all(32),
            borderRadius: 32,
            opacity: 0.12,
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_download_rounded, size: 48, color: Colors.orange),
                  const SizedBox(height: 16),
                  Text(trans.text("set_restore_title"), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  Text(trans.text("set_restore_desc"), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 24),
                  ...selectedTables.keys.map((key) => _buildRestoreOption(
                    title: trans.text(key),
                    value: selectedTables[key]!,
                    onChanged: (v) => setDialogState(() => selectedTables[key] = v!),
                  )),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _buildModalBtn(trans.text("btn_cancel"), Colors.transparent, AppColors.textSecondary, () => Navigator.pop(c)),
                      const SizedBox(width: 12),
                      _buildModalBtn(trans.text("btn_confirm"), Colors.orange, Colors.white, () => Navigator.pop(c, selectedTables)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (result != null && result.values.any((v) => v)) {
      if (!mounted) return;
      AppNotifications.showInfo(context, trans.text("msg_restart_required"));
      
      try {
        final List<String> tablesToSync = [];
        if (result['restore_baza'] == true) tablesToSync.add('products');
        if (result['restore_kirim'] == true) tablesToSync.add('stock_in');
        if (result['restore_chiqim'] == true) tablesToSync.add('stock_out');
        if (result['restore_jihozlar'] == true) {
          tablesToSync.addAll(['assets', 'asset_locations', 'asset_categories']);
        }
        if (result['restore_orders'] == true) {
          tablesToSync.addAll(['branch_orders', 'branch_order_items']);
        }

        await SyncService().fullResync(tables: tablesToSync);
        
        if (mounted) {
          AppNotifications.showSuccess(context, trans.text("msg_saved"));
        }
      } catch (e) {
        if (mounted) {
          AppNotifications.showError(context, "${trans.text("msg_error")}: $e");
        }
      }
    }
  }

  Widget _buildRestoreOption({required String title, required bool value, required ValueChanged<bool?> onChanged}) {
    return CheckboxListTile(
      value: value,
      onChanged: onChanged,
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      dense: true,
      activeColor: Colors.orange,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      contentPadding: EdgeInsets.zero,
    );
  }

  Future<void> _pickProfileImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      if (mounted) {
        await context.read<ProfileProvider>().updateImage(result.files.single.path!);
      }
    }
  }

  void _createBackup() async {
    final trans = AppTranslations();
    try {
      final path = await DatabaseHelper.instance.createBackup(null);
      if (path != null && mounted) {
        AppNotifications.showSuccess(context, "${trans.text("msg_backup_ok")}: $path");
      }
    } catch (e) {
      if (mounted) {
        AppNotifications.showError(context, "${trans.text("msg_error")}: $e");
      }
    }
  }

  Future<void> _restoreLocalBackup() async {
    final trans = AppTranslations();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      if (!mounted) return;
      final confirmed = await AppDialogs.showConfirmDialog(
        context: context,
        title: trans.text("set_restore_local_title"),
        content: trans.text("set_restore_local_desc"),
        confirmText: trans.text("btn_confirm"),
        cancelText: trans.text("btn_cancel"),
      );

      if (confirmed == true) {
        try {
          final success = await DatabaseHelper.instance.restoreBackup(result.files.single.path!);
          if (success && mounted) {
            AppNotifications.showSuccess(context, trans.text("msg_factory_reset_done"));
          }
        } catch (e) {
          if (mounted) {
            AppNotifications.showError(context, "${trans.text("msg_error")}: $e");
          }
        }
      }
    }
  }

  Future<void> _clearHistory() async {
    final trans = AppTranslations();
    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: trans.text("set_clear_data"),
      content: "${trans.text("set_clear_data_desc")}?",
      confirmText: trans.text("btn_confirm"),
      cancelText: trans.text("btn_cancel"),
    );

    if (confirmed == true) {
      try {
        await DatabaseHelper.instance.clearAllData();
        if (mounted) {
          AppNotifications.showSuccess(context, trans.text("msg_saved"));
        }
      } catch (e) {
        if (mounted) {
          AppNotifications.showError(context, "${trans.text("msg_error")}: $e");
        }
      }
    }
  }

  Future<void> _factoryReset() async {
    final trans = AppTranslations();
    final confirm = await AppDialogs.showConfirmDialog(
      context: context,
      title: trans.text("dlg_factory_reset_title"),
      content: trans.text("dlg_factory_reset_content"),
      confirmText: trans.text("btn_confirm"),
      cancelText: trans.text("btn_cancel"),
    );
    if (confirm == true) {
      try {
        await DatabaseHelper.instance.factoryReset();
        if (mounted) {
          AppNotifications.showSuccess(context, trans.text("msg_factory_reset_done"));
        }
      } catch (e) {
        if (mounted) {
          AppNotifications.showError(context, "${trans.text("msg_error")}: $e");
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final trans = context.watch<AppTranslations>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0), // ListView already has internal padding
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          children: [
            // Header
            if (widget.showHeader)
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  trans.text('menu_settings'), 
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
              ),

            // PROFIL
            _buildSectionTitle(trans.text("set_profil")),
            _buildProfileCard(),
            
            const SizedBox(height: 12),

                  // UMUMIY
                  _buildSectionTitle(trans.text("set_umumiy")),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 5.5,
                    children: [
                      _buildToggleCard(
                        title: trans.text("dark_mode"),
                        subtitle: trans.text(context.watch<ThemeProvider>().isDarkMode ? "set_theme_on" : "set_theme_off"),
                        icon: Icons.dark_mode_rounded,
                        value: context.watch<ThemeProvider>().isDarkMode,
                        onChanged: (v) => context.read<ThemeProvider>().toggleTheme(v),
                      ),
                      _buildLanguageCard(),
                    ],
                  ),
              
              const SizedBox(height: 12),

              // XAVFSIZLIK
              _buildSectionTitle(trans.text("set_xavfsizlik")),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 5.5,
                children: [
                   _buildToggleCard(
                    title: trans.text("set_pin_enable"),
                    subtitle: trans.text("set_pin_desc"),
                    icon: Icons.dialpad_rounded,
                    value: context.watch<AuthProvider>().isPinEnabled,
                    onChanged: (v) async {
                      if (v && !context.read<AuthProvider>().hasPin) {
                        _showPinSetupDialog(context, trans);
                      } else {
                        await context.read<AuthProvider>().togglePin(v);
                      }
                    },
                  ),
                  _buildActionCard(
                    title: trans.text("set_pin_change"),
                    subtitle: trans.text("set_pin_change_desc"),
                    icon: Icons.lock_reset_rounded,
                    color: Colors.blueAccent,
                    onTap: () => _showPinSetupDialog(context, trans),
                  ),

                  _buildActionCard(
                    title: trans.text("menu_backup"),
                    subtitle: trans.text("set_backup_subtitle"),
                    icon: Icons.cloud_upload_rounded,
                    color: Colors.green,
                    onTap: _createBackup,
                  ),
                  _buildActionCard(
                    title: trans.text("set_restore_title"),
                    subtitle: trans.text("set_sync_subtitle"),
                    icon: Icons.cloud_download_rounded,
                    color: Colors.orange,
                    onTap: _fullCloudSync,
                  ),
                  _buildActionCard(
                    title: trans.text("set_excel_import"),
                    subtitle: trans.text("set_excel_import_desc"),
                    icon: Icons.upload_file_rounded,
                    color: Colors.teal,
                    onTap: () {
                       AppNotifications.showInfo(context, trans.text("set_excel_import"));
                    },
                  ),
                  _buildActionCard(
                    title: trans.text("set_restore_local_title"),
                    subtitle: trans.text("set_restore_local_desc"),
                    icon: Icons.restore_rounded,
                    color: Colors.purple,
                    onTap: _restoreLocalBackup,
                  ),
                   _buildActionCard(
                    title: "Parolni o'zgartirish",
                    subtitle: "Hisob paroli yangilash",
                    icon: Icons.password_rounded,
                    color: Colors.amber,
                    onTap: () => _showPasswordChangeDialog(context, trans),
                  ),
                   _buildActionCard(
                    title: trans.text("set_update_title"),
                    subtitle: trans.text("set_update_subtitle"),
                    icon: Icons.system_update_rounded,
                    color: Colors.blue,
                    onTap: () => UpdateService.checkUpdate(forceShowNoUpdate: true),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // XODISA VA XAVFLAR
              _buildSectionTitle(trans.text("set_danger_zone"), color: Colors.red),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 5.5,
                children: [
                  _buildActionCard(
                    title: trans.text("set_clear_data"),
                    subtitle: trans.text("set_clear_data_desc"),
                    icon: Icons.delete_sweep_rounded,
                    color: Colors.orange,
                    onTap: _clearHistory,
                  ),
                  _buildActionCard(
                    title: trans.text("set_reset_title"),
                    subtitle: trans.text("set_factory_reset_desc"),
                    icon: Icons.factory_rounded,
                    color: Colors.red,
                    onTap: _factoryReset,
                  ),
                ],
              ),
            const SizedBox(height: 32),
            Center(
              child: Column(
                children: [
                  Text("Clinical Warehouse v$_appVersion", 
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: LiquidColors.of(context).muted.withValues(alpha: 0.4))),
                  const SizedBox(height: 4),
                  Text("Powered by Asadbek © 2026", 
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: LiquidColors.of(context).muted.withValues(alpha: 0.3))),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => _updateDeviceName(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: LiquidColors.of(context).muted.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text("🖥 Qurilma: ${_deviceNameController.text}", 
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: LiquidColors.of(context).muted.withValues(alpha: 0.5))),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
      child: Text(
        title, 
        style: TextStyle(
          fontSize: 10, 
          fontWeight: FontWeight.w800, 
          color: color ?? AppColors.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    final profile = context.watch<ProfileProvider>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
      child: Row(
        children: [
          InkWell(
            onTap: _pickProfileImage,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                image: profile.imagePath != null
                    ? DecorationImage(
                        image: profile.imagePath!.contains('http')
                            ? NetworkImage(profile.imagePath!) as ImageProvider
                            : FileImage(File(profile.imagePath!)),
                        fit: BoxFit.cover,
                      )
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: profile.imagePath == null
                  ? const Icon(Icons.person_rounded, color: Colors.white, size: 28)
                  : null,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  profile.name, 
                  style: TextStyle(
                    fontSize: 17, 
                    fontWeight: FontWeight.w800, 
                    color: LiquidColors.of(context).body,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  profile.email, 
                  style: TextStyle(
                    fontSize: 13, 
                    color: AppColors.textSecondary.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _showProfileEditDialog(context),
            icon: const Icon(Icons.edit_note_rounded, color: AppColors.primary),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.primary.withValues(alpha: 0.08),
              padding: const EdgeInsets.all(8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      borderRadius: 16,
      opacity: 0.03,
      child: Row(
        children: [
          _buildIconBox(icon, AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: -0.2, color: LiquidColors.of(context).body)),
                Text(subtitle, style: TextStyle(fontSize: 9, color: LiquidColors.of(context).muted.withValues(alpha: 0.7))),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.7,
            alignment: Alignment.centerRight,
            child: CupertinoSwitch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: Colors.white.withValues(alpha: 0.3),
              thumbColor: Colors.white,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageCard() {
    final trans = AppTranslations();
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      borderRadius: 16,
      opacity: 0.03,
      child: Row(
        children: [
          _buildIconBox(Icons.language_rounded, Colors.purple),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(trans.text("set_lang_title"), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: -0.2, color: LiquidColors.of(context).body)),
                Text(trans.text("set_lang_desc"), style: TextStyle(fontSize: 9, color: LiquidColors.of(context).muted.withValues(alpha: 0.7))),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildLangBtn("uz", trans.currentLocale == 'uz', () => trans.setLocale('uz')),
              const SizedBox(width: 4),
              _buildLangBtn("ru", trans.currentLocale == 'ru', () => trans.setLocale('ru')),
              const SizedBox(width: 4),
              _buildLangBtn("tr", trans.currentLocale == 'tr', () => trans.setLocale('tr')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLangBtn(String label, bool isActive, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : Colors.transparent,
          border: Border.all(color: isActive ? AppColors.primary : AppColors.glassBorder.withValues(alpha: 0.15)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label, 
          style: TextStyle(
            color: isActive ? Colors.white : AppColors.textSecondary, 
            fontSize: 13, 
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  final _deviceNameController = TextEditingController();

  Future<void> _loadDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceNameController.text = prefs.getString('device_name') ?? Platform.localHostname;
  }

  void _updateDeviceName() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Qurilmani nomlash"),
        content: TextField(
          controller: _deviceNameController,
          decoration: const InputDecoration(hintText: "Masalan: Ombor PC, Registratura"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("Bekor qilish")),
          TextButton(
            onPressed: () async {
              final name = _deviceNameController.text;
              final navigator = Navigator.of(c);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('device_name', name);
              if (mounted) {
                setState(() {});
                if (navigator.canPop()) {
                  navigator.pop();
                }
              }
            },
            child: const Text("Saqlash"),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: GlassContainer(
        padding: const EdgeInsets.all(10),
        borderRadius: 20,
        opacity: 0.03,
        child: Row(
          children: [
            _buildIconBox(icon, color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: LiquidColors.of(context).body)),
                  Text(subtitle, style: TextStyle(color: LiquidColors.of(context).muted, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconBox(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
      child: Icon(icon, size: 24, color: color),
    );
  }

  void _showProfileEditDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.1),
      builder: (c) {
        final profile = c.watch<ProfileProvider>();
        final trans = c.watch<AppTranslations>();
        return Center(
          child: GlassContainer(
            width: 360,
            padding: const EdgeInsets.all(32),
            borderRadius: 32,
            opacity: 0.08,
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(trans.text("set_profile"), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                  const SizedBox(height: 24),
                  // Image Preview
                  InkWell(
                    onTap: _pickProfileImage,
                    borderRadius: BorderRadius.circular(40),
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        image: profile.imagePath != null
                            ? DecorationImage(
                                image: profile.imagePath!.contains('http')
                                    ? NetworkImage(profile.imagePath!) as ImageProvider
                                    : FileImage(File(profile.imagePath!)),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: profile.imagePath == null
                          ? const Icon(Icons.person_rounded, color: Colors.white, size: 40)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _pickProfileImage,
                    child: Text(trans.text("set_change_photo"), style: const TextStyle(fontSize: 11)),
                  ),
                  const SizedBox(height: 16),
                  _buildModalInput(controller: _nameController, label: trans.text("col_name"), icon: Icons.badge_outlined),
                  const SizedBox(height: 16),
                  _buildModalInput(controller: _emailController, label: "Email", icon: Icons.email_outlined),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.lock_outline, size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(c); // Close profile dialog
                          _showPasswordChangeDialog(context, trans); // Open password change dialog
                        },
                        child: const Text("Parolni o'zgartirish", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _buildModalBtn(trans.text("btn_cancel"), Colors.transparent, AppColors.textSecondary, () => Navigator.pop(c)),
                      const SizedBox(width: 12),
                      _buildModalBtn(trans.text("btn_save"), AppColors.primary, Colors.white, () {
                        _updateProfile();
                        Navigator.pop(c);
                      }),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showPinSetupDialog(BuildContext dialogCtx, AppTranslations trans) {
    final pinController = TextEditingController();
    final auth = dialogCtx.read<AuthProvider>();
    
    showDialog(
      context: dialogCtx,
      barrierColor: Colors.black.withValues(alpha: 0.1),
      builder: (c) => Center(
        child: GlassContainer(
          width: 340,
          padding: const EdgeInsets.all(32),
          borderRadius: 32,
          opacity: 0.1,
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.dialpad_rounded, size: 48, color: AppColors.primary),
                const SizedBox(height: 16),
                Text(trans.text("set_pin_change"), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(trans.text("set_pin_change_desc"), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 24),
                TextField(
                  controller: pinController,
                  obscureText: true,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 16),
                  decoration: const InputDecoration(
                    counterText: "",
                    border: InputBorder.none,
                    hintText: "••••",
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _buildModalBtn(trans.text("btn_cancel"), Colors.transparent, AppColors.textSecondary, () => Navigator.pop(c)),
                    const SizedBox(width: 12),
                    _buildModalBtn(trans.text("btn_save"), AppColors.primary, Colors.white, () async {
                      if (pinController.text.length == 4) {
                        final successMsg = trans.text("msg_pin_saved");
                        await auth.updatePin(pinController.text);
                        await auth.togglePin(true);
                        
                        if (!mounted) return;
                        if (c.mounted) Navigator.pop(c);
                        if (!mounted) return;
                        
                        AppNotifications.showSuccess(context, successMsg);
                      } else {
                        AppNotifications.showError(context, trans.text("msg_pin_error"));
                      }
                    }),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPasswordChangeDialog(BuildContext dialogCtx, AppTranslations trans) {
    final passController = TextEditingController();
    final auth = dialogCtx.read<AuthProvider>();
    bool obscure = true;

    showDialog(
      context: dialogCtx,
      barrierColor: Colors.black.withValues(alpha: 0.1),
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) => Center(
          child: GlassContainer(
            width: 340,
            padding: const EdgeInsets.all(32),
            borderRadius: 32,
            opacity: 0.1,
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.security_rounded, size: 48, color: Colors.amber),
                  const SizedBox(height: 16),
                  const Text("Yangi parol", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  const Text("Hisobingiz uchun yangi parol kiriting", style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 24),
                  _buildModalInput(
                    controller: passController, 
                    label: "Yangi parol", 
                    icon: Icons.lock_outline, 
                    isPassword: obscure,
                  ),
                  TextButton(
                    onPressed: () => setDialogState(() => obscure = !obscure),
                    child: Text(obscure ? "Ko'rsatish" : "Berkitish", style: const TextStyle(fontSize: 10)),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _buildModalBtn(trans.text("btn_cancel"), Colors.transparent, AppColors.textSecondary, () => Navigator.pop(c)),
                      const SizedBox(width: 12),
                      _buildModalBtn(trans.text("btn_save"), Colors.amber, Colors.white, () async {
                        if (passController.text.length >= 6) {
                          final success = await auth.updatePassword(passController.text);
                          if (!mounted) return;
                          if (c.mounted) Navigator.pop(c);
                          if (success) {
                            AppNotifications.showSuccess(context, "Parol muvaffaqiyatli yangilandi");
                          } else {
                            AppNotifications.showError(context, "Xatolik yuz berdi");
                          }
                        } else {
                          AppNotifications.showError(context, "Parol kamida 6 belgidan iborat bo'lishi kerak");
                        }
                      }),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildModalInput({required TextEditingController controller, required String label, required IconData icon, bool isPassword = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 6),
          child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textTertiary)),
        ),
        GlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          borderRadius: 12,
          opacity: 0.03,
          child: TextField(
            controller: controller,
            obscureText: isPassword,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              icon: Icon(icon, size: 16, color: AppColors.primary.withValues(alpha: 0.4)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModalBtn(String label, Color bg, Color text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          boxShadow: bg != Colors.transparent ? [BoxShadow(color: bg.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))] : [],
        ),
        child: Text(label, style: TextStyle(color: text, fontSize: 11, fontWeight: FontWeight.w900)),
      ),
    );
  }
}
