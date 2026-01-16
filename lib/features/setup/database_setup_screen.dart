import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:clinical_warehouse/core/database/database_helper.dart';
import 'package:clinical_warehouse/features/splash/splash_screen.dart';

class DatabaseSetupScreen extends StatefulWidget {
  const DatabaseSetupScreen({super.key});

  @override
  State<DatabaseSetupScreen> createState() => _DatabaseSetupScreenState();
}

class _DatabaseSetupScreenState extends State<DatabaseSetupScreen> {
  bool _isLoading = false;
  String? _error;

  Future<void> _createNewDatabase() async {
    setState(() => _isLoading = true);
    
    // 1. Let user pick a DIRECTORY
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: "Ma'lumotlar bazasi saqlanadigan papkani tanlang",
    );

    if (selectedDirectory != null) {
      // 2. Define the DB file name
      final dbPath = p.join(selectedDirectory, 'omborxona_data.db');
      
      await _finalizeSetup(dbPath);
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickExistingDatabase() async {
    setState(() => _isLoading = true);
    
    // 1. Let user pick a FILE (.db)
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: "Mavjud baza faylini (.db) tanlang",
      type: FileType.any, // .db extension filter might be finicky on some OS, keeping Any but checking ext
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      
      if (!path.endsWith('.db')) {
        setState(() {
          _error = "Iltimos, faqat .db formatidagi faylni tanlang!";
          _isLoading = false;
        });
        return;
      }

      await _finalizeSetup(path);
    } else {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _useDefaultLocation() async {
     // Just proceed, DatabaseHelper will fallback to default logic if we don't set anything
     // But to be explicit, we won't set the param, effectively using default.
     // OR we can explicitly get the default path and set it.
     // Let's just navigate to Splash, main.dart logic will handle it? 
     // wait, main.dart will trigger this screen again if we don't set SOMETHING.
     // So we must set a flag or path.
     
     // Actually, let's just use the internal path explicitly so config is 'set'
      setState(() => _isLoading = true);
      // We don't need to do anything, just proceed. 
      // But wait, if we don't set a path, `getConfiguredPath` returns null.
      // So we should probably set a flag "use_default" or similar. 
      // For now, let's just make the user pick. The user asked for it. 
      // I'll leave "Default" hidden or as an automatic fallback if they cancel? NO.
      // Let's stick to the user's request: "Foydalanuvchi ozi tanlasa".
      
      // I will add a text button for "Default Location (Automatic)" just in case.
      await DatabaseHelper.instance.setDatabasePath(''); // Empty string = marker for default?
      // No, my DatabaseHelper logic checks for null.
      // I should update DatabaseHelper to handle empty string as "Default" too?
      // Or just navigate away. 
      
      // Better strategy: We can't use DatabaseHelper's fallback logic nicely if we loop.
      // Let's just restart the app or Go to Splash.
      // I'll add a 'Skip / Default' button that sets a special marker or just lets the user through.
      
      // Hack: For now, I will NOT offer a default button unless requested. The user wants control.
  }

  Future<void> _finalizeSetup(String path) async {
    try {
      await DatabaseHelper.instance.setDatabasePath(path);
      
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SplashScreen()),
        );
      }
    } catch (e) {
      setState(() {
        _error = "Xatolik: $e";
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E88E5), // Matched Splash Screen Blue
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/logo.png', width: 100, height: 100),
              const SizedBox(height: 24),
              const Text(
                "Baza Joylashuvi",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                "Dastur ishlashi uchun ma'lumotlar bazasi qayerda saqlanishini tanlang.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
              ),
              const SizedBox(height: 32),
              
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ),

              if (_isLoading)
                const CircularProgressIndicator()
              else ...[
                _OptionButton(
                  icon: Icons.create_new_folder_rounded,
                  title: "Yangi Baza Yaratish",
                  subtitle: "Papkada yangi fayl ochiladi",
                  color: Colors.blue,
                  onTap: _createNewDatabase,
                ),
                const SizedBox(height: 16),
                _OptionButton(
                  icon: Icons.folder_open_rounded,
                  title: "Mavjud Bazani Tanlash",
                  subtitle: "Eski .db faylni ko'rsating",
                  color: Colors.orange,
                  onTap: _pickExistingDatabase,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _OptionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: color.withOpacity(0.5)),
            borderRadius: BorderRadius.circular(16),
            color: color.withOpacity(0.1),
          ),
          child: Row(
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5))),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white.withOpacity(0.3)),
            ],
          ),
        ),
      ),
    );
  }
}
