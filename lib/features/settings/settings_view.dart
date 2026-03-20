import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clinical_warehouse/core/theme/theme_provider.dart';
import 'package:clinical_warehouse/core/localization/app_translations.dart';
import 'package:clinical_warehouse/core/services/auth_provider.dart';
import 'package:clinical_warehouse/core/services/profile_provider.dart';
import 'package:clinical_warehouse/core/services/sync_service.dart';
import 'package:clinical_warehouse/core/database/database_helper.dart';
import 'package:clinical_warehouse/core/widgets/app_dialogs.dart';
import 'package:clinical_warehouse/core/services/excel_service.dart';
import 'package:clinical_warehouse/core/services/update_service.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final profile = context.read<ProfileProvider>();
    _nameController.text = profile.name;
    _emailController.text = profile.email;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _loginController.dispose();
    _passwordController.dispose();
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

  Future<void> _updateLogin() async {
    final auth = context.read<AuthProvider>();
    await auth.updateCredentials(_loginController.text, _passwordController.text);
    _loginController.clear();
    _passwordController.clear();
    if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppTranslations().text('saved'))),
      );
    }
  }

  Future<void> _fullCloudSync() async {
    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: 'Bulutdan to\'liq yuklash',
      content: 'Barcha mahalliy ma\'lumotlar o\'chiriladi va bulutdagilar bilan yangilanadi. Davom etasizmi?',
      confirmText: 'Ha, yuklash',
      cancelText: 'Bekor qilish',
    );

    if (confirmed == true) {
      try {
        await SyncService().fullResync();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ma\'lumotlar muvaffaqiyatli yangilandi')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Xatolik: $e')),
          );
        }
      }
    }
  }

  Future<void> _factoryReset() async {
    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: 'Zavod sozlamalariga qaytarish',
      content: 'Diqqat! Barcha ma\'lumotlar to\'liq o\'chib ketadi. Bu amalni qaytarib bo\'lmaydi.',
      confirmText: 'To\'liq o\'chirish',
      cancelText: 'Bekor qilish',
    );

    if (confirmed == true) {
      await DatabaseHelper.instance.factoryReset();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tizim tozalandi')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final trans = AppTranslations();

    return Scaffold(
      appBar: AppBar(
        title: Text(trans.text('menu_settings')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(title: trans.text('profile')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(labelText: trans.text('name')),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailController,
                    decoration: InputDecoration(labelText: trans.text('email')),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _updateProfile,
                    child: Text(trans.text('save')),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: trans.text('security')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _loginController,
                    decoration: const InputDecoration(labelText: 'Login'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Parol'),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _updateLogin,
                    child: Text(trans.text('update')),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: trans.text('appearance')),
          ListTile(
            title: Text(trans.text('dark_mode')),
            trailing: Switch(
              value: theme.isDarkMode,
              onChanged: (val) => theme.toggleTheme(val),
              activeThumbColor: Theme.of(context).colorScheme.primary,
            ),
          ),
          ListTile(
            title: Text(trans.text('language')),
            subtitle: Text(trans.currentLocale == 'uz' ? 'O\'zbekcha' : 'Русский'),
            onTap: () {
              final newLocale = trans.currentLocale == 'uz' ? 'ru' : 'uz';
              trans.setLocale(newLocale);
            },
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: 'Sinxronizatsiya va Yangilanish'),
          ListTile(
            leading: const Icon(Icons.cloud_download, color: Colors.blue),
            title: const Text('Bulutdan to\'liq yuklash (Full Resync)'),
            subtitle: const Text('Local ma\'lumotlarni o\'chirib, bulutdan qayta tortish'),
            onTap: _fullCloudSync,
          ),
          ListTile(
            leading: const Icon(Icons.file_download, color: Colors.green),
            title: const Text('Jihozlarni eksport qilish (Excel)'),
            onTap: () => ExcelService.exportAssetsHierarchy(),
          ),
          ListTile(
            leading: const Icon(Icons.system_update, color: Colors.orange),
            title: const Text('Yangilanishlarni tekshirish'),
            onTap: () => UpdateService.checkUpdate(forceShowNoUpdate: true),
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: 'Tizim'),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Zavod sozlamalariga qaytarish', style: TextStyle(color: Colors.red)),
            onTap: _factoryReset,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
