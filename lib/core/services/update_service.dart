import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';

class UpdateService {
  // --- KONFIGURATSIYA: O'zingizning GitHub ma'lumotlaringizni kiriting ---
  static const String _githubUser = 'Asadbek0121'; // GitHub foydalanuvchi nomi
  static const String _githubRepo = 'OBI'; // Repozitoriya nomi

  static Future<void> checkUpdate(BuildContext context) async {
    // Desktop (Windows/Mac) bo'lsa tekshiramiz
    if (!Platform.isWindows && !Platform.isMacOS) return;

    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String currentVersion = packageInfo.version;

      debugPrint("🚀 [Updater] Hozirgi versiya: $currentVersion");

      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$_githubUser/$_githubRepo/releases/latest'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String latestTag = (data['tag_name'] as String);
        final String latestVersion = latestTag.replaceFirst('v', '').split('+')[0];
        
        debugPrint("🚀 [Updater] Oxirgi versiya: $latestVersion");

        if (_isNewer(latestVersion, currentVersion)) {
          String downloadUrl = "";
          final assets = data['assets'] as List;
          
          if (assets.isNotEmpty) {
            // Windows uchun .msix yoki .exe ni qidiramiz
            if (Platform.isWindows) {
              final msix = assets.firstWhere((a) => a['name'].toString().endsWith('.msix') || a['name'].toString().endsWith('.exe'), orElse: () => assets[0]);
              downloadUrl = msix['browser_download_url'];
            } else if (Platform.isMacOS) {
              final dmg = assets.firstWhere((a) => a['name'].toString().endsWith('.dmg') || a['name'].toString().endsWith('.zip'), orElse: () => assets[0]);
              downloadUrl = dmg['browser_download_url'];
            }

            if (downloadUrl.isNotEmpty && context.mounted) {
              _showUpdateDialog(context, latestVersion, downloadUrl, data['body'] ?? '');
            }
          }
        }
      }
    } catch (e) {
      debugPrint("❌ [Updater] Xatolik: $e");
    }
  }

  static bool _isNewer(String latest, String current) {
    try {
      List<int> latestParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      List<int> currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      
      for (int i = 0; i < latestParts.length; i++) {
        if (i >= currentParts.length) return true;
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }
    } catch (_) {}
    return false;
  }

  static void _showUpdateDialog(BuildContext context, String version, String url, String notes) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.rocket_launch, color: Colors.blueAccent),
            const SizedBox(width: 10),
            Text('Yangi versiya tayyor! (v$version)'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ilovada yangi imkoniyatlar va xatoliklar tuzatilgan.'),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text("Yangiliklar:", style: TextStyle(fontWeight: FontWeight.bold)),
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                width: double.maxFinite,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(child: Text(notes)),
              ),
            ],
            const SizedBox(height: 10),
            const Text('Hozir yangilashni xohlaysizmi?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keyinroq'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Yuklab olish / Yangilash', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
